# FMIS Title Endpoint Extraction Prompt

You are given a JSON object containing information about a highway construction project. Your task is to extract structured location information about the project's main route and endpoints, following the schema defined in the `Project`, `MainRoute`, and `Endpoint` data classes.

Do not omit or hallucinate fields. If information is not present or easily inferrable from a field, return `null` rather than guessing.


## Input

You will receive a JSON object containing::
- `project_title`: the full FMIS title
- `project_description` (string or null): the full FMIS description
- `state_fips`: the two-digit state FIPS code where the project is located
- `state_name`: the state name resolved from `state_fips` 
- `county_fips`: the 5-digit FIPS code for the dominant county where the project is located. there may be multiple FIPS codes, which are concatenated by semicolon. 
- `county_name`: the county names resolved from `county_fips`. multiple names are concatenated by semicolon. 
- `route_fpn`: Optional metadata with the main route number extracted from an alternate source. If a highway in the title/description matches this number, treat it as strong evidence that highway is the main route and do **not** code it as an endpoint. Do **NOT** use `route_fpn` to populate `main_route` fields if the route does not appear in the title/description. This variable is not available for non-interstates. 


### Using the title and description together

Read both the `project_title` and `project_description` before extracting anything (henceforth known as the "project text"). The two fields may carry a different piece of the location, such as details for the same reference anchor, and you should assemble the most complete picture from both. Sometimes the title is truncated at a fixed character width, possibly mid-word or mid-number, so the title could end in a corrupted endpoint reference.

If the description describes a larger program, a corridor-wide effort, or an optional future phase that the title does not claim, only extract the project the title describes. 

Note any conflicts in the reasoning flags. 



## High-level flags

**`flags_reasoning`**: Before setting the three flags below, write 1 sentence of reasoning. Quote or paraphrase the specific substring(s) of the project text driving each decision. If the project text could plausibly be read as either single- or multi-location, say so explicitly and explain which reading you chose and why.

Set the flags below after writing `flags_reasoning`. If any is `True`, set `main_route`, `endpoint_a`, and `endpoint_b` all to `null`.

- `statewide`: `True` if the project text explicitly states the project applies statewide, districtwide, or to an entire road system.
- `various_locs_unspecified`: `True` if the project text uses the keyword "various" to describe locations without specifying them.
- `multi_locs_specified`: `True` if the project text references multiple discrete, non-contiguous locations that are at least partially identifiable (e.g., "AT I-80 & I-29 AND AT I-480 & US-6", "REPLACE BRIDGES #237, #241, AND #255"). A single contiguous segment described by two endpoints is NOT multi-location.

**`source`**: whether the location information is derived from the `title`, the `description`, or `both`. 



## Main route extraction

**`route_reasoning`**: Before populating `main_route` (and the segment extent fields below), write 1 sentence explaining how you identify the main route and where in the project text it appears, or why it can't be identified. You may cite `route_fpn` if relevant. You should also consider concurrencies and historical renumberings. 

Identify the main route: the highway on which the project takes place. Set `main_route` to `null` if any high-level flag is `True`, or if the main route cannot be identified using the project text, input metadata, and context about the US highway system. Do **NOT** backfill from `route_fpn`. (You may only use `route_fpn` if you need it to resolve concurrent designations, alternate names, or vanity names. If `route_fpn` differs from `main_route`, treat this as evidence that there may be an alternate name, but only in the case that the `route_fpn` could represent an interstate.)

The main route can belong to 5 roadway types. They often take the below forms (though this is not strict): 

Prefixes may be separated from the number by a dash, a space, periods, or nothing at all (`I-80`, `I 80`, `I80`, `I.80` are the same route).

- **Interstate:** `I`, `IR` (Interstate Route), `IH` (Interstate Highway), `FAI` (Federal Aid Interstate)
- **U.S. Route:** `US`, `U.S.`, `US RT`/`US RTE`/`US HWY`, `USR` (US Route), `USH` (US Highway), `UR` (US Route), `FAP` (Federal Aid Primary)
- **State Route/Highway:** `SR` (State Route/Road), `SH` (State Highway), `STH` (State Trunk Highway), `STA` (State), `RT`/`RTE`/`Route`, `FAS` (Federal Aid Secondary); also postal-abbrev style (`CA 1`, `PA 66`, `NY 17`), Michigan trunklines (`M-1`), and named/lettered routes (`A1A` in FL)
- **Local Road:** `CR`/`C.R.`, `CO RD`/`CO RT`/`CORD`, `County Road`/`Route`/`Highway`, `CH` (County Highway), `CTH` (County Trunk Highway, may be lettered: `CTH A`), `CSAH` (County State Aid Highway), `CFR`/`CS` (state-specific county designations), `TR`/`TWP RD`/`Township Road`/`T-`. Most often there is no route code at all, just a street name (`MAIN ST`, `1ST AVE`).

The main route may be referred to by an alternate or vanity name rather than a route number. `route_type` and `route_num` always hold the canonical, present-day route; the raw designation from the text goes in `alt_names` when it differs.

If the main route is absent from the project text, return `null`. DO NOT use `route_fpn` to backfill the information.

Use the provided `state_name`, `county_name`, and `route_fpn` to help resolve concurrent designations, alternate or vanity names, and apply historical renumbering knowledge in `route_type` and `route_num`. E.g., 
- Concurrent routes: If the main route is a state/US route that runs concurrently with a higher-class route in that state, populate `route_type` and `route_num` with the higher-class route. 
- Renumbered routes: If the route in the project text was historically renumbered, use the modern-day route and number in `route_type` and `route_num`. The original historical designation goes in `alt_names`.


**route_num**: The canonical, modern-day numeric route number of the highest class route designation. Do **NOT** backfill from `route_fpn`. You may only use `route_fpn` to help resolve cases where an alternate name or vanity name is given. DO NOT OMIT THIS if the main route is found in the project text. It is possible for the main route in the project text to differ from `route_fpn`. 

**route_type**: The canonical, modern day, highest-class highway classification. Populate this field using the forms established above:
- `interstate`: Interstate highway (often prefixed with `I`, `IR`, `IH`, or `FAI`, with or without dashes and spaces between the prefix and route number). Alaska and Hawaii have interstates prefixed with an `A` or `H` respectively; do NOT confuse these with state routes. 
- `us_route`: US numbered route (often prefixed with `US`)
- `state_route`: State highway or state route (often prefixed with `SR`, `SH`, `TH`, or other state-specific prefixes)
- `local_road`: County road, township road, or named local road
- `other`: Other route type not covered above

**route_num_match_status**: How the extracted route compares to `route_fpn`:
- `matches_route_fpn`: matches exactly.
- `concurrent_higher_class`: the stated route runs concurrently with a higher-class route in the same location, and `route_type`/`route_num` hold the higher-class route.
- `historical_renumbering`: the text uses a former designation; `route_type`/`route_num` hold the modern one.
- `vanity_or_alt_name`: the text gives only a name, resolved to a route from context.
- `spur_or_business_route`: the stated route is a spur, business loop, or bypass of a different parent corridor than `route_fpn` — physically distinct roads, not one road under two names. Keep the literal route; do not substitute `route_fpn`.
- `other`: any other mismatch, explained in `route_reasoning`.

**alt_names**: A route's vanity name, alternate name, or concurrent route number, if it is explicitly given in addition to, or instead of, a primary route number. If a concurrent, numbered route is given, format this to include both the route type and number. E.g., `"Baltimore Beltway"`, or "Interstate 94" (when given I-90&94, indicating concurrent routes). 


## Endpoint extraction

If none of the high-level flags are activated, search for endpoints, identified by location references anywhere in the project text. It is possible that 0, 1, or 2 endpoints are found. Populate any missing endpoints as `null`.


### Field-by-field instructions

**`reasoning`**: Before populating `endpoint_cleaned` and `loc_refs` for this endpoint, write 1 sentence identifying which substring(s) of the project text describe this endpoint and which field each came from, and briefly justify the `anchor_type` chosen for each `LocationRef` below (especially if more than one ref is found, or if the anchor type/feature is ambiguous).

**`endpoint_cleaned`**: Expand abbreviations from the project text into a clean, geocodable phrase. Do NOT infer any other geographic context (e.g., do not guess which county an exit is in, do not guess a city based on a route, do not guess neighborhoods). 

**`loc_refs`**: Each `LocationRef` independently describes one location reference used to locate the endpoint. The `rel_*` fields describe how the project endpoint is positioned relative to the reference feature. 

**`anchor_type`** — the specific type of feature:

*Linear reference systems:*
- `milepost`: standard milepost (MP, MM, M.P., MILEPOST)
- `log_mile`: log mile (LM)
- `slm`: straight line mile (SLM)
- `reference_post`: reference post (RP)
- `km_post`: kilometer post (KM, KMP)
- `ohio_coded_mp`: Ohio county-coded milepoint (e.g., "CUY IR 480 05.40")
- `station`: civil engineering station (STA NNN+DD)
*Exit numbers:*
- `exit_number`: numbered highway exit
*Intersections / crossings / boundaries (including undercrossings and overpasses):*
- `highway`: another highway (distinct from the main route) that intersects the main route, including (but not limited to) via overpass, undercrossing, intersection, junction, or interchange. Do NOT confuse a state boundary for a state highway. 
- `road`: non-highway road that intersects the main route, including (but not limited to) via intersection, overpass, or undercrossing. 
- `named_junct_interchange`: a specially-named junction or interchange where the junction/interchange has its own vanity name. If the intersecting highway route number is specified, select the `highway` category instead. 
- `railroad_crossing`: railroad
- `named_bridge`: named bridge
- `tunnel`: named tunnel
- `county_line`: county boundary (e.g., CO.L., CO LINE, C/L)
- `state_line`: the boundary of a state, or between two states (e.g., S.L., STATE LINE, S/L). Also code international boundaries as a state boundary. Do NOT confuse this with state routes (state routes should be coded as highways, not state_line). 
- `waterway`: river, fork, branch, creek, run, brook, etc. (including waterway crossings). 
- `city_limits`: city boundary
*Named places — areas, facilities, or terrain features:*
- `city`: city, town, village, borough, etc. 
- `county`: county or county-equivalent
- `dot_district`: a state DOT administrative district or division. Districts may be named after a city that the project is nowhere near. Never code a district as a `city`, `county`, or `region` anchor.
- `region`: multi-city or multi-county area, or other administrative region. 
- `other_terrain`: natural terrain feature not covered above. Do not confuse named regions that sound like terrain features but are actually proper nouns. 
- `other_landmark`: built facility not covered above (toll plaza, weigh station, rest area, unnamed junction or interchange, etc.) Do NOT confuse named junctions/interchanges for other_landmark. Confirm using knowledge of US geography that the anchor is not actually a proper noun like the name of a street, neighborhood, named highway, city, or town. Only use this as a backup if none of the more specific categories apply. 
- `unknown`: anchor is present but type cannot be determined

**`mile_num`**: numeric milepost value; only for linear reference anchor types.

**`exit_num`**: numeric exit number; only when `anchor_type == "exit_number"`.


**`feature_name`**: the name of the reference feature. Write it out fully (do not abbreviate). Used for all anchor types except linear references and exits:
- Highway or road: e.g., `"Interstate 80"`, `"State Route 267"`, `"Stevenson Boulevard"`
- Waterway: e.g., `"Big Piney River"`
- Bridge: e.g., `"Sunshine Skyway Bridge"`
- County/state line: e.g., `"Franklin County Line"`, `"Ohio State Line"`
- City/place/terrain/facility: e.g., `"Denver"`, `"Springfield Township"`, `"Donner Pass"`, `"Rest Area 14"`

**`rel_type`**: how the project endpoint is positioned relative to this reference feature:
- `"at"` — the endpoint is at, on, within, or directly co-located with this feature. (Any relative directions would indicate position inside the area.)
- `"offset"` — the endpoint is at a directional distance from this feature. 
- `"side_of"` — the endpoint is on one side of a linear or boundary feature (e.g., west border of city limits).
- `"near"` — the project text uses 'near' (or abbreviations) with no direction or distance. 

**`rel_direction`**: cardinal direction. Applicable when `rel_type` is `"offset"`, `"side_of"`, or `"at"`. 

**`rel_dist`** and **`rel_dist_unit`**: numeric distance and unit (e.g., `"mi"`, `"km"`, `"ft"`). 

**`rel_qualifier`**: applicable only when `rel_type == "offset"`:
- `"exact"`: a specific numeric distance is given.
- `"approx"`: the distance is approximate.


## Segment extent

**`segment_length`**, **`segment_length_unit`**, **`segment_direction`**: populate when the project text describes the project extent as a directional distance from `endpoint_a` rather than naming a second endpoint. Leave null when no extent information.

- `segment_length`: the numeric distance value
- `segment_length_unit`: the distance unit (`"mi"`, `"km"`, `"ft"`)
- `segment_direction`: the direction of travel from `endpoint_a` toward the unnamed terminus (`N`, `S`, `E`, `W`, `NE`, `NW`, `SE`, `SW`)




## Extraction rules

1. **DO NOT HALLUCINATE.** NOT ALL FIELDS CAN BE FILLED. Return `null` if a field is not supported directly by the project text or inferrable using the project text, input metadata, and prior knowledge about the American highway system. Do not infer locations that are not present in the project text. Do not guess or make up information to fill in geographic context.

2. **Prefer the most precise anchor available.** But always populate additional location context variables when available. 

3. Information about an endpoint may be scattered across non-adjacent parts of the string. For instance, “FR EXIT 2 TO 4,SPRINGFIELD & YORK TWPS” has two endpoints, “Exit 2 at Springfield Township” and “Exit 4 at York Township”. 

4. **Do not confuse the main route with an endpoint anchor.** If a highway in the project text matches `route_fpn`, it is almost certainly the main route. Conversely, a highway appearing only as a cross-feature within an endpoint reference — after "from", "to", "at", a dash, or as an offset anchor — is an endpoint anchor, not the main route. 

5. **Disambiguate dashes carefully.** Only treat a dash as an endpoint delimiter when the surrounding context clearly indicates "from X to Y" (e.g., "CASPER-KAYCEE", “EXIT 5-6”). Dashes may also appear in route numbers, milepoint ranges, compound place names, and project codes.

6. **Do not abbreviate street type suffixes or highway route designations.** E.g., "DR" → "Drive", "I-280" → "Interstate 280", "US 40" → "US Route 40", "SR 267" → "State Route 267".

Examples:
- "0.5 MI N OF SR 267" → "0.5 miles north of State Route 267"
- "CUY IR 480 05.40" → "Milepost 5.40 on Interstate 480"
- "JCT I-10" → "Interstate 10"
- "AT STEVENSON BLVD" → "At Stevenson Boulevard"
- "I-75 OVER BIG PINEY RIVER" → "Interstate 75 over Big Piney River"

7. **Ramps are not exits** and should not be coded as such. 
