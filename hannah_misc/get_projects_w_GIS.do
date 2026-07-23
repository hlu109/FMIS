/*==============================================================================
 	FMIS data processing 
    This script saves a copy of the FMIS project-level data with only the projects that have GIS data. 
==============================================================================*/
* Set user
local user = c(username)
if "`user'" == "andersonkovesci"{
	global output "/Users/andersonkovesci/Dropbox/FHWA cost data/Output/Andy"
	global data "/Users/andersonkovesci/Dropbox/FHWA cost data/Data"
	global raw_data "$data/Raw"
	global intermediate_data "$data/Intermediate"
}
else if "`user'" == "hl2266"{
    global project_root "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data"
    global output "$project_root/Output/Hannah"
    global data "$project_root/Data"
	global raw_data "$data/Raw"
	global intermediate_data "$data/Intermediate"
}
* add your username and paths here as an else if condition
else {
	 display as error "Set your user"
}
* check that output folders exist and create them if not 
if !direxists("$output") mkdir "$output"
if !direxists("$intermediate_data") mkdir "$intermediate_data"

* ==============================================================================

* load FMIS data
use "$intermediate_data/project_level_FMIS.dta", clear

* filter to projects with GIS data
keep if !mi(gis_routeid) | !mi(gis_beginpoint) | !mi(gis_endpoint)

* compute project length using GIS mile points 
gen gis_length = gis_endpoint - gis_beginpoint

duplicates tag gis_routeid recipientid federal_project_number, gen(n_proj_per_routeid)
// duplicates drop gis_routeid recipientid federal_project_number, force
save "$intermediate_data/project_level_FMIS_w_GIS.dta", replace

* ==============================================================================
* filter projects and data view for manual spot checks of the mile points 

keep if gis_length < 10000 // manually drop one observation in which the mile endpoint is 15790. Based on the context of the project and the starting mileage, this is clearly a typo and should probably be 1.579

sum gis_beginpoint
sum gis_endpoint
sum gis_length
sum fp_ic 
sum has_new_construction

keep recipientid federal_project_number projecttitle state_fips gis_routeid gis_beginpoint gis_endpoint gis_length fp_ic has_new_construction county_fips county_name authconstdate completedate completion_year
