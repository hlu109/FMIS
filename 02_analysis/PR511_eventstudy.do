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
* add your username and paths here as an else if condition
else {
	 display as error "Set your user"
}
* check that output folders exist and create them if not 
if !direxists("$output") mkdir "$output"
if !direxists("$intermediate_data") mkdir "$intermediate_data"

* ==============================================================================
global out_dir "$output/PR511_FMIS"
if !direxists("$out_dir") mkdir "$out_dir"

use "$intermediate_data/PR511_hubbardmazzeo_chained.dta", clear

preserve
collapse (count) chain_count = chain_id (first) chain_id, by(st county)
summarize chain_count
keep if chain_count == 1
display "Number of counties with only one chain ever: " _N

* store the identifiers for these counties  
tempfile one_chain_counties
save `one_chain_counties'
restore

// there are only 232 counties that only had one chain in the entire history of PR-511

* aggregate chains by year 
collapse (firstnm) chain_id, by(open_year st county)
preserve
collapse (count) chain_count = chain_id, by(st county)
summarize chain_count
keep if chain_count == 1
display "Number of counties with only one chain (when chains are aggregated within year): " _N
restore

* ==============================================================================
* Event study
* ==============================================================================

use "$intermediate_data/PR511_hubbardmazzeo_chained.dta", clear
merge 1:1 chain_id using `one_chain_counties', keep(3) nogen
rename st state_fips
rename county countyid
keep state_fips countyid route open_year open_month chain_id
tempfile pr511_one_chain_counties
save `pr511_one_chain_counties'

* merge with FMIS cost data 
use "$intermediate_data/receipt_level_FMIS_lite_program_codes.dta", clear
keep if funding_program == "Interstate Construction"
keep if completion_year <= 2000 & completion_year >= 1950
keep state_fips countyid county_fips federal_project_number completedate completion_year total_cost_mills detail_improvementtype

drop if detail_improvementtype == 5 | detail_improvementtype == 59 // drop maintenance resurfacing and bridge resurfacing
gen new_construction = detail_improvementtype == 1 | detail_improvementtype == 7 | detail_improvementtype == 8 | detail_improvementtype == 17 | detail_improvementtype == 50 // new construction roadway, maintenance relocation, bridge new construction, construction engineering, new tunnel
gen new_construction_cost = total_cost_mills if new_construction == 1
gen row_cost = total_cost_mills if detail_improvementtype == 16 
gen pe_cost = total_cost_mills if detail_improvementtype == 15

* merge with PR-511 data 
merge m:1 state_fips countyid using `pr511_one_chain_counties', keep(3) nogen
// note there are 5 chains from PR-511 that yielded 0 matches for state x county in FMIS 

* compute event time 
gen event_time = completion_year - open_year

* aggregate FMIS spending by year, state, county 
collapse (sum) total_cost_mills new_construction_cost row_cost pe_cost (firstnm) event_time open_year, by(county_fips completion_year)

* adjust for inflation 
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) keep(match) nogen
gen total_cost_mills_adj = total_cost_mills / cpi
gen new_construction_cost_mills_adj = new_construction_cost / cpi
gen row_cost_mills_adj = row_cost / cpi
gen pe_cost_mills_adj = pe_cost / cpi
drop cpi total_cost_mills new_construction_cost row_cost pe_cost

rename year completion_year

* ==============================================================================
* Plot event study
* ==============================================================================

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
    xlabel(, labsize(small)) ///
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
    xlabel(, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "New construction includes receipts with an improvement type of new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
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
    xlabel(, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
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
    xlabel(, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
    note( ///
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_pecost_avg.png", replace width(2400)

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
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
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
        "Year is computed as the FMIS completion year minus the PR-511 open year." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "Number of counties: `n_counties'.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_IC_eventstudy_pecost_avg_etm5p5.png", replace width(2400)

restore 