/*==============================================================================
 	Total national highway spending
 	Hannah Lu 
	02/24/2026

	This script processes FHWA Highway Statistics data on total highway spending across all levels of government.
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

* Load FHWA total national highway spending data
* DISCHT 1945-2001: https://www.fhwa.dot.gov/ohim/hs01/discht.htm
* DISB-C 2000-2023: https://www.fhwa.dot.gov/policyinformation/statistics/2023/disbc.cfm
import excel using "$raw_data/FHWA_Highway_Statistics/disbc_2000_2023.xlsx", cellrange(A85:E111) firstrow clear
drop in 1/2 // drop intermediate headers
rename Year year
save "$intermediate_data/FHWA_Highway_Statistics/disbc_2000_2023.dta", replace

import excel using "$raw_data/FHWA_Highway_Statistics/discht_1945_2001.xls", cellrange(A52:E111) firstrow clear
drop in 1/2 // drop intermediate headers
rename Year year
* save as .dta 
save "$intermediate_data/FHWA_Highway_Statistics/discht_1945_2001.dta", replace
* drop years 2000 and 2001 due to duplicate data
drop if year == 2000 | year == 2001

* stack datasets
append using "$intermediate_data/FHWA_Highway_Statistics/disbc_2000_2023.dta"

* rename columns and convert to numeric
rename CapitalOutlay cap_mills
rename Maintenance maint_mills
rename AdministrationHighwayLaw admin_law_int_mills
rename DebtRetirement debt_retire_mills
destring cap_mills, replace
destring maint_mills, replace
destring admin_law_int_mills, replace
destring debt_retire_mills, replace
gen total_hw_spend_mills = cap_mills + maint_mills + admin_law_int_mills + debt_retire_mills

* compute inflation-adjusted spending in 2025 dollars
merge 1:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_hw_spend_mills_adj = total_hw_spend_mills / cpi
gen cap_mills_adj = cap_mills / cpi
gen maint_mills_adj = maint_mills / cpi
gen admin_law_int_mills_adj = admin_law_int_mills / cpi
gen debt_retire_mills_adj = debt_retire_mills / cpi
label variable total_hw_spend_mills_adj "Total US Highway Spending, all levels of government (millions 2025 USD)"
label variable cap_mills_adj "Capital Outlays (millions 2025 USD)"
label variable maint_mills_adj "Maintenance (millions 2025 USD)"
label variable admin_law_int_mills_adj "Administrative, Law Enforcement, Bond Interest (millions 2025 USD)"
label variable debt_retire_mills_adj "Debt Retirement (millions 2025 USD)"

tempfile total_hw_spend
save `total_hw_spend'


* ==============================================================================
* Load interstate spending data from Brooks and Liscow 

use "$raw_data/BrooksLiscow_Annual_In-House_Dataset.dta", clear
keep state_name YEAR FED_INT_CONST_EXP_fa3 
// FED_INT_CONST_EXP_fa3 is total federal interstate cosntruction expenditures from FHWA Highway Statistics series FA3; I believe this should be in nominal (thousands?) of dollars  // TODO check this 
rename YEAR year
keep if state_name == "US_Total"
drop state_name

* adjust for inflation 	
merge 1:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen FED_INT_CONST_EXP_fa3_2025 = FED_INT_CONST_EXP_fa3 / cpi 
gen FED_INT_CONST_EXP_fa3_mills_2025 = FED_INT_CONST_EXP_fa3_2025 / 1000
gen FED_INT_CONST_EXP_fa3_bills_2025 = FED_INT_CONST_EXP_fa3_mills_2025 / 1000
label variable FED_INT_CONST_EXP_fa3_mills_2025 "Total Fed Interstate Construction Expenditure (FA3, millions 2025 USD)"
label variable FED_INT_CONST_EXP_fa3_bills_2025 "Total Fed Interstate Construction Expenditure (FA3, billions 2025 USD)"

* merge with the above total highway spending 
merge 1:1 year using `total_hw_spend', nogen

save "$intermediate_data/FHWA_Highway_Statistics/total_hw_spend.dta", replace
