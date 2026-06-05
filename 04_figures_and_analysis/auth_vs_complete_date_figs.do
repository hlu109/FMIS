/*==============================================================================
 	FMIS data exploration
	This script compares time series spending figures that are plotted against construction authorization date vs completion date.
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
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear

gen authconstyear = year(authconstdate)

* adjust for inflation
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_cost_bills_adj_completion = total_cost_mills / cpi / 1000 // adjusted using completion year
rename year completion_year
drop cpi 
rename authconstyear year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_cost_bills_adj_authconst = total_cost_mills / cpi / 1000 // adjusted using authorization year
drop cpi total_cost_mills
rename year authconstyear 

keep if funding_program == "Interstate Construction"
keep if is_construction == 1

* ==============================================================================
* spending by completion date
* ==============================================================================
preserve 
collapse (sum) total_cost_bills_adj_completion, by(completion_year)
drop if mi(total_cost_bills_adj_completion)
drop if completion_year < 1940 | completion_year > 2000
graph twoway line total_cost_bills_adj_completion completion_year, ///
    title("Interstate Construction Spending by Completion Year", size(medium)) ///
    subtitle("New Construction, Reconstruction, and Rehabilitation", size(small)) ///
    ytitle("Billions of 2025 USD" "(Indexed by Completion Year)") ///
    xtitle("Completion Year") ///
    note( ///
        "Spending is adjusted for inflation using completion year." ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
        "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement" "(obsolete), bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
        "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation.", ///
        size(small) span ///
    )
graph export "$output/IC_constr_spend_by_completionyear_inflation_adj_completion.png", replace width(2500)
restore

* ==============================================================================
* spending by authorization date
* ==============================================================================
preserve 
collapse (sum) total_cost_bills_adj_authconst, by(authconstyear)
drop if mi(total_cost_bills_adj_authconst)
drop if authconstyear < 1940 | authconstyear > 2000
graph twoway line total_cost_bills_adj_authconst authconstyear, ///
    title("Interstate Construction Spending by Construction Authorization Year", size(medium)) ///
    subtitle("New Construction, Reconstruction, and Rehabilitation", size(small)) ///
    ytitle("Billions of 2025 USD" "(Indexed by Authorization Year)") ///
    xtitle("Construction Authorization Year") ///
    note( ///
        "Spending is adjusted for inflation using construction authorization year." ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
        "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement" "(obsolete), bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
        "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation.", ///
        size(small) span ///
    )
graph export "$output/IC_constr_spend_by_authyear_inflation_adj_constauth.png", replace width(2500)
restore

preserve 
collapse (sum) total_cost_bills_adj_completion, by(authconstyear)
drop if mi(total_cost_bills_adj_completion)
drop if authconstyear < 1940 | authconstyear > 2000
graph twoway line total_cost_bills_adj_completion authconstyear, ///
    title("Interstate Construction Spending by Construction Authorization Year", size(medium)) ///
    subtitle("New Construction, Reconstruction, and Rehabilitation", size(small)) ///
    ytitle("Billions of 2025 USD" "(Indexed by Completion Year)") ///
    xtitle("Construction Authorization Year") ///
    note( ///
        "Spending is adjusted for inflation using completion year." ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
        "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement" "(obsolete), bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
        "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation.", ///
        size(small) span ///
    )
graph export "$output/IC_constr_spend_by_authyear_inflation_adj_completion.png", replace width(2500)
restore

