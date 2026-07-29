# Geocoding Performance Evaluation

High-level documentation of how we evaluate the FMIS geocoding pipeline. 

## What this does

The geocoding pipeline (`03_geocode_FMIS`) turns FMIS project titles into highway
**segments** — `sf` LINESTRINGs with two endpoints. This module measures how good
those predicted segments are by comparing them against ground-truth segments, and
reports both overall and stratified performance so we can see where geocoding works
well and where it breaks down.

There is no hand-coded validation data (and no capacity to produce it). Instead we
lean on two *objective* ground-truth sources that already encode true segment
locations.

## The two ground-truth sources

| Source | What it is | Ground truth | Extra signal |
|---|---|---|---|
| **PR-511 single-open** | FMIS interstate projects in county×route pairs with exactly one PR-511 opening year ever, giving an unambiguous FMIS↔PR-511 match | PR-511 segment, re-geocoded from its route + milepost endpoints | opening date |
| **FMIS GIS endpoints** | Post-2010 FMIS v5 projects that report `gis_beginpoint`/`gis_endpoint` mileposts along a route | those mileposts snapped onto the route network | — |

Both reduce to the same shape — `(route_id, milepost_start, milepost_end)` snapped
onto a highway route — so a single ground-truth builder handles both.

## How we split the data

Splits are a **label overlay, not a physical partition.** The geocoder still runs on
the entire universe of projects (validation and test projects have to be geocoded too,
or we couldn't score them). A split table simply tags each project:

- **test** — held out; final numbers only, never tuned against.
- **val** — what we iterate the pipeline/prompt against.
- **train** — everything else; unlabeled dev material we can inspect freely
  (`train = universe − val − test`).

Each ground-truth source is split roughly in half into val and test. The split is done
**by geographic cluster** (county×route for PR-511, route/county for GIS) rather than by
individual project, so the same true segment never lands in both halves. Assignments
are frozen via a hash of the cluster key so they stay stable as scope widens.

Here the "model" being validated is really *the developer plus the geocoding pipeline*,
so the point of holding out a test set is to keep us honest and avoid quietly overfitting
our prompts and heuristics to the cases we can see.

## Metrics

All spatial metrics work on either ground-truth source and are computed in a single
projected CRS (**EPSG:5070, CONUS Albers**) so lengths and positions are in meters.

- **Crow-flies error** — geodesic distance between predicted and true endpoints
  (start + end, summed). Simplest; ignores road curvature and overlap.
- **Along-route error** — the same endpoint distances measured *along the highway*
  (via mileposts), so road wiggle is accounted for.
- **Segment IOU** — Jaccard overlap of the two segments' milepost intervals, in [0, 1].
  Captures whether the segments *actually overlap*, not just how far apart their ends are.
- **Length error** — predicted vs true segment length (signed diff, absolute diff, ratio).
- **Temporal penalty** (PR-511 only) — |FMIS completion date − PR-511 opening date|,
  combined with the spatial penalty via a spatially-weighted geometric mean.

All endpoint metrics are orientation-robust: a segment's two ends may be labeled in
either order, so each metric takes the better of the two pairings.

## Layout

```
Code/FMIS_container/
├── utils/geo_utils.R       # shared geo helpers (also used by geocoding): transform to
│                           #   EPSG:5070, LINESTRING -> milepost read-off, and
│                           #   (route_id, mp_start, mp_end) -> LINESTRING on route
└── 04_geocode_eval/
    ├── helpers/                  # metrics, ground-truth builder, splits, eval runner
    ├── main/            # ordered entry points (build GT, build splits, run eval)
    └── tests/              # unit tests for the metric functions

Data/Intermediate/geocode_eval/
├── splits/                 # projectid -> {train,val,test} + strata
├── ground_truth/           # cached snapped GT segments (.gpkg)
├── predictions/<run_id>/   # cached predicted segments + read-off mileposts (.gpkg)
└── metrics/                # flat output CSVs (per-project + summary), no subdirs
```

Cached geometry is stored as **GeoPackage** so it round-trips `sf` (geometry, column
names, types, CRS) losslessly and is openable in any GIS tool.

## Reference data

- **NHPN** (National Highway Planning Network) — the route network segments are snapped
  to and linearly referenced against (`Data/Raw/NHPN/…geojson`). Segments carry
  `ROUTE_ID`, `STFIPS`, `CTFIPS`, and per-segment `BEGIN_POIN`/`END_POINT` mileposts.
- **PR-511** geodata (Brooks/Liscow replication) — source for PR-511 ground-truth
  geometry; re-geocoded against NHPN rather than using the 1-mile-normalized version.

## Open items

- FMIS `route_fpn` ↔ PR-511 `route` crosswalk (needed before the PR-511 test set can be
  materialized; the exact evaluable-project count depends on it).
- Consolidate the ad-hoc input variants under `Data/Intermediate/geocoding/inputs/` into
  one canonical universe table + the split table.
