/*==============================================================================
 	FMIS data processing 
    This script cleans and saves the receipt-level FMIS data. 
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
* Receipt-level data
* ==============================================================================

* Import raw FMIS data and gen common variables. 
import delimited "$data/CSVs/combined_data.csv", clear bindquote(strict) varnames(1)

* Completion year for grouping projects/reciepts 
gen completion_year = regexs(1) if regexm(completedate, "/([0-9]{4})$")
destring completion_year, replace

rename federalprojectnumber federal_project_number
* In the variable detail_improvementtype, there is a category (15) called preliminary engineering, which is by far the most common.

* Define improvement labels 
global improvement_lbl_def ///
  0  "N/A" ///
  1  "New Construction Roadway" ///
  2  "4R - Reconstruction (Obsolete)" ///
  3  "4R - Added Capacity" ///
  4  "4R - No Added Capacity" ///
  5  "4R - Maintenance Resurfacing" ///
  6  "4R - Restoration & Rehabilitation" ///
  7  "4R - Maintenance Relocation" ///
  8  "Bridge New Construction" ///
  9  "Bridge Replacement (Obsolete)" ///
  10 "Bridge Replacement - Added Capacity" ///
  11 "Bridge Replacement - No Added Capacity" ///
  12 "Bridge Rehabilitation (Obsolete)" ///
  13 "Bridge Rehabilitation - Added Capacity" ///
  14 "Bridge Rehabilitation - No Added Capacity" ///
  15 "Preliminary Engineering" ///
  16 "Right of Way" ///
  17 "Construction Engineering" ///
  18 "Planning" ///
  19 "Research" ///
  20 "Environmental Only" ///
  21 "Safety" ///
  22 "Rail/Hwy Crossing" ///
  23 "Transit" ///
  24 "Traffic Management/Engineering - HOV" ///
  25 "Vehicle Weight Enforcement Program" ///
  26 "Ferry Boats" ///
  27 "Administration" ///
  28 "Facilities for Pedestrians and Bicycles" ///
  29 "Acquisition of Scenic Easements and Scenic/Historic Sites" ///
  30 "Scenic or Historic Highway Programs" ///
  31 "Landscaping and Other Scenic Beautification" ///
  32 "Historic Preservation" ///
  33 "Rehabilitation/Operation of Historic Transportation Buildings etc." ///
  34 "Preservation of Abandoned Railway Corridors" ///
  35 "Control and Removal of Outdoor Advertising" ///
  36 "Archaeological Planning & Research" ///
  37 "Mitigation of Water Pollution due to Highway Runoff" ///
  38 "Safety and Education for Peds/Bicyclists" ///
  39 "Establishment of Transportation Museums" ///
  40 "Special Bridge" ///
  41 "Youth Conservation Service" ///
  42 "Training" ///
  43 "Utilities" ///
  44 "Other" ///
  45 "Debt Service" ///
  46 "Design-Build Contract (Obsolete)" ///
  47 "Bridge Preventive Maintenance" ///
  48 "Bridge Protection" ///
  49 "Bridge Inspection and Bridge Related Training" ///
  50 "New Tunnel" ///
  51 "Tunnel Replacement" ///
  52 "Tunnel Rehabilitation" ///
  53 "Tunnel Preventive Maintenance" ///
  54 "Tunnel Protection" ///
  55 "Tunnel Inspection and Tunnel Related Training" ///
  56 "Other Asset Inspection" ///
  57 "Safety - Non Infrastructure" ///
  58 "Freight" ///
  59 "Bridge Resurfacing" ///
  60 "Highway Infrastructure Preventive Maintenance" ///
  61 "Routine Maintenance" ///
  62 "Operations" ///
  63 "Electric Vehicle & Charging Infrastructure" ///
  64 "Other Alternative Fuel Vehicles & Infrastructure" ///
  65 "Resilience Planning" ///
  66 "Resilience Improvement - Highway Project" ///
  67 "Resilience Improvement - Transit or Port Projects" ///
  68 "Resilience Improvement - Natural Infrastructure" ///
  69 "Community Resilience and Evacuation Routes" ///
  70 "At-Risk Coastal Infrastructure - Highway Project" ///
  71 "At-Risk Coastal Infrastructure - Transit or Port Projects" ///
  72 "At-Risk Coastal Infrastructure - Natural Infrastructure"
label define improvement_lbl $improvement_lbl_def, replace
label values detail_improvementtype improvement_lbl

* Create total cost variable, costs are either gis, or nongis. 
gen total_cost = nongis_totalcost 
replace total_cost = gis_totalcost if total_cost == . 
gen total_cost_mills = total_cost / 1000000 

* Add costs by level of government or other source
gen federal_funds = nongis_federalfunds
replace federal_funds = gis_federalfunds if federal_funds == .
gen state_funds = nongis_statefunds
replace state_funds = gis_statefunds if state_funds == .
gen local_funds = nongis_localfunds
replace local_funds = gis_localfunds if local_funds == .
gen private_funds = nongis_privatefunds
replace private_funds = gis_privatefunds if private_funds == .
gen nonmonetary_funds = nongis_nonmonetaryfunds
replace nonmonetary_funds = gis_nonmonetaryfunds if nonmonetary_funds == .
gen other_funds = nongis_otherfunds
replace other_funds = gis_otherfunds if other_funds == .
* check if total cost is equal to the sum of fund breakdown (account for small rounding errors)
gen total_funds_equal = abs(federal_funds + state_funds + local_funds + private_funds + nonmonetary_funds + other_funds - total_cost) < 1
tab total_funds_equal
* TODO: maybe move this to a separate do file for data checks? and export the output to a csv?


* Define Regions
gen region = ""
replace region = "Northeast" if inlist(recipientid, 9,23,25,33,44,50,34,36,42)
replace region = "Midwest" if inlist(recipientid, 17,18,26,39,55,19,20,27,29,31,38,46)
replace region = "South" if inlist(recipientid, 10,11,12,13,24,37,45,51,54,1,21,28,47,5,22,40,48)
replace region = "West" if inlist(recipientid, 2,4,6,8,15,16,30,32,35,41,49,53,56)

* Get Functional System and System Code 
gen functional_system = gisbreakdown_functionalsystem
replace functional_system = nongis_functionalsystem if functional_system == .
gen system_code = gisbreakdown_systemcode
replace system_code = nongis_systemcode if system_code == .

global functional_system_lbl_def ///
    0  "No Functional System" ///
    1  "Interstate" ///
    2  "PA - Other Freeways & Expressways" ///
    3  "PA - Other" ///
    4  "Minor Arterial" ///
    5  "Major Collector" ///
    6  "Minor Collector" ///
    7  "Local"
label define functional_system_lbl $functional_system_lbl_def, replace
label values functional_system functional_system_lbl
global system_code_lbl_def ///
    0  "Undefined" ///
    1  "Interstate" ///
    2  "NHS Non-Interstate" ///
    3  "Other Federal-Aid Highway" ///
    4  "Not on any Federal-Aid System"
label define system_code_lbl $system_code_lbl_def, replace
label values system_code system_code_lbl

gen interstate_functional = functional_system == 1
gen interstate_syscode = system_code == 1

* Reformat the detail_lastactiondate variable 
gen detail_lastactiondate_temp = regexs(0) if regexm(detail_lastactiondate, "([0-9]{2}/[0-9]{2}/[0-9]{4})")
gen detail_lastactiondate_numeric = date(detail_lastactiondate_temp, "MDY")
format detail_lastactiondate_numeric %tdCCYY-NN-DD
drop detail_lastactiondate_temp detail_lastactiondate
rename detail_lastactiondate_numeric detail_lastactiondate

rename nepaclassofaction nepa_class
rename nepaclassofactiondecisiondate nepa_decision_date

* export 
keep recipientid projectstatus projecttitle detail_lastactiondate detail_linenumber projectdescription total_cost_mills federal_funds state_funds local_funds private_funds nonmonetary_funds other_funds completedate authpedate authrowdate authconstdate authsprdate authotherdate nepa_class nepa_decision_date recipientremarks divisionremarks detail_prefix nongis_countyid gisbreakdown_countyid gis_routeid detail_improvementtype completion_year federal_project_number region functional_system system_code interstate_functional interstate_syscode
save "$intermediate_data/receipt_level_FMIS.dta", replace

* also export lite version 
drop projecttitle projectdescription completedate authconstdate recipientremarks divisionremarks nongis_countyid gisbreakdown_countyid gis_routeid gisbreakdown_countyid

save "$intermediate_data/receipt_level_FMIS_lite.dta", replace

exit

* ==============================================================================
* Project-level data
* ==============================================================================
use "$intermediate_data/receipt_level_FMIS.dta", clear

* Collapse to the project level, and save
* aggregate the improvement types to the project level, and count number of reciepts
tostring detail_improvementtype, gen(proj_improv_types)
bysort federal_project_number recipientid: gen strL alltypes = proj_improv_types[1]
bysort federal_project_number recipientid: replace alltypes = alltypes[_n-1] + "; " + proj_improv_types if _n>1 & proj_improv_types != ""
by federal_project_number recipientid: replace alltypes = alltypes[_N]
	
gen receipts = 1 // this is used for reciept counts

* add interstate_functional and interstate_syscode to the project-level data
collapse (sum) receipts total_cost_mills federal_funds state_funds local_funds private_funds nonmonetary_funds other_funds (firstnm) region projectstatus projecttitle projectdescription completedate authconstdate recipientremarks divisionremarks detail_prefix nongis_countyid gisbreakdown_countyid gis_routeid (lastnm) alltypes completion_year (max) interstate_functional interstate_syscode, by(federal_project_number recipientid)

label variable interstate_functional "True if at least one receipt is interstate"
label variable interstate_syscode "True if at least one receipt is interstate"

save "$data/Intermediate/project_level_FMIS.dta", replace

* also export lite version
drop projecttitle projectdescription completedate authconstdate recipientremarks divisionremarks nongis_countyid gisbreakdown_countyid gis_routeid

save "$intermediate_data/project_level_FMIS_lite.dta", replace
