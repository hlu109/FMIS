/*==============================================================================
 	FMIS data exploration
	This script plots figures related to project durations.
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
global fig_height = 384 // 4 inches, so it fits on Google Docs nicely 
* ==============================================================================
global duration_dir "$output/project_duration"
if !direxists("$duration_dir") mkdir "$duration_dir"

* ==============================================================================

use "$intermediate_data/receipt_level_FMIS.dta", clear
drop projectdescription recipientremarks divisionremarks nongis_countyid gisbreakdown_countyid gis_routeid // cut down size by removing unnecessary variables (but we want to keep title for some diagnostics)

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
* look at outliers with really long durations of construction stage 
// preserve
drop if mi(const_duration)
keep if const_duration > 20 // years 

order recipientid federal_project_number const_duration authconstdate completedate projecttitle detail_improvementtype 

// restore 

exit

* cut down the dataset size for the remainder of this script 
drop projecttitle 



* ==============================================================================
* number of reimbursements over time that have a construction start and end date (all IC; count)
// plot a line for: 
// - reimbursements with construction complete data 
// - reimbursements with both construction complete and auth date 
// later we may want to filter to closed/completed projects 

preserve
collapse ///
    (sum) has_completedate has_both_dates total_rows, by(completion_year)
replace total_rows = total_rows / 1000
replace has_completedate = has_completedate / 1000
replace has_both_dates = has_both_dates / 1000

graph twoway ///
    (line total_rows completion_year) ///
    (line has_completedate completion_year) ///
    (line has_both_dates completion_year), ///
    title("Number of Reimbursements with Construction Start and End Dates", size(medium)) ///
    subtitle("Interstate Construction", size(small)) ///
    ytitle("Thousands of Reimbursements") ///
    xtitle("Completion Year") ///
    xlabel(1950(10)2025) ///
    legend( ///
        label(1 "All reimbursements") ///
        label(2 "Has complete date") ///
        label(3 "Has construction" "authorization and" "complete date") ///
        size(small) ///
    ) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."', ///
        size(small) span ///
    )
graph export "$duration_dir/reimb_construction_dates_IC.png", replace width(2500)

* share of reimbursements over time that have a construction start and end date (all IC; count)
gen pct_has_completedate = 100 * has_completedate / total_rows if total_rows > 0
gen pct_has_both_dates = 100 * has_both_dates / total_rows if total_rows > 0

graph twoway ///
    (line pct_has_completedate completion_year) ///
    (line pct_has_both_dates completion_year), ///
    title("Share of Reimbursements with Construction Start and End Dates", size(medium)) ///
    subtitle("Interstate Construction", size(small)) ///
    ytitle("Percent of reimbursements") ///
    xtitle("Completion Year") ///
    xlabel(1950(10)2025) ///
    ylabel(0(10)100) ///
    legend( ///
        label(1 "Has complete date") ///
        label(2 "Has construction" "authorization and" "complete date") ///
        size(small) ///
    ) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."', ///
        size(small) span ///
    )
graph export "$duration_dir/reimb_construction_dates_IC_share.png", replace width(2500)
restore


* number of reimbursements over time that have a construction start and end date (all IC; cost weight)
// TODO 


* share of reimbursements over time that have a construction start and end date (all IC; cost weight)
// TODO 




* number of reimbursements over time that have a construction start and end date (IC, construction; count)
preserve 
keep if is_construction
collapse ///
    (sum) has_completedate has_both_dates total_rows, by(completion_year)
replace total_rows = total_rows / 1000
replace has_completedate = has_completedate / 1000
replace has_both_dates = has_both_dates / 1000

graph twoway ///
    (line total_rows completion_year) ///
    (line has_completedate completion_year) ///
    (line has_both_dates completion_year), ///
    title("Number of Reimbursements with Construction Start and End Dates", size(medium)) ///
    subtitle("Interstate Construction; construction improvement types only", size(small)) ///
    ytitle("Thousands of Reimbursements") ///
    xtitle("Completion Year") ///
    xlabel(1950(10)2025) ///
    legend( ///
        label(1 "All reimbursements") ///
        label(2 "Has complete date") ///
        label(3 "Has construction" "authorization and" "complete date") ///
        size(small) ///
    ) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "Included construction improvement types are new construction, reconstruction, and rehabilitation: " ///
        "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
        "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete)," "bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
        "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation." ///
        "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance.", ///
        size(vsmall) span ///
    )
graph export "$duration_dir/reimb_construction_dates_IC_const.png", replace width(2500)

* share of reimbursements over time that have a construction start and end date (IC, construction; count)
gen pct_has_completedate = 100 * has_completedate / total_rows if total_rows > 0
gen pct_has_both_dates = 100 * has_both_dates / total_rows if total_rows > 0

graph twoway ///
    (line pct_has_completedate completion_year) ///
    (line pct_has_both_dates completion_year), ///
    title("Share of Reimbursements with Construction Start and End Dates", size(medium)) ///
    subtitle("Interstate Construction; construction improvement types only", size(small)) ///
    ytitle("Percent of reimbursements") ///
    xtitle("Completion Year") ///
    xlabel(1950(10)2025) ///
    ylabel(0(10)100) ///
    legend( ///
        label(1 "Has complete date") ///
        label(2 "Has construction" "authorization and" "complete date") ///
        size(small) ///
    ) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "Included construction improvement types are new construction, reconstruction, and rehabilitation: " ///
        "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
        "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete)," "bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
        "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation." ///
        "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance.", ///
        size(vsmall) span ///
    )
graph export "$duration_dir/reimb_construction_dates_IC_const_share.png", replace width(2500)
restore

* share of reimbursements over time that have a construction start and end date (IC, construction; count)
* BY CONSTRUCTION TYPE
preserve 
keep if !mi(work_type)
collapse ///
    (sum) has_completedate has_both_dates total_rows, by(completion_year work_type)
replace total_rows = total_rows / 1000
replace has_both_dates = has_both_dates / 1000
gen pct_has_both_dates = 100 * has_both_dates / total_rows

graph twoway ///
    (line pct_has_both_dates completion_year if work_type == 1) ///
    (line pct_has_both_dates completion_year if work_type == 2) ///
    (line pct_has_both_dates completion_year if work_type == 3) ///
    (line pct_has_both_dates completion_year if work_type == 4), ///
    title("Share of Reimbursements with Both Construction Start and End Dates", size(medium)) ///
    subtitle("Interstate Construction; by construction type", size(small)) ///
    ytitle("Percent of reimbursements") ///
    xtitle("Completion Year") ///
    xlabel(1950(10)2025) ///
    legend( ///
        label(1 "New Construction") ///
        label(2 "Reconstruction") ///
        label(3 "Rehabilitation") ///
        label(4 "Maintenance") ///
        size(small) ///
    ) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
        "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete)," "bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
        "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation." ///
        "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance.", ///
        size(vsmall) span ///
    )
graph export "$duration_dir/reimb_construction_dates_IC_const_share_by_type.png", replace width(2500)
restore

* number of reimbursements over time that have a construction start and end date (IC, construction; cost weight)
* share of reimbursements over time that have a construction start and end date (IC, construction; cost weight)


* ==============================================================================
* project durations 
* ==============================================================================
* avg project duration over time for IC reimbursements, separated by improvement type for main types of construction
drop if mi(completedate) | mi(authconstdate)
drop if mi(work_type)

preserve
drop if completion_year > 2000
collapse (mean) const_duration, by(completion_year work_type)

graph twoway ///
    (line const_duration completion_year if work_type == 1) ///
    (line const_duration completion_year if work_type == 2) ///
    (line const_duration completion_year if work_type == 3) ///
    (line const_duration completion_year if work_type == 4), ///
    title("Average Construction Work Duration by Improvement Type" "for Interstate Construction Reimbursements", size(medium)) ///
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
        "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
        "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
        "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete)," "bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
        "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation." ///
        "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance.", ///
        size(vsmall) span ///
    )
graph export "$duration_dir/IC_const_duration_by_impvmt_type.png", replace width(2500)
restore

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
        "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance.", ///
        size(vsmall) span ///
    )
graph export "$duration_dir/IC_const_duration_by_impvmt_type_costwgt.png", replace width(2500)
restore 

* same as above but plot against the authorization date instead
preserve
drop if authconstyear < 1940 | authconstyear > 2000
collapse (mean) const_duration, by(authconstyear work_type)
graph twoway ///
    (line const_duration authconstyear if work_type == 1) ///
    (line const_duration authconstyear if work_type == 2) ///
    (line const_duration authconstyear if work_type == 3) ///
    (line const_duration authconstyear if work_type == 4), ///
    title("Average Construction Work Duration by Improvement Type" "for Interstate Construction Reimbursements", size(medium)) ///
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
        "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
        "New construction reimbursements include new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
        "Reconstruction reimbursements include 4R reconstruction (obsolete), 4R added capacity, 4R no added capacity, bridge replacement (obsolete)," "bridge replacement (added capacity), bridge replacement (no added capacity), and tunnel replacement." ///
        "Rehabilitation reimbursements include 4R restoration and rehabilitation, rehabilitation (added capacity), bridge rehabilitation" "(obsolete), bridge rehabilitation (added capacity), bridge rehabilitation (no added capacity), and tunnel rehabilitation." ///
        "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance.", ///
        size(vsmall) span ///
    )
graph export "$duration_dir/IC_const_duration_by_impvmt_type_by_authconst.png", replace width(2500)
restore

* duplicate with cost-weighted mean duration (by authorization year)
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
        "Maintenance reimbursements include maintenance resurfacing, bridge preventive maintenance, bridge protection, tunnel preventive maintenance," "tunnel protection, bridge resurfacing, and highway infrastructure preventive maintenance.", ///
        size(vsmall) span ///
    )
graph export "$duration_dir/IC_const_duration_by_impvmt_type_by_authconst_costwgt.png", replace width(2500)
restore

* new construction only: duration percentiles (p10, p25, p50, p75, p90) over time

preserve
keep if work_type == 1
drop if completion_year > 2000
collapse (p10) d_p10=const_duration (p25) d_p25=const_duration (p50) d_p50=const_duration (p75) d_p75=const_duration (p90) d_p90=const_duration, by(completion_year)

graph twoway ///
    (line d_p10 completion_year) ///
    (line d_p25 completion_year) ///
    (line d_p50 completion_year) ///
    (line d_p75 completion_year) ///
    (line d_p90 completion_year), ///
    title("Percentiles of Construction Work Duration" "New Construction; Interstate Construction Reimbursements", size(medium)) ///
    ytitle("Years") ///
    xtitle("Completion Year") ///
    legend( ///
        order(5 4 3 2 1) ///
        label(1 "10th percentile") ///
        label(2 "25th percentile") ///
        label(3 "50th percentile") ///
        label(4 "75th percentile") ///
        label(5 "90th percentile") ///
        size(small) ///
    ) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
        "Sample restricted to new construction reimbursements: new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
        "Percentiles (10th, 25th, 50th, 75th, 90th) are computed within each completion year.", ///
        size(vsmall) span ///
    )
graph export "$duration_dir/IC_const_duration_newconstr_pctiles_by_completedate.png", replace width(2500)
restore

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
        label(1 "10th percentile") ///
        label(2 "25th percentile") ///
        label(3 "50th percentile") ///
        label(4 "75th percentile") ///
        label(5 "90th percentile") ///
        size(small) ///
    ) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "Percentiles are weighted by reimbursement cost (billions of 2025 USD)." ///
        "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
        "Sample restricted to new construction reimbursements: new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
        "Percentiles (10th, 25th, 50th, 75th, 90th) are computed within each completion year.", ///
        size(vsmall) span ///
    )
graph export "$duration_dir/IC_const_duration_newconstr_pctiles_by_completedate_costwgt.png", replace width(2500)
restore

preserve
keep if work_type == 1
drop if authconstyear < 1940 | authconstyear > 2000
collapse (p10) d_p10=const_duration (p25) d_p25=const_duration (p50) d_p50=const_duration (p75) d_p75=const_duration (p90) d_p90=const_duration, by(authconstyear)

graph twoway ///
    (line d_p10 authconstyear) ///
    (line d_p25 authconstyear) ///
    (line d_p50 authconstyear) ///
    (line d_p75 authconstyear) ///
    (line d_p90 authconstyear), ///
    title("Percentiles of Construction Work Duration" "New Construction; Interstate Construction Reimbursements", size(medium)) ///
    ytitle("Years") ///
    xtitle("Authorization Year") ///
    legend( ///
        order(5 4 3 2 1) ///
        label(1 "10th percentile") ///
        label(2 "25th percentile") ///
        label(3 "50th percentile") ///
        label(4 "75th percentile") ///
        label(5 "90th percentile") ///
        size(small) ///
    ) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
        "Sample restricted to new construction reimbursements: new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
        "Percentiles (10th, 25th, 50th, 75th, 90th) are computed within each authorization year.", ///
        size(vsmall) span ///
    )
graph export "$duration_dir/IC_const_duration_newconstr_pctiles_by_authconst.png", replace width(2500)
restore

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
        label(1 "10th percentile") ///
        label(2 "25th percentile") ///
        label(3 "50th percentile") ///
        label(4 "75th percentile") ///
        label(5 "90th percentile") ///
        size(small) ///
    ) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "Percentiles are weighted by spending in 2025 USD." ///
        "Construction work duration is calculated as the difference between the completion date and the construction authorization date." ///
        "Sample restricted to new construction reimbursements: new construction roadway, maintenance relocation, bridge new construction, and new tunnel." ///
        "Percentiles (10th, 25th, 50th, 75th, 90th) are computed within each authorization year.", ///
        size(vsmall) span ///
    )
graph export "$duration_dir/IC_const_duration_newconstr_pctiles_by_authconst_costwgt.png", replace width(2500)
restore


* ==============================================================================
* histogram of durations 
* ==============================================================================
* histogram of duration for all reimbursements for any construction
preserve
drop if mi(const_duration)
keep if is_construction
histogram const_duration, frequency ///
    title("Time between construction authorization and completion", size(medium)) ///
    subtitle("Interstate Construction; new construction, reconstruction, and rehabilitation reimbursements", size(small)) ///
    xtitle("Years") ///
    ytitle("Number of reimbursements") ///
    ylabel(, format(%9.0fc)) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "Sample excludes maintenance reimbursements.", ///
        size(small) span ///
    )
graph export "$duration_dir/IC_const_duration_hist_any_construction.png", replace width(2500)
restore

* histogram of duration for reimbursements for new construction
preserve
drop if mi(const_duration)
keep if work_type == 1
histogram const_duration, frequency ///
    title("Time between construction authorization and completion", size(medium)) ///
    subtitle("Interstate Construction; new construction reimbursements", size(small)) ///
    xtitle("Years") ///
    ytitle("Number of reimbursements") ///
    ylabel(, format(%9.0fc)) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "Sample restricted to new construction roadway, maintenance relocation, bridge new construction, and new tunnel.", ///
        size(small) span ///
    )
graph export "$duration_dir/IC_const_duration_hist_newconstr.png", replace width(2500)
restore

* histogram of duration for reimbursements for reconstruction
preserve
drop if mi(const_duration)
keep if work_type == 2
histogram const_duration, frequency ///
    title("Time between construction authorization and completion", size(medium)) ///
    subtitle("Interstate Construction; reconstruction reimbursements", size(small)) ///
    xtitle("Years") ///
    ytitle("Number of reimbursements") ///
    ylabel(, format(%9.0fc)) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "Sample restricted to 4R reconstruction, 4R added or no added capacity, bridge replacement, and tunnel replacement.", ///
        size(small) span ///
    )
graph export "$duration_dir/IC_const_duration_hist_reconstr.png", replace width(2500)
restore

* histogram of duration for reimbursements for rehabilitation
preserve
drop if mi(const_duration)
keep if work_type == 3
histogram const_duration, frequency ///
    title("Time between construction authorization and completion", size(medium)) ///
    subtitle("Interstate Construction; rehabilitation reimbursements", size(small)) ///
    xtitle("Years") ///
    ytitle("Number of reimbursements") ///
    ylabel(, format(%9.0fc)) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "Sample restricted to 4R restoration and rehabilitation, rehabilitation with capacity changes, bridge rehabilitation, and" "tunnel rehabilitation.", ///
        size(small) span ///
    )
graph export "$duration_dir/IC_const_duration_hist_rehab.png", replace width(2500)
restore

* histogram of duration for reimbursements for maintenance
preserve
drop if mi(const_duration)
keep if work_type == 4
histogram const_duration, frequency ///
    title("Time between construction authorization and completion", size(medium)) ///
    subtitle("Interstate Construction; maintenance reimbursements", size(small)) ///
    xtitle("Years") ///
    ytitle("Number of reimbursements") ///
    ylabel(, format(%9.0fc)) ///
    note( ///
        `"Reimbursements are identified by the "Interstate Construction" funding program codes."' ///
        "Sample restricted to maintenance resurfacing, bridge preventive maintenance and protection, tunnel preventive maintenance" "and protection, bridge resurfacing, and highway infrastructure preventive maintenance.", ///
        size(small) span ///
    )
graph export "$duration_dir/IC_const_duration_hist_maint.png", replace width(2500)
restore

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
        "Sample excludes maintenance reimbursements.", ///
        size(small) span ///
    )
graph export "$duration_dir/IC_const_duration_hist_any_construction_costwgt.png", replace width(2500)
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
        "Sample restricted to new construction roadway, maintenance relocation, bridge new construction, and new tunnel.", ///
        size(small) span ///
    )
graph export "$duration_dir/IC_const_duration_hist_newconstr_costwgt.png", replace width(2500)
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
        "Sample restricted to 4R reconstruction, 4R added or no added capacity, bridge replacement, and tunnel replacement.", ///
        size(small) span ///
    )
graph export "$duration_dir/IC_const_duration_hist_reconstr_costwgt.png", replace width(2500)
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
        "Sample restricted to 4R restoration and rehabilitation, rehabilitation with capacity changes, bridge rehabilitation, and" "tunnel rehabilitation.", ///
        size(small) span ///
    )
graph export "$duration_dir/IC_const_duration_hist_rehab_costwgt.png", replace width(2500)
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
        "Sample restricted to maintenance resurfacing, bridge preventive maintenance and protection, tunnel preventive maintenance" "and protection, bridge resurfacing, and highway infrastructure preventive maintenance.", ///
        size(small) span ///
    )
graph export "$duration_dir/IC_const_duration_hist_maint_costwgt.png", replace width(2500)
restore

exit 
* ==============================================================================
* tabulations of most common dates 
* ==============================================================================
* get list of project IDs that have construction or maintenance 
keep if !mi(work_type)
keep recipientid federal_project_number
duplicates drop
tempfile project_ids
save `project_ids', replace

* merge with project-level data to select only the projects that have construction or maintenance
merge 1:1 recipientid federal_project_number using "$intermediate_data/project_level_FMIS_lite.dta", keep(3) nogen
gen int authconstyear = year(authconstdate)

* adjust for inflation
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_cost_bills_adj = total_cost_mills / cpi / 1000
rename year completion_year
drop cpi total_cost_mills


* only pre-1964
preserve
keep if authconstyear < 1964
tab authconstdate, sort
tab authconstdate [aw=total_cost_bills_adj], sort
restore 

preserve
keep if completion_year < 1964
tab completedate, sort
tab completedate [aw=total_cost_bills_adj], sort
restore 


* all years 
tab authconstdate, sort
tab completedate, sort
tab authconstdate [aw=total_cost_bills_adj], sort
tab completedate [aw=total_cost_bills_adj], sort


