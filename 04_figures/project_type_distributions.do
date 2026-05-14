/*==============================================================================
 	FMIS data exploration
 	Hannah Lu 
	02/25/2026

	This script plots figures showing the distribution of FMIS project types.
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

// * load receipt-level data 
// use "$intermediate_data/receipt_level_FMIS_lite.dta", clear

// * drop data before 1947 (no CPI data)
// * Andy drops data before 1950 to filter out years without much data so we'll do the same actually 
// keep if completion_year >= 1950 & completion_year < 2025 

// * adjust costs for inflation 
// rename completion_year year
// merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
// gen total_cost_mills_adjusted = total_cost_mills / cpi
// gen total_cost_bills_adjusted = total_cost_mills_adjusted / 1000

// * collapse to project code level 
// gen frequency = 1
// collapse (sum) frequency total_cost_bills_adjusted total_cost_mills_adjusted, by(detail_improvementtype)
// gen mean_cost_mills_adjusted = total_cost_mills_adjusted / frequency
// egen total_obs = total(frequency)
// gen percent_share = (frequency / total_obs) * 100
// replace total_cost_bills_adjusted = . if total_cost_bills_adjusted == 0
// replace mean_cost_mills_adjusted = . if mean_cost_mills_adjusted == 0


// * ==============================================================================
// * Figures 
// * ==============================================================================

// * Share of most common improvement types
// preserve
// gsort -percent_share 
// keep in 1/20
// * Note this graph differs very slightly from Andy's in FMIS_exploration.do because he keeps all years of data whereas we drop < 1950 and >= 2025 (which is so we can adjust for inflation)
// graph bar percent_share, ///
//     over(detail_improvementtype, ///
//         sort(percent_share) descending ///
//         label(angle(30) labsize(vsmall))) ///
//     blabel(bar, format(%9.2f)) ///
//     title("Most Common Improvement Types") ytitle("% of Project Receipts")
// graph export "$output/frequency_by_impvmt_types.png", replace
// restore


// * Total cost of the most common improvement types
// preserve
// gsort -total_cost_bills_adjusted 
// keep in 1/20
// graph bar total_cost_bills_adjusted, ///
//     over(detail_improvementtype, ///
//         sort(total_cost_bills_adjusted) descending ///
//         label(angle(30) labsize(vsmall))) ///
//     blabel(bar, format(%9.0f)) ///
// 	title("Total Cost of Most Common Improvement Types") ytitle("Billions of 2025 Dollars")
// graph export "$output/total_cost_by_impvmt_types.png", replace
// restore


// * Avg cost of the most common improvement types
// preserve
// gsort -mean_cost_mills_adjusted 
// keep in 1/20
// graph bar mean_cost_mills_adjusted, ///
//     over(detail_improvementtype, ///
//         sort(mean_cost_mills_adjusted) descending ///
//         label(angle(30) labsize(vsmall))) ///
//     blabel(bar, format(%9.2f)) ///
//     title("Average Cost per Receipt of Most Common Improvement Types") ytitle("Millions of 2025 Dollars")
// graph export "$output/ave_cost_by_impvmt_types.png", replace
// restore

* ==============================================================================
* Breakdown by decade
* ==============================================================================

* load receipt-level data 
// use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
use "$intermediate_data/receipt_level_FMIS_lite_program_codes.dta", clear

* drop data before 1947 (no CPI data)
* Note Andy drops data before 1950 to filter out years without much data
rename completion_year year
keep if year < 2025 & year >= 1947

* adjust costs for inflation 
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_cost_mills_adjusted = total_cost_mills / cpi
gen total_cost_bills_adjusted = total_cost_mills_adjusted / 1000

gen decade = floor(year/10)*10
gen frequency = 1


* ==============================================================================

* identify top 10 improvement types overall by frequency
// preserve
//     keep if year >= 1950 // Andy drops data before 1950 to filter out years without much data
//     collapse (sum) frequency, by(detail_improvementtype)
//     gsort -frequency
//     keep in 1/10
//     gen overall_rank = _n
//     keep detail_improvementtype overall_rank
//     tempfile top10freq
//     save `top10freq'
// restore

// * identify top 10 improvement types overall by frequency
// preserve
//     keep if year >= 1950 // Andy drops data before 1950 to filter out years without much data
//     collapse (sum) total_cost_bills_adjusted, by(detail_improvementtype)
//     gsort -total_cost_bills_adjusted
//     keep in 1/10
//     gen overall_rank = _n
//     keep detail_improvementtype overall_rank
//     tempfile top10cost
//     save `top10cost'
// restore

// tempfile processed_data 
// save `processed_data'

// * keep only top 10 improvement types by frequency 
// merge m:1 detail_improvementtype using `top10freq', keep(3) nogen

// collapse (sum) frequency (first) overall_rank, by(decade detail_improvementtype)

// * compute within-decade shares 
// bys decade: egen total_obs_decade = total(frequency)
// gen percent_share_decade = 100 * frequency / total_obs_decade


// * plot top improvement types by decade
// levelsof decade, local(decades)
// foreach d of local decades {
//     if `d' < 1950 { // Andy drops data before 1950 to filter out years without much data
//         continue
//     }
//     display "Plotting decade `d'"

//     * plot share of top 10 improvement types
//     preserve
//         keep if decade == `d'
//         collapse (sum) frequency, by(detail_improvementtype)
//         egen total_obs = total(frequency)
//         gen percent_share = 100 * frequency / total_obs
//         gsort -percent_share
//         keep in 1/10
//         graph hbar percent_share, ///
//             over(detail_improvementtype, ///
//                 sort(percent_share) descending ///
//                 label(labsize(small))) ///
//             blabel(none) ///
//             ylabel(0(10)60) ///
//             title("Top Improvement Types in the `d's" "by Receipt Frequency") ///
//             ytitle("% of Receipts") ///
//             note("Top improvement codes are specific to this decade and may not match the top improvement codes across all years.", size(small) span)
//         graph export "$output/top_impvmt_types_freq_`d'.png", replace
//     restore

//     * repeat for interstate-only 
//     preserve
//         keep if interstate_syscode == 1
//         keep if decade == `d'
//         collapse (sum) frequency, by(detail_improvementtype)
//         egen total_obs = total(frequency)
//         gen percent_share = 100 * frequency / total_obs
//         gsort -percent_share
//         keep in 1/10
//         graph hbar percent_share, ///
//             over(detail_improvementtype, ///
//                 sort(percent_share) descending ///
//                 label(labsize(small))) ///
//             blabel(none) ///
//             ylabel(0(10)60) ///
//             title("Top Improvement Types in the `d's for Interstates" "by Receipt Frequency") ///
//             ytitle("% of Receipts") ///
//             note( ///
//                 "Interstate projects identified by federal-aid system code." /// 
//                 "Top improvement codes are specific to this decade and may not match the top improvement codes across all years.", ///
//                 size(small) span ///
//             )
//         graph export "$output/top_impvmt_types_freq_interstate_`d'.png", replace
//     restore

//     * plot total cost of top 10 improvement types
//     preserve
//     keep if decade == `d'
//     collapse (sum) total_cost_bills_adjusted, by(detail_improvementtype)
//     gsort -total_cost_bills_adjusted
//     keep in 1/10
//     graph hbar total_cost_bills_adjusted, ///
//         over(detail_improvementtype, ///
//             sort(total_cost_bills_adjusted) descending ///
//             label(labsize(small))) ///
//         blabel(none) ///
//         ylabel(0(10)110) ///
//         title("Top Improvement Types in the `d's" "by Total Cost") ///
//         ytitle("Billions of 2025 Dollars") ///
//         note("Top improvement codes are specific to this decade and may not match the top improvement codes across all years.", size(small) span)
//     graph export "$output/top_impvmt_types_cost_`d'.png", replace
//     restore

//     * repeat for interstate-only 
//     preserve
//         keep if interstate_syscode == 1
//         keep if decade == `d'
//         collapse (sum) total_cost_bills_adjusted, by(detail_improvementtype)
//         gsort -total_cost_bills_adjusted
//         keep in 1/10
//         graph hbar total_cost_bills_adjusted, ///
//             over(detail_improvementtype, ///
//                 sort(total_cost_bills_adjusted) descending ///
//                 label(labsize(small))) ///
//                 blabel(none) ///
//                 ylabel(0(10)110) ///
//                 title("Top Improvement Types in the `d's for Interstates" "by Total Cost") ///
//                 ytitle("Billions of 2025 Dollars") ///
//                 note( ///
//                     "Interstate projects identified by federal-aid system code." /// 
//                     "Top improvement codes are specific to this decade and may not match the top improvement codes across all years.", ///
//                     size(small) span ///
//                 )
//         graph export "$output/top_impvmt_types_cost_interstate_`d'.png", replace
//     restore
// }


* plot top improvement types by cost for interstate between 1950-1993 
preserve
keep if interstate_syscode == 1
keep if year >= 1950 & year <= 1993
collapse (sum) total_cost_bills_adjusted, by(detail_improvementtype)
gsort -total_cost_bills_adjusted
keep in 1/20
graph hbar total_cost_bills_adjusted, ///
    over(detail_improvementtype, sort(total_cost_bills_adjusted) descending label(labsize(vsmall))) ///
    title("Top Improvement Types by Cost for Interstate" "(System Code) Reimbursements") ///
    subtitle("1950-1993", size(medium)) ///
    ytitle("Billions of 2025 Dollars") ///
    note( ///
        "Interstate reimbursements identified by federal-aid system code.", ///
        size(small) span ///
    )
graph export "$output/top_impvmt_types_cost_interstate_1950_1993.png", replace
restore

* plot top improvement types by cost for Interstate Construction funding stream between 1950-1993 
preserve
keep if funding_program == "Interstate Construction"
keep if year >= 1950 & year <= 1993
collapse (sum) total_cost_bills_adjusted, by(detail_improvementtype)
gsort -total_cost_bills_adjusted
keep in 1/20
graph hbar total_cost_bills_adjusted, ///
    over(detail_improvementtype, sort(total_cost_bills_adjusted) descending label(labsize(vsmall))) ///
    title("Top Improvement Types by Cost for Reimbursements from the"  `""Interstate Construction" Funding Stream"', size(medium)) ///
    subtitle("1950-1993", size(medium)) ///
    ytitle("Billions of 2025 Dollars") ///
    note( ///
        "Interstate Construction reimbursements identified by funding program code.", ///
        size(small) span ///
    )
graph export "$output/top_impvmt_types_cost_IC_1950_1993.png", replace
restore

exit

* get distribution of project types pre 1956 (by adjusted cost)
preserve 
keep if year >= 1950 & year < 1956
collapse (sum) total_cost_bills_adjusted, by(detail_improvementtype)
graph hbar total_cost_bills_adjusted, ///
    over(detail_improvementtype, sort(total_cost_bills_adjusted) descending) ///
    title("Distribution of FMIS Project Types Before 1956") ///
    ytitle("Billions of 2025 Dollars") ///
    note("Data covers 1950-1955.")
graph export "$output/top_impvmt_types_cost_1950_1955.png", replace

restore 

* ==============================================================================
* Distribution of spending by federal aid system code
* ==============================================================================

* get distribution of spending by federal aid system code 
preserve 
keep if year >= 1950 & year < 2025 
collapse (sum) total_cost_bills_adjusted, by(system_code)

gsort -total_cost_bills_adjusted
graph hbar total_cost_bills_adjusted, over(system_code) ///
    title("Distribution of FMIS Spending by Federal-Aid System Code") ///
    ytitle("Billions of 2025 Dollars") ///
    note("Data covers 1950-2024.") ///
    graphregion(margin(l=15 r=25))
graph export "$output/system_code_by_cost.png", replace
restore 

* get distribution of spending by federal aid system code 1950-1955
preserve 
keep if year >= 1950 & year < 1956
collapse (sum) total_cost_bills_adjusted, by(system_code)

gsort -total_cost_bills_adjusted
graph hbar total_cost_bills_adjusted, ///
    over(system_code, label(labsize(small))) ///
    title("Distribution of FMIS Spending by Federal-Aid System Code, 1950-1955", size(medsmall)) ///
    ytitle("Billions of 2025 Dollars") ///
    note("Data covers 1950-1955.") ///
    graphregion(margin(l=15 r=25))
graph export "$output/system_code_by_cost_1950_1955.png", replace
restore 