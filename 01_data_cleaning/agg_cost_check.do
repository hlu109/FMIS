/*==============================================================================
 	FMIS data exploration
 	Hannah Lu 
	02/26/2026

	This script checks annual FMIS costs when aggregated from receipts vs from projects. 
==============================================================================*/
* Set user
local user = c(username)
if "`user'" == "andersonkovesci" {
	global output "/Users/andersonkovesci/Dropbox/FHWA cost data/FMIS_graphs"
	global raw_data "/Users/andersonkovesci/Dropbox/FHWA cost data/Data/Raw"
	global intermediate_data "/Users/andersonkovesci/Dropbox/FHWA cost data/Data/Intermediate"
}
else if "`user'" == "hl2266" {
    global output "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data/Output/Hannah"
	global raw_data "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data/Data/Raw"
	global intermediate_data "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data/Data/Intermediate"
}
* add your username and paths here as an else if condition
else {
	 display as error "Set your user"
}
* check that output folders exist and create them if not 
if !direxists("$output") mkdir "$output"
if !direxists("$intermediate_data") mkdir "$intermediate_data"
* ==============================================================================

* load projects-level data
use "$intermediate_data/project_level_FMIS_lite.dta", clear

collapse (sum) total_cost_mills, by(completion_year)
rename total_cost_mills total_cost_projects
tempfile projects_costs_agg
save `projects_costs_agg'

* load receipts-level data
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear

collapse (sum) total_cost_mills, by(completion_year)
rename total_cost_mills total_cost_receipts

merge 1:1 completion_year using `projects_costs_agg', nogen
gen cost_diff = total_cost_projects - total_cost_receipts
gen match_check = cost_diff < 0.000001