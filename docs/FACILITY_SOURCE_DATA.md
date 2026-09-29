# Facility source exports — where they live

Short version: **not in this repository, ever.**

## Why

**This is prospective protection, not breach remediation.** No personal-data
breach was established, and no registry export has ever been committed to this
repository — verified with `git log --all`. The rule exists so that a stray
`git add -A` cannot publish one.

The NHFR export is withheld for a licensing reason. Its redistribution terms
were never captured: the registry publishes no licence and no terms of use,
and its only public rights statement reserves all rights to the Federal
Ministry of Health. Written permission is required before it, or
facility-level records derived from it, may be redistributed.

It also carries contact details at scale — roughly 30,500 telephone numbers
and 7,000 email addresses across 31,390 records — and this repository is
public. No named individual appears in it, and its officer-contact columns
(`verified_email`, `validated_mobile`, `published_email`, and four others) are
empty across every row. So the contact volume is a reason for care, not
evidence of exposure.

It is large, too: about 20 MB, which would sit in every clone forever even
after deletion.

`.gitignore` blocks the filenames we use, but the rule is a backstop. The
habit is what matters: keep the export outside the repository and hand its
path to whatever needs it.

## Licensed public datasets may stay tracked

This rule targets **private** exports with unestablished terms. It does not
apply to licensed public datasets, which belong in the repository wherever
their attribution and redistribution requirements are satisfied:

| Dataset | Licence | Status |
|---|---|---|
| GRID3 NGA Health Facilities v2.0 | CC BY 4.0 | May stay tracked, with attribution |
| HOTOSM Nigeria Health Facilities | ODbL 1.0 | May stay tracked, with attribution and share-alike |
| NHFR export | none published; all rights reserved | Withheld pending written permission |

The `.gitignore` rule carries explicit negations for `grid3_*` and `hotosm_*`
so it can never block one of them by accident.

## Where to keep them

Anywhere outside every Git working tree and outside cloud-synced folders. A
directory that works:

```
~/wellapath-private-data/nhfr/
```

Use `chmod 700` on the directory and `chmod 600` on the files. On macOS, note
that `~/Documents` and `~/Desktop` are usually iCloud-synced, so they are not
suitable.

## How scripts reach them

Every audit script takes the path as an argument, or reads the directory from
`WELLAPATH_PRIVATE_DATA`. No script hardcodes a personal path.

```bash
export WELLAPATH_PRIVATE_DATA=~/wellapath-private-data

python3 scripts/audit/nhfr_crosswalk.py \
  --wellapath /path/to/facilities.ng.v1.1.json \
  --out /tmp/facility-audit
```

With `WELLAPATH_PRIVATE_DATA` set, `--nhfr` defaults to
`$WELLAPATH_PRIVATE_DATA/nhfr/nigeria_health_facilities.csv`. Pass `--nhfr`
explicitly to override it.

## What may be committed

Derived artifacts only, and only when they are contact-free:

- aggregate counts, distributions and totals;
- field inventories and schema descriptions;
- crosswalk classification totals;
- provenance records: source, checksum, record count, access method.

## What may not

- The export itself, in any format.
- Facility-level records, extracted or reshaped.
- Any telephone number, email address or website from a registry.
- An ambulance or contact shortlist carrying anything beyond identifiers.

If a report would be less useful without a contact in it, the report is wrong,
not the rule.

## Provenance

Record where an export came from at the time you obtain it: source URL, access
timestamp, any terms shown, and the file's SHA-256. An export whose origin was
not recorded is usable for analysis and not for production — say so in the
record rather than inferring the origin later from file timestamps or sync
metadata.
