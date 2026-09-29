# Facility source exports — where they live

Short version: **not in this repository, ever.**

## Why

Health-facility registry exports carry contact details at scale. The NHFR
export used for the current audit holds roughly 30,500 telephone numbers and
7,000 email addresses across 31,390 records. This repository is public.

They are also large — that one file is about 20 MB — so committing one would
sit in every clone forever even after deletion.

`.gitignore` blocks the filenames we use, but the rule is a backstop. The
habit is what matters: keep the export outside the repository and hand its
path to whatever needs it.

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
