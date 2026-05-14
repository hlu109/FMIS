/*==============================================================================
 	FMIS data exploration
	This script plots figures related to project durations.
==============================================================================*/
* only need to install once 
// ssc install tab_chi

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
global duration_dir "$output/project_duration"
if !direxists("$duration_dir") mkdir "$duration_dir"
global pr511_intermediate "$intermediate_data/pr_511"
if !direxists("$pr511_intermediate") mkdir "$pr511_intermediate"

* ==============================================================================

use "$intermediate_data/receipt_level_FMIS.dta", clear
drop projectdescription recipientremarks divisionremarks nongis_countyid gisbreakdown_countyid gis_routeid // cut down size by removing unnecessary variables (but we want to keep title for some diagnostics)
drop projecttitle

keep if funding_program == "Interstate Construction"
drop if completion_year < 1950 | completion_year > 2025 | mi(completion_year)
gen byte has_completedate = !mi(completedate)
gen byte has_both_dates = !mi(completedate) & !mi(authconstdate)
gen const_duration = (completedate - authconstdate) / 365 if !mi(completedate) & !mi(authconstdate)
gen authconstyear = year(authconstdate)
gen byte total_rows = 1

* adjust for inflation
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keep(3) keepusing(cpi) nogen
gen total_cost_bills_adj = total_cost_mills / cpi / 1000
rename year completion_year
drop cpi total_cost_mills

* ==============================================================================
// * look at outliers with really long durations of construction stage 
// // preserve
// drop if mi(is_construction) | !is_construction
// drop if mi(const_duration)
// keep if const_duration > 20 // years 

// gen pseudo_route = substr(strtrim(federal_project_number), 1, 3)

// order recipientid federal_project_number const_duration authconstdate completedate projecttitle detail_improvementtype 
// di "tabulations of construction projects with durations over 20 years (includes new construction, reconstruction, and rehabilitation)"

// tab state_fips, sort
// tab state_fips [aw=total_cost_bills_adj], sort
// exit

// tab completion_year, sort
// tab completion_year [aw=total_cost_bills_adj], sort
// tab authconstyear, sort
// tab authconstyear [aw=total_cost_bills_adj], sort

// tabsort state_fips completion_year
// tabsort state_fips authconstyear
// // restore 

// exit

// * cut down the dataset size for the remainder of this script 
// drop projecttitle 

// keep if federal_project_number == "0156084-01" | federal_project_number == "0105057-01" | federal_project_number == "0647014-01" | federal_project_number == "0645005-01" | federal_project_number == "0793224" | federal_project_number == "2955045" | federal_project_number == "0702107-01" | federal_project_number == "902008" | federal_project_number == "0031040" | federal_project_number == "0056106"
// drop projectdescription recipientremarks divisionremarks nongis_countyid gisbreakdown_countyid gis_routeid 
// // cut down size by removing unnecessary variables (but we want to keep title for some diagnostics)
// gen const_duration = (completedate - authconstdate) / 365 if !mi(completedate) & !mi(authconstdate)
// drop if const_duration < 20 | const_duration == .
// order recipientid federal_project_number const_duration authsprdate authpedate authrowdate authconstdate completedate projecttitle detail_improvementtype 
// gsort -const_duration 

* ==============================================================================
* number of reimbursements over time that have a construction start and end date (all IC; count)

// preserve
// collapse ///
//     (sum) has_completedate has_both_dates total_rows, by(completion_year)
// replace total_rows = total_rows / 1000
// replace has_completedate = has_completedate / 1000
// replace has_both_dates = has_both_dates / 1000

// graph twoway ///
//     (line total_rows completion_year) ///
//     (line has_completedate completion_year) ///
//     (line has_both_dates completion_year), ///
//     title("Number of Reimbursements with Construction Start and End Dates", size(medium)) ///
//     subtitle("Interstate Construction", size(small)) ///
//     ytitle("Thousands of Reimbursements") ///
//     xtitle("Completion Year") ///
//     xlabel(1950(10)2025) ///
//     legend( ///
//         label(1 "All reimbursements") ///
//         label(2 "Has complete date") ///
//         label(3 "Has construction" "authorization and" "complete date") ///
//         size(small) ///
//     ) ///
//     note( ///
//         `"Reimbursements are identified by the "Interstate Construction" funding program codes."', ///
//         size(small) span ///
//     )
// graph export "$duration_dir/reimb_construction_dates_IC.png", replace width(2500)

// * share of reimbursements over time that have a construction start and end date (all IC; count)
// gen pct_has_completedate = 100 * has_completedate / total_rows if total_rows > 0
// gen pct_has_both_dates = 100 * has_both_dates / total_rows if total_rows > 0

// graph twoway ///
//     (line pct_has_completedate completion_year) ///
//     (line pct_has_both_dates completion_year), ///
//     title("Share of Reimbursements with Construction Start and End Dates", size(medium)) ///
//     subtitle("Interstate Construction", size(small)) ///
//     ytitle("Percent of reimbursements") ///
//     xtitle("Completion Year") ///
//     xlabel(1950(10)2025) ///
//     ylabel(0(10)100) ///
//     legend( ///
//         label(1 "Has complete date") ///
//         label(2 "Has construction" "authorization and" "complete date") ///
//         size(small) ///
//     ) ///
//     note( ///
//         `"Reimbursements are identified by the "Interstate Construction" funding program codes."', ///
//         size(small) span ///
//     )
// graph export "$duration_dir/reimb_construction_dates_IC_share.png", replace width(2500)
// restore


// * number of reimbursements over time that have a construction start and end date (all IC; cost weight)
// // TODO 


// * share of reimbursements over time that have a construction start and end date (all IC; cost weight)
// // TODO 




// * number of reimbursements over time that have a construction start and end date (IC, construction; count)
// preserve 
// keep if is_construction
// collapse ///
//     (sum) has_completedate has_both_dates total_rows, by(completion_year)
// replace total_rows = total_rows / 1000
// replace has_completedate = has_completedate / 1000
// replace has_both_dates = has_both_dates / 1000

// graph twoway ///
//     (line total_rows completion_year) ///
//     (line has_completedate completion_year) ///
//     (line has_both_dates completion_year), ///
//     title("Number of Reimbursements with Construction Start and End Dates", size(medium)) ///
//     subtitle("Interstate Construction; construction improvement types only", size(small)) ///
//     ytitle("Thousands of Reimbursements") ///
//     xtitle("Completion Year") ///
//     xlabel(1950(10)2025) ///
//     legend( ///
//         label(1 "All reimbursements") ///
//         label(2 "Has complete date") ///
//         label(3 "Has construction" "authorization and" "complete date") ///
//         size(small) ///
//     ) ///
//     note( ///
//         `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
//         "Included construction improvement types are new construction, reconstruction, and rehabilitation: " ///
//         "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
//         "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete)," "bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
//         "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation." ///
//         "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance.", ///
//         size(vsmall) span ///
//     )
// graph export "$duration_dir/reimb_construction_dates_IC_const.png", replace width(2500)

// * share of reimbursements over time that have a construction start and end date (IC, construction; count)
// gen pct_has_completedate = 100 * has_completedate / total_rows if total_rows > 0
// gen pct_has_both_dates = 100 * has_both_dates / total_rows if total_rows > 0

// graph twoway ///
//     (line pct_has_completedate completion_year) ///
//     (line pct_has_both_dates completion_year), ///
//     title("Share of Reimbursements with Construction Start and End Dates", size(medium)) ///
//     subtitle("Interstate Construction; construction improvement types only", size(small)) ///
//     ytitle("Percent of reimbursements") ///
//     xtitle("Completion Year") ///
//     xlabel(1950(10)2025) ///
//     ylabel(0(10)100) ///
//     legend( ///
//         label(1 "Has complete date") ///
//         label(2 "Has construction" "authorization and" "complete date") ///
//         size(small) ///
//     ) ///
//     note( ///
//         `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
//         "Included construction improvement types are new construction, reconstruction, and rehabilitation: " ///
//         "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
//         "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete)," "bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
//         "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation." ///
//         "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance.", ///
//         size(vsmall) span ///
//     )
// graph export "$duration_dir/reimb_construction_dates_IC_const_share.png", replace width(2500)
// restore

// * share of reimbursements over time that have a construction start and end date (IC, construction; count)
// * BY CONSTRUCTION TYPE
// preserve 
// keep if !mi(work_type)
// collapse ///
//     (sum) has_completedate has_both_dates total_rows, by(completion_year work_type)
// replace total_rows = total_rows / 1000
// replace has_both_dates = has_both_dates / 1000
// gen pct_has_both_dates = 100 * has_both_dates / total_rows

// graph twoway ///
//     (line pct_has_both_dates completion_year if work_type == 1) ///
//     (line pct_has_both_dates completion_year if work_type == 2) ///
//     (line pct_has_both_dates completion_year if work_type == 3) ///
//     (line pct_has_both_dates completion_year if work_type == 4), ///
//     title("Share of Reimbursements with Both Construction Start and End Dates", size(medium)) ///
//     subtitle("Interstate Construction; by construction type", size(small)) ///
//     ytitle("Percent of reimbursements") ///
//     xtitle("Completion Year") ///
//     xlabel(1950(10)2025) ///
//     legend( ///
//         label(1 "New Construction") ///
//         label(2 "Reconstruction") ///
//         label(3 "Rehabilitation") ///
//         label(4 "Maintenance") ///
//         size(small) ///
//     ) ///
//     note( ///
//         `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
//         "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
//         "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete)," "bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
//         "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation." ///
//         "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance.", ///
//         size(vsmall) span ///
//     )
// graph export "$duration_dir/reimb_construction_dates_IC_const_share_by_type.png", replace width(2500)
// restore

* number of reimbursements over time that have a construction start and end date (IC, construction; cost weight)
* share of reimbursements over time that have a construction start and end date (IC, construction; cost weight)

* ==============================================================================
* project durations 
* ==============================================================================
* avg project duration over time for IC reimbursements, separated by improvement type for main types of construction
drop if mi(completedate) | mi(authconstdate)
drop if mi(work_type)

tempfile ic_duration_base
save `ic_duration_base', replace

// foreach subsample in full cty_per_yr cty_rt_per_yr cty_life cty_rt_life cty_openyr_ever cty_rt_openyr_ever {
foreach subsample in full {
    use `ic_duration_base', clear

    if "`subsample'" == "full" {
        local fig_suffix "_full"
        local sample_note ""
        local sample_size_note = ""
    }
    else if "`subsample'" == "cty_per_yr" {
        local fig_suffix "_cty_max1chain_per_yr"
        local sample_note "Sample restricted to counties with at most one PR-511 chain per opening year."
        merge m:1 county_fips using "$pr511_intermediate/pr511_cty_max_one_chain_per_yr.dta", keep(3) nogen
        * count unique number of counties
        preserve
        keep county_fips
        duplicates drop
        local sample_size_note = "Number of unique counties: `=string(_N, "%9.0fc")'."
        restore
    }
    else if "`subsample'" == "cty_rt_per_yr" {
        local fig_suffix "_cty_rt_max1chain_per_yr"
        local sample_note "Sample restricted to county x route cells with at most one PR-511 chain per opening year."
        gen str3 fpn_prefix = substr(strtrim(federal_project_number), 1, 3)
        gen strL route = ustrregexra(fpn_prefix, "[^0-9]", "")
        destring route, replace
        drop fpn_prefix
        merge m:1 county_fips route using "$pr511_intermediate/pr511_cty_rt_max_one_chain_per_yr.dta", keep(3) nogen
        * count unique number of county x route cells
        preserve
        keep county_fips route
        duplicates drop
        local sample_size_note = "Number of unique county x route cells: `=string(_N, "%9.0fc")'."
        restore
    }
    else if "`subsample'" == "cty_life" {
        local fig_suffix "_cty_1chain_ever"
        local sample_note "Sample restricted to counties with only one PR-511 chain across all years."
        merge m:1 county_fips using "$pr511_intermediate/pr511_cty_single_chain_ever.dta", keep(3) nogen
        * count unique number of counties
        preserve
        keep county_fips
        duplicates drop
        local sample_size_note = "Number of unique counties: `=string(_N, "%9.0fc")'."
        restore
    }
    else if "`subsample'" == "cty_rt_life" {
        local fig_suffix "_cty_rt_1chain_ever"
        local sample_note "Sample restricted to county x route cells with only one PR-511 chain across all years."
        gen str3 fpn_prefix = substr(strtrim(federal_project_number), 1, 3)
        gen strL route = ustrregexra(fpn_prefix, "[^0-9]", "")
        destring route, replace
        drop fpn_prefix
        merge m:1 county_fips route using "$pr511_intermediate/pr511_cty_rt_single_chain_ever.dta", keep(3) nogen
        * count unique number of county x route cells
        preserve
        keep county_fips route
        duplicates drop
        local sample_size_note = "Number of unique county x route cells: `=string(_N, "%9.0fc")'."
        restore
    }
    else if "`subsample'" == "cty_openyr_ever" {
        local fig_suffix "_cty_1openyr_ever"
        local sample_note "Sample restricted to counties where all chains opened in a single year."
        merge m:1 county_fips using "$pr511_intermediate/pr511_cty_single_openyr_ever.dta", keep(3) nogen
        * count unique number of counties
        preserve
        keep county_fips
        duplicates drop
        local sample_size_note = "Number of unique counties: `=string(_N, "%9.0fc")'."
        restore
    }
    else if "`subsample'" == "cty_rt_openyr_ever" {
        local fig_suffix "_cty_rt_1openyr_ever"
        local sample_note "Sample restricted to county x route cells where all chains opened in a single year."
        gen str3 fpn_prefix = substr(strtrim(federal_project_number), 1, 3)
        gen strL route = ustrregexra(fpn_prefix, "[^0-9]", "")
        destring route, replace
        drop fpn_prefix
        merge m:1 county_fips route using "$pr511_intermediate/pr511_cty_rt_single_openyr_ever.dta", keep(3) nogen
        * count unique number of county x route cells
        preserve
        keep county_fips route
        duplicates drop
        local sample_size_note = "Number of unique county x route cells: `=string(_N, "%9.0fc")'."
        restore
    }


    * ==========================
    * Duration Averages 
    * ==========================
    // preserve
    // drop if completion_year > 2000
    // collapse (mean) const_duration, by(completion_year work_type)

    // graph twoway ///
    //     (line const_duration completion_year if work_type == 1) ///
    //     (line const_duration completion_year if work_type == 2) ///
    //     (line const_duration completion_year if work_type == 3) ///
    //     (line const_duration completion_year if work_type == 4), ///
    //     title("Average Construction Work Duration by Improvement Type" "for Interstate Construction Reimbursements", size(medium)) ///
    //     ytitle("Years") ///
    //     xtitle("Completion Year") ///
    //     legend( ///
    //         label(1 "New Construction") ///
    //         label(2 "Reconstruction") ///
    //         label(3 "Rehabilitation") ///
    //         label(4 "Maintenance") ///
    //         size(small) ///
    //     ) ///
    //     note( ///
    //         `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
    //         "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
    //         "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
    //         "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete)," "bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
    //         "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation." ///
    //         "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance." ///
    //         `"`sample_note'"' ///
    //         `"`sample_size_note'"' ///
    //         , size(vsmall) span ///
    //     )
    // graph export "$duration_dir/IC_const_duration_by_impvmt_type`fig_suffix'.png", replace width(2500)
    // restore

    * same as above but with cost-weighted mean duration
    preserve
    drop if completion_year > 2000
    collapse (mean) const_duration [aw=total_cost_bills_adj], by(completion_year work_type)
    graph twoway ///
        (line const_duration completion_year if work_type == 1) ///
        (line const_duration completion_year if work_type == 2) ///
        (line const_duration completion_year if work_type == 3) ///
        (line const_duration completion_year if work_type == 4), ///
        title("Cost-Weighted Average Construction Work Duration by Improvement Type" "for Interstate Construction Reimbursements", size(medium)) ///
        ytitle("Years") ///
        xtitle("Completion Year") ///
        legend( ///
            label(1 "New Construction") ///
            label(2 "Reconstruction") ///
            label(3 "Rehabilitation") ///
            label(4 "Maintenance") ///
            size(small) ///
        ) ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Means are weighted by reimbursement cost (billions of 2025 USD)." ///
            "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
            "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
            "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete)," "bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
            "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation." ///
            "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(vsmall) span ///
        ) ///
        graphregion(margin(l=15 r=15))
    graph export "$duration_dir/IC_const_duration_by_impvmt_type_costwgt`fig_suffix'.png", replace width(2500)
    restore

    * same as above but plot against the authorization date instead, no cost weighting 
    // preserve
    // drop if authconstyear < 1940 | authconstyear > 2000
    // collapse (mean) const_duration, by(authconstyear work_type)
    // graph twoway ///
    //     (line const_duration authconstyear if work_type == 1) ///
    //     (line const_duration authconstyear if work_type == 2) ///
    //     (line const_duration authconstyear if work_type == 3) ///
    //     (line const_duration authconstyear if work_type == 4), ///
    //     title("Average Construction Work Duration by Improvement Type" "for Interstate Construction Reimbursements", size(medium)) ///
    //     ytitle("Years") ///
    //     xtitle("Authorization Year") ///
    //     legend( ///
    //         label(1 "New Construction") ///
    //         label(2 "Reconstruction") ///
    //         label(3 "Rehabilitation") ///
    //         label(4 "Maintenance") ///
    //         size(small) ///
    //     ) ///
    //     note( ///
    //         `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
    //         "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
    //         "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
    //         "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete)," "bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
    //         "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation." ///
    //         "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance." ///
    //         `"`sample_note'"' ///
    //         `"`sample_size_note'"' ///
    //         , size(vsmall) span ///
    //     )
    // graph export "$duration_dir/IC_const_duration_by_impvmt_type_by_authconst`fig_suffix'.png", replace width(2500)
    // restore

    * same as above with cost-weighted mean duration (by authorization year)
    preserve
    drop if authconstyear < 1940 | authconstyear > 2000
    collapse (mean) const_duration [aw=total_cost_bills_adj], by(authconstyear work_type)
    graph twoway ///
        (line const_duration authconstyear if work_type == 1) ///
        (line const_duration authconstyear if work_type == 2) ///
        (line const_duration authconstyear if work_type == 3) ///
        (line const_duration authconstyear if work_type == 4), ///
        title("Cost-Weighted Average Construction Work Duration by Improvement Type" "for Interstate Construction Reimbursements", size(medium)) ///
        ytitle("Years") ///
        xtitle("Authorization Year") ///
        legend( ///
            label(1 "New Construction") ///
            label(2 "Reconstruction") ///
            label(3 "Rehabilitation") ///
            label(4 "Maintenance") ///
            size(small) ///
        ) ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Means are weighted by spending in 2025 USD." ///
            "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
            "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
            "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete)," "bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
            "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation." ///
            "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(vsmall) span ///
        ) ///
        graphregion(margin(l=15 r=15))
    graph export "$duration_dir/IC_const_duration_by_impvmt_type_by_authconst_costwgt`fig_suffix'.png", replace width(2500)
    restore


    * ==========================
    * duration by percentile, new construction only (p10, p25, p50, p75, p90) over time
    * ==========================
    // preserve
    // keep if work_type == 1
    // drop if completion_year > 2000
    // collapse (p10) d_p10=const_duration (p25) d_p25=const_duration (p50) d_p50=const_duration (p75) d_p75=const_duration (p90) d_p90=const_duration, by(completion_year)

    // graph twoway ///
    //     (line d_p10 completion_year) ///
    //     (line d_p25 completion_year) ///
    //     (line d_p50 completion_year) ///
    //     (line d_p75 completion_year) ///
    //     (line d_p90 completion_year), ///
    //     title("Percentiles of Construction Work Duration" "New Construction; Interstate Construction Reimbursements", size(medium)) ///
    //     ytitle("Years") ///
    //     xtitle("Completion Year") ///
    //     legend( ///
    //         order(5 4 3 2 1) ///
    //         label(1 "10th pctile") ///
    //         label(2 "25th pctile") ///
    //         label(3 "50th pctile") ///
    //         label(4 "75th pctile") ///
    //         label(5 "90th pctile") ///
    //         size(small) ///
    //     ) ///
    //     note( ///
    //         `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
    //         "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
    //         "Sample restricted to new construction reimbursements: new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
    //         "Percentiles (10th, 25th, 50th, 75th, 90th) are computed within each completion year." ///
    //         `"`sample_note'"' ///
    //         `"`sample_size_note'"' ///
    //         , size(vsmall) span ///
    //     )
    // graph export "$duration_dir/IC_const_duration_newconstr_pctiles_by_completedate`fig_suffix'.png", replace width(2500)
    // restore

    * same as above but cost-weighted 
    preserve
    keep if work_type == 1
    drop if completion_year > 2000
    collapse (p10) d_p10=const_duration (p25) d_p25=const_duration (p50) d_p50=const_duration (p75) d_p75=const_duration (p90) d_p90=const_duration [aw=total_cost_bills_adj], by(completion_year)

    graph twoway ///
        (line d_p10 completion_year) ///
        (line d_p25 completion_year) ///
        (line d_p50 completion_year) ///
        (line d_p75 completion_year) ///
        (line d_p90 completion_year), ///
        title("Cost-Weighted Percentiles of Construction Work Duration" "New Construction; Interstate Construction Reimbursements", size(medium)) ///
        ytitle("Years") ///
        xtitle("Completion Year") ///
        legend( ///
            order(5 4 3 2 1) ///
            label(1 "10th pctile") ///
            label(2 "25th pctile") ///
            label(3 "50th pctile") ///
            label(4 "75th pctile") ///
            label(5 "90th pctile") ///
            size(small) ///
        ) ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Percentiles are weighted by reimbursement cost (billions of 2025 USD)." ///
            "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
            "Sample restricted to new construction reimbursements: new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
            "Percentiles (10th, 25th, 50th, 75th, 90th) are computed within each completion year." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(vsmall) span ///
        ) ///
        graphregion(margin(l=15 r=15))
    graph export "$duration_dir/IC_const_duration_newconstr_pctiles_by_completedate_costwgt`fig_suffix'.png", replace width(2500)
    restore

    * same as above but plot against the authorization date instead, no cost weighting 
    // preserve
    // keep if work_type == 1
    // drop if authconstyear < 1940 | authconstyear > 2000
    // collapse (p10) d_p10=const_duration (p25) d_p25=const_duration (p50) d_p50=const_duration (p75) d_p75=const_duration (p90) d_p90=const_duration, by(authconstyear)

    // graph twoway ///
    //     (line d_p10 authconstyear) ///
    //     (line d_p25 authconstyear) ///
    //     (line d_p50 authconstyear) ///
    //     (line d_p75 authconstyear) ///
    //     (line d_p90 authconstyear), ///
    //     title("Percentiles of Construction Work Duration" "New Construction; Interstate Construction Reimbursements", size(medium)) ///
    //     ytitle("Years") ///
    //     xtitle("Authorization Year") ///
    //     legend( ///
    //         order(5 4 3 2 1) ///
    //         label(1 "10th pctile") ///
    //         label(2 "25th pctile") ///
    //         label(3 "50th pctile") ///
    //         label(4 "75th pctile") ///
    //         label(5 "90th pctile") ///
    //         size(small) ///
    //     ) ///
    //     note( ///
    //         `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
    //         "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
    //         "Sample restricted to new construction reimbursements: new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
    //         "Percentiles (10th, 25th, 50th, 75th, 90th) are computed within each authorization year." ///
    //         `"`sample_note'"' ///
    //         `"`sample_size_note'"' ///
    //         , size(vsmall) span ///
    //     )
    // graph export "$duration_dir/IC_const_duration_newconstr_pctiles_by_authconst`fig_suffix'.png", replace width(2500)
    // restore

    * same as above but cost-weighted 
    preserve
    keep if work_type == 1
    drop if authconstyear < 1940 | authconstyear > 2000
    collapse (p10) d_p10=const_duration (p25) d_p25=const_duration (p50) d_p50=const_duration (p75) d_p75=const_duration (p90) d_p90=const_duration [aw=total_cost_bills_adj], by(authconstyear)

    graph twoway ///
        (line d_p10 authconstyear) ///
        (line d_p25 authconstyear) ///
        (line d_p50 authconstyear) ///
        (line d_p75 authconstyear) ///
        (line d_p90 authconstyear), ///
        title("Cost-Weighted Percentiles of Construction Work Duration" "New Construction; Interstate Construction Reimbursements", size(medium)) ///
        ytitle("Years") ///
        xtitle("Authorization Year") ///
        legend( ///
            order(5 4 3 2 1) ///
            label(1 "10th pctile") ///
            label(2 "25th pctile") ///
            label(3 "50th pctile") ///
            label(4 "75th pctile") ///
            label(5 "90th pctile") ///
            size(small) ///
        ) ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Percentiles are weighted by spending in 2025 USD." ///
            "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
            "Sample restricted to new construction reimbursements: new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
            "Percentiles (10th, 25th, 50th, 75th, 90th) are computed within each authorization year." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(vsmall) span ///
        ) ///
        graphregion(margin(l=15 r=15))
    graph export "$duration_dir/IC_const_duration_newconstr_pctiles_by_authconst_costwgt`fig_suffix'.png", replace width(2500)
    restore


    * ==========================================================================
    * histogram of durations 
    * ==========================================================================
    // * histogram of duration for all reimbursements for any construction
    // preserve
    // drop if mi(const_duration)
    // keep if is_construction
    // histogram const_duration, frequency ///
    //     title("Time between construction authorization and completion", size(medium)) ///
    //     subtitle("Interstate Construction; new construction, reconstruction, and rehabilitation reimbursements", size(small)) ///
    //     xtitle("Years") ///
    //     ytitle("Number of reimbursements") ///
    //     ylabel(, format(%9.0fc)) ///
    //     note( ///
    //         `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
    //         "Sample excludes maintenance reimbursements." ///
    //         `"`sample_note'"' ///
    //         `"`sample_size_note'"' ///
    //         , size(small) span ///
    //     )
    // graph export "$duration_dir/IC_const_duration_hist_any_construction`fig_suffix'.png", replace width(2500)
    // restore

    // * histogram of duration for reimbursements for new construction
    // preserve
    // drop if mi(const_duration)
    // keep if work_type == 1
    // histogram const_duration, frequency ///
    //     title("Time between construction authorization and completion", size(medium)) ///
    //     subtitle("Interstate Construction; new construction reimbursements", size(small)) ///
    //     xtitle("Years") ///
    //     ytitle("Number of reimbursements") ///
    //     ylabel(, format(%9.0fc)) ///
    //     note( ///
    //         `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
    //         "Sample restricted to new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
    //         `"`sample_note'"' ///
    //         `"`sample_size_note'"' ///
    //         , size(small) span ///
    //     )
    // graph export "$duration_dir/IC_const_duration_hist_newconstr`fig_suffix'.png", replace width(2500)
    // restore

    // * histogram of duration for reimbursements for reconstruction
    // preserve
    // drop if mi(const_duration)
    // keep if work_type == 2
    // histogram const_duration, frequency ///
    //     title("Time between construction authorization and completion", size(medium)) ///
    //     subtitle("Interstate Construction; reconstruction reimbursements", size(small)) ///
    //     xtitle("Years") ///
    //     ytitle("Number of reimbursements") ///
    //     ylabel(, format(%9.0fc)) ///
    //     note( ///
    //         `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
    //         "Sample restricted to 4R reconstruction, 4R added or no added capacity, bridge replacement, and tunnel replacement." ///
    //         `"`sample_note'"' ///
    //         `"`sample_size_note'"' ///
    //         , size(small) span ///
    //     )
    // graph export "$duration_dir/IC_const_duration_hist_reconstr`fig_suffix'.png", replace width(2500)
    // restore

    // * histogram of duration for reimbursements for rehabilitation
    // preserve
    // drop if mi(const_duration)
    // keep if work_type == 3
    // histogram const_duration, frequency ///
    //     title("Time between construction authorization and completion", size(medium)) ///
    //     subtitle("Interstate Construction; rehabilitation reimbursements", size(small)) ///
    //     xtitle("Years") ///
    //     ytitle("Number of reimbursements") ///
    //     ylabel(, format(%9.0fc)) ///
    //     note( ///
    //         `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
    //         "Sample restricted to 4R restoration and rehabilitation, rehabilitation with capacity changes, bridge rehabilitation, and" "tunnel rehabilitation." ///
    //         `"`sample_note'"' ///
    //         `"`sample_size_note'"' ///
    //         , size(small) span ///
    //     )
    // graph export "$duration_dir/IC_const_duration_hist_rehab`fig_suffix'.png", replace width(2500)
    // restore

    // * histogram of duration for reimbursements for maintenance
    // preserve
    // drop if mi(const_duration)
    // keep if work_type == 4
    // histogram const_duration, frequency ///
    //     title("Time between construction authorization and completion", size(medium)) ///
    //     subtitle("Interstate Construction; maintenance reimbursements", size(small)) ///
    //     xtitle("Years") ///
    //     ytitle("Number of reimbursements") ///
    //     ylabel(, format(%9.0fc)) ///
    //     note( ///
    //         `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
    //         "Sample restricted to maintenance resurfacing, bridge preventive maintenance and protection, tunnel preventive maintenance" "and protection, bridge resurfacing, and highway infrastructure preventive maintenance." ///
    //         `"`sample_note'"' ///
    //         `"`sample_size_note'"' ///
    //         , size(small) span ///
    //     )
    // graph export "$duration_dir/IC_const_duration_hist_maint`fig_suffix'.png", replace width(2500)
    // restore

    * same histograms, weighted by costs (histogram does not allow aweights; bin duration and sum cost per bin)
    local duration_binwidth 1
    preserve
    drop if mi(const_duration) | mi(total_cost_bills_adj)
    keep if is_construction
    gen double _dur_bin = `duration_binwidth' * floor(const_duration / `duration_binwidth')
    collapse (sum) spend = total_cost_bills_adj, by(_dur_bin)
    sort _dur_bin
    twoway bar spend _dur_bin, ///
        title("Time between construction authorization and completion, cost-weighted", size(medium)) ///
        subtitle("Interstate Construction; new construction, reconstruction, and rehabilitation reimbursements", size(small)) ///
        xtitle("Years") ///
        ytitle("Billions of 2025 USD") ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Projects with missing cost data are excluded." ///
            "Sample excludes maintenance reimbursements." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(small) span ///
        )
    graph export "$duration_dir/IC_const_duration_hist_any_construction_costwgt`fig_suffix'.png", replace width(2500)
    restore

    preserve
    drop if mi(const_duration) | mi(total_cost_bills_adj)
    keep if work_type == 1
    gen double _dur_bin = `duration_binwidth' * floor(const_duration / `duration_binwidth')
    collapse (sum) spend = total_cost_bills_adj, by(_dur_bin)
    sort _dur_bin
    twoway bar spend _dur_bin, ///
        title("Time between construction authorization and completion, cost-weighted", size(medium)) ///
        subtitle("Interstate Construction; new construction reimbursements", size(small)) ///
        xtitle("Years") ///
        ytitle("Billions of 2025 USD") ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Projects with missing cost data are excluded." ///
            "Sample restricted to new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(small) span ///
        )
    graph export "$duration_dir/IC_const_duration_hist_newconstr_costwgt`fig_suffix'.png", replace width(2500)
    restore

    preserve
    drop if mi(const_duration) | mi(total_cost_bills_adj)
    keep if work_type == 2
    gen double _dur_bin = `duration_binwidth' * floor(const_duration / `duration_binwidth')
    collapse (sum) spend = total_cost_bills_adj, by(_dur_bin)
    sort _dur_bin
    twoway bar spend _dur_bin, ///
        title("Time between construction authorization and completion, cost-weighted", size(medium)) ///
        subtitle("Interstate Construction; reconstruction reimbursements", size(small)) ///
        xtitle("Years") ///
        ytitle("Billions of 2025 USD") ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Projects with missing cost data are excluded." ///
            "Sample restricted to 4R reconstruction, 4R added or no added capacity, bridge replacement, and tunnel replacement." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(small) span ///
        )
    graph export "$duration_dir/IC_const_duration_hist_reconstr_costwgt`fig_suffix'.png", replace width(2500)
    restore

    preserve
    drop if mi(const_duration) | mi(total_cost_bills_adj)
    keep if work_type == 3
    gen double _dur_bin = `duration_binwidth' * floor(const_duration / `duration_binwidth')
    collapse (sum) spend = total_cost_bills_adj, by(_dur_bin)
    sort _dur_bin
    twoway bar spend _dur_bin, ///
        title("Time between construction authorization and completion, cost-weighted", size(medium)) ///
        subtitle("Interstate Construction; rehabilitation reimbursements", size(small)) ///
        xtitle("Years") ///
        ytitle("Billions of 2025 USD") ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Projects with missing cost data are excluded." ///
            "Sample restricted to 4R restoration and rehabilitation, rehabilitation with capacity changes, bridge rehabilitation, and" "tunnel rehabilitation." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(small) span ///
        )
    graph export "$duration_dir/IC_const_duration_hist_rehab_costwgt`fig_suffix'.png", replace width(2500)
    restore

    preserve
    drop if mi(const_duration) | mi(total_cost_bills_adj)
    keep if work_type == 4
    gen double _dur_bin = `duration_binwidth' * floor(const_duration / `duration_binwidth')
    collapse (sum) spend = total_cost_bills_adj, by(_dur_bin)
    sort _dur_bin
    twoway bar spend _dur_bin, ///
        title("Time between construction authorization and completion, cost-weighted", size(medium)) ///
        subtitle("Interstate Construction; maintenance reimbursements", size(small)) ///
        xtitle("Years") ///
        ytitle("Billions of 2025 USD") ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Projects with missing cost data are excluded." ///
            "Sample restricted to maintenance resurfacing, bridge preventive maintenance and protection, tunnel preventive maintenance" "and protection, bridge resurfacing, and highway infrastructure preventive maintenance." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(small) span ///
        )
    graph export "$duration_dir/IC_const_duration_hist_maint_costwgt`fig_suffix'.png", replace width(2500)
    restore

    * same cost-weighted histograms as above but using log durations
    local log_duration_binwidth 0.1
    preserve
    drop if mi(const_duration) | mi(total_cost_bills_adj)
    drop if const_duration <= 0
    keep if is_construction
    gen double _log_duration = log(const_duration)
    gen double _log_dur_bin = `log_duration_binwidth' * floor(_log_duration / `log_duration_binwidth')
    collapse (sum) spend = total_cost_bills_adj, by(_log_dur_bin)
    sort _log_dur_bin
    twoway bar spend _log_dur_bin, barwidth(`log_duration_binwidth') ///
        title("Log time between construction authorization and completion, cost-weighted", size(medium)) ///
        subtitle("Interstate Construction; new construction, reconstruction, and rehabilitation reimbursements", size(small)) ///
        xtitle("Log years") ///
        ytitle("Billions of 2025 USD") ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Projects with missing cost data are excluded." ///
            "Projects with non-positive duration are excluded before taking logs." ///
            "Sample excludes maintenance reimbursements." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(small) span ///
        )
    graph export "$duration_dir/IC_const_duration_hist_any_construction_costwgt_logdur`fig_suffix'.png", replace width(2500)
    restore

    preserve
    drop if mi(const_duration) | mi(total_cost_bills_adj)
    drop if const_duration <= 0
    keep if work_type == 1
    gen double _log_duration = log(const_duration)
    gen double _log_dur_bin = `log_duration_binwidth' * floor(_log_duration / `log_duration_binwidth')
    collapse (sum) spend = total_cost_bills_adj, by(_log_dur_bin)
    sort _log_dur_bin
    twoway bar spend _log_dur_bin, barwidth(`log_duration_binwidth') ///
        title("Log time between construction authorization and completion, cost-weighted", size(medium)) ///
        subtitle("Interstate Construction; new construction reimbursements", size(small)) ///
        xtitle("Log years") ///
        ytitle("Billions of 2025 USD") ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Projects with missing cost data are excluded." ///
            "Projects with non-positive duration are excluded before taking logs." ///
            "Sample restricted to new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(small) span ///
        )
    graph export "$duration_dir/IC_const_duration_hist_newconstr_costwgt_logdur`fig_suffix'.png", replace width(2500)
    restore

    preserve
    drop if mi(const_duration) | mi(total_cost_bills_adj)
    drop if const_duration <= 0
    keep if work_type == 2
    gen double _log_duration = log(const_duration)
    gen double _log_dur_bin = `log_duration_binwidth' * floor(_log_duration / `log_duration_binwidth')
    collapse (sum) spend = total_cost_bills_adj, by(_log_dur_bin)
    sort _log_dur_bin
    twoway bar spend _log_dur_bin, barwidth(`log_duration_binwidth') ///
        title("Log time between construction authorization and completion, cost-weighted", size(medium)) ///
        subtitle("Interstate Construction; reconstruction reimbursements", size(small)) ///
        xtitle("Log years") ///
        ytitle("Billions of 2025 USD") ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Projects with missing cost data are excluded." ///
            "Projects with non-positive duration are excluded before taking logs." ///
            "Sample restricted to 4R reconstruction, 4R added or no added capacity, bridge replacement, and tunnel replacement." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(small) span ///
        )
    graph export "$duration_dir/IC_const_duration_hist_reconstr_costwgt_logdur`fig_suffix'.png", replace width(2500)
    restore

    preserve
    drop if mi(const_duration) | mi(total_cost_bills_adj)
    drop if const_duration <= 0
    keep if work_type == 3
    gen double _log_duration = log(const_duration)
    gen double _log_dur_bin = `log_duration_binwidth' * floor(_log_duration / `log_duration_binwidth')
    collapse (sum) spend = total_cost_bills_adj, by(_log_dur_bin)
    sort _log_dur_bin
    twoway bar spend _log_dur_bin, barwidth(`log_duration_binwidth') ///
        title("Log time between construction authorization and completion, cost-weighted", size(medium)) ///
        subtitle("Interstate Construction; rehabilitation reimbursements", size(small)) ///
        xtitle("Log years") ///
        ytitle("Billions of 2025 USD") ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Projects with missing cost data are excluded." ///
            "Projects with non-positive duration are excluded before taking logs." ///
            "Sample restricted to 4R restoration and rehabilitation, rehabilitation with capacity changes, bridge rehabilitation, and" "tunnel rehabilitation." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(small) span ///
        )
    graph export "$duration_dir/IC_const_duration_hist_rehab_costwgt_logdur`fig_suffix'.png", replace width(2500)
    restore

    preserve
    drop if mi(const_duration) | mi(total_cost_bills_adj)
    drop if const_duration <= 0
    keep if work_type == 4
    gen double _log_duration = log(const_duration)
    gen double _log_dur_bin = `log_duration_binwidth' * floor(_log_duration / `log_duration_binwidth')
    collapse (sum) spend = total_cost_bills_adj, by(_log_dur_bin)
    sort _log_dur_bin
    twoway bar spend _log_dur_bin, barwidth(`log_duration_binwidth') ///
        title("Log time between construction authorization and completion, cost-weighted", size(medium)) ///
        subtitle("Interstate Construction; maintenance reimbursements", size(small)) ///
        xtitle("Log years") ///
        ytitle("Billions of 2025 USD") ///
        note( ///
            `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
            "Projects with missing cost data are excluded." ///
            "Projects with non-positive duration are excluded before taking logs." ///
            "Sample restricted to maintenance resurfacing, bridge preventive maintenance and protection, tunnel preventive maintenance" "and protection, bridge resurfacing, and highway infrastructure preventive maintenance." ///
            `"`sample_note'"' ///
            `"`sample_size_note'"' ///
            , size(small) span ///
        )
    graph export "$duration_dir/IC_const_duration_hist_maint_costwgt_logdur`fig_suffix'.png", replace width(2500)
    restore
}
exit

// * ==============================================================================
// * tabulations of most common dates 
// * ==============================================================================
// * get list of project IDs that have construction or maintenance 
// keep if !mi(work_type)
// keep recipientid federal_project_number
// duplicates drop
// tempfile project_ids
// save `project_ids', replace

// * merge with project-level data to select only the projects that have construction or maintenance
// merge 1:1 recipientid federal_project_number using "$intermediate_data/project_level_FMIS_lite.dta", keep(3) nogen
// gen int authconstyear = year(authconstdate)

// * adjust for inflation
// rename completion_year year
// merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
// gen total_cost_bills_adj = total_cost_mills / cpi / 1000
// rename year completion_year
// drop cpi total_cost_mills


// * only pre-1964
// preserve
// keep if authconstyear < 1964
// tab authconstdate, sort
// tab authconstdate [aw=total_cost_bills_adj], sort
// restore 

// preserve
// keep if completion_year < 1964
// tab completedate, sort
// tab completedate [aw=total_cost_bills_adj], sort
// restore 


// * all years 
// tab authconstdate, sort
// tab completedate, sort
// tab authconstdate [aw=total_cost_bills_adj], sort
// tab completedate [aw=total_cost_bills_adj], sort



* ==============================================================================
* Duration per PR-511 pseudo-mile by FMIS authorization year
* ==============================================================================

use "$intermediate_data/project_level_FMIS_lite.dta", clear
keep if fp_ic 
keep if has_new_construction

gen int authconstyear = year(authconstdate)
drop if mi(authconstyear) | mi(completion_year)
drop if authconstyear < 1950 | authconstyear > 1988
sort authconstyear

gen double const_duration = (completedate - authconstdate) / 365

* adjust cost for inflation
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) keep(master match) nogen
gen total_cost_mills_adj = total_cost_mills / cpi
rename year completion_year

* compute share of spending for each project relative to its completion year
bysort completion_year: egen double total_cost_yr = sum(total_cost_mills_adj)
gen double spend_share = total_cost_mills_adj / total_cost_yr if total_cost_yr > 0

tempfile fmis_base
save `fmis_base'

* full sample baseline, then PR-511 subsamples (same FMIS project panel; only national annual PR-511 mi is rebuilt)
// foreach subsample in full cty_per_yr cty_rt_per_yr cty_life cty_rt_life cty_openyr_ever cty_rt_openyr_ever {
foreach subsample in cty_openyr_ever cty_rt_openyr_ever {
    tempfile pr511_mi_by_yr

    use "$intermediate_data/PR511_hubbardmazzeo_chained.dta", clear
    drop if open_year < 1960
    drop if open_year > 1995
    drop if mi(open_year)
    rename st state_fips
    gen long county_fips = real(string(state_fips, "%02.0f") + string(county, "%03.0f")) if !mi(state_fips) & !mi(county)

    if "`subsample'" == "full" {
        local fig_suffix "_full"
        local sample_note ""
        local sample_size_note = ""
    }
    else if "`subsample'" == "cty_per_yr" {
        local fig_suffix "_cty_max1chain_per_yr"
        local sample_note "Sample restricted to counties with at most one PR-511 chain per opening year."
        merge m:1 county_fips using "$pr511_intermediate/pr511_cty_max_one_chain_per_yr.dta", keep(3) nogen
        drop if open_year >= 1980
        * count unique number of counties 
        preserve
        keep county_fips
        duplicates drop
        local sample_size_note = "Number of unique counties: `=string(_N, "%9.0fc")'."
        restore
        }
    else if "`subsample'" == "cty_rt_per_yr" {
        local fig_suffix "_cty_rt_max1chain_per_yr"
        local sample_note "Sample restricted to county x route cells with at most one PR-511 chain per opening year."
        merge m:1 county_fips route using "$pr511_intermediate/pr511_cty_rt_max_one_chain_per_yr.dta", keep(3) nogen
        drop if open_year >= 1980
        * count unique number of county x route cells
        preserve
        keep county_fips route
        duplicates drop
        local sample_size_note = "Number of unique county x route cells: `=string(_N, "%9.0fc")'."
        restore
    }
    else if "`subsample'" == "cty_life" {
        local fig_suffix "_cty_1chain_ever"
        local sample_note "Sample restricted to counties with only one PR-511 chain across all years."
        merge m:1 county_fips using "$pr511_intermediate/pr511_cty_single_chain_ever.dta", keep(3) nogen
        drop if open_year >= 1980
        * count unique number of counties
        preserve
        keep county_fips
        duplicates drop
        local sample_size_note = "Number of unique counties: `=string(_N, "%9.0fc")'."
        restore
    }
    else if "`subsample'" == "cty_rt_life" {
        local fig_suffix "_cty_rt_1chain_ever"
        local sample_note "Sample restricted to county x route cells with only one PR-511 chain across all years."
        merge m:1 county_fips route using "$pr511_intermediate/pr511_cty_rt_single_chain_ever.dta", keep(3) nogen
        drop if open_year >= 1980
        * count unique number of county x route cells
        preserve
        keep county_fips route
        duplicates drop
        local sample_size_note = "Number of unique county x route cells: `=string(_N, "%9.0fc")'."
        restore
    }
    else if "`subsample'" == "cty_openyr_ever" {
        local fig_suffix "_cty_1openyr_ever"
        local sample_note "Sample restricted to counties where all chains opened in a single year."
        merge m:1 county_fips using "$pr511_intermediate/pr511_cty_single_openyr_ever.dta", keep(3) nogen
        drop if open_year >= 1980
        * count unique number of counties
        preserve
        keep county_fips
        duplicates drop
        local sample_size_note = "Number of unique counties: `=string(_N, "%9.0fc")'."
        restore
    }
    else if "`subsample'" == "cty_rt_openyr_ever" {
        local fig_suffix "_cty_rt_1openyr_ever"
        local sample_note "Sample restricted to county x route cells where all chains opened in a single year."
        merge m:1 county_fips route using "$pr511_intermediate/pr511_cty_rt_single_openyr_ever.dta", keep(3) nogen
        drop if open_year >= 1980
        * count unique number of county x route cells
        preserve
        keep county_fips route
        duplicates drop
        local sample_size_note = "Number of unique county x route cells: `=string(_N, "%9.0fc")'."
        restore
    }

    rename open_year pr_year
    collapse (sum) pr511_mi = chain_len, by(pr_year)
    save `pr511_mi_by_yr', replace

    * match PR-511 mileage to FMIS with optional lag year range from 0 to 5
    forvalues lag = 0/5 {
        use `fmis_base', clear
        gen int pr_year = completion_year - `lag'
        merge m:1 pr_year using `pr511_mi_by_yr', keep(3) nogen keepusing(pr511_mi)
        replace pr511_mi = 0 if mi(pr511_mi)
        
        gen double pseudo_mi = pr511_mi * spend_share
        // drop if mi(pseudo_mi) | pseudo_mi == 0
        
        // preserve
        collapse (sum) const_duration pseudo_mi, by(authconstyear)
        gen double duration_per_mi = const_duration / pseudo_mi

        twoway (line duration_per_mi authconstyear), ///
            title("Mean construction duration per pseudo-mile of interstate opened", size(medsmall)) ///
            subtitle("IC-funded new construction projects; FMIS complete year assumed lagged by `lag' year(s)", size(vsmall)) ///
            xtitle("Construction authorization year", size(small)) ///
            ytitle("Years per pseudo-mile", size(small)) ///
            xlabel(1955(5)1990, labsize(small)) ///
            legend(off) ///
            note( ///
                "Sample restricted to FMIS projects where at least one reimbursement is funded by Interstate Construction program codes and at least one reimbursement has an improvement type of new construction" "(new construction roadway, maintenance relocation, bridge new construction, or new tunnel)." ///
                "Duration is computed as the difference between the completion date and the construction authorization date." ///
                "PR-511 mileage is allocated to FMIS projects in proportion to each project's share of total spending in that completion year." ///
                "FMIS completion year is assumed to be lagged by `lag' year(s) and matched to PR-511 opening year from `lag' years earlier." ///
                `"`sample_note'"' ///
                `"`sample_size_note'"' ///
                , size(vsmall) span ///
            )
        graph export "$duration_dir/duration_per_pseudo_mi_by_authyr_lag`lag'`fig_suffix'.png", replace width(2400)
        // restore
    }
}

* compute duration per mile before aggregating, then take the average? 

