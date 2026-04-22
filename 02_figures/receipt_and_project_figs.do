/*==============================================================================
 	FMIS data exploration
	This script generates figures related to receipts and projects. Some code copied and modified from Andy. 
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

/*==========================
 Num projects by year
===========================*/
use "$intermediate_data/project_level_FMIS_lite.dta", clear
gen n_proj = 1
gen n_proj_ic = 1 if fp_ic
gen n_proj_ic_newconstr = 1 if fp_ic == 1 & has_new_construction == 1
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
collapse (sum) n_proj n_proj_ic n_proj_ic_newconstr, by(completion_year)

graph twoway line n_proj n_proj_ic n_proj_ic_newconstr completion_year, sort /// 
    title("Number of Projects by Completion Year") ///
    ytitle("Number of Projects") ///
    ylabel(, format(%9.0fc)) ///
    xtitle("Completion Year") ///
    legend(label(1 "All Projects") label(2 "Interstate Construction" "Projects") label(3 "IC with New Construction")) ///
	note( ///
		"Interstate projects have at least one reimbursement funded by 'Interstate Construction' program codes." ///
		"New construction projects have at least one reimbursement classified as new construction (new construction roadway, bridge new construction, maintenance relocation, or new tunnel).", ///
		size(small) span ///
	)
graph export "$output/num_projects_by_yr_w_IC.png", replace width(2500)

* version without all projects, so the other lines are more visible
graph twoway line n_proj_ic n_proj_ic_newconstr completion_year, sort /// 
    title("Interstate Construction Projects by Completion Year") ///
    ytitle("Number of Projects") ///
    ylabel(, format(%9.0fc)) ///
    xtitle("Completion Year") ///
    lcolor(stc2 stc3) ///
    legend(label(1 "Interstate Construction" "Projects") label(2 "IC with New Construction")) ///
	note( ///
		"Interstate projects have at least one reimbursement funded by 'Interstate Construction' program codes." ///
		"New construction projects have at least one reimbursement classified as new construction (new construction roadway, bridge new construction, maintenance relocation, or new tunnel).", ///
		size(small) span ///
	)
graph export "$output/num_projects_by_yr_w_IC_only.png", replace width(2500)


/*===============================
 Num reimbursements by year 
================================*/
use "$intermediate_data/project_level_FMIS_lite.dta", clear
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
gen receipts_ic = receipts if fp_ic == 1
gen receipts_ic_newconstr = receipts if fp_ic == 1 & has_new_construction == 1
collapse (sum) receipts receipts_ic receipts_ic_newconstr, by(completion_year)
graph twoway line receipts receipts_ic receipts_ic_newconstr completion_year, sort /// 
    title("Number of Reimbursements by Completion Year") ///
    ytitle("Number of Reimbursements") ///
    ylabel(, format(%9.0fc)) ///
    xtitle("Completion Year") ///
    legend(label(1 "All Reimbursements") label(2 "Interstate Construction") label(3 "IC New Construction")) ///
	note( ///
		"Interstate construction reimbursements are identified by the 'Interstate Construction' funding program codes." ///
		"New construction reimbursements are new construction roadway, bridge new construction, maintenance relocation, or new tunnel.", ///
		size(small) span ///
	)
graph export "$output/num_reimb_by_yr_w_IC.png", replace width(2500)


/*=======================
 Num receipts per project
========================*/
use "$intermediate_data/project_level_FMIS_lite.dta", clear
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
gen receipts_ic = receipts if fp_ic == 1
gen receipts_ic_newconstr = receipts if fp_ic == 1 & has_new_construction == 1
collapse (mean) receipts receipts_ic receipts_ic_newconstr, by(completion_year)

graph twoway line receipts receipts_ic receipts_ic_newconstr completion_year, sort ///
	title("Average Number of Reimbursements per Project") ///
	ytitle("Reimbursements per Project") ///
	xtitle("Completion Year") ///
	legend(label(1 "All Projects") label(2 "Interstate Construction" "Projects") label(3 "IC with New Construction")) ///
	note( ///
		"Interstate projects have at least one reimbursement funded by 'Interstate Construction' program codes." ///
		"New construction projects have at least one reimbursement classified as new construction (new construction roadway, bridge new construction, maintenance relocation, or new tunnel).", ///
		size(small) span ///
	) ///
	graphregion(margin(l=15 r=15))
graph export "$output/reimb_per_proj_by_yr_w_IC.png", replace width(2500)


/*===============================
 Average reimbursement cost over time
================================*/
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data

gen double total_mills_all = total_cost_mills
gen double total_mills_ic = total_cost_mills if funding_program == "Interstate Construction"
gen double total_mills_ic_newconstr = total_cost_mills if funding_program == "Interstate Construction" & new_construction

collapse (mean) total_mills_all total_mills_ic total_mills_ic_newconstr, by(completion_year)

* adjust for inflation
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", nogen
gen total_mills_all_adj = total_mills_all / cpi
gen total_mills_ic_adj = total_mills_ic / cpi
gen total_mills_ic_newconstr_adj = total_mills_ic_newconstr / cpi

graph twoway line total_mills_all_adj total_mills_ic_adj total_mills_ic_newconstr_adj year, sort ///
    title("Average Adjusted Reimbursement Cost Over Time") ///
    ytitle("Millions of 2025 USD") ///
    xtitle("Completion Year") ///
    ylabel(, format(%9.0fc)) ///
    legend(label(1 "All Reimbursements") label(2 "Interstate Construction") label(3 "IC with New Construction")) ///
    note( ///
		"Interstate construction reimbursements are identified by the 'Interstate Construction' funding program codes. " ///
		"New construction reimbursements are new construction roadway, bridge new construction, maintenance relocation, or new tunnel.", ///
        size(small) span ///
    ) ///
	graphregion(margin(l=20 r=5))
graph export "$output/avg_reimb_cost_by_yr_w_IC.png", replace width(2500)


/*===============================
 Average project cost over time 
================================*/
use "$intermediate_data/project_level_FMIS_lite.dta", clear
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data

gen double total_mills_all = total_cost_mills
gen double total_mills_ic = total_cost_mills if fp_ic == 1
gen double total_mills_ic_newconstr = total_cost_mills if fp_ic == 1 & has_new_construction == 1

collapse (mean) total_mills_all total_mills_ic total_mills_ic_newconstr, by(completion_year)

* adjust for inflation
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keep(3) nogen
gen total_mills_all_adj = total_mills_all / cpi
gen total_mills_ic_adj = total_mills_ic / cpi
gen total_mills_ic_newconstr_adj = total_mills_ic_newconstr / cpi

graph twoway line total_mills_all_adj total_mills_ic_adj total_mills_ic_newconstr_adj year, sort ///
    title("Average Adjusted Project Cost Over Time") ///
    ytitle("Millions of 2025 USD") ///
    xtitle("Completion Year") ///
    legend(label(1 "All Projects") label(2 "Interstate Construction") label(3 "IC with New Construction")) ///
    note( ///
        "Interstate projects have at least one reimbursement funded by 'Interstate Construction' program codes." ///
		"New construction projects have at least one reimbursement classified as new construction (new construction roadway, bridge new construction, maintenance relocation, or new tunnel).", ///
        size(small) span ///
    )
graph export "$output/avg_project_cost_by_yr_w_IC.png", replace width(2500)


/*===============================
 Num reimbursements by year (IC only)
================================*/
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
gen fp_ic = funding_program == "Interstate Construction"

gen receipts = 1
gen receipts_newconstr = 1 if new_construction

* adjust for inflation
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) keep(match) nogen
gen total_cost_mills_adj = total_cost_mills / cpi
rename year completion_year

preserve
keep if fp_ic
collapse (sum) receipts receipts_newconstr, by(completion_year)
graph twoway line receipts receipts_newconstr completion_year, sort /// 
    title("Number of Reimbursements by Completion Year") ///
	subtitle("Interstate Construction Funding Only") ///
    ytitle("Number of Reimbursements") ///
    xtitle("Completion Year") ///
	ylabel(, format(%9.0fc)) ///
	xlabel(1960(10)2020) ///
    legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
    note( ///
		"Interstate construction reimbursements are identified by the 'Interstate Construction' funding program codes." ///
		"New construction reimbursements are new construction roadway, bridge new construction, maintenance relocation, or new tunnel.", ///
        size(small) span ///
    )
graph export "$output/num_reimb_by_yr_IC.png", replace width(2500)
restore


/*===============================
 Average reimbursement cost over time (IC only)
================================*/
preserve 
keep if fp_ic
gen total_cost_mills_adj_newconstr = total_cost_mills_adj if new_construction
collapse (mean) total_cost_mills_adj total_cost_mills_adj_newconstr, by(completion_year)

graph twoway line total_cost_mills_adj total_cost_mills_adj_newconstr completion_year, sort /// 
    title("Average Adjusted Reimbursement Cost Over Time") ///
	subtitle("Interstate Construction Funding Only") ///
    ytitle("Millions of 2025 USD") ///
    xtitle("Completion Year") ///
	xlabel(1960(10)2020) ///
    legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
    note( ///
		"Interstate construction reimbursements are identified by the 'Interstate Construction' funding program codes." ///
		"New construction reimbursements are new construction roadway, bridge new construction, maintenance relocation, or new tunnel.", ///
        size(small) span ///
    )
graph export "$output/avg_receipt_cost_by_yr_IC.png", replace width(2500)

keep if completion_year <= 2000
graph twoway line total_cost_mills_adj total_cost_mills_adj_newconstr completion_year, sort /// 
    title("Average Adjusted Reimbursement Cost Over Time") ///
	subtitle("Interstate Construction Funding Only; Completion Year <= 2000") ///
    ytitle("Millions of 2025 USD") ///
    xtitle("Completion Year") ///
	xlabel(1960(10)2000) ///
    legend(label(1 "All") label(2 "New Construction")) ///
    note( ///
        "Interstate construction reimbursements are identified by the 'Interstate Construction' funding program code." ///
		"New construction reimbursements are new construction roadway, bridge new construction, maintenance relocation, or new tunnel. " ///
		"Series restricted to completion years 2000 and earlier.", ///
        size(small) span ///
    )
graph export "$output/avg_receipt_cost_by_yr_IC_pre2000.png", replace width(2500)
restore 


/*===============================
 Num projects by year (IC only)
================================*/
use "$intermediate_data/project_level_FMIS_lite.dta", clear
keep if fp_ic
gen n_proj = 1
gen n_proj_newconstr = 1 if has_new_construction

preserve 
collapse (sum) n_proj n_proj_newconstr, by(completion_year)

graph twoway line n_proj n_proj_newconstr completion_year, sort /// 
    title("Number of Projects by Completion Year") ///
	subtitle("Interstate Construction Funding Only") ///
    ytitle("Number of Projects") ///
    xtitle("Completion Year") ///
    ylabel(, format(%9.0fc)) ///
	xlabel(1960(10)2020) ///
    legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
    note( ///
        "Projects are considered to be interstate if at least one reimbursement is funded by the 'Interstate Construction' program." ///
		`"New construction is identified by the improvement type code "new construction roadway", "bridge new construction", and "new tunnel"."' ///
		"Projects are considered to be new construction if at least one reimbursement is classified as new construction.", ///
        size(small) span ///
    )
graph export "$output/num_projects_by_yr_IC.png", replace width(2500)
restore 

/*===============================
 Average reimbursements per project (IC only)
================================*/
gen receipts_new_constr = receipts if has_new_construction

preserve 
collapse (mean) receipts receipts_new_constr, by(completion_year)
graph twoway line receipts receipts_new_constr completion_year, sort /// 
    title("Average Reimbursements per Project") ///
	subtitle("Interstate Construction Funding Only") ///
    xtitle("Completion Year") ///
    ytitle("Reimbursements per Project") ///
	xlabel(1960(10)2020) ///
    legend(label(1 "All") label(2 "New Construction")) ///
    note( ///
        "Reimbursements are identified by the 'Interstate Construction' funding program code." ///
		"Projects are considered to be interstate if at least one reimbursement is funded by the 'Interstate Construction' program." ///
		`"New construction is identified by the improvement type code "new construction roadway", "bridge new construction", and "new tunnel"."' ///
		"Projects are considered to be new construction if at least one reimbursement is classified as new construction.", ///
        size(small) span ///
    )
graph export "$output/receipts_per_proj_by_yr_IC.png", replace width(2500)

keep if completion_year <= 2000
graph twoway line receipts receipts_new_constr completion_year, sort /// 
    title("Average Reimbursements per Project") ///
	subtitle("Interstate Construction Funding Only; Completion Year <= 2000") ///
    xtitle("Completion Year") ///
    ytitle("Reimbursements per Project") ///
	xlabel(1960(10)2000) ///
    legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
    note( ///
        "Reimbursements are identified by the 'Interstate Construction' funding program code." ///
		"Projects are considered to be interstate if at least one reimbursement is funded by the 'Interstate Construction' program." ///
		`"New construction is identified by the improvement type code "new construction roadway", "bridge new construction", and "new tunnel"."' ///
		"Projects are considered to be new construction if at least one reimbursement is classified as new construction." ///
		"Series restricted to completion years 2000 and earlier.", ///
        size(small) span ///
    )
graph export "$output/receipts_per_proj_by_yr_IC_pre2000.png", replace width(2500)
restore 


/*===============================
 Average project cost over time (IC only)
================================*/
gen total_cost_mills_adj_newconstr = total_cost_mills_adj if has_new_construction

preserve 
collapse (mean) total_cost_mills_adj total_cost_mills_adj_newconstr, by(completion_year)
graph twoway line total_cost_mills_adj total_cost_mills_adj_newconstr completion_year, sort /// 
    title("Average Adjusted Project Cost Over Time") ///
	subtitle("Interstate Construction Funding Only") ///
    ytitle("Millions of 2025 USD") ///
    xtitle("Completion Year") ///
	xlabel(1960(10)2020) ///
    legend(label(1 "All") label(2 "New Construction")) ///
    note( ///
        "Projects are included in this sample if at least one reimbursement is funded by the 'Interstate Construction' program." ///
		`"New construction is identified by the improvement type code "new construction roadway", "bridge new construction", and "new tunnel"."' ///
		"Projects are considered to be new construction if at least one reimbursement is classified as new construction.", ///
        size(small) span ///
    )
graph export "$output/avg_project_cost_by_yr_IC.png", replace width(2500)

keep if completion_year <= 2000
graph twoway line total_cost_mills_adj total_cost_mills_adj_newconstr completion_year, sort /// 
    title("Average Adjusted Project Cost Over Time") ///
	subtitle("Interstate Construction Funding Only; Completion Year <= 2000") ///
    ytitle("Millions of 2025 USD") ///
    xtitle("Completion Year") ///
	xlabel(1960(10)2000) ///
    legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
    note( ///
        "Projects are included in this sample if at least one receipt is funded by the 'Interstate Construction' program." ///
		`"New construction is identified by the improvement type code "new construction roadway", "bridge new construction", and "new tunnel"."' ///
		"Projects are considered to be new construction if at least one reimbursement is classified as new construction." ///
		"Series restricted to completion years 2000 and earlier.", ///
        size(small) span ///
    )
graph export "$output/avg_project_cost_by_yr_IC_pre2000.png", replace width(2500)
restore 







// Average number of receipts for each project code (project ID or project work type?). 
// Average number of receipts per project for each project code (project ID or project work type?). (projects usually have multiple work types and sometimes have multiple federal aid system codes, so there isn't a great way to do this.)

* ==============================================================================

