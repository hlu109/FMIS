/*==============================================================================
 	FMIS data exploration
 	Hannah Lu 
	02/25/2026

	This script exports a smaller version of the FMIS receipts and 
	projects-level data with fewer variables for faster data loading.
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

* load receipt-level data 
use "$intermediate_data/receipt_level_FMIS.dta", clear
drop projecttitle projectdescription completedate authconstdate recipientremarks divisionremarks nongis_countyid gisbreakdown_countyid gis_routeid gisbreakdown_countyid

save "$intermediate_data/receipt_level_FMIS_lite.dta", replace


* load projects-level data 
use "$intermediate_data/project_level_FMIS.dta", clear
drop projecttitle projectdescription completedate authconstdate recipientremarks divisionremarks nongis_countyid gisbreakdown_countyid gis_routeid

save "$intermediate_data/project_level_FMIS_lite.dta", replace
