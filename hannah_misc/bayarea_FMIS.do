/*==============================================================================
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
use "$intermediate_data/receipt_level_FMIS.dta", clear

// label define programcode_lbl "0420" "Interstate Construction" "0430" "Interstate Construction, 100 percent" "04C0" "Interstate Construction, 1956" "04P0" "Interstate Construction, TMFW" "0500" "Interstate Construction, 1/2 percent Minimum" "0550" "Interstate Construction, Urgent Supplemental Non-Interstate" "05C0" "Interstate Construction, 1/2 % Minimum, TMFW" "0590" "Interstate Construction, 1/2 percent Minimum, 100 percent Federal Participation" "17A0" "Interstate Construction, Transfer, New York, 1986" "1870" "Interstate Construction, Shakwak Project" "1880" "Interstate Construction, I-287 Bypass" "8230" "Interstate Substitution, Before FY-84, from GF" "A510" "Interstate Construction, 1/2 percent Minimum" "EC20" "Interstate Construction, 1/2 percent Minimum, Combined Road Plan Demo" "EG20" "Interstate Construction, 1/2 percent Minimum, Combined Road Plan Demo., 100 percent" "X420" "Interstate Construction, 1/4 percent National Highway Institute", replace
// label values programcode programcode_lbl

// keep if detail_programcode == "0420" | detail_programcode == "0430" | detail_programcode == "04C0" | detail_programcode == "04P0" | detail_programcode == "0500" | detail_programcode == "0550" | detail_programcode == "05C0" | detail_programcode == "0590" | detail_programcode == "17A0" | detail_programcode == "1870" | detail_programcode == "01880" | detail_programcode == "08230" | detail_programcode == "0A510" | detail_programcode == "0EC20" | detail_programcode == "0EG20" | detail_programcode == "0X420"

keep if interstate_syscode == 1
keep if completion_year <= 1993
keep if completion_year <= 1979 & completion_year >= 1960
// keep if state_fips == 06
// keep if countyid == 85 | countyid == 81 // | countyid == 75 | countyid == 87 | countyid == 0 | countyid == 999 
* san mateo, santa clara, san francisco, santa cruz counties + unknown and statewide 
keep if detail_improvementtype <= 14

sort completedate federal_project_number


// keep if strmatch(projecttitle, "*280*")
// keep if strmatch(projecttitle, "*junipero*")

* adjust for inflation 
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_cost_millions_adjusted = total_cost_mills / cpi

// drop state_fips
// keep if projectstatus == 11
drop projectstatus
drop private_funds nonmonetary_funds other_funds region interstate_functional interstate_syscode transactiondate recipientid projectdescription projectenddate recipientremarks divisionremarks detail_linenumber detail_prefix nongis_countyid gis_routeid gisbreakdown_countyid total_cost_mills federal_funds state_funds local_funds

// save "$data/Hannah sandbox/FMIS_sanmateo_santaclara.dta", replace