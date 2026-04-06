/*==============================================================================
 	FMIS data processing 
    This script processes program codes and funding streams. 
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
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear

* label top program codes
gen program_code_name = ""

* top program codes for interstates
replace program_code_name = "Interstate Construction" if detail_programcode == "0420"
replace program_code_name = "Interstate 4R" if detail_programcode == "0440"
replace program_code_name = "NHPP (FAST Act)" if detail_programcode == "Z001"
replace program_code_name = "Interstate Maintenance (TEA-21)" if detail_programcode == "Q010"
replace program_code_name = "Interstate Maintenance (ISTEA)" if detail_programcode == "04M0"
replace program_code_name = "Interstate Maintenance (SAFETEA-LU FY2006-2009)" if detail_programcode == "L010"
replace program_code_name = "NHPP (MAP-21)" if detail_programcode == "M001"
replace program_code_name = "Interstate Maintenance (SAFETEA-LU Extension)" if detail_programcode == "L01E"
replace program_code_name = "NHPP (MAP-21 Extension)" if detail_programcode == "M0E1"
replace program_code_name = "Interstate Maintenance (TEA-21 Extensions FY2004-2005)" if detail_programcode == "H010"
replace program_code_name = "NHS (TEA-21)" if detail_programcode == "Q050"
replace program_code_name = "NHS-National Highway System (ISTEA)" if detail_programcode == "3150"
replace program_code_name = "Interstate Construction, 100 percent" if detail_programcode == "0430"
replace program_code_name = "0120 (unknown program code)" if detail_programcode == "0120"
replace program_code_name = "NHS (SAFETEA-LU FY2006-2009)" if detail_programcode == "L050"
replace program_code_name = "Interstate Discretionary" if detail_programcode == "0540"
replace program_code_name = "NHS (SAFETEA-LU Extension)" if detail_programcode == "L05E"
replace program_code_name = "Urban Extensions" if detail_programcode == "0320"
replace program_code_name = "NHS (TEA-21 Extensions FY2004-2005)" if detail_programcode == "H050"
replace program_code_name = "STBG - Flex" if detail_programcode == "Z240"

* rest of top program codes for other projects
replace program_code_name = "Federal-Aid - Secondary" if detail_programcode == "0220"
replace program_code_name = "Federal-Aid - Consolidated Primary" if detail_programcode == "0100"
replace program_code_name = "1180 (unknown program code)" if detail_programcode == "1180"
replace program_code_name = "Federal-Aid - Rural Secondary" if detail_programcode == "0750"
replace program_code_name = "1170 (unknown program code)" if detail_programcode == "1170"
replace program_code_name = "STBG STP-FLEX (TEA-21)" if detail_programcode == "Q240"
replace program_code_name = "Railway-Highway Crossing Hazard Elimination" if detail_programcode == "1390"
replace program_code_name = "Federal-Aid Urban System" if detail_programcode == "W360"
replace program_code_name = "STP-State Flexible" if detail_programcode == "33D0"
replace program_code_name = "1140 (unknown program code)" if detail_programcode == "1140"
replace program_code_name = "STBG - STP FLEXIBLE (SAFETEA-LU)" if detail_programcode == "L240"
replace program_code_name = "STBG - STP Flex (MAP-21)" if detail_programcode == "M240"

local acronym_notes ///
    `"ISTEA: Intermodal Surface Transportation Efficiency Act"' ///
    `"SAFETEA-LU: Safe, Accountable, Flexible, Efficient Transportation Equity Act: A Legacy for Users"' ///
    `"FAST Act: Fixing America's Surface Transportation Act"' ///
    `"MAP-21: Moving Ahead for Progress in the 21st Century Act"' ///
    `"TEA-21: Transportation Equity Act for the 21st Century"' ///
    `"STBG: Surface Transportation Block Grant"' ///
    `"STP: State Transportation Program (or State Transportation Plan?)"' ///
    `"NHPP: National Highway Performance Program"' ///
    `"NHS: National Highway System"'

// * parse funding streams  
// gen funding_program = ""
// replace funding_program = "Interstate Construction" if inlist(detail_programcode, "0420", "0430", "04C0", "04P0", "0500", "0550", "05C0", "0590", "17A0")
// replace funding_program = "Interstate Construction" if inlist(detail_programcode, "1870", "1880", "8230", "A510", "EC20", "EG20", "X420")
// replace funding_program = "Interstate Maintenance" if inlist(detail_programcode, "04M0", "04L0", "Q010", "Q440", "0AB0")
// replace funding_program = "Interstate Maintenance" if inlist(detail_programcode, "H010", "L010", "L01E", "L01R")
// replace funding_program = "Interstate Maintenance Discretionary" if inlist(detail_programcode, "0560", "31B0", "31D0", "Q020")
// replace funding_program = "Interstate Maintenance Discretionary" if inlist(detail_programcode, "H020", "L020", "L02E")
// replace funding_program = "National Highway Performance Program" if inlist(detail_programcode, "Z0E1", "Z0E2", "Z51E", "Z53E", "Z001", "Z002")
// replace funding_program = "National Highway Performance Program" if inlist(detail_programcode, "Z510", "Z530", "M0E1", "M0E2", "M001", "M002")

save "$intermediate_data/receipt_level_FMIS_lite_program_codes.dta", replace