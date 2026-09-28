#!/usr/bin/env python3
"""Phase 1 audit of the facilities artifact the app actually loads.

Reproducible and read-only. Takes the artifact path, emits a machine-readable
JSON report plus a short human summary. Facility-level detail stays in the
JSON; the summary carries totals, categories and a handful of non-sensitive
examples, because a human report that reproduces the dataset is a copy of the
dataset.

    python3 scripts/audit/audit_facilities.py <artifact.json> <out-dir>

Nothing here writes to the artifact, the repository or the network.
"""
from __future__ import annotations

import hashlib
import json
import math
import re
import sys
import unicodedata
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

# Nigeria's approximate bounding box, deliberately generous: this is a sanity
# filter for obviously wrong coordinates (0,0, swapped lat/lon, another
# continent), not a border definition.
NG_LAT = (4.0, 14.0)
NG_LON = (2.5, 15.0)

# Coordinates equal to these are almost always a generation bug rather than a
# location.
SUSPECT_POINTS = {(0.0, 0.0)}


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def norm_name(value: str) -> str:
    """Normalisation used for duplicate detection only.

    Lowercase, strip accents, collapse punctuation and whitespace, and drop a
    few extremely common facility words that carry no distinguishing power.
    Deliberately conservative: it is used to FIND candidates for review, never
    to merge anything.
    """
    s = unicodedata.normalize("NFKD", value or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.lower()
    s = re.sub(r"[^a-z0-9]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


STOPWORDS = {"the", "and", "of", "nigeria", "nig"}


def name_key(value: str) -> str:
    toks = [t for t in norm_name(value).split() if t not in STOPWORDS]
    return " ".join(sorted(toks))


def haversine_km(a_lat, a_lon, b_lat, b_lon) -> float:
    r = 6371.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp = math.radians(b_lat - a_lat)
    dl = math.radians(b_lon - a_lon)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(h))


# Structural checks only. A number that parses is not a number that answers.
PHONE_OK = re.compile(r"^\+?[0-9][0-9\s().-]{6,20}[0-9]$")
EMAIL_OK = re.compile(r"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src = Path(sys.argv[1])
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)

    raw = json.loads(src.read_text(encoding="utf-8"))

    # The artifact may be a bare list or an envelope; handle both without
    # guessing which.
    if isinstance(raw, list):
        records, envelope = raw, {}
    elif isinstance(raw, dict):
        envelope = {k: v for k, v in raw.items() if not isinstance(v, list)}
        list_keys = [k for k, v in raw.items() if isinstance(v, list)]
        if len(list_keys) != 1:
            print(f"cannot identify the record list; list-valued keys: {list_keys}")
            return 2
        records = raw[list_keys[0]]
        envelope["_record_list_key"] = list_keys[0]
    else:
        print("unexpected top-level JSON type")
        return 2

    report: dict = {
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "artifact": {
            "path": str(src),
            "sha256": sha256_of(src),
            "bytes": src.stat().st_size,
        },
        "envelope": envelope,
        "record_count": len(records),
    }

    # ── field inventory ───────────────────────────────────────────────────
    field_present = Counter()
    field_nonempty = Counter()
    field_types: dict[str, Counter] = defaultdict(Counter)
    for r in records:
        if not isinstance(r, dict):
            continue
        for k, v in r.items():
            field_present[k] += 1
            field_types[k][type(v).__name__] += 1
            if v not in (None, "", [], {}):
                field_nonempty[k] += 1
    report["fields"] = {
        k: {
            "present": field_present[k],
            "non_empty": field_nonempty[k],
            "types": dict(field_types[k]),
        }
        for k in sorted(field_present)
    }

    def pick(rec: dict, *names):
        for n in names:
            if n in rec and rec[n] not in (None, ""):
                return rec[n]
        return None

    # ── coverage ──────────────────────────────────────────────────────────
    by_state = Counter()
    by_lga = Counter()
    by_ownership = Counter()
    by_level = Counter()
    for r in records:
        by_state[str(pick(r, "state", "state_name", "admin1") or "«missing»")] += 1
        lga = pick(r, "lga", "lga_name", "admin2")
        by_lga[f"{pick(r,'state','state_name') or '«missing»'} / {lga or '«missing»'}"] += 1
        by_ownership[str(pick(r, "ownership", "owner", "sector") or "«missing»")] += 1
        by_level[str(pick(r, "level", "type", "facility_type", "category") or "«missing»")] += 1

    report["coverage"] = {
        "by_state": dict(by_state.most_common()),
        "by_ownership": dict(by_ownership.most_common()),
        "by_level": dict(by_level.most_common()),
        "lga_count": len([k for k in by_lga if "«missing»" not in k]),
        "by_lga_top_25": dict(by_lga.most_common(25)),
    }

    # ── contact presence and structure ────────────────────────────────────
    phones = emails = phone_bad = email_bad = 0
    bad_phone_examples: list[str] = []
    for r in records:
        p = pick(r, "phone", "telephone", "phone_number", "contact_phone")
        if p:
            phones += 1
            if not PHONE_OK.match(str(p).strip()):
                phone_bad += 1
                if len(bad_phone_examples) < 5:
                    # Shape only, digits masked: a malformed number is still
                    # someone's number.
                    bad_phone_examples.append(re.sub(r"\d", "#", str(p))[:40])
        e = pick(r, "email", "contact_email")
        if e:
            emails += 1
            if not EMAIL_OK.match(str(e).strip()):
                email_bad += 1

    report["contacts"] = {
        "records_with_phone": phones,
        "records_with_email": emails,
        "phone_structurally_invalid": phone_bad,
        "email_structurally_invalid": email_bad,
        "phone_shape_examples_masked": bad_phone_examples,
        "note": "Structure only. A number that parses is not a number that answers.",
    }

    # ── coordinates ───────────────────────────────────────────────────────
    missing_coords = invalid_coords = outside_ng = suspect = 0
    pts: list[tuple[float, float, int]] = []
    for i, r in enumerate(records):
        lat = pick(r, "lat", "latitude", "y")
        lon = pick(r, "lon", "lng", "longitude", "x")
        if lat is None or lon is None:
            missing_coords += 1
            continue
        try:
            la, lo = float(lat), float(lon)
        except (TypeError, ValueError):
            invalid_coords += 1
            continue
        if math.isnan(la) or math.isnan(lo) or abs(la) > 90 or abs(lo) > 180:
            invalid_coords += 1
            continue
        if (round(la, 4), round(lo, 4)) in SUSPECT_POINTS:
            suspect += 1
        if not (NG_LAT[0] <= la <= NG_LAT[1] and NG_LON[0] <= lo <= NG_LON[1]):
            outside_ng += 1
        pts.append((la, lo, i))

    report["coordinates"] = {
        "missing": missing_coords,
        "structurally_invalid": invalid_coords,
        "outside_nigeria_bbox": outside_ng,
        "suspect_null_island": suspect,
        "usable": len(pts),
        "bbox_used": {"lat": NG_LAT, "lon": NG_LON, "note": "generous sanity filter, not a border"},
    }

    # ── duplicates ────────────────────────────────────────────────────────
    exact_key = Counter()
    for r in records:
        exact_key[
            (
                name_key(str(pick(r, "name", "facility_name") or "")),
                norm_name(str(pick(r, "state", "state_name") or "")),
                norm_name(str(pick(r, "lga", "lga_name") or "")),
            )
        ] += 1
    exact_dupes = {k: v for k, v in exact_key.items() if v > 1 and k[0]}

    # Near-duplicates: same normalised name key, same state, within 2 km.
    near = 0
    by_key: dict[tuple, list[tuple[float, float, int]]] = defaultdict(list)
    for la, lo, i in pts:
        r = records[i]
        by_key[
            (
                name_key(str(pick(r, "name", "facility_name") or "")),
                norm_name(str(pick(r, "state", "state_name") or "")),
            )
        ].append((la, lo, i))
    for key, group in by_key.items():
        if not key[0] or len(group) < 2:
            continue
        for a in range(len(group)):
            for b in range(a + 1, len(group)):
                if haversine_km(group[a][0], group[a][1], group[b][0], group[b][1]) <= 2.0:
                    near += 1

    report["duplicates"] = {
        "exact_name_state_lga_groups": len(exact_dupes),
        "exact_name_state_lga_extra_records": sum(v - 1 for v in exact_dupes.values()),
        "near_duplicate_pairs_same_name_within_2km": near,
        "method": "normalised name key (accent-stripped, punctuation-collapsed, "
        "token-sorted, common words dropped) plus state/LGA; near-duplicates "
        "additionally require 2 km proximity. Candidates for review only.",
    }

    # ── provenance fields ─────────────────────────────────────────────────
    prov_names = [
        "source",
        "source_version",
        "source_updated_at",
        "updated_at",
        "last_verified",
        "verified_at",
        "contact_verified_at",
        "verification_method",
        "operational_status",
        "contact_status",
        "confidence",
    ]
    present = {n: field_nonempty.get(n, 0) for n in prov_names}
    report["provenance_fields"] = {
        "expected": prov_names,
        "present_non_empty": {k: v for k, v in present.items() if v},
        "absent": [k for k, v in present.items() if not v],
        "records_with_no_source_information": len(records)
        - max([present.get("source", 0), present.get("source_version", 0)] or [0]),
    }

    (out / "facility_audit.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    # ── human summary ─────────────────────────────────────────────────────
    L = []
    L.append(f"Artifact      {src.name}")
    L.append(f"sha256        {report['artifact']['sha256']}")
    L.append(f"bytes         {report['artifact']['bytes']:,}")
    L.append(f"records       {report['record_count']:,}")
    L.append("")
    L.append("By state")
    for k, v in list(by_state.most_common()):
        L.append(f"  {k:<28} {v:>6,}")
    L.append(f"  distinct LGAs (named)        {report['coverage']['lga_count']:>6,}")
    L.append("")
    L.append("By ownership")
    for k, v in by_ownership.most_common(8):
        L.append(f"  {k:<28} {v:>6,}")
    L.append("")
    L.append("By level / type")
    for k, v in by_level.most_common(10):
        L.append(f"  {k:<28} {v:>6,}")
    L.append("")
    L.append("Contacts")
    L.append(f"  with a phone number          {phones:>6,}")
    L.append(f"  with an email address        {emails:>6,}")
    L.append(f"  phone structurally invalid   {phone_bad:>6,}")
    L.append(f"  email structurally invalid   {email_bad:>6,}")
    L.append("")
    L.append("Coordinates")
    L.append(f"  usable                       {len(pts):>6,}")
    L.append(f"  missing                      {missing_coords:>6,}")
    L.append(f"  structurally invalid         {invalid_coords:>6,}")
    L.append(f"  outside the Nigeria bbox     {outside_ng:>6,}")
    L.append(f"  at 0,0                       {suspect:>6,}")
    L.append("")
    L.append("Duplicates (review candidates, not merges)")
    L.append(f"  exact name+state+LGA groups  {len(exact_dupes):>6,}")
    L.append(f"  extra records in those       {sum(v-1 for v in exact_dupes.values()):>6,}")
    L.append(f"  near-dupe pairs within 2 km  {near:>6,}")
    L.append("")
    L.append("Provenance fields present")
    L.append(f"  {report['provenance_fields']['present_non_empty'] or 'none'}")
    L.append(f"  absent: {', '.join(report['provenance_fields']['absent'])}")
    L.append("")
    L.append("Fields in the record shape")
    for k, v in report["fields"].items():
        L.append(f"  {k:<24} present {v['present']:>5,}  non-empty {v['non_empty']:>5,}  {v['types']}")

    text = "\n".join(L)
    (out / "facility_audit.txt").write_text(text + "\n", encoding="utf-8")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
