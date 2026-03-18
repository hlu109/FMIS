/*==============================================================================
 	FMIS data exploration
 	Hannah Lu 
	03/05/2026

	This script generates figures related to receipts and projects. Some code copied and modified from Andy. 
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

/*==========================
 Num projects by year
===========================*/
use "$intermediate_data/project_level_FMIS_lite.dta", clear
gen n_obs = 1
gen n_obs_interstate = 1 if interstate_syscode == 1
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
collapse (sum) n_obs n_obs_interstate, by(completion_year)

* add count of projects with at least one interstate new construction receipt
preserve
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if completion_year >= 1950 & completion_year < 2025
keep if interstate_syscode == 1 & (detail_improvementtype == 1 | detail_improvementtype == 8 | detail_improvementtype == 50)
keep recipientid federal_project_number completion_year
duplicates drop
// note we don't need to merge with project data because we already have project count 
gen n_obs_interstate_newconstr = 1
collapse (sum) n_obs_interstate_newconstr, by(completion_year)
tempfile interstate_newconstr
save `interstate_newconstr'
restore

merge 1:1 completion_year using `interstate_newconstr', nogen

// graph twoway line n_obs n_obs_interstate n_obs_interstate_newconstr completion_year, sort /// 
//     title("Number of Projects by Completion Year") ///
//     ytitle("Number of Projects") ///
//     ylabel(, format(%9.0fc)) ///
//     xtitle("Completion Year") ///
//     legend(label(1 "All Projects") label(2 "Interstate Projects") label(3 "Interstate Projects" "with New Construction")) ///
// 	note( ///
// 		"Interstate projects are those that have at least one receipt with an interstate federal-aid system code." ///
// 		`"Interstate projects with new construction are those that have at least one interstate receipt classified as "' ///
// 		`""new construction roadway", "bridge new construction", or "new tunnel"."', ///
// 		size(small) span ///
// 	)
// graph export "$output/num_projects_by_yr_with_interstate.png", replace width(2500)

* version without all projects, so the other lines are more visible
graph twoway line n_obs_interstate n_obs_interstate_newconstr completion_year, sort /// 
    title("Number of Interstate Projects by Completion Year") ///
    ytitle("Number of Projects") ///
    ylabel(, format(%9.0fc)) ///
    xtitle("Completion Year") ///
    lcolor(stc2 stc3) ///
    legend(label(1 "Interstate Projects") label(2 "Interstate Projects" "with New Construction")) ///
	note( ///
		"Interstate projects are those that have at least one receipt with an interstate federal-aid system code." ///
		`"Interstate projects with new construction are those that have at least one interstate receipt classified as "' ///
		`""new construction roadway", "bridge new construction", or "new tunnel"."', ///
		size(small) span ///
	)
graph export "$output/num_projects_by_yr_interstate_only.png", replace width(2500)

exit 
/*===============================
 Num Receipts by year 
================================*/
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
gen n_obs = 1
gen n_obs_interstate = 1 if interstate_syscode == 1
gen n_obs_interstate_newconstr = 1 if interstate_syscode == 1 & (detail_improvementtype == 1 | detail_improvementtype == 8 | detail_improvementtype == 50)
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
collapse (sum) n_obs n_obs_interstate n_obs_interstate_newconstr, by(completion_year)
graph twoway line n_obs n_obs_interstate n_obs_interstate_newconstr completion_year, sort /// 
    title("Number of Receipts by Completion Year") ///
    ytitle("Number of Receipts") ///
    ylabel(, format(%9.0fc)) ///
    xtitle("Completion Year") ///
    legend(label(1 "All Receipts") label(2 "Interstate Receipts") label(3 "Interstate Projects" "with New Construction")) ///
	note( ///
        "Interstate classification is defined by federal aid system code." ///
        `"New construction includes "new construction roadway", "bridge new construction", and "new tunnel"."', ///
		size(small) span ///
	)
graph export "$output/num_receipts_by_yr_with_interstate.png", replace width(2500)


/*=======================
 Num receipts per project
========================*/
use "$intermediate_data/project_level_FMIS_lite.dta", clear
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
gen receipts_interstate = receipts if interstate_syscode == 1
collapse (mean) receipts receipts_interstate, by(completion_year)

* add mean receipts for interstate new construction projects
preserve
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if completion_year >= 1950 & completion_year < 2025
keep if interstate_syscode == 1 & (detail_improvementtype == 1 | detail_improvementtype == 8 | detail_improvementtype == 50)
* crosswalk to project data 
keep recipientid federal_project_number
duplicates drop
merge 1:1 recipientid federal_project_number using "$intermediate_data/project_level_FMIS_lite.dta", keep(match) nogen
collapse (mean) receipts, by(completion_year)
rename receipts receipts_interstate_newconstr
tempfile receipts_newconstr
save `receipts_newconstr'
restore

merge 1:1 completion_year using `receipts_newconstr', nogen

graph twoway line receipts receipts_interstate receipts_interstate_newconstr completion_year, sort ///
	title("Average Number of Receipts per Project" "by Completion Year") ///
	ytitle("Receipts per Project") ///
	xtitle("Completion Year") ///
	legend(label(1 "All Projects") label(2 "Interstate Projects") label(3 "Interstate Projects" "with New Construction")) ///
	note( ///
		"Interstate projects are those that have at least one receipt with an interstate federal-aid system code." ///
		`"Interstate projects with new construction are those that have at least one interstate receipt classified as "' ///
		`""new construction roadway", "bridge new construction", or "new tunnel"."', ///
		size(small) span ///
	) ///
	graphregion(margin(l=15 r=15))
graph export "$output/receipts_per_proj_by_year_with_interstate.png", replace width(2500)


/*===============================
 Average receipt cost over time
================================*/
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data

* collapse all receipts
preserve
collapse (mean) total_cost_mills, by(completion_year)
rename total_cost_mills avg_all
tempfile all
save `all'
restore

* collapse interstate receipts only
preserve
keep if interstate_syscode == 1
collapse (mean) total_cost_mills, by(completion_year)
rename total_cost_mills avg_interstate
tempfile interstate
save `interstate'
restore

* collapse interstate new construction only
keep if interstate_syscode == 1
keep if detail_improvementtype == 1 | detail_improvementtype == 8 | detail_improvementtype == 50 // new construction roadway, bridge new construction, and new tunnel
collapse (mean) total_cost_mills, by(completion_year)
rename total_cost_mills avg_interstate_newconstr

* merge all series
merge 1:1 completion_year using `interstate', nogen
merge 1:1 completion_year using `all', nogen
rename completion_year year

* adjust for inflation
merge m:1 year using "$intermediate_data/CPI_2025.dta", nogen
gen avg_all_adj = avg_all / cpi
gen avg_interstate_adj = avg_interstate / cpi
gen avg_interstate_newconstr_adj = avg_interstate_newconstr / cpi

graph twoway line avg_all_adj avg_interstate_adj avg_interstate_newconstr_adj year, sort ///
    title("Average Adjusted Receipt Cost Over Time") ///
    ytitle("Millions of 2025 USD") ///
    xtitle("Completion Year") ///
    ylabel(, format(%9.0fc)) ///
    legend(label(1 "All Receipts") label(2 "Interstate Receipts") label(3 "Interstate Projects" "with New Construction")) ///
    note( ///
        "Interstate classification is defined by federal aid system code." ///
        `"New construction includes receipts for "new construction roadway", "bridge new construction", and "new tunnel"."', ///
        size(small) span ///
    ) ///
	graphregion(margin(l=20 r=5))
graph export "$output/avg_receipt_cost_by_yr_with_interstate.png", replace width(2500)


/*===============================
 Average project cost over time 
================================*/
use "$intermediate_data/project_level_FMIS_lite.dta", clear
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data

* collapse all projects
preserve
collapse (mean) total_cost_mills, by(completion_year)
rename total_cost_mills avg_all
tempfile all
save `all'
restore

* collapse interstate projects only
preserve
keep if interstate_syscode == 1
collapse (mean) total_cost_mills, by(completion_year)
rename total_cost_mills avg_interstate
tempfile interstate
save `interstate'
restore

* collapse interstate new construction projects (projects with at least one interstate new construction receipt)
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if interstate_syscode == 1
keep if detail_improvementtype == 1 | detail_improvementtype == 8 | detail_improvementtype == 50 // new construction roadway, bridge new construction, and new tunnel
keep recipientid federal_project_number
duplicates drop
merge 1:1 recipientid federal_project_number using "$intermediate_data/project_level_FMIS_lite.dta", keep(match) nogen
collapse (mean) total_cost_mills, by(completion_year)
rename total_cost_mills avg_interstate_newconstr
tempfile interstate_newconstr
save `interstate_newconstr'

* merge all series and adjust for inflation
use `all', clear
merge 1:1 completion_year using `interstate', nogen
merge 1:1 completion_year using `interstate_newconstr', nogen
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keep(3) nogen
gen avg_all_adj = avg_all / cpi
gen avg_interstate_adj = avg_interstate / cpi
gen avg_interstate_newconstr_adj = avg_interstate_newconstr / cpi

graph twoway line avg_all_adj avg_interstate_adj avg_interstate_newconstr_adj year, sort ///
    title("Average Adjusted Project Cost Over Time") ///
    ytitle("Millions of 2025 USD") ///
    xtitle("Completion Year") ///
    legend(label(1 "All Projects") label(2 "Interstate Projects") label(3 "Interstate Projects" "with New Construction")) ///
    note( ///
        "Interstate classification is defined by federal aid system code." ///
		`"Interstate projects with new construction are those that have at least one interstate receipt classified as "' ///
		`""new construction roadway", "bridge new construction", or "new tunnel"."', ///
        size(small) span ///
    )
graph export "$output/avg_project_cost_by_yr_with_interstate.png", replace width(2500)



// Average number of receipts for each project code (project ID or project work type?). 
// Average number of receipts per project for each project code (project ID or project work type?). (projects usually have multiple work types and sometimes have multiple federal aid system codes, so there isn't a great way to do this.)

* ==============================================================================

