/*==============================================================================
 	FMIS data exploration
	This script generates outputs related to program codes/funding streams.
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

* load FMIS data
use "$intermediate_data/receipt_level_FMIS_lite_program_codes.dta", clear

// local acronym_notes ///
//     "ISTEA: Intermodal Surface Transportation Efficiency Act" ///
//     "SAFETEA-LU: Safe, Accountable, Flexible, Efficient Transportation Equity Act: A Legacy for Users" ///
//     "FAST Act: Fixing America's Surface Transportation Act" ///
//     "MAP-21: Moving Ahead for Progress in the 21st Century Act" ///
//     "TEA-21: Transportation Equity Act for the 21st Century" ///
//     "STBG: Surface Transportation Block Grant" ///
//     "STP: State Transportation Program" ///
//     "NHPP: National Highway Performance Program" ///
//     "NHS: National Highway System"

rename completion_year year
rename total_cost_mills total_fmis_cost_mills
// gen interstate_func_cost_mills = total_fmis_cost_mills if interstate_functional == 1
// gen interstate_syscode_cost_mills = total_fmis_cost_mills if interstate_syscode == 1
gen fp_ic_cost_mills = total_fmis_cost_mills if funding_program == "Interstate Construction"
gen fp_im_cost_mills = total_fmis_cost_mills if funding_program == "Interstate Maintenance"
gen fp_imd_cost_mills = total_fmis_cost_mills if funding_program == "Interstate Maintenance Discretionary"
gen fp_nhpp_cost_mills = total_fmis_cost_mills if funding_program == "National Highway Performance Program"

* merge in cpi data and adjust for inflation
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen

gen total_fmis_cost_bills_adj = total_fmis_cost_mills / cpi / 1000
// gen int_func_cost_bills_adj = interstate_func_cost_mills / cpi / 1000
// gen int_syscode_cost_bills_adj = interstate_syscode_cost_mills / cpi / 1000
gen fp_ic_cost_bills_adj = fp_ic_cost_mills / cpi / 1000
gen fp_im_cost_bills_adj = fp_im_cost_mills / cpi / 1000
gen fp_imd_cost_bills_adj = fp_imd_cost_mills / cpi / 1000
gen fp_nhpp_cost_bills_adj = fp_nhpp_cost_mills / cpi / 1000

* drop data from early and late years 
drop if total_fmis_cost_bills_adj == .


********************************************************************************
* Figures 
********************************************************************************

/*====
 Top 20 program codes by % spending  
====*/
preserve 
keep if year >= 1950 & year < 2025
gen frequency = 1
collapse (sum) total_fmis_cost_bills_adj frequency (first) program_code_name, by(detail_programcode)
egen total_obs = total(frequency)
gen percent_share = 100 * frequency / total_obs
gsort -percent_share
keep in 1/20
graph hbar percent_share, ///
    over(program_code_name, sort(percent_share) descending label(labsize(vsmall))) ///
    title("Top 20 Program Codes by Share of Costs", size(small)) ///
    ytitle("Percent of Total Costs") ///
    note( ///
        "Data covers 1950-2024." ///
        "Observations are at the receipt level." ///
        "Costs are indexed to 2025 dollars.", ///
        size(vsmall) span ///
    ) ///
    graphregion(margin(l=15 r=15))
graph export "$output/top20_program_codes_cost_share.png", replace width(2500)
restore

/*====
 Top 20 program codes by % spending - interstate only 
====*/
preserve
keep if interstate_syscode == 1
keep if year >= 1950 & year < 2025
gen frequency = 1
collapse (sum) total_fmis_cost_bills_adj frequency (first) program_code_name, by(detail_programcode)
egen total_obs = total(frequency)
gen percent_share = 100 * frequency / total_obs
gsort -percent_share
keep in 1/20
graph hbar percent_share, ///
    over(program_code_name, sort(percent_share) descending label(labsize(vsmall))) ///
    title("Top 20 Program Codes by Share of Costs for Interstate Receipts", size(small)) ///
    ytitle("Percent of Total Costs") ///
    note( ///
        "Data covers 1950-2024." ///
        "Observations are at the receipt level." ///
        "Costs are indexed to 2025 dollars." ///
        "Interstate projects are identified by federal aid system code.", ///
        size(vsmall) span ///
    ) ///
    graphregion(margin(l=15 r=15))
graph export "$output/top20_program_codes_cost_share_interstate.png", replace width(2500)
restore

exit 

/*====
 Program code funding sources 
====*/
preserve
collapse (sum) fp_ic_cost_bills_adj fp_im_cost_bills_adj fp_imd_cost_bills_adj fp_nhpp_cost_bills_adj, by(year)

graph twoway ///
    (line fp_ic_cost_bills_adj year) ///
    (line fp_im_cost_bills_adj year) ///
    (line fp_imd_cost_bills_adj year) ///
    (line fp_nhpp_cost_bills_adj year), ///
    title("Comparison of Program Code Funding Sources") ///
    ytitle("Billions of 2025 USD", xoffset(-3)) ///
    xtitle("Completion Year") ///
    legend(label(1 "Interstate Construction") label(2 "Interstate Maintenance") label(3 "Interstate Maintenance" "Discretionary") label(4 "National Highway" "Performance Program")) ///
    note( ///
		"Observations are at the receipt level." ///
		"A single project may have multiple sources of funding besides the funding sources plotted here.", ///
		size(small) span ///
	) ///
	graphregion(margin(l=15 r=15))
graph export "$output/program_code_explore.png", replace width(2500)
restore