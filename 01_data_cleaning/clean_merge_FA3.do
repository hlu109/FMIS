/*==============================================================================
 	FMIS
 	Hannah Lu 
	02/24/2026

	This script merges FHWA Highway Statistics FA-3 data from 1956 to 2024. Run this AFTER running clean_merge_FA3.R.
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
* Load FA-3 1956 - 1993 interstate spending data from Brooks and Liscow 

use "$raw_data/BrooksLiscow_Annual_In-House_Dataset.dta", clear
keep if state_name == "US_Total"
drop state_name
keep YEAR FED_INT_CONST_EXP_fa3 
// FED_INT_CONST_EXP_fa3 is total federal interstate cosntruction expenditures from FHWA Highway Statistics series FA3; this should be in nominal thousands of dollars
rename YEAR year
rename FED_INT_CONST_EXP_fa3 FA3_interstate

* save temp file 
tempfile fa3_1956_1993
save `fa3_1956_1993'

* ==============================================================================

* load FA3_interstate.csv
import delimited using "$intermediate_data/FHWA_Highway_Statistics/FA3_interstate_1994_2024.csv", clear

rename interstate FA3_interstate
rename interstate_maintenance FA3_intmaint
rename interstate_highway_substitute FA3_inthwysub

// stack with fa3_1956_1993
append using `fa3_1956_1993'
sort year 
egen FA3_int_all = rowtotal(FA3_interstate FA3_intmaint FA3_inthwysub)

// I verified that for 1990-1993, the interstate data from BrooksLiscow is taken exclusively from the "Interstate" column and not merged with other columns like "Interstate Maintenance" or "Interstate Highway Substitute". However, older years also have this data. We should eventually collect this.

* adjust for inflation 	
merge 1:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) keep(3) nogen
gen FA3_interstate_adj_mills = FA3_interstate / cpi / 1000
gen FA3_intmaint_adj_mills = FA3_intmaint / cpi / 1000
gen FA3_inthwysub_adj_mills = FA3_inthwysub / cpi / 1000
gen FA3_int_all_adj_mills = FA3_int_all / cpi / 1000

gen FA3_interstate_adj_bills = FA3_interstate_adj_mills / 1000
gen FA3_intmaint_adj_bills = FA3_intmaint_adj_mills / 1000
gen FA3_inthwysub_adj_bills = FA3_inthwysub_adj_mills / 1000
gen FA3_int_all_adj_bills = FA3_int_all_adj_mills / 1000

label variable FA3_interstate_adj_mills "Total Fed Interstate Expenditure (FA3, millions 2025 USD)"
label variable FA3_intmaint_adj_mills "Total Fed Interstate Maintenance Expenditure (FA3, millions 2025 USD)"
label variable FA3_inthwysub_adj_mills "Total Fed Interstate Highway Substitute Expenditure (FA3, millions 2025 USD)"
label variable FA3_interstate_adj_bills "Total Fed Interstate Expenditure (FA3, billions 2025 USD)"
label variable FA3_intmaint_adj_bills "Total Fed Interstate Maintenance Expenditure (FA3, billions 2025 USD)"
label variable FA3_inthwysub_adj_bills "Total Fed Interstate Highway Substitute Expenditure (FA3, billions 2025 USD)"
label variable FA3_int_all_adj_mills "Sum of Interstate, Interstate Maintenance, and Interstate Highway Substitute"
label variable FA3_int_all_adj_bills "Sum of Interstate, Interstate Maintenance, and Interstate Highway Substitute"

save "$intermediate_data/FHWA_Highway_Statistics/FA3_interstate_1956_2024.dta", replace