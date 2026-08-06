# FMIS Title Endpoint Extraction Prompt

You are given a JSON object containing the title of a highway construction project, along with state and county metadata. Your task is to extract structured location information about the project's main route and endpoints, following the schema defined in the `Project`, `MainRoute`, and `Endpoint` data classes.

Do not omit or hallucinate fields. If information is not present or easily inferrable from a field, return `null` rather than guessing.


## Input

You will receive a JSON object containing::
- `project_title` (string): the full FMIS title
- `state_fips` (string): the two-digit state FIPS code where the project is located
- `state_name` (string): the state name resolved from `state_fips` 
- `county_fips` (string): the 5-digit FIPS code for the dominant county where the project is located
- `county_name` (string): the county name resolved from `county_fips`
- `route_fpn` (integer or null): metadata with the main route number extracted from an alternate source. If a highway in the title matches this number, treat it as strong evidence that highway is the main route and do **not** code it as an endpoint. Do **NOT** use `route_fpn` to populate `main_route` fields if the route does not appear in the title text.


## Title-level flags

Set these first. If any is `True`, set `main_route`, `endpoint_a`, and `endpoint_b` all to `null`.

- `statewide`: `True` if the title explicitly states the project applies statewide, districtwide, or to an entire road system.
- `various_locs_unspecified`: `True` if the title uses the keyword "various" to describe locations without specifying them.
- `multi_locs_specified`: `True` if the title references multiple discrete, non-contiguous locations that are at least partially identifiable (e.g., "AT I-80 & I-29 AND AT I-480 & US-6", "REPLACE BRIDGES #237, #241, AND #255"). A single contiguous segment described by two endpoints is NOT multi-location.


## Main route extraction

Identify the main route: the highway on which the project takes place. Set `main_route` to `null` if any title-level flag is `True`, or if the main route cannot be identified using the title, input metadata, and context about the US highway system. Do **NOT** backfill from `route_fpn`. (You may only use `route_fpn` if you need it to resolve concurrent designations, alternate names, or vanity names.)

The main route often appears at the start of the title, written in one of these forms:
- `I-80` — dash separator (most common)
- `I 80` — space separator
- `I80` — no separator
- `IR 80` — "Interstate Route" abbreviation
- `IH 80` — "Interstate Highway" abbreviation
- `FAI 80` — "Federal Aid Interstate" abbreviation
- `ON I-80 FROM ...` — preceded by "ON"
However, it is also possible that the main route is present but does not appear at the start. 

It is also possible that the main route is referred to by an alternate name or vanity name rather than the route number. Think of `route_designation` as the cleaned and standardized version of the raw text while `route_type` and `route_num` reflect the canonical, present-day parsed data. They may differ when the title uses a concurrent designation, an alternate/vanity name, or a historically renumbered route.

Finally, it is possible that the main route is absent from the title, in which case, return `null`. **If the main route is absent, DO NOT use `route_fpn` to backfill the information.**

**Do not promote an endpoint anchor to main route.** A highway that appears only as a cross-feature within an endpoint reference — e.g., after "from", "to", "at", or as an offset anchor — is serving as a location landmark, not as the main route. 

**route_designation**: Expand abbreviations from the title into a clean, geocodable phrase. Do NOT infer any other geographic context. If a named route, vanity name, or alternate name is given instead of a route number, capture the name used in the title rather than the primary name. (E.g., if a title says `"Baltimore Beltway"`, capture `"Baltimore Beltway"` instead of Interstate 695.)

**route_type**: The canonical, modern day, highest-class highway classification. Options include:
- `interstate`: Interstate highway (`I-XX`, `IR XX`, `IH XX`, `FAI XX`)
- `us_route`: US numbered route (`US-XX`)
- `state_route`: State highway or state route (`SR`, `SH`, `TH`, and other state-specific prefixes)
- `local_road`: County road, township road, or named local road
- `other`: Other route type not covered above

**route_num**: The canonical, modern-day numeric route number of the highest class route designation. Do **NOT** backfill from `route_fpn`. You may only use `route_fpn` to help resolve cases where an alternate name or vanity name is given. 

Use the provided `state_name`, `county_name`, and `route_fpn` to help resolve concurrent designations, alternate or vanity names, and apply historical renumbering knowledge in `route_type` and `route_num`. E.g., 
- Concurrent routes: If the main route is a state/US route that runs concurrently with a higher-class route in that state, populate `route_type` and `route_num` with the higher-class route. 
- Renumbered routes: If the route in the title was historically renumbered, use the current route and number in `route_type` and `route_num`. The original designation still goes in `route_designation`.


## Endpoint extraction

If none of the title-level flags are activated, search for endpoints, identified by location references in the title. It is possible that zero, one, or two endpoints are found. Populate any missing endpoints as `null`. 


### Field-by-field instructions

**endpoint_cleaned**: Expand abbreviations from the title into a clean, geocodable phrase. Do NOT infer any other geographic context (e.g., do not guess which county an exit is in, do not guess a city based on a route, do not guess neighborhoods). 

Do not include terms like "interchange", "junction", or "intersection". These are implicit in the precision level and anchor_type coding.

**precision**: Assign based on the most precise information present:
- `6` = linear reference (milepost, log mile, SLM, reference post, KM post, Ohio coded, station)
- `5` = exit number
- `4` = intersection or crossing with a named feature (road, highway, river, railroad, named bridge, boundary line of county/state, etc.)
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
- `state_line`: state boundary (S.L., STATE LINE, S/L). Also code international boundaries as a state boundary.
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

**cross_feature_name**: The name of the intersecting feature, applicable only when `precision == 4`. E.g., road name, highway name, river name, railroad name, bridge name, etc. For county/state lines, format it as e.g., "Franklin County Line", "Ohio State Line".

**offset_dist**, **offset_unit**, **offset_direction**: Applicable only when `precision == 2` or `precision == 3`. Extract the numeric distance, unit (e.g., "mi", "km", "ft"), and cardinal direction. If "NEAR" or "NR" appears with no numeric distance, leave `offset_dist` and `offset_direction` as `null` and set `offset_qualifier = "near"`.

**offset_qualifier**:
- `"exact"`: a specific numeric distance is given ("0.5 MI N OF ...")
- `"approx"`: the distance is qualified as approximate ("APPROXIMATELY 3 MI N OF ...")
- `"near"`: the title uses "NEAR" or "NR" with no measurable distance ("NEAR TREMONTON")


## Extraction rules

1. **DO NOT HALLUCINATE.** NOT ALL FIELDS CAN BE FILLED. Return `null` if a field is not supported directly by the title text is inferrable using the title, input metadata, and prior knowledge about the American highway system. Do not infer locations that are not present in the title. Do not make up information to fill in geographic context (e.g., do not guess which township an exit is in, do not guess a county based on a route).

2. **Prefer the most precise anchor available.** But always populate additional location context variables when available. 

3. Information about an endpoint may be scattered across non-adjacent parts of the string. For instance, “FR EXIT 2 TO 4,SPRINGFIELD & YORK TWPS” has two endpoints, “Exit 2 at Springfield Township” and “Exit 4 at York Township”. 


4. **The main route is NOT an endpoint.** The highway that is the main route should be recorded in `main_route`, NOT as `endpoint_a` or `endpoint_b`. Use `route_fpn` as a strong signal: if a highway in the title matches `route_fpn`, it is almost certainly the main route and should NOT be coded as an endpoint. A highway appears as an endpoint *only* when it is a distinct intersecting route that serves as a 'from', 'to', or 'at' landmark. 

5. **Disambiguate dashes carefully.** Only treat a dash as an endpoint delimiter when the surrounding context clearly indicates "from X to Y" (e.g., "CASPER-KAYCEE", “EXIT 5-6”). Dashes may also appear in route numbers, milepoint ranges, compound place names, and project codes.

6. **Ignore work descriptions.** Project titles may include work descriptions (e.g., "DECK OVERLAY", "RESURFACE", "WIDEN", "GRADE", "DRAIN", "PCCT PAVT", "STRS"). 

7. **Do not abbreviate street type suffixes or highway route designations.** E.g., "DR" → "Drive", "I-280" → "Interstate 280", "US 40" → "US Route 40", "SR 267" → "State Route 267".

Examples:
- "0.5 MI N OF SR 267" → "0.5 miles north of State Route 267"
- "CUY IR 480 05.40" → "Milepost 5.40 on Interstate 480"
- "JCT I-10" → "Interstate 10"
- "AT STEVENSON BLVD" → "At Stevenson Boulevard"
- "I-75 OVER BIG PINEY RIVER" → "Interstate 75 over Big Piney River"

8. **Ramps are not exits** and should not be coded as such. 
