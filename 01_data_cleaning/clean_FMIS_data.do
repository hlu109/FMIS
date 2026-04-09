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

* Define project status 
global projectstatus_lbl_def ///
    1  "State Certification Signature needed" ///
    2  "Unsigned, State Certification Signature needed" ///
    3  "State Recommendation Signature needed" ///
    4  "State Authorization Signature needed" ///
    5  "State Modification Signature needed" ///
    6  "Division Review Signature needed" ///
    7  "Division Recommendation Signature needed" ///
    8  "Division Authorization Signature needed" ///
    10 "Active" ///
    11 "Closed" ///
    12 "Closed Pending Expenditures" ///
    13 "Withdrawn" ///
    14 "Withdrawn Pending Expenditures" ///
    16 "Rejected By Division"
label define projectstatus_lbl $projectstatus_lbl_def, replace
label values projectstatus projectstatus_lbl

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

* add variables related to formula or grant funding 
label variable detail_programcode "Program Code"
// label variable detail_fain "Federal Award Identification Number" // all empty
// label variable detail_grantnumber "Discretionary Grant Award Number" // all empty

* location variables 
gen state_fips = gis_stateid
replace state_fips = nongis_stateid if state_fips == .
* correct mariana islands because the state id is 75 in FMIS but FIPS code is 69 (all other state IDs match census FIPS codes)
replace state_fips = 69 if state_fips == 75 

gen countyid = gisbreakdown_countyid
replace countyid = nongis_countyid if countyid == .
gen county_fips = real(string(state_fips, "%02.0f") + string(countyid, "%03.0f")) ///
    if !mi(state_fips) & !mi(countyid)

global countyid_lbl_def ///
    999  "statewide"
label define countyid_lbl $countyid_lbl_def, replace
label values countyid countyid_lbl

gen urban_rural = nongis_urbanorrural
replace urban_rural = gisbreakdown_urbanorrural if urban_rural == .
global urban_rural_lbl_def ///
    0  "Statewide" ///
    1  "Rural" ///
    2  "Urban"
label define urban_rural_lbl $urban_rural_lbl_def, replace
label values urban_rural urban_rural_lbl

* label county values using external csv mapping from FIPS to name 
tempfile fmis_snap_countylbl
save `fmis_snap_countylbl'
import delimited using "$raw_data/census_county_FIPS_crosswalk.txt", ///
    varnames(1) delimiter("|") stringcols(_all) clear
gen long county_fips_num = real(strtrim(statefp) + strtrim(countyfp))
keep county_fips_num countyname
drop if mi(county_fips_num)
duplicates drop county_fips_num, force
quietly count
local n_co = r(N)
capture label drop county_fips_lbl
label define county_fips_lbl, replace
forvalues i = 1/`n_co' {
    local v = county_fips_num[`i']
    local t = strtrim(countyname[`i'])
    local t_clean : subinstr local t `"""' "", all
    local t80 = substr(`"`t_clean'"', 1, 80)
    label define county_fips_lbl `v' `"`t80'"', add
}
local lbl_build "`c(tmpdir)'/st_county_fips_lbl.do"
label save county_fips_lbl using "`lbl_build'", replace
use `fmis_snap_countylbl', clear
run "`lbl_build'"
capture erase "`lbl_build'"
label values county_fips county_fips_lbl

* label state and recipientid values using external excel mappings

* FMIS_stateid_map.xlsx: two columns (ID, name), no header row
tempfile fmis_snap_state_lbl
save `fmis_snap_state_lbl'

import excel using "$intermediate_data/FMIS_stateid_map.xlsx", clear
unab statecols : _all
local c1 : word 1 of `statecols'
local c2 : word 2 of `statecols'
capture confirm numeric variable `c1'
if _rc {
    destring `c1', gen(_stateid_map) force
    drop `c1'
}
else rename `c1' _stateid_map
rename `c2' _state_lbl
keep _stateid_map _state_lbl
drop if missing(_stateid_map)
duplicates drop _stateid_map, force
quietly count
local _nstate = r(N)
capture label drop stateid_lbl
label define stateid_lbl, replace
forvalues _i = 1/`_nstate' {
    local _v = _stateid_map[`_i']
    local _t = strtrim(_state_lbl[`_i'])
    local _t_clean : subinstr local _t `"""' "", all
    local _t80 = substr(`"`_t_clean'"', 1, 80)
    label define stateid_lbl `_v' `"`_t80'"', add
}
local lbl_state "`c(tmpdir)'/st_stateid_lbl.do"
label save stateid_lbl using "`lbl_state'", replace
use `fmis_snap_state_lbl', clear
run "`lbl_state'"
capture erase "`lbl_state'"
label values state_fips stateid_lbl

* FMIS_recipientid_map.xlsx: header row; col1 = Recipient ID, col2 = Name
tempfile fmis_snap_recip_lbl
save `fmis_snap_recip_lbl'
import excel using "$intermediate_data/FMIS_recipientid_map.xlsx", firstrow clear
unab reccols : _all
local r1 : word 1 of `reccols'
local r2 : word 2 of `reccols'
capture confirm numeric variable `r1'
if _rc {
    destring `r1', gen(_recipid_map) force
    drop `r1'
}
else rename `r1' _recipid_map
rename `r2' _recip_lbl
keep _recipid_map _recip_lbl
drop if missing(_recipid_map)
duplicates drop _recipid_map, force
quietly count
local _nrec = r(N)
capture label drop recipient_lbl
label define recipient_lbl, replace
forvalues _j = 1/`_nrec' {
    local _w = _recipid_map[`_j']
    local _s = strtrim(_recip_lbl[`_j'])
    local _s_clean : subinstr local _s `"""' "", all
    local _s80 = substr(`"`_s_clean'"', 1, 80)
    label define recipient_lbl `_w' `"`_s80'"', add
}
local lbl_recip "`c(tmpdir)'/st_recipientid_lbl.do"
label save recipient_lbl using "`lbl_recip'", replace
use `fmis_snap_recip_lbl', clear
run "`lbl_recip'"
capture erase "`lbl_recip'"
label values recipientid recipient_lbl


* Process the date variables 
* Pull years for relevant date variables
gen completion_year = regexs(1) if regexm(completedate, "/([0-9]{4})$")
destring completion_year, replace
gen finalvoucher_year = regexs(1) if regexm(finalvoucherdate, "/([0-9]{4})")
destring finalvoucher_year, replace
gen latestpayment_year = regexs(1) if regexm(latestpaymentdate, "/([0-9]{4})")
destring latestpayment_year, replace
gen detaillastaction_year = regexs(1) if regexm(detail_lastactiondate, "/([0-9]{4})")
destring detaillastaction_year, replace

* Convert variables to date/numeric class instead of string
foreach d in authsprdate authpedate authrowdate authconstdate authotherdate completedate finalvoucherdate latestpaymentdate lastactiondate transactiondate detail_lastactiondate {
    gen `d'_temp = regexs(0) if regexm(`d', "([0-9]{2}/[0-9]{2}/[0-9]{4})")
    gen `d'_numeric = date(`d'_temp, "MDY")
    format `d'_numeric %tdCCYY-NN-DD
    drop `d'_temp `d'
    rename `d'_numeric `d'
}
label variable projectenddate "Expected end date"
label variable finalvoucherdate "Date of final expenditure or date the final voucher was paid"
label variable latestpaymentdate "Date of most recent expenditure against the project"

// * Add NEPA variables
// rename nepaclassofaction nepa_class
// rename nepaclassofactiondecisiondate nepa_decision_date
// global nepa_class_lbl_def ///
//     0  "Undefined" ///
//     1  "Categorial Exclusions" ///
//     2  "Environmental Assessment" ///
//     3  "Environmental Impact Statement"
// label define nepa_class_lbl $nepa_class_lbl_def, replace
// label values nepa_class nepa_class_lbl
// label variable nepa_class "NEPA Class of Action"
// label variable nepa_decision_date "Decision date for NEPA class of action"


* export 
keep recipientid state_fips county_fips countyid projectstatus projecttitle detail_linenumber projectdescription total_cost_mills federal_funds state_funds local_funds private_funds nonmonetary_funds other_funds authsprdate authpedate authrowdate authconstdate authotherdate completedate finalvoucherdate latestpaymentdate projectenddate lastactiondate transactiondate detail_lastactiondate recipientremarks divisionremarks detail_prefix nongis_countyid gisbreakdown_countyid gis_routeid detail_improvementtype completion_year finalvoucher_year latestpayment_year detaillastaction_year federal_project_number region functional_system system_code interstate_functional interstate_syscode detail_programcode urban_rural
save "$intermediate_data/receipt_level_FMIS.dta", replace

* also export lite version 
drop projecttitle projectdescription recipientremarks divisionremarks nongis_countyid gisbreakdown_countyid gis_routeid

save "$intermediate_data/receipt_level_FMIS_lite.dta", replace


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

* add interstate_functional and interstate_syscode to the project-level data(we take the max so that even if the project only has one interstate receipt, the entire project is classified as interstate)
// TODO: should verify that the location variables (county, urban_rural, etc) are consistent across receipts within a project 
collapse (sum) receipts total_cost_mills federal_funds state_funds local_funds private_funds nonmonetary_funds other_funds (firstnm) region projectstatus projecttitle projectdescription authsprdate authpedate authrowdate authconstdate authotherdate completedate finalvoucherdate latestpaymentdate projectenddate lastactiondate transactiondate recipientremarks divisionremarks detail_prefix state_fips county_fips countyid gis_routeid urban_rural (lastnm) alltypes completion_year (max) interstate_functional interstate_syscode, by(federal_project_number recipientid)

label variable interstate_functional "True if at least one receipt is interstate"
label variable interstate_syscode "True if at least one receipt is interstate"

* relabel the state and county values (not sure why it disappeared)
label values state_fips stateid_lbl
label values county_fips county_fips_lbl
label values countyid countyid_lbl

save "$data/Intermediate/project_level_FMIS.dta", replace

* also export lite version
drop projecttitle projectdescription recipientremarks divisionremarks gis_routeid

save "$intermediate_data/project_level_FMIS_lite.dta", replace
