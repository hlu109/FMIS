/*==============================================================================
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
else if "`user'" == "fm557"{
	global project_root "C:/Users/fm557/YLS Dropbox/Finn Meffe/FHWA cost data"
	global output "$project_root/Output/Finn"
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
global pr511_intermediate "$intermediate_data/PR_511"
if !direxists("$pr511_intermediate") mkdir "$pr511_intermediate"

global out_dir "$output/PR511_FMIS"
if !direxists("$out_dir") mkdir "$out_dir"

use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear

preserve
collapse (count) chain_count = chain_id (first) chain_id, by(st county)
summarize chain_count
keep if chain_count == 1
display "Number of counties with only one chain ever: " _N

* store the identifiers for these counties  
tempfile one_chain_counties
save `one_chain_counties'
restore

* aggregate chains by year 
collapse (firstnm) chain_id, by(open_year st county)
preserve
collapse (count) chain_count = chain_id, by(st county)
summarize chain_count
keep if chain_count == 1
display "Number of counties with only one chain (when chains are aggregated within year): " _N

tempfile one_year_counties
save `one_year_counties'
restore

* ==============================================================================
* Event study for counties with exactly one PR-511 chain ever
* ==============================================================================

use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
merge 1:1 chain_id using `one_chain_counties', keep(3) nogen
rename st state_fips
rename county countyid
keep state_fips countyid route open_year open_month chain_id
tempfile pr511_one_chain_counties
save `pr511_one_chain_counties'

* merge with FMIS cost data 
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if funding_program == "Interstate Construction"
keep if completion_year <= 2000 & completion_year >= 1950
keep state_fips countyid county_fips federal_project_number completedate completion_year total_cost_mills detail_improvementtype new_construction

drop if detail_improvementtype == 5 | detail_improvementtype == 59 // drop maintenance resurfacing and bridge resurfacing
gen new_construction_cost = total_cost_mills if new_construction == 1
gen row_cost = total_cost_mills if detail_improvementtype == 16 
gen pe_cost = total_cost_mills if detail_improvementtype == 15

* merge with PR-511 data 
merge m:1 state_fips countyid using `pr511_one_chain_counties', keep(3) nogen
// note there are 5 chains from PR-511 that yielded 0 matches for state x county in FMIS 

* compute event time 
gen event_time = completion_year - open_year

* aggregate FMIS spending by year, state, county 
collapse (sum) total_cost_mills new_construction_cost row_cost pe_cost (firstnm) event_time state_fips countyid, by(county_fips open_year completion_year)

* adjust for inflation 
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) keep(match) nogen
gen total_cost_mills_adj = total_cost_mills / cpi
gen new_construction_cost_mills_adj = new_construction_cost / cpi
gen row_cost_mills_adj = row_cost / cpi
gen pe_cost_mills_adj = pe_cost / cpi
drop cpi total_cost_mills new_construction_cost row_cost pe_cost

rename year completion_year

* replace empty years with zeros

egen county_fips_id = group(county_fips)
drop if missing(event_time)

tsset county_fips_id event_time
tsfill, full

* fill out county_fips
bysort county_fips_id: ereplace county_fips = mode(county_fips)

local costs total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj
foreach cost of local costs {
	replace `cost' = 0 if `cost' == .
}

save "$out_dir/PR511_FMIS_eventstudy_singlechain.dta", replace

* ==============================================================================
* Plot event study

* compute number of counties to print in graph 
preserve
bysort county_fips: keep if _n == 1
local n_counties = _N
restore

* aggregate into average spending at each event time
preserve
collapse (mean) total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj, by(event_time)

twoway ///
    (line total_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one PR-511 chain ever", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-20(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Total cost excludes receipts with an improvement type of maintenance resurfacing or bridge resurfacing." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_totalcost_avg.png", replace width(2400)

twoway ///
    (line new_construction_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for new construction" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one PR-511 chain ever", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-20(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "New construction includes receipts with an improvement type of new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_newconstr_avg.png", replace width(2400)

twoway ///
    (line row_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for ROW" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one PR-511 chain ever", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-20(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Cost includes only receipts with an improvement type of right-of-way." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_rowcost_avg.png", replace width(2400)

twoway ///
    (line pe_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for preliminary engineering" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one PR-511 chain ever", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-20(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Cost includes only receipts with an improvement type of preliminary engineering." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_pecost_avg.png", replace width(2400)
*exit 

* same series, event time restricted to −5 … +5 years
keep if inrange(event_time, -5, 5)

twoway ///
    (line total_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one PR-511 chain ever" "Event time −5 to +5 years", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-5(1)5, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Total cost excludes receipts with an improvement type of maintenance resurfacing or bridge resurfacing." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_totalcost_avg_etm5p5.png", replace width(2400)

twoway ///
    (line new_construction_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for new construction" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one PR-511 chain ever" "Event time −5 to +5 years", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-5(1)5, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "New construction includes receipts with an improvement type of new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_newconstr_avg_etm5p5.png", replace width(2400)

twoway ///
    (line row_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for ROW" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one PR-511 chain ever" "Event time −5 to +5 years", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-5(1)5, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Cost includes only receipts with an improvement type of right-of-way." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_rowcost_avg_etm5p5.png", replace width(2400)

twoway ///
    (line pe_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for preliminary engineering" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one PR-511 chain ever" "Event time −5 to +5 years", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-5(1)5, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Cost includes only receipts with an improvement type of preliminary engineering." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_pecost_avg_etm5p5.png", replace width(2400)

restore 


* ==============================================================================
* Event study for all PR-511 chains, aggregated to county x open_year
* ==============================================================================

* aggregate one observation per county x open_year
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
collapse (count) chain_count = chain_id, by(st county open_year)
rename st state_fips
rename county countyid
keep state_fips countyid open_year
tempfile pr511_allchains_countyyear
save `pr511_allchains_countyyear'

* merge with FMIS cost data
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if funding_program == "Interstate Construction"
// keep if completion_year >= 1950
keep if completion_year <= 2000 & completion_year >= 1950
keep state_fips countyid county_fips federal_project_number completedate completion_year total_cost_mills detail_improvementtype new_construction

drop if detail_improvementtype == 5 | detail_improvementtype == 59 // drop maintenance resurfacing and bridge resurfacing
gen new_construction_cost = total_cost_mills if new_construction == 1
gen row_cost = total_cost_mills if detail_improvementtype == 16
gen pe_cost = total_cost_mills if detail_improvementtype == 15

* merge with PR-511 data 
joinby state_fips countyid using `pr511_allchains_countyyear'
// note we can't use the merge function since we need a many-to-many merge
// merge m:1 state_fips countyid using `pr511_allchains_countyyear', keep(3) nogen

* compute event time 
gen event_time = completion_year - open_year

* aggregate FMIS spending by year, state, county 
collapse (sum) total_cost_mills new_construction_cost row_cost pe_cost (firstnm) event_time state_fips countyid, by(county_fips open_year completion_year)

* adjust for inflation
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) keep(match) nogen
gen total_cost_mills_adj = total_cost_mills / cpi
gen new_construction_cost_mills_adj = new_construction_cost / cpi
gen row_cost_mills_adj = row_cost / cpi
gen pe_cost_mills_adj = pe_cost / cpi
drop cpi total_cost_mills new_construction_cost row_cost pe_cost
rename year completion_year

* replace empty years with zeros

egen county_fips_year_id = group(county_fips open_year)
drop if missing(event_time)

tsset county_fips_year_id event_time
tsfill, full

foreach cost of varlist total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj {
	replace `cost' = 0 if `cost' == .
}

save "$out_dir/PR511_FMIS_eventstudy_allchains.dta", replace

* ==============================================================================
* Plot event study

* compute number of counties to print in graph 
preserve
bysort county_fips: keep if _n == 1
local n_counties = _N
restore

* aggregate into average spending at each event time
preserve
collapse (mean) total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj, by(event_time)
drop if event_time > 40

twoway ///
    (line total_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction" "around PR-511 opening", size(medsmall)) ///
    subtitle("All PR-511 chains, aggregated to one observation per county x year", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-40(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Total cost excludes receipts with an improvement type of maintenance resurfacing or bridge resurfacing." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data is from 1950 to 2000 but event study is truncated at +20 years to remove likely unrelated outliers." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_totalcost_avg_allchains.png", replace width(2400)

twoway ///
    (line new_construction_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for new construction" "around PR-511 opening", size(medsmall)) ///
    subtitle("All PR-511 chains, aggregated to one observation per county x year", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-40(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "New construction includes receipts with an improvement type of new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data is from 1950 to 2000 but event study is truncated at +20 years to remove likely unrelated outliers." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_newconstr_avg_allchains.png", replace width(2400)

twoway ///
    (line row_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for ROW" "around PR-511 opening", size(medsmall)) ///
    subtitle("All PR-511 chains, aggregated to one observation per county x year", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-40(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Cost includes only receipts with an improvement type of right-of-way." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data is from 1950 to 2000 but event study is truncated at +20 years to remove likely unrelated outliers." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_rowcost_avg_allchains.png", replace width(2400)

twoway ///
    (line pe_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for preliminary engineering" "around PR-511 opening", size(medsmall)) ///
    subtitle("All PR-511 chains, aggregated to one observation per county x year", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-40(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Cost includes only receipts with an improvement type of preliminary engineering." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data is from 1950 to 2000 but event study is truncated at +20 years to remove likely unrelated outliers." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_pecost_avg_allchains.png", replace width(2400)

// * same series, event time restricted to −5 … +5 years
// keep if inrange(event_time, -5, 5)

// twoway ///
//     (line total_cost_mills_adj event_time), ///
//     xline(0, lpattern(dot)) ///
//     title("Average spending in FMIS Interstate Construction" "around PR-511 opening", size(medsmall)) ///
//     subtitle("All PR-511 chains, aggregated to one observation per county x year" "Event time −5 to +5 years", size(vsmall)) ///
//     xtitle("Years after PR-511 opening", size(small)) ///
//     ytitle("Millions of 2025 USD", size(small)) ///
//     xlabel(-5(1)5, labsize(small)) ///
//     ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
//     note( ///
//         "Total cost excludes receipts with an improvement type of maintenance resurfacing or bridge resurfacing." ///
//         "Year is computed as the FMIS completion year minus the PR-511 open year." ///
//         `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
//         "FMIS data from 1950 to 2000." ///
//         "Number of counties: `n_counties'.", ///
//          size(vsmall) span ///
//     ) ///
//     legend(off) ///
//     ysize(4) xsize(6)
// graph export "$out_dir/pr511_IC_eventstudy_totalcost_avg_etm5p5_allchains.png", replace width(2400)

// twoway ///
//     (line new_construction_cost_mills_adj event_time), ///
//     xline(0, lpattern(dot)) ///
//     title("Average spending in FMIS Interstate Construction for new construction" "around PR-511 opening", size(medsmall)) ///
//     subtitle("All PR-511 chains, aggregated to one observation per county x year" "Event time −5 to +5 years", size(vsmall)) ///
//     xtitle("Years after PR-511 opening", size(small)) ///
//     ytitle("Millions of 2025 USD", size(small)) ///
//     xlabel(-5(1)5, labsize(small)) ///
//     ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
//     note( ///
//         "New construction includes receipts with an improvement type of new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
//         "Year is computed as the FMIS completion year minus the PR-511 open year." ///
//         `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
//         "FMIS data from 1950 to 2000." ///
//         "Number of counties: `n_counties'.", ///
//          size(vsmall) span ///
//     ) ///
//     legend(off) ///
//     ysize(4) xsize(6)
// graph export "$out_dir/pr511_IC_eventstudy_newconstr_avg_etm5p5_allchains.png", replace width(2400)

// twoway ///
//     (line row_cost_mills_adj event_time), ///
//     xline(0, lpattern(dot)) ///
//     title("Average spending in FMIS Interstate Construction for ROW" "around PR-511 opening", size(medsmall)) ///
//     subtitle("All PR-511 chains, aggregated to one observation per county x year" "Event time −5 to +5 years", size(vsmall)) ///
//     xtitle("Years after PR-511 opening", size(small)) ///
//     ytitle("Millions of 2025 USD", size(small)) ///
//     xlabel(-5(1)5, labsize(small)) ///
//     ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
//     note( ///
//         "Cost includes only receipts with an improvement type of right-of-way." ///
//         "Year is computed as the FMIS completion year minus the PR-511 open year." ///
//         `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
//         "FMIS data from 1950 to 2000." ///
//         "Number of counties: `n_counties'.", ///
//          size(vsmall) span ///
//     ) ///
//     legend(off) ///
//     ysize(4) xsize(6)
// graph export "$out_dir/pr511_IC_eventstudy_rowcost_avg_etm5p5_allchains.png", replace width(2400)

// twoway ///
//     (line pe_cost_mills_adj event_time), ///
//     xline(0, lpattern(dot)) ///
//     title("Average spending in FMIS Interstate Construction for preliminary engineering" "around PR-511 opening", size(medsmall)) ///
//     subtitle("All PR-511 chains, aggregated to one observation per county x year" "Event time −5 to +5 years", size(vsmall)) ///
//     xtitle("Years after PR-511 opening", size(small)) ///
//     ytitle("Millions of 2025 USD", size(small)) ///
//     xlabel(-5(1)5, labsize(small)) ///
//     ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
//     note( ///
//         "Cost includes only receipts with an improvement type of preliminary engineering." ///
//         "Year is computed as the FMIS completion year minus the PR-511 open year." ///
//         `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
//         "FMIS data from 1950 to 2000." ///
//         "Number of counties: `n_counties'.", ///
//          size(vsmall) span ///
//     ) ///
//     legend(off) ///
//     ysize(4) xsize(6)
// graph export "$out_dir/pr511_IC_eventstudy_pecost_avg_etm5p5_allchains.png", replace width(2400)

restore

* ==============================================================================
* Event study for counties with exactly one PR-511 year ever
* ==============================================================================

use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
merge m:1 st county using `one_year_counties', keep(3) nogen
rename st state_fips
rename county countyid
keep state_fips countyid open_year
duplicates drop
tempfile pr511_one_year_counties
save `pr511_one_year_counties'


* merge with FMIS cost data 
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if funding_program == "Interstate Construction"
keep if completion_year <= 2000 & completion_year >= 1950
keep state_fips countyid county_fips federal_project_number completedate completion_year total_cost_mills detail_improvementtype new_construction

drop if detail_improvementtype == 5 | detail_improvementtype == 59 // drop maintenance resurfacing and bridge resurfacing
gen new_construction_cost = total_cost_mills if new_construction == 1
gen row_cost = total_cost_mills if detail_improvementtype == 16 
gen pe_cost = total_cost_mills if detail_improvementtype == 15

* merge with PR-511 data 
merge m:1 state_fips countyid using `pr511_one_year_counties', keep(3) nogen

* compute event time 
gen event_time = completion_year - open_year

* aggregate FMIS spending by year, state, county 
collapse (sum) total_cost_mills new_construction_cost row_cost pe_cost (firstnm) event_time state_fips countyid, by(county_fips open_year completion_year)

* adjust for inflation 
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) keep(match) nogen
gen total_cost_mills_adj = total_cost_mills / cpi
gen new_construction_cost_mills_adj = new_construction_cost / cpi
gen row_cost_mills_adj = row_cost / cpi
gen pe_cost_mills_adj = pe_cost / cpi
drop cpi total_cost_mills new_construction_cost row_cost pe_cost

rename year completion_year

* replace empty years with zeros

egen county_fips_id = group(county_fips)
drop if missing(event_time)

tsset county_fips_id event_time
tsfill, full

foreach cost of varlist total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj {
	replace `cost' = 0 if `cost' == .
}

save "$out_dir/PR511_FMIS_eventstudy_singleyear.dta", replace

* ==============================================================================
* Plot event study

* compute number of counties to print in graph 
preserve
bysort county_fips: keep if _n == 1
local n_counties = _N
restore

* aggregate into average spending at each event time
preserve
collapse (mean) total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj, by(event_time)
drop if event_time > 40

twoway ///
    (line total_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one year of PR-511 data ever", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-40(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Total cost excludes receipts with an improvement type of maintenance resurfacing or bridge resurfacing." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_totalcost_avg_oneyear.png", replace width(2400)

twoway ///
    (line new_construction_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for new construction" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one year of PR-511 data ever", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-40(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "New construction includes receipts with an improvement type of new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_newconstr_avg_oneyear.png", replace width(2400)

twoway ///
    (line row_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for ROW" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one year of PR-511 data ever", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-40(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Cost includes only receipts with an improvement type of right-of-way." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_rowcost_avg_oneyear.png", replace width(2400)

twoway ///
    (line pe_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for preliminary engineering" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one year of PR-511 data ever", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-40(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Cost includes only receipts with an improvement type of preliminary engineering." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_pecost_avg_oneyear.png", replace width(2400)

* Repeat with +-5 year time range

keep if inrange(event_time, -5, 5)

twoway ///
    (line total_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one year of PR-511 data ever" "Event time −5 to +5 years", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-5(1)5, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Total cost excludes receipts with an improvement type of maintenance resurfacing or bridge resurfacing." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_totalcost_avg_oneyear_etm5p5.png", replace width(2400)

twoway ///
    (line new_construction_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for new construction" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one year of PR-511 data ever" "Event time −5 to +5 years", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-5(1)5, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "New construction includes receipts with an improvement type of new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_newconstr_avg_oneyear_etm5p5.png", replace width(2400)

twoway ///
    (line row_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for ROW" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one year of PR-511 data ever" "Event time −5 to +5 years", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-5(1)5, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Cost includes only receipts with an improvement type of right-of-way." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_rowcost_avg_oneyear_etm5p5.png", replace width(2400)

twoway ///
    (line pe_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for preliminary engineering" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one year of PR-511 data ever" "Event time −5 to +5 years", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-5(1)5, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Cost includes only receipts with an improvement type of preliminary engineering." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_pecost_avg_oneyear_etm5p5.png", replace width(2400)

restore 

* ==============================================================================
* Event study for counties where FMIS spending is concentrated in +/- 4 year period
* ==============================================================================

* Find total FMIS costs
use "$out_dir/PR511_FMIS_eventstudy_singlechain.dta", clear
local costs total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj
foreach cost of local costs {
    local newname = substr("`cost'", 1, 10) + "_sum"
    bysort county_fips_id: egen `newname' = total(`cost')
}

collapse (firstnm) county_fips (first) *_sum, by(county_fips_id)
tempfile fmis_total_county
save `fmis_total_county'

* Find period FMIS totals 

local yearthreshold 4
// currently set at +- 4 years

use "$out_dir/PR511_FMIS_eventstudy_singlechain.dta", clear
drop if event_time < -(`yearthreshold') | event_time > (`yearthreshold')
local costs total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj
foreach cost of local costs {
    local newname = substr("`cost'", 1, 10) + "_5yrsum"
    bysort county_fips_id: egen `newname' = total(`cost')
} 
replace county_fips = strtrim(county_fips)
collapse (lastnm) county_fips (first) *_5yrsum, by(county_fips_id)

merge 1:1 county_fips_id using `fmis_total_county', nogen

* Find percentages to use as cutoffs

foreach cost in total_cost new_constr row_cost_m pe_cost_mi {
    gen `cost'_pct = `cost'_5yrsum / `cost'_sum
}

rename (row_cost_m_pct pe_cost_mi_pct) (row_cost_pct pe_cost_pct)
keep county_fips county_fips_id *_pct
tempfile fmis_pct
save `fmis_pct'

* ==============================================================================
* Plot event study (replication of previous set up)

// Set percentage cutoff
local pct_cutoff 0.5

use "$out_dir/PR511_FMIS_eventstudy_singlechain.dta", clear
merge m:1 county_fips using `fmis_pct', nogen
keep if total_cost_pct > `pct_cutoff'

preserve
bysort county_fips: keep if _n == 1
local n_counties = _N
restore

collapse (mean) total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj, by(event_time)

twoway ///
    (line total_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one PR-511 chain ever and over 50% of spending concentrated in a +/- 4 year period", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-20(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Total cost excludes receipts with an improvement type of maintenance resurfacing or bridge resurfacing." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_totalcost_avg_concentrated.png", replace width(2400)

use "$out_dir/PR511_FMIS_eventstudy_singlechain.dta", clear
merge m:1 county_fips using `fmis_pct', nogen
keep if new_constr_pct > `pct_cutoff'

preserve
bysort county_fips: keep if _n == 1
local n_counties = _N
restore

collapse (mean) total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj, by(event_time)

twoway ///
    (line new_construction_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for new construction" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one PR-511 chain ever and over 50% of spending concentrated in a +/- 4 year period", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-20(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "New construction includes receipts with an improvement type of new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_newconstr_avg_concentrated.png", replace width(2400)

use "$out_dir/PR511_FMIS_eventstudy_singlechain.dta", clear
merge m:1 county_fips using `fmis_pct', nogen
keep if row_cost_pct > `pct_cutoff'

preserve
bysort county_fips: keep if _n == 1
local n_counties = _N
restore

collapse (mean) total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj, by(event_time)

twoway ///
    (line row_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for ROW" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one PR-511 chain ever and over 50% of spending concentrated in a +/- 4 year period", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-20(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Cost includes only receipts with an improvement type of right-of-way." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_rowcost_avg_concentrated.png", replace width(2400)

use "$out_dir/PR511_FMIS_eventstudy_singlechain.dta", clear
merge m:1 county_fips using `fmis_pct', nogen
keep if pe_cost_pct > `pct_cutoff'

preserve
bysort county_fips: keep if _n == 1
local n_counties = _N
restore

collapse (mean) total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj, by(event_time)

twoway ///
    (line pe_cost_mills_adj event_time), ///
    xline(0, lpattern(dot)) ///
    title("Average spending in FMIS Interstate Construction for preliminary engineering" "around PR-511 opening", size(medsmall)) ///
    subtitle("For counties with exactly one PR-511 chain ever and over 50% of spending concentrated in a +/- 4 year period", size(vsmall)) ///
    xtitle("Years after PR-511 opening", size(small)) ///
    ytitle("Millions of 2025 USD", size(small)) ///
    xlabel(-20(5)40, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Cost includes only receipts with an improvement type of preliminary engineering." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000." ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_pecost_avg_concentrated.png", replace width(2400)