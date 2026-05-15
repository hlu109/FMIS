# FMIS Title Endpoint Extraction Prompt

You are given a JSON object containing the title of a highway construction project, along with state and county metadata. Your task is to extract structured location information about the project's endpoints, following the schema defined in the `Project` and `Endpoint` data classes.

Do not omit or hallucinate fields. If information is not present in the title, return `null` for that field rather than guessing.


## Input

You will receive a JSON object containing::
- `project_title` (string): the full FMIS title
- `state_fips` (integer): the state FIPS code where the project is located
- `state_name` (string): the state name resolved from `state_fips` 
- `county_fips` (integer): the dominant county FIPS code for the project
- `county_name` (string): the county name resolved from `county_fips`
- `route_num` (integer or null): the main route number, if already extracted


## Title-level flags

Set these first. If any is `True`, set both `endpoint_a` and `endpoint_b` to `null`.

- `statewide`: `True` if the title explicitly states the project applies statewide, districtwide, or to an entire road system.
- `various_locs_unspecified`: `True` if the title uses the keyword "various" to describe locations without specifying them.
- `multi_locs_specified`: `True` if the title references multiple discrete, non-contiguous locations that are at least partially identifiable (e.g., "AT I-80 & I-29 AND AT I-480 & US-6", "REPLACE BRIDGES #237, #241, AND #255"). A single contiguous segment described by two endpoints is NOT multi-location.


## Endpoint extraction

If none of the title-level flags are activated, search for endpoints, identified by location references in the title. It is possible that zero, one, or two endpoints are found. Populate any missing endpoints as `null`. 


### Field-by-field instructions

**endpoint_cleaned**: Expand abbreviations from the title into a clean, geocodable phrase. Do NOT infer any other geographic context (e.g., do not guess which county an exit is in, do not guess a city based on a route, do not guess neighborhoods). 

**precision**: Assign based on the most precise information present:
- `6` = linear reference (milepost, log mile, SLM, reference post, KM post, Ohio coded, station)
- `5` = exit number
- `4` = intersection or crossing with a named feature (road, highway, river, railroad, etc.) 
- `3` = offset (distance + direction) from a precise anchor (intersection, exit, milepost)
- `2` = offset from an imprecise named place anchor (city, county, region)
- `1` = named place only (city, county, region)

**anchor_type**: The type of feature being referenced. Options are:
- `milepost`: standard milepost along a route (MP, MM, M.P., MILEPOST)
- `log_mile`: log mile system (LM)
- `slm`: straight line mile (SLM)
- `reference_post`: reference post (RP)
- `km_post`: kilometer post (KM, KMP)
- `ohio_coded_mp`: Ohio's county-coded milepoint format (CCC IR NNN DD.DD, e.g., "CUY IR 480 05.40")
- `station`: civil engineering station number (STA NNN+DD)
- `exit_number`: numbered highway exit
- `highway`: intersection or junction with another highway
- `road`: intersection with a non-highway road
- `railroad_crossing`: crossing with a railroad
- `named_bridge`: named bridge
- `tunnel`: named tunnel
- `county_line`: county boundary (CO.L., CO LINE, C/L)
- `state_line`: state boundary (S.L., STATE LINE, S/L)
- `waterway`: named river, fork, branch, creek, run, brook, etc.
- `other_terrain`: other natural feature not covered above
- `city`: city, town, village, or borough name
- `city_limits`: city boundary
- `county`: county or county-equivalent name
- `region`: multi-county area, DOT district, or other administrative region with no finer resolution
- `other_landmark`: other named built infrastructure not covered above (e.g., toll facility, truck weigh station, rest area)
- `unknown`: anchor is clearly present but its type cannot be determined

**city** / **county**: Populate when explicitly stated in the *title*. Do NOT use county_fips; they may disagree. 

**mile_num**: The numeric milepost value, applicable only when `precision == 6`. 

**exit_num**: The numeric exit value, applicable only when `precision == 5`. 

**cross_feature_name**: The name of the intersecting feature, applicable only when `precision == 4`. E.g., road name, highway name, river name, railroad name. 

**offset_dist**, **offset_unit**, **offset_direction**: Applicable only when `precision == 2` or `precision == 3`. Extract the numeric distance, unit (e.g., "mi", "km", "ft"), and cardinal direction. If "NEAR" or "NR" appears with no numeric distance, leave `offset_dist` and `offset_direction` as `null` and set `offset_qualifier = "near"`.

**offset_qualifier**:
- `"exact"`: a specific numeric distance is given ("0.5 MI N OF ...")
- `"approx"`: the distance is qualified as approximate ("APPROXIMATELY 3 MI N OF ...")
- `"near"`: the title uses "NEAR" or "NR" with no measurable distance ("NEAR TREMONTON")


## Extraction rules

1. **DO NOT HALLUCINATE.** NOT ALL FIELDS CAN BE FILLED. Return `null` if a field is not supported directly by the title text or the input metadata. Do not infer locations that are not present in the title. Do not use prior knowledge to fill in geographic context (e.g., do not guess which township an exit is in, do not guess a county based on a route, do not guess a road's name from its number).

2. **Prefer the most precise anchor available.** But always populate additional location context variables when available. 

3. Information about an endpoint may be scattered across non-adjacent parts of the string. For instance, “FR EXIT 2 TO 4,SPRINGFIELD & YORK TWPS” has two endpoints, “Exit 2 at Springfield Township” and “Exit 4 at York Township”. 


4. **Disambiguate dashes carefully.** Only treat a dash as an endpoint delimiter when the surrounding context clearly indicates "from X to Y" (e.g., "CASPER-KAYCEE", “EXIT 5-6”). Dashes may also appear in route numbers, milepoint ranges, compound place names, and project codes.

5. **Ignore work descriptions.** Project titles may include work descriptions (e.g., "DECK OVERLAY", "RESURFACE", "WIDEN", "GRADE", "DRAIN", "PCCT PAVT", "STRS"). 

6. **Do not abbreviate street type suffixes or highway route designations.** E.g., "DR" → "Drive", "I-280" → "Interstate 280", "US 40" → "US Route 40", "SR 267" → "State Route 267".

Examples:
- "0.5 MI N OF SR 267" → "0.5 miles north of State Route 267"
- "CUY IR 480 05.40" → "Milepost 5.40 on Interstate 480"
- "JCT I-10" → "Junction with Interstate 10"
- "AT STEVENSON BLVD" → "At Stevenson Boulevard"
- "I-75 OVER BIG PINEY RIVER" → "Interstate 75 over Big Piney River"

7. **Ramps are not exits** and should not be coded as such. 









## Output schema

```python
class Project(BaseModel):
    statewide: bool
    various_locs_unspecified: bool
    multi_locs_specified: bool
    endpoint_a: Endpoint | None
    endpoint_b: Endpoint | None

class Endpoint(BaseModel):
    endpoint_cleaned: str | None
    precision: Literal[1, 2, 3, 4, 5, 6] | None
    anchor_type: Literal[
        "milepost", "log_mile", "slm", "reference_post", "km_post",
        "ohio_coded_mp", "station", "exit_number", "highway", "road",
        "railroad_crossing", "named_bridge", "tunnel",
        "county_line", "state_line", "waterway", "other_terrain",
        "city", "city_limits", "county", "region",
        "other_landmark", "unknown"
    ] | None
    city: str | None
    county: str | None
    mile_num: float | None
    exit_num: int | None
    cross_feature_name: str | None
    offset_dist: float | None
    offset_unit: Literal["mi", "km", "ft"] | None
    offset_direction: Literal["N", "S", "E", "W", "NE", "NW", "SE", "SW"] | None
    offset_qualifier: Literal["exact", "near", "approx"] | None
```
