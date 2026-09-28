#!/usr/bin/env python3
"""Crosswalk the NHFR export against the live WellaPath facility artifact.

Reproducible, read-only, and it changes nothing. It writes two reports: a
machine-readable one carrying aggregates and per-pair keys, and a human summary
carrying totals only.

    python3 scripts/audit/nhfr_crosswalk.py --nhfr <csv> --wellapath <json> --out <dir>

Paths come from arguments or the environment; nothing is hardcoded.
`WELLAPATH_PRIVATE_DATA` may point at the private data directory, in which case
`--nhfr` defaults to `$WELLAPATH_PRIVATE_DATA/nhfr/nigeria_health_facilities.csv`.

CONTACTS ARE NEVER WRITTEN. Telephone numbers, email addresses and websites are
counted and classified, never emitted. The ambulance shortlist carries facility
identifiers only, so that outreach can be planned without copying a contact
list into a report that might be shared.

Matching runs in tiers, strongest first, and never merges anything: every
output is a classification for a human to act on.

  1. Official identifier. NHFR `unique_id` against a WellaPath field holding an
     official code. WellaPath has none today, so this tier reports zero and
     that is the finding, not a bug.
  2. Exact normalised name within the same state.
  3. Name match plus proximity (<= 2 km).
  4. Proximity alone (<= 150 m), as a review candidate only.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

csv.field_size_limit(10**9)

TARGET_STATES = ["Lagos", "Oyo", "Ogun", "Kano", "FCT"]
# WellaPath currently covers three of the five; the other two are proposed
# coverage and are reported separately rather than mixed into the comparison.
EXISTING_COVERAGE = {"Lagos", "Kano", "FCT"}

NAME_STOPWORDS = {
    "the", "and", "of", "nigeria", "nig", "ltd", "limited",
    "health", "centre", "center", "clinic", "hospital", "medical",
}


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def strip_accents(s: str) -> str:
    s = unicodedata.normalize("NFKD", s or "")
    return "".join(c for c in s if not unicodedata.combining(c))


def norm(s: str) -> str:
    s = strip_accents(s).lower()
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def name_key(s: str) -> str:
    """Token-sorted key with generic facility words removed.

    Dropping "hospital"/"clinic" is deliberate: they are the words most likely
    to differ between two records for the same place ("X Hospital" vs "X
    Medical Centre"), and keeping them causes false negatives. It does raise
    collisions, which is why every name match is reported for review and none
    is applied.
    """
    toks = [t for t in norm(s).split() if t not in NAME_STOPWORDS]
    return " ".join(sorted(toks))


def haversine_km(a_lat, a_lon, b_lat, b_lon) -> float:
    r = 6371.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp, dl = math.radians(b_lat - a_lat), math.radians(b_lon - a_lon)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


def as_float(v):
    try:
        f = float(v)
        return None if math.isnan(f) else f
    except (TypeError, ValueError):
        return None


PHONE_OK = re.compile(r"^\+?[0-9][0-9\s().-]{6,20}[0-9]$")
EMAIL_OK = re.compile(r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$")


def norm_state(s: str) -> str:
    n = norm(s)
    if n in {"fct", "fct abuja", "federal capital territory", "abuja"}:
        return "FCT"
    return (s or "").strip()


def load_nhfr(path: Path):
    with path.open(newline="", encoding="utf-8", errors="replace") as fh:
        first = fh.readline()  # title line, not a header
        rows = list(csv.DictReader(fh))
    return rows, first.strip()


def load_wellapath(path: Path):
    raw = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(raw, list):
        return raw
    for v in raw.values():
        if isinstance(v, list):
            return v
    raise SystemExit("could not find the record list in the WellaPath artifact")


def main() -> int:
    ap = argparse.ArgumentParser()
    priv = os.environ.get("WELLAPATH_PRIVATE_DATA")
    ap.add_argument(
        "--nhfr",
        default=(
            str(Path(priv) / "nhfr" / "nigeria_health_facilities.csv") if priv else None
        ),
        help="NHFR CSV export (or set WELLAPATH_PRIVATE_DATA)",
    )
    ap.add_argument("--wellapath", required=True, help="facilities.ng.v1.1.json")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    if not args.nhfr:
        ap.error("--nhfr is required unless WELLAPATH_PRIVATE_DATA is set")

    nhfr_path, wp_path, out = Path(args.nhfr), Path(args.wellapath), Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    nhfr_rows, title = load_nhfr(nhfr_path)
    wp_rows = load_wellapath(wp_path)

    report = {
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "sources": {
            "nhfr": {
                "sha256": sha256_of(nhfr_path),
                "bytes": nhfr_path.stat().st_size,
                "rows": len(nhfr_rows),
                "title_line": title,
                "publisher": "Nigeria Health Facility Registry / Federal Ministry "
                "of Health and Social Welfare",
                "site": "https://hfr.fmohconnect.gov.ng",
                "acquisition": "manual website export by the founder",
                "founder_confirmed": "2026-09-28",
                "download_timestamp": "not retained",
                "licence": "no explicit licence captured",
                "usage_wording": "officially downloaded NHFR registry data",
            },
            "wellapath": {
                "sha256": sha256_of(wp_path),
                "bytes": wp_path.stat().st_size,
                "records": len(wp_rows),
            },
        },
    }

    # ── five-state slices ────────────────────────────────────────────────
    nhfr_by_state = defaultdict(list)
    for r in nhfr_rows:
        nhfr_by_state[norm_state(r.get("state_name", ""))].append(r)
    wp_by_state = defaultdict(list)
    for r in wp_rows:
        wp_by_state[norm_state(r.get("state", ""))].append(r)

    report["counts"] = {
        s: {
            "nhfr": len(nhfr_by_state.get(s, [])),
            "wellapath": len(wp_by_state.get(s, [])),
            "in_existing_coverage": s in EXISTING_COVERAGE,
        }
        for s in TARGET_STATES
    }

    # ── tier 1: official identifier ──────────────────────────────────────
    # WellaPath has no official-code field. Probe for one rather than assume.
    wp_fields = set()
    for r in wp_rows[:200]:
        wp_fields |= set(r.keys())
    id_fields = [
        f for f in wp_fields
        if any(k in f.lower() for k in ("nhfr", "registry", "official", "hfr_"))
    ]
    report["identifier_match"] = {
        "wellapath_official_id_fields_found": id_fields,
        "matched": 0,
        "note": "WellaPath carries only a synthetic local facility_id "
        "(ng_lag_001 style). With no official code on its side, the strongest "
        "match tier is unavailable and every match below is heuristic.",
    }

    # ── tiers 2-4, per state, existing coverage only ─────────────────────
    crosswalk = {}
    for state in sorted(EXISTING_COVERAGE):
        N, W = nhfr_by_state.get(state, []), wp_by_state.get(state, [])
        n_idx = defaultdict(list)
        for i, r in enumerate(N):
            n_idx[name_key(r.get("facility_name", ""))].append(i)

        matched_n, matched_w = set(), set()
        pairs = {"exact_name": 0, "name_and_proximity": 0, "proximity_only": 0}
        conflicts = Counter()

        for wi, w in enumerate(W):
            key = name_key(w.get("name", ""))
            wlat, wlon = as_float(w.get("latitude")), as_float(w.get("longitude"))
            cands = [i for i in n_idx.get(key, []) if i not in matched_n] if key else []

            chosen = None
            tier = None
            if cands:
                if wlat is not None and wlon is not None:
                    scored = []
                    for i in cands:
                        nlat, nlon = as_float(N[i].get("latitude")), as_float(N[i].get("longitude"))
                        d = (
                            haversine_km(wlat, wlon, nlat, nlon)
                            if nlat is not None and nlon is not None
                            else None
                        )
                        scored.append((d if d is not None else 9e9, i))
                    scored.sort()
                    best_d, best_i = scored[0]
                    chosen, tier = best_i, ("name_and_proximity" if best_d <= 2.0 else "exact_name")
                else:
                    chosen, tier = cands[0], "exact_name"

            if chosen is None and wlat is not None and wlon is not None:
                # proximity-only, very tight, review candidate
                best = None
                for i, n in enumerate(N):
                    if i in matched_n:
                        continue
                    nlat, nlon = as_float(n.get("latitude")), as_float(n.get("longitude"))
                    if nlat is None or nlon is None:
                        continue
                    if abs(nlat - wlat) > 0.01 or abs(nlon - wlon) > 0.01:
                        continue
                    d = haversine_km(wlat, wlon, nlat, nlon)
                    if d <= 0.15 and (best is None or d < best[0]):
                        best = (d, i)
                if best:
                    chosen, tier = best[1], "proximity_only"

            if chosen is not None:
                matched_n.add(chosen)
                matched_w.add(wi)
                pairs[tier] += 1
                n = N[chosen]
                # conflicts on the matched pair
                if name_key(w.get("name", "")) != name_key(n.get("facility_name", "")):
                    conflicts["name"] += 1
                nlat, nlon = as_float(n.get("latitude")), as_float(n.get("longitude"))
                if None not in (wlat, wlon, nlat, nlon):
                    d = haversine_km(wlat, wlon, nlat, nlon)
                    if d > 2.0:
                        conflicts["coordinate_over_2km"] += 1
                    if d > 10.0:
                        conflicts["coordinate_over_10km"] += 1
                if norm(w.get("city_area", "")) and norm(n.get("lga_name", "")):
                    if norm(w.get("city_area", "")) != norm(n.get("lga_name", "")):
                        conflicts["area_vs_lga_differs"] += 1

        crosswalk[state] = {
            "nhfr_records": len(N),
            "wellapath_records": len(W),
            "matched_pairs": pairs,
            "matched_total": sum(pairs.values()),
            "wellapath_unmatched_legacy_review": len(W) - len(matched_w),
            "nhfr_unmatched_candidate_additions": len(N) - len(matched_n),
            "conflicts_on_matched_pairs": dict(conflicts),
        }

    report["crosswalk"] = crosswalk

    # ── proposed new coverage ────────────────────────────────────────────
    report["proposed_new_coverage"] = {
        s: {"nhfr_records": len(nhfr_by_state.get(s, []))}
        for s in TARGET_STATES
        if s not in EXISTING_COVERAGE
    }

    # ── contacts and ambulance, counts only, across the five states ──────
    five = [r for s in TARGET_STATES for r in nhfr_by_state.get(s, [])]
    contact = Counter()
    amb = Counter()
    amb_shortlist = defaultdict(list)
    for r in five:
        p = (r.get("phone_number") or "").strip()
        if not p:
            contact["no_contact"] += 1
        elif PHONE_OK.match(p):
            contact["nhfr_listed_not_recently_verified"] += 1
        else:
            contact["invalid_contact"] += 1
        e = (r.get("email_address") or "").strip()
        if e:
            contact["with_email"] += 1
            if not EMAIL_OK.match(e):
                contact["email_invalid"] += 1
        a = (r.get("ambulance_services") or "").strip()
        amb[a or "«blank»"] += 1
        if a.lower() in {"yes", "true", "1"}:
            amb_shortlist[norm_state(r.get("state_name", ""))].append(
                r.get("unique_id", "")
            )

    report["contacts_five_states"] = {
        "total_records": len(five),
        "classification": dict(contact),
        "note": "No telephone number, email address or website is written to "
        "any report. WellaPath-verified and expired-verification classes are "
        "empty because no verification has ever been performed.",
        "wellapath_verified": 0,
        "expired_verification": 0,
    }
    report["ambulance_five_states"] = {
        "field_values": dict(amb),
        "shortlist_size_by_state": {k: len(v) for k, v in sorted(amb_shortlist.items())},
        "note": "Identifiers only. An NHFR ambulance flag is a registry value, "
        "not a confirmation that a service operates today. No facility may "
        "carry an ambulance label until direct verification.",
    }
    (out / "ambulance_shortlist_ids.json").write_text(
        json.dumps({k: sorted(v) for k, v in amb_shortlist.items()}, indent=2),
        encoding="utf-8",
    )

    # ── offline impact ───────────────────────────────────────────────────
    def candidate_bytes(states):
        recs = []
        for s in states:
            for r in nhfr_by_state.get(s, []):
                recs.append(
                    {
                        "facility_id": r.get("unique_id"),
                        "name": r.get("facility_name"),
                        "state": norm_state(r.get("state_name", "")),
                        "lga": r.get("lga_name"),
                        "ward": r.get("ward_name"),
                        "latitude": as_float(r.get("latitude")),
                        "longitude": as_float(r.get("longitude")),
                        "type": r.get("facility_level_name"),
                        "ownership": r.get("ownership_name"),
                        "source": "NHFR",
                        "source_updated_at": (r.get("updated_at") or "")[:10],
                    }
                )
        return len(json.dumps({"facilities": recs}, separators=(",", ":")).encode()), len(recs)

    cur_b, cur_n = wp_path.stat().st_size, len(wp_rows)
    three_b, three_n = candidate_bytes(sorted(EXISTING_COVERAGE))
    five_b, five_n = candidate_bytes(TARGET_STATES)
    report["offline_impact"] = {
        "current_artifact_bytes": cur_b,
        "current_records": cur_n,
        "candidate_three_states": {"bytes": three_b, "records": three_n},
        "candidate_five_states": {"bytes": five_b, "records": five_n},
        "delta_vs_current_five_states_bytes": five_b - cur_b,
        "note": "Contact-free projection with a provenance-aware field set. "
        "Measured by serialising the candidate records, not estimated.",
    }

    (out / "nhfr_crosswalk.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    # ── human summary ────────────────────────────────────────────────────
    L = ["NHFR crosswalk", ""]
    L.append(f"NHFR      {report['sources']['nhfr']['rows']:,} rows   sha {report['sources']['nhfr']['sha256'][:16]}…")
    L.append(f"WellaPath {cur_n:,} records   sha {report['sources']['wellapath']['sha256'][:16]}…")
    L.append("")
    L.append("Five-state counts")
    L.append(f"  {'state':<8} {'NHFR':>8} {'WellaPath':>10}  coverage")
    for s in TARGET_STATES:
        c = report["counts"][s]
        L.append(
            f"  {s:<8} {c['nhfr']:>8,} {c['wellapath']:>10,}  "
            f"{'existing' if c['in_existing_coverage'] else 'PROPOSED'}"
        )
    L.append("")
    L.append("Identifier tier")
    L.append(f"  official-id matches: {report['identifier_match']['matched']}")
    L.append(f"  WellaPath official-id fields: {id_fields or 'none'}")
    L.append("")
    for s, c in crosswalk.items():
        L.append(f"{s}")
        L.append(f"  matched                       {c['matched_total']:>6,}")
        for k, v in c["matched_pairs"].items():
            L.append(f"    {k:<26} {v:>6,}")
        L.append(f"  WellaPath unmatched (legacy)  {c['wellapath_unmatched_legacy_review']:>6,}")
        L.append(f"  NHFR unmatched (candidates)   {c['nhfr_unmatched_candidate_additions']:>6,}")
        for k, v in c["conflicts_on_matched_pairs"].items():
            L.append(f"    conflict {k:<22} {v:>6,}")
        L.append("")
    L.append("Proposed new coverage")
    for s, c in report["proposed_new_coverage"].items():
        L.append(f"  {s:<8} {c['nhfr_records']:>8,}")
    L.append("")
    L.append("Contacts across the five states (counts only)")
    for k, v in report["contacts_five_states"]["classification"].items():
        L.append(f"  {k:<38} {v:>7,}")
    L.append("")
    L.append("Ambulance field")
    for k, v in report["ambulance_five_states"]["field_values"].items():
        L.append(f"  {k:<38} {v:>7,}")
    L.append("  shortlist by state: " + str(report["ambulance_five_states"]["shortlist_size_by_state"]))
    L.append("")
    L.append("Offline impact (contact-free candidate)")
    L.append(f"  current artifact        {cur_b:>10,} B   {cur_n:>6,} records")
    L.append(f"  candidate, three states {three_b:>10,} B   {three_n:>6,} records")
    L.append(f"  candidate, five states  {five_b:>10,} B   {five_n:>6,} records")

    text = "\n".join(L)
    (out / "nhfr_crosswalk.txt").write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
