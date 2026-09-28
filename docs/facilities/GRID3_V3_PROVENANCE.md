# GRID3 Nigeria Health Facilities v3.0 — provenance record

Recorded 2026-09-28. Nothing in this document changes the production facility
artifact. No dataset was downloaded in bulk; the figures below come from the
publisher's metadata and from counting queries against the official feature
service.

## Source

| | |
|---|---|
| Title | GRID3 NGA - Health Facilities v3.0 |
| Landing page | `https://data.grid3.org/datasets/grid3-nga-health-facilities-v3-0` |
| Metadata API | `https://hub.arcgis.com/api/v3/datasets?filter[slug]=GRID3::grid3-nga-health-facilities-v3-0` |
| Feature service | `https://services3.arcgis.com/BU6Aadhn6tbBEdyk/arcgis/rest/services/GRID3_NGA_health_facility_v3_0/FeatureServer/0` |
| Item id | `827e3638dc204f4b9ddbbd19b00954d6_0` |
| Publisher | GRID3 / CIESIN, Columbia University |
| Accessed | 2026-09-28 |
| Record count | **41,778** (confirmed by a count query, matching the metadata) |
| Extent | 2.7137, 4.2820 to 14.6364, 13.8652 (WGS 84) |

The landing page is a JavaScript application and returns no readable content to
a plain fetch. Everything here came from the Hub metadata API and the feature
service, both of which are public and need no account.

## Licence and citation

**CC BY 4.0.** The publisher's own wording:

> Users are free to use, copy, distribute, transmit, and adapt the work for
> commercial and non-commercial purposes, without restriction, as long as clear
> attribution of the source is provided.

Copyright 2026, The Trustees of Columbia University in the City of New York.

Required citation:

> Center for Integrated Earth System Information (CIESIN), Columbia University
> 2026. GRID3 NGA - Health Facilities v3.0. New York: Columbia University.
> https://doi.org/10.7916/s6cq-1q98. Accessed [DAY MONTH YEAR].

Commercial use is permitted and attribution is the only condition, so the
licence is compatible with shipping derived data in the app provided the
attribution appears somewhere a user can reach.

## Limitations, in the publisher's words

These are quoted rather than paraphrased, because the paraphrase is what tends
to get lost between a data pipeline and a product decision.

> The GRID3 NGA - Health Facilities v3.0 dataset is a **non-exhaustive,
> non-validated** geographic representation of health facility points…

> Temporal mismatches exist among the input data and other reference data…
> This may lead to health facilities not being identified or **the erroneous
> inclusion of abandoned health facilities**.

> This dataset **has not been fully validated by government officials or
> in-country stakeholders**.

> CIESIN, Columbia University, its co-authors, and their sponsors **do not
> guarantee the accuracy, reliability, or completeness** of any data provided.

The publisher does separately describe the dataset as "considered operational",
which refers to its fitness as a data product, not to any individual facility
being open.

**Nothing in this dataset establishes that a given facility is currently open,
that its services are available, or that its ownership or level has recently
been checked.** The publisher says the opposite in three places.

## Coverage — the finding that shapes everything else

GRID3 v3.0 covers **24 states**: Abia, Adamawa, Bauchi, Bayelsa, Borno, Delta,
Enugu, FCT Abuja, Gombe, Jigawa, Kaduna, Kano, Katsina, Kebbi, Kogi, Kwara,
Nasarawa, Niger, Ogun, Osun, Oyo, Sokoto, Yobe, Zamfara.

**Lagos is not among them.** Confirmed twice: absent from the publisher's own
state list, and absent from a distinct-values query against the live service.

Set against the artifact the app currently loads:

| State | WellaPath v1.1 | GRID3 v3.0 | |
|---|---:|---:|---|
| Lagos | 2,690 (50.3%) | **0** | not covered |
| Kano | 2,040 (38.2%) | 2,124 | covered |
| FCT | 614 (11.5%) | 1,047 | covered |
| **Total** | **5,344** | 41,778 nationally | |

So GRID3 v3.0 can inform at most **49.7%** of the current dataset, and cannot
touch the largest state. Any refresh built on it alone would leave Lagos on
data of unknown provenance while Kano and FCT moved to a sourced, dated basis —
a split that has to be a deliberate decision rather than a side effect.

## Fields

36 attributes. The ones that matter for this work:

| Field | Why it matters |
|---|---|
| `nhfr_facility_code` | The official National Health Facility Registry code. **Populated on 4,063 of 41,778 records (9.7%)**, so identifier matching is viable for under a tenth of the data and the crosswalk cannot lead with it. |
| `state_standard`, `lga_standard`, `ward_standard` | A real admin hierarchy, which the current artifact lacks |
| `facility_ownership`, `facility_ownership_type` | Public/private, which the current artifact lacks entirely |
| `facility_level`, `facility_type` | A richer taxonomy than the current four values |
| `functional` | Values observed: `Functional`, `Partially Functional`, `Not-Functional`, `Closed`, `Unknown`, and empty |
| `date_created`, `input_data_sources`, `input_data_record_ids` | Per-record provenance |
| `gps_accuracy`, `flag1`–`flag6`, `issues`, `flag_count` | The publisher's own quality flags |

**There is no telephone field and no email field.** GRID3 cannot supply or
refresh contact details, so the 45 phone numbers in the current artifact stay
exactly as unverified as they are today. Any contact refresh needs a different
source and human verification.

## Reproducibility

Both the metadata and the counting queries are plain public HTTP with no
authentication, so every figure here is reproducible:

```
curl 'https://hub.arcgis.com/api/v3/datasets?filter%5Bslug%5D=GRID3::grid3-nga-health-facilities-v3-0'
curl '<feature-service>/query?where=1%3D1&returnCountOnly=true&f=json'
curl '<feature-service>/query?where=1%3D1&outFields=state_standard&returnDistinctValues=true&returnGeometry=false&f=json'
```

A bulk export would use the service's paged query or the Hub download endpoint.
**No bulk download was taken**, because the coverage finding above should be
decided on before 41,778 records are pulled into this project.

## Not a blocker, but a decision

Access, licence, metadata and reproducibility are all fine. GRID3 v3.0 is a
usable source. The open question is not whether it can be used but whether a
refresh that covers half the dataset and excludes the largest state is the
right next step, or whether Lagos needs a source identified first so both move
together.
