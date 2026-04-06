/*==============================================================================
    This script analyzes the location variables in FMIS. 
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

* adjust for inflation 
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_cost_mills_adjusted = total_cost_mills / cpi
gen total_cost_bills_adjusted = total_cost_mills_adjusted / 1000

* identify state capitals 
tempfile state_caps
preserve
    import delimited using "$intermediate_data/state_capitals_FIPS.csv", varnames(1) clear
    keep county_fips
    save `state_caps'
restore

merge m:1 county_fips using `state_caps', keep(master match)
gen byte state_capital_county = (_merge == 3)
drop _merge

replace state_capital_county = 0 if missing(state_capital_county)

gen county_status = countyid
replace county_status = 1 if state_capital_county
replace county_status = 2 if countyid != 999 & countyid != 0 & !state_capital_county & !missing(countyid)
replace county_status = 0 if missing(countyid)
global county_status_lbl_def ///
    999  "Statewide" ///
    0  "Unknown/Missing" ///
    1  "State Capital" ///
    2  "Non-State Capital"
label define county_status_lbl $county_status_lbl_def, replace
label values county_status county_status_lbl


* get per capita costs 

* ==============================================================================
* Figures
* ==============================================================================
drop if year < 1950 | year > 2025

* figure legend labels 
local leg0 : label county_status_lbl 0
local leg1 : label county_status_lbl 1
local leg2 : label county_status_lbl 2
local leg999 : label county_status_lbl 999

* plot costs of projects by county type
preserve
collapse (sum) total_cost_bills_adjusted, by(year county_status)

graph twoway ///
    (line total_cost_bills_adjusted year if county_status == 0) ///
    (line total_cost_bills_adjusted year if county_status == 1) ///
    (line total_cost_bills_adjusted year if county_status == 2) ///
    (line total_cost_bills_adjusted year if county_status == 999), ///
    title("Total FMIS Expenditures by County Status") ///
    ytitle("Billions of 2025 USD") xtitle("Completion Year") ///
    xlabel(1950(10)2020) ///
    legend(title("County Type") order(3 "`leg2'" 2 "`leg1'" 4 "`leg999'" 1 "`leg0'")) ///
    note( ///
        "Some state capitals intersect with multiple counties. In such cases, the county with the largest overlap is" ///
        `"identified as the "state capital county"."', ///
        size(small) span ///
    )
graph export "$output/costs_by_county_status.png", replace width(2500)
restore

* same plot but interstate only 
preserve
keep if interstate_syscode == 1
collapse (sum) total_cost_bills_adjusted, by(year county_status)

graph twoway ///
    (line total_cost_bills_adjusted year if county_status == 0) ///
    (line total_cost_bills_adjusted year if county_status == 1) ///
    (line total_cost_bills_adjusted year if county_status == 2) ///
    (line total_cost_bills_adjusted year if county_status == 999), ///
    title("Total FMIS Interstate Expenditures by County Status") ///
    ytitle("Billions of 2025 USD") xtitle("Completion Year") ///
    xlabel(1950(10)2020) ///
    legend(title("County Type") order(3 "`leg2'" 2 "`leg1'" 4 "`leg999'" 1 "`leg0'")) ///
    note( ///
        "Some state capitals intersect with multiple counties. In such cases, the county with the largest overlap is" ///
        `"identified as the "state capital county"."', ///
        size(small) span ///
    )

graph export "$output/costs_by_county_status_interstate.png", replace width(2500)
restore