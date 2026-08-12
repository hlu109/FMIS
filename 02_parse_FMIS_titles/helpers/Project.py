import pandas as pd
from pydantic import BaseModel
from typing import Literal, Optional


class MainRoute(BaseModel):
    route_type: Optional[Literal["interstate", "us_route", "state_route",
                                 "local_road", "other"]] = None
    route_num: Optional[int] = None
    route_num_match_status: Optional[Literal["matches_route_fpn",
                                             "concurrent_higher_class",
                                             "historical_renumbering",
                                             "vanity_or_alt_name",
                                             "spur_or_business_route",
                                             "other"]] = None
    alt_names: Optional[str] = None


# Maximum number of LocationRef entries per endpoint stored in the flat table.
MAX_ANCHORS = 3


class LocationRef(BaseModel):
    """
    A single location reference that helps describe where an endpoint is.
    Can be stacked with other LocationRefs to describe more complex endpoint info.

    Note: the `precision` variable is deterministically derived downstream when converting the Endpoint objects to tabular form based on the anchor type and any relative offset information.
    """
    anchor_type: Optional[Literal["milepost", "log_mile", "slm",
                                  "reference_post", "km_post", "ohio_coded_mp",
                                  "station", "exit_number", "highway", "road",
                                  "named_junct_interchange",
                                  "railroad_crossing", "named_bridge",
                                  "tunnel", "county_line", "state_line",
                                  "waterway", "other_terrain", "city",
                                  "city_limits", "county", "region",
                                  "other_landmark", "unknown"]] = None

    mile_num: Optional[float] = None
    exit_num: Optional[int] = None
    feature_name: Optional[str] = None

    # relative positional information
    rel_type: Optional[Literal["at", "offset", "side_of", "near"]] = None
    rel_direction: Optional[Literal["N", "S", "E", "W", "NE", "NW", "SE",
                                    "SW"]] = None
    rel_dist: Optional[float] = None
    rel_dist_unit: Optional[str] = None  # e.g., "mi", "km", "ft"
    rel_qualifier: Optional[Literal[
        "exact", "approx"]] = None  # only when rel_type == "offset"


class Endpoint(BaseModel):
    reasoning: Optional[str] = None
    endpoint_cleaned: Optional[str] = None
    loc_refs: Optional[list[LocationRef]] = None


class Project(BaseModel):
    flags_reasoning: Optional[str] = None
    statewide: bool
    various_locs_unspecified: bool
    multi_locs_specified: bool
    route_reasoning: Optional[str] = None
    segment_length: Optional[float] = None
    segment_length_unit: Optional[str] = None  # "mi", "km", "ft"
    segment_direction: Optional[Literal["N", "S", "E", "W", "NE", "NW", "SE",
                                        "SW"]] = None
    main_route: Optional[MainRoute] = None
    endpoint_a: Optional[Endpoint] = None
    endpoint_b: Optional[Endpoint] = None


###############################################################################
# Convert Project objects to tabular form
###############################################################################

MAIN_ROUTE_FIELDS = list(MainRoute.model_fields.keys())
REF_FIELDS = list(LocationRef.model_fields.keys())

ANCHOR_TYPE_TO_PRECISION = {
    # 6 — linear references
    "milepost": "6",
    "log_mile": "6",
    "slm": "6",
    "reference_post": "6",
    "km_post": "6",
    "ohio_coded_mp": "6",
    "station": "6",
    # 5 — exit number
    "exit_number": "5",
    # 4 — intersections / crossings / boundaries
    "highway": "4",
    "road": "4",
    "named_junct_interchange": "4",
    "railroad_crossing": "4",
    "named_bridge": "4",
    "tunnel": "4",
    "county_line": "4",
    "state_line": "4",
    "waterway": "4",
    "city_limits": "4",
    # 1 — named places
    "city": "1",
    "county": "1",
    "region": "1",
    "other_terrain": "1",
    "other_landmark": "1",
    # unknown
    "unknown": None,
}


def _flatten_main_route(main_route: Optional[MainRoute]) -> dict:
    if main_route is None:
        return {f"main_{field}": None for field in MAIN_ROUTE_FIELDS}
    data = main_route.model_dump()
    return {f"main_{field}": data[field] for field in MAIN_ROUTE_FIELDS}


def _flatten_endpoint(endpoint: Optional[Endpoint], suffix: str) -> dict:
    prefix = f"ep_{suffix.lower()}"  # e.g., "ep_a" or "ep_b"

    if endpoint is None:
        # return a row with all empty fields
        row = {
            f"{prefix}_reasoning": None,
            f"{prefix}_cleaned": None,
            f"{prefix}_n_refs": None,
            f"{prefix}_max_precision": None,
            f"{prefix}_city": None,
            f"{prefix}_county": None,
        }
        for i in range(MAX_ANCHORS):
            for f in REF_FIELDS:
                row[f"{prefix}_ref{i+1}_{f}"] = None
            row[f"{prefix}_ref{i+1}_precision"] = None
        return row

    refs = endpoint.loc_refs if endpoint.loc_refs is not None else []

    # Pair each ref with its derived precision string so we can sort and reuse it below.
    ref_prec_pairs = []
    for r in refs:
        prec = ANCHOR_TYPE_TO_PRECISION.get(r.anchor_type, None)
        ref_prec_pairs.append((r, prec))

    # Sort highest precision first. Treat None (unknown anchor type) as 0 so it falls last.
    def prec_sort_key(pair):
        prec = pair[1]
        return int(prec) if prec is not None else 0

    ref_prec_pairs.sort(key=prec_sort_key, reverse=True)

    # Also compute the highest precision so it's easier to access later
    max_prec = ref_prec_pairs[0][1] if ref_prec_pairs else None

    row = {
        f"{prefix}_reasoning":
        endpoint.reasoning,
        f"{prefix}_cleaned":
        endpoint.endpoint_cleaned,
        f"{prefix}_n_refs":
        len(refs),
        f"{prefix}_max_precision":
        max_prec,
        # extract city and county as top-level fields in Endpoint object for downstream convenience (if they exist)
        # TODO (low priority): handle endpoints with multiple city refs. Currently takes the first.
        f"{prefix}_city":
        next((r.feature_name for r in refs if r.anchor_type == "city"), None),
        f"{prefix}_county":
        next((r.feature_name for r in refs if r.anchor_type == "county"),
             None),
    }

    for i in range(MAX_ANCHORS):
        if i < len(ref_prec_pairs):
            ref, prec = ref_prec_pairs[i]
            data = ref.model_dump()
        else:
            # if there are fewer refs than MAX_ANCHORS, fill the remaining slots with None
            ref, prec = None, None
            data = {}
        for f in REF_FIELDS:
            row[f"{prefix}_ref{i+1}_{f}"] = data.get(f)
        row[f"{prefix}_ref{i+1}_precision"] = prec
    return row


def project_to_dataframe(project: Project) -> pd.DataFrame:
    """Flatten a Project into a single-row DataFrame."""
    row = {
        "flags_reasoning": project.flags_reasoning,
        "statewide": project.statewide,
        "various_locs_unspecified": project.various_locs_unspecified,
        "multi_locs_specified": project.multi_locs_specified,
        "route_reasoning": project.route_reasoning,
        "segment_length": project.segment_length,
        "segment_length_unit": project.segment_length_unit,
        "segment_direction": project.segment_direction,
    }
    row.update(_flatten_main_route(project.main_route))
    row.update(_flatten_endpoint(project.endpoint_a, "A"))
    row.update(_flatten_endpoint(project.endpoint_b, "B"))
    return pd.DataFrame([row])
