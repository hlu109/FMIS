/*==============================================================================
 	FMIS data processing 
	
    Pull some project examples for Zach and keep all the original data columns.
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

* load raw csv 
import delimited "$data/CSVs/combined_data.csv", clear bindquote(strict) varnames(1)


* Import raw FMIS data and gen common variables. 
import delimited "$data/CSVs/combined_data.csv", clear bindquote(strict) varnames(1)

* filter to the 3 projects we want 
* recipientid = 42, federalprojectnumber = 0794018-01
* recipientid = 17, federalprojectnumber = 1807013-01
* recipientid = 17, federalprojectnumber = 1807011-01
keep if (recipientid == 42 & federalprojectnumber == "0794018-01") | (recipientid == 17 & federalprojectnumber == "1807013-01") | (recipientid == 17 & federalprojectnumber == "1807011-01")

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

* export as csv 
export delimited using "$data/Hannah sandbox/project_examples_for_Zach.csv", replace