import pandas as pd
from pydantic import BaseModel
from typing import Literal, Optional


class MainRoute(BaseModel):
    route_designation: Optional[str] = None
    route_type: Optional[Literal["interstate", "us_route", "state_route", "other"]] = None
    route_num: Optional[int] = None




class Endpoint(BaseModel):
    endpoint_cleaned: Optional[str] = None
    precision: Optional[Literal["1", "2", "3", "4", "5", "6"]] = None
    anchor_type: Optional[Literal[
        "milepost", "log_mile", "slm", "reference_post", "km_post",
        "ohio_coded_mp", "station", "exit_number", "highway", "road",
        "railroad_crossing", "named_bridge", "tunnel",
        "county_line", "state_line", "waterway", "other_terrain",
        "city", "city_limits", "county", "region",
        "other_landmark", "unknown"
    ]] = None
    city: Optional[str] = None
    county: Optional[str] = None
    mile_num: Optional[float] = None
    exit_num: Optional[int] = None
    cross_feature_name: Optional[str] = None
    offset_dist: Optional[float] = None
    offset_unit: Optional[str] = None # should we hard code as mi, km, ft literals? 
    offset_direction: Optional[Literal["N", "S", "E", "W", "NE", "NW", "SE", "SW"]] = None # should we relax to generic string? 
    offset_qualifier: Optional[Literal["exact", "near", "approx"]] = None


class Project(BaseModel):
    statewide: bool
    various_locs_unspecified: bool
    multi_locs_specified: bool
    main_route: Optional[MainRoute] = None
    endpoint_a: Optional[Endpoint] = None
    endpoint_b: Optional[Endpoint] = None

MAIN_ROUTE_FIELDS = list(MainRoute.model_fields.keys())
ENDPOINT_FIELDS = list(Endpoint.model_fields.keys())


def _flatten_main_route(main_route: Optional[MainRoute]) -> dict:
    if main_route is None:
        return {f"main_{field}": None for field in MAIN_ROUTE_FIELDS}
    data = main_route.model_dump()
    return {f"main_{field}": data[field] for field in MAIN_ROUTE_FIELDS}


def _flatten_endpoint(endpoint: Optional[Endpoint], suffix: str) -> dict:
    if endpoint is None:
        return {f"{field}_{suffix}": None for field in ENDPOINT_FIELDS}
    data = endpoint.model_dump()
    return {f"{field}_{suffix}": data[field] for field in ENDPOINT_FIELDS}


def project_to_dataframe(project: Project) -> pd.DataFrame:
    """Flatten a Project into a single-row DataFrame."""
    row = {
        "statewide": project.statewide,
        "various_locs_unspecified": project.various_locs_unspecified,
        "multi_locs_specified": project.multi_locs_specified,
    }
    row.update(_flatten_main_route(project.main_route))
    row.update(_flatten_endpoint(project.endpoint_a, "A"))
    row.update(_flatten_endpoint(project.endpoint_b, "B"))
    return pd.DataFrame([row])
