/*==============================================================================
 	FMIS data processing 
    This script cleans and saves FMIS data, exporting it in four formats:
    * rich receipt-level data
    * a smaller 'lite' version of the receipt-level data, with some larger and less-used variables removed for faster data processing 
    * rich project-level data
    * a smaller 'lite' version of the project-level data, with some larger and less-used variables removed for faster data processing. 

    Hannah notes: this is the input data structure, as far as I understand
    * the raw xml contains nested fields: 
        * project 
            * reimbursements (which seem to be denoted "detail" in the xml?)
                * GISBreakdown_ (which may contain multiple GIS entries, including multiple counties)
    I think the input csv contains distinct rows for distinct "GISBreakdown_" fields for each reimbursement and project. 

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
global labels_dir = "$intermediate_data/stata_labels"
if !direxists("$labels_dir") mkdir "$labels_dir"

* Import raw FMIS data and gen common variables. 
import delimited "$data/CSVs/combined_data.csv", clear bindquote(strict) varnames(1)

rename federalprojectnumber federal_project_number

* Add County Names
gen countyid = gisbreakdown_countyid 
replace countyid = nongis_countyid if countyid == .

gen state_fips = gis_stateid
replace state_fips = nongis_stateid if state_fips == .
* correct mariana islands because the state id is 75 in FMIS but FIPS code is 69 (all other state IDs match census FIPS codes)
replace state_fips = 69 if state_fips == 75 

gen long county_fips = real(string(state_fips, "%02.0f") + string(countyid, "%03.0f")) ///
    if !mi(state_fips) & !mi(countyid)

global countyid_lbl_def ///
    999  "statewide" ///
    0  "unknown"
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
global county_labels_do_path = "$labels_dir/county_labels.do"
if !fileexists("$county_labels_do_path") {
    preserve 
    import delimited using "$intermediate_data/census_county_FIPS_crosswalk.csv", ///
        varnames(1) encoding(UTF-8) bindquote(strict) clear stringcols(5 8)
    gen long county_fips_num = real(strtrim(county_fips_full))
    keep county_fips_num countyname
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
    label save county_fips_lbl using "$county_labels_do_path", replace
    restore
}
run "$county_labels_do_path"
label values county_fips county_fips_lbl

* parse multiple counties
decode county_fips, gen(county_name)
tostring county_fips, replace force

* Save the county list for project level data
preserve
tostring detail_improvementtype, gen(proj_improv_types)
gen row = _n
sort federal_project_number recipientid row
foreach var of varlist proj_improv_types county_fips county_name {
    replace `var' = "" if `var' == "."
    capture drop `var'_combined
    by federal_project_number recipientid: gen `var'_combined = `var'[1]
	by federal_project_number recipientid: replace `var'_combined = cond( ///
		!regexm(`var'_combined[_n-1], "(^|; )" + `var' + "($|;)"), ///
		cond(`var'_combined[_n-1] == "", `var', `var'_combined[_n-1] + "; " + `var'), ///
    `var'_combined[_n-1]) if _n > 1  
	by federal_project_number recipientid: replace `var' = `var'_combined[_N]
}
bysort recipientid federal_project_number: gen n = _n
keep if n == 1 
keep recipientid federal_project_number proj_improv_types county_fips county_name
save "$intermediate_data/aggregated_proj_strings.dta", replace
restore

* Aggregate to the reimbursement level
sort federal_project_number recipientid detail_programcode detail_linenumber gisbreakdown_index
foreach var of varlist county_fips county_name {
    replace `var' = "" if `var' == "."
    capture drop `var'_combined
    by federal_project_number recipientid detail_programcode detail_linenumber: ///
        gen `var'_combined = `var'[1]
    by federal_project_number recipientid detail_programcode detail_linenumber: ///
        replace `var'_combined = cond( ///
            !regexm(`var'_combined[_n-1], "(^|; )" + `var' + "($|;)"), ///
            cond(`var'_combined[_n-1] == "", `var', `var'_combined[_n-1] + "; " + `var'), ///
            `var'_combined[_n-1]) if _n > 1
    by federal_project_number recipientid detail_programcode detail_linenumber: ///
        replace `var' = `var'_combined[_N]
}

* drop to the reimbursement level
keep if gisbreakdown_index == . | gisbreakdown_index == 1

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

* classify construction work types 
gen new_construction = detail_improvementtype == 1 | detail_improvementtype == 7 | detail_improvementtype == 8 | detail_improvementtype == 50 // new construction roadway, maintenance relocation, bridge new construction, new tunnel
gen reconstruction = detail_improvementtype == 2 | detail_improvementtype == 3 | detail_improvementtype == 4 | detail_improvementtype == 9 | detail_improvementtype == 10 | detail_improvementtype == 11 | detail_improvementtype == 51 // 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete), bridge replacement (added capacity), bridge replacement (no added capacity), tunnel replacement
gen rehabilitation = detail_improvementtype == 6 | detail_improvementtype == 12 | detail_improvementtype == 13 | detail_improvementtype == 14 | detail_improvementtype == 52 // 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation (obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), tunnel rehabilitation
gen maintenance = detail_improvementtype == 5 | detail_improvementtype == 47 | detail_improvementtype == 48 | detail_improvementtype == 53 | detail_improvementtype == 54 | detail_improvementtype == 59 | detail_improvementtype == 60 // maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance, tunnel protection, bridge resurfacing, highway infrastructure preventive maintenance
gen work_type = .
replace work_type = 1 if new_construction == 1
replace work_type = 2 if reconstruction == 1
replace work_type = 3 if rehabilitation == 1
replace work_type = 4 if maintenance == 1
label define work_type_lbl 1 "New Construction" 2 "Reconstruction" 3 "Rehabilitation" 4 "Maintenance"
label values work_type work_type_lbl
gen is_construction = new_construction == 1 | reconstruction == 1 | rehabilitation == 1
label variable is_construction "Construction work includes new construction, reconstruction, and rehabilitation"

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


* label state and recipientid values 
// we hard-code this here because it's not too long, and this makes the script run faster than if we referenced another external file 

// state_fips 
global state_fips_lbl_def ///
    1  "Alabama" ///
    2  "Alaska" ///
    4  "Arizona" ///
    5  "Arkansas" ///
    6  "California" ///
    8  "Colorado" ///
    9  "Connecticut" ///
    10  "Delaware" ///
    11  "District of Columbia" ///
    12  "Florida" ///
    13  "Georgia" ///
    15  "Hawaii" ///
    16  "Idaho" ///
    17  "Illinois" ///
    18  "Indiana" ///
    19  "Iowa" ///
    20  "Kansas" ///
    21  "Kentucky" ///
    22  "Louisiana" ///
    33  "New Hampshire" ///
    34  "New Jersey" ///
    35  "New Mexico" ///
    36  "New York" ///
    37  "North Carolina" ///
    38  "North Dakota" ///
    39  "Ohio" ///
    40  "Oklahoma" ///
    41  "Oregon" ///
    42  "Pennsylvania" ///
    44  "Rhode Island" ///
    45  "South Carolina" ///
    46  "South Dakota" ///
    47  "Tennessee" ///
    48  "Texas" ///
    49  "Utah" ///
    50  "Vermont" ///
    51  "Virginia" ///
    53  "Washington" ///
    54  "West Virginia" ///
    55  "Wisconsin" ///
    56  "Wyoming" ///
    60  "American Samoa" ///
    66  "Guam" ///
    69  "N Mariana" ///
    72  "Puerto Rico" ///
    78  "United States Virgin Islands" ///
    81  "Canada"
label define state_fips_lbl $state_fips_lbl_def, replace
label values state_fips state_fips_lbl

global recipientid_lbl_def ///
    0	"Headquarters" ///
    1	"Alabama" ///
    2	"Alaska" ///
    4	"Arizona" ///
    5  "Arkansas" ///
    6  "California" ///
    8  "Colorado" ///
    9	"Connecticut" ///
    10	"Delaware" ///
    11	"District Of Columbia" ///
    12	"Florida" ///
    13	"Georgia" ///
    15	"Hawaii" ///
    16	"Idaho" ///
    17	"Illinois" ///
    18	"Indiana" ///
    19	"Iowa" ///
    20	"Kansas" ///
    21	"Kentucky" ///
    22	"Louisiana" ///
    23	"Maine" ///
    24	"Maryland" ///
    25	"Massachusetts" ///
    26	"Michigan" ///
    27	"Minnesota" ///
    28	"Mississippi" ///
    29	"Missouri" ///
    30	"Montana" ///
    31	"Nebraska" ///
    32	"Nevada" ///
    33	"New Hampshire" ///
    34	"New Jersey" ///
    35	"New Mexico" ///
    36	"New York" ///
    37	"North Carolina" ///
    38	"North Dakota" ///
    39	"Ohio" ///
    40	"Oklahoma" ///
    41	"Oregon" ///
    42	"Pennsylvania" ///
    44	"Rhode Island" ///
    45	"South Carolina" ///
    46	"South Dakota" ///
    47	"Tennessee" ///
    48	"Texas" ///
    49	"Utah" ///
    50	"Vermont" ///
    51	"Virginia" ///
    53	"Washington" ///
    54	"West Virginia" ///
    55	"Wisconsin" ///
    56	"Wyoming" ///
    60	"American Samoa" ///
    66	"Guam" ///
    72	"Puerto Rico" ///
    75	"N Mariana" ///
    78	"United States Virgin Islands" ///
    81	"Canada" ///
    91	"Port Authority of NY and NJ"
label define recipientid_lbl $recipientid_lbl_def, replace
label values recipientid recipientid_lbl

// TODO: move this to after we convert the dates to date variables, and just use the year() function instead of regex 
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

* parse funding streams  
gen funding_program = ""
replace funding_program = "Interstate Construction" if inlist(detail_programcode, "0420", "0430", "04C0", "04P0", "0500", "0550", "05C0", "0590", "17A0")
replace funding_program = "Interstate Construction" if inlist(detail_programcode, "1870", "1880", "8230", "A510", "EC20", "EG20", "X420")
replace funding_program = "Interstate Maintenance" if inlist(detail_programcode, "04M0", "04L0", "Q010", "Q440", "0AB0")
replace funding_program = "Interstate Maintenance" if inlist(detail_programcode, "H010", "L010", "L01E", "L01R")
replace funding_program = "Interstate Maintenance Discretionary" if inlist(detail_programcode, "0560", "31B0", "31D0", "Q020")
replace funding_program = "Interstate Maintenance Discretionary" if inlist(detail_programcode, "H020", "L020", "L02E")
replace funding_program = "National Highway Performance Program" if inlist(detail_programcode, "Z0E1", "Z0E2", "Z51E", "Z53E", "Z001", "Z002")
replace funding_program = "National Highway Performance Program" if inlist(detail_programcode, "Z510", "Z530", "M0E1", "M0E2", "M001", "M002")

* adjust for inflation 
// TODO 


* export 
keep recipientid state_fips county_fips county_name projectstatus projecttitle detail_linenumber projectdescription total_cost_mills federal_funds state_funds local_funds private_funds nonmonetary_funds other_funds authsprdate authpedate authrowdate authconstdate authotherdate completedate finalvoucherdate latestpaymentdate projectenddate lastactiondate transactiondate detail_lastactiondate recipientremarks divisionremarks detail_prefix gis_routeid detail_improvementtype completion_year finalvoucher_year latestpayment_year detaillastaction_year federal_project_number region functional_system system_code interstate_functional interstate_syscode detail_programcode urban_rural funding_program new_construction reconstruction rehabilitation maintenance is_construction work_type
save "$intermediate_data/receipt_level_FMIS.dta", replace

label save using "$labels_dir/FMIS_labels.do", replace

* also export lite version 
drop projecttitle projectdescription recipientremarks divisionremarks gis_routeid county_name

save "$intermediate_data/receipt_level_FMIS_lite.dta", replace

* ==============================================================================
* Project-level data
* ==============================================================================
use "$intermediate_data/receipt_level_FMIS.dta", clear
* Collapse to the project level, and save

* identify funding programs (indicators are true if at least one receipt is funded by the program)
gen fp_ic = funding_program == "Interstate Construction"
gen fp_im = funding_program == "Interstate Maintenance"
gen fp_imd = funding_program == "Interstate Maintenance Discretionary"
gen fp_nhpp = funding_program == "National Highway Performance Program"

gen receipts = 1 // this is used for reciept counts

// TODO: should verify that the location variables (county, urban_rural, etc) are consistent across receipts within a project 
collapse ///
    (sum) receipts total_cost_mills federal_funds state_funds local_funds private_funds nonmonetary_funds other_funds ///
    (firstnm) region projectstatus projecttitle projectdescription authsprdate authpedate authrowdate authconstdate authotherdate completedate finalvoucherdate latestpaymentdate projectenddate lastactiondate transactiondate recipientremarks divisionremarks detail_prefix state_fips gis_routeid urban_rural ///
    (lastnm) completion_year ///
    (max) interstate_functional interstate_syscode fp_ic fp_im fp_imd fp_nhpp (max) has_new_construction = new_construction ///
    (max) has_reconstruction = reconstruction ///
    (max) has_rehabilitation = rehabilitation ///
    (max) has_maintenance = maintenance ///
    (max) has_construction = is_construction ///
    , by(federal_project_number recipientid)
// note the max codes for indicator variables so that the project adopts the feature if at least one reimbursement has the feature

merge 1:1 federal_project_number recipientid using "$intermediate_data/aggregated_proj_strings.dta", nogen

* update labels    
label variable interstate_functional "True if at least one receipt is interstate"
label variable interstate_syscode "True if at least one receipt is interstate"
label variable fp_ic "True if at least one receipt is funded by Interstate Construction"
label variable fp_im "True if at least one receipt is funded by Interstate Maintenance"
label variable fp_imd "True if at least one receipt is funded by Interstate Maintenance Discretionary"
label variable fp_nhpp "True if at least one receipt is funded by National Highway Performance Program"

run "$labels_dir/FMIS_labels.do"
label values recipientid recipientid_lbl
label values state_fips state_fips_lbl

save "$data/Intermediate/project_level_FMIS.dta", replace

* also export lite version
drop projecttitle projectdescription recipientremarks divisionremarks gis_routeid

save "$intermediate_data/project_level_FMIS_lite.dta", replace
