/*==============================================================================
* Assign FMIS spending to PR511 projects based on the shape of event study costs
made in PR511_eventstudy.  
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

* Segment-length variable in PR511_hubbardmazzeo_chained.dta.
local miles_var chain_len

* parameterize t window for costs. I set this to 5 as of now
local prof_lo -5
local prof_hi 5

* ==============================================================================
* Make cost profile based on single year structure
* ==============================================================================

use "$intermediate_data/PR511_FMIS_eventstudy_singleyear.dta", clear
collapse (mean) total_cost_mills_adj new_construction_cost_mills_adj ///
    row_cost_mills_adj pe_cost_mills_adj, by(event_time)
	
rename total_cost_mills_adj            f_total
rename new_construction_cost_mills_adj f_newc
rename row_cost_mills_adj              f_row
rename pe_cost_mills_adj               f_pe

* optional truncation of the profile support
if "`prof_lo'" != "" {
    foreach f of varlist f_* {
        replace `f' = 0 if event_time < `prof_lo'
    }
}
if "`prof_hi'" != "" {
    foreach f of varlist f_* {
        replace `f' = 0 if event_time > `prof_hi'
    }
}

tempfile profile
save `profile'

* ==============================================================================
* Full county_fips x open_year with miles
* ==============================================================================

* state_fips x countyid -> county_fips crosswalk from FMIS
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
collapse (firstnm) county_fips, by(state_fips countyid)
tempfile county_xwalk
save `county_xwalk'

* chain-level PR511
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
capture confirm variable `miles_var'
if _rc {
    display as error ///
        "Miles var `miles_var' not found, set at top"
    exit 111
}
rename st state_fips
rename county countyid
keep chain_id state_fips countyid open_year `miles_var'
rename `miles_var' miles

* attach county_fips
merge m:1 state_fips countyid using `county_xwalk', keep(1 3)
count if _merge == 1
display "Chains with no matching county_fips in FMIS (dropped): " r(N)
keep if _merge == 3
drop _merge

* remove chains without an open year
gen byte no_open_year = missing(open_year)
count if no_open_year
display "PR-511 chains with a missing open_year (held out of allocation): " r(N)

preserve
    keep if no_open_year
    tempfile undated_chains
    save `undated_chains'
restore

keep if !no_open_year
drop no_open_year

tempfile chains
save `chains'

* ==============================================================================
* Actual spending figures from FMIS
* ==============================================================================

use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if funding_program == "Interstate Construction"
keep if completion_year <= 2000 & completion_year >= 1950
keep state_fips countyid county_fips federal_project_number completedate ///
    completion_year total_cost_mills detail_improvementtype new_construction

drop if detail_improvementtype == 5 | detail_improvementtype == 59 // drop maintenance resurfacing and bridge resurfacing
gen new_construction_cost = total_cost_mills if new_construction == 1
gen row_cost = total_cost_mills if detail_improvementtype == 16
gen pe_cost   = total_cost_mills if detail_improvementtype == 15

* keep only counties that have a PR-511 chain
preserve
use `chains', clear
collapse (sum) miles, by(county_fips)
drop miles
tempfile pr511_counties
save `pr511_counties'
restore
merge m:1 county_fips using `pr511_counties', keep(3) nogen

* one pot of spending per county x completion_year (no double counting)
collapse (sum) total_cost_mills new_construction_cost row_cost pe_cost, ///
    by(county_fips completion_year)

* adjust for inflation
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) keep(match) nogen
gen total_cost_mills_adj            = total_cost_mills      / cpi
gen new_construction_cost_mills_adj = new_construction_cost / cpi
gen row_cost_mills_adj              = row_cost              / cpi
gen pe_cost_mills_adj               = pe_cost               / cpi
drop cpi total_cost_mills new_construction_cost row_cost pe_cost
rename year completion_year

foreach c of varlist *_mills_adj {
    replace `c' = 0 if missing(`c')
}

tempfile actual
save `actual'

* ==============================================================================
* Allocate county-year spending across openings (by mileage)
* ==============================================================================

use `chains', clear

* cross openings with the county's spending years (many-to-many within county)
joinby county_fips using `actual'

* event time of each opening relative to each completion year
gen event_time = completion_year - open_year

* bring in the profile weights; event times outside support get zero weight
merge m:1 event_time using `profile', keep(1 3) keepusing(f_*) nogen
foreach f of varlist f_total f_newc f_row f_pe {
    replace `f' = 0 if missing(`f')
}

* total miles opening in the county (fallback denominator)
bysort county_fips completion_year: egen double county_miles = total(miles)

local measures total newc row pe
local var_total total_cost_mills_adj
local var_newc  new_construction_cost_mills_adj
local var_row   row_cost_mills_adj
local var_pe    pe_cost_mills_adj

foreach m of local measures {
    * weight = miles opened * predicted single-year spending at this event time
    gen double w_`m' = miles * f_`m'
    bysort county_fips completion_year: egen double tw_`m' = total(w_`m')

    * share of this county-year's spending going to this opening
    gen double share_`m' = cond(tw_`m' > 0, w_`m' / tw_`m', miles / county_miles)

    * allocated spending, then estimated cost = sum over years
    gen double alloc_`m' = share_`m' * `var_`m''
}

* check to make sure sums are correct
preserve
collapse (sum) alloc_total, by(county_fips completion_year)
merge 1:1 county_fips completion_year using `actual', ///
    keepusing(total_cost_mills_adj) keep(3) nogen
gen double _gap = abs(alloc_total - total_cost_mills_adj)
summarize _gap
assert _gap < 1e-6 | total_cost_mills_adj == 0
display "Mapping OK: allocated spending matches county-year totals"
restore

collapse (sum) est_total = alloc_total est_newc = alloc_newc ///
    est_row = alloc_row est_pe = alloc_pe ///
    (firstnm) state_fips countyid county_fips open_year miles, ///
    by(chain_id)

gen byte no_open_year = 0

* append undated chains for visibility
append using `undated_chains'
replace no_open_year = 1 if no_open_year == .

label variable est_total    "Estimated total cost, millions 2025 USD"
label variable est_newc     "Estimated new-construction cost, millions 2025 USD"
label variable est_row      "Estimated right-of-way cost, millions 2025 USD"
label variable est_pe       "Estimated preliminary-engineering cost, millions 2025 USD"
label variable miles        "Chain miles"
label variable no_open_year "1 = chain has no open_year; not estimated"

order chain_id county_fips state_fips countyid open_year miles no_open_year est_*
sort county_fips open_year chain_id

save "$intermediate_data/PR511_segmentcosts_by_chain.dta", replace

* ==============================================================================
* Summaries and figure
* ==============================================================================

use "$intermediate_data/PR511_segmentcosts_by_chain.dta", clear
count
display "Total PR-511 chains in output: " r(N)
count if no_open_year == 0
display "Number of PR-511 chains with a cost estimate: " r(N)
count if no_open_year == 1
display "Number of PR-511 chains left un-estimated (no open_year): " r(N)
summarize est_total est_newc est_row est_pe miles if no_open_year == 0, detail

* distribution of estimated total cost per opening
twoway ///
    (histogram est_total, frequency), ///
    title("Estimated total cost for PR-511 chains", size(medsmall)) ///
    subtitle("Allocated from the single-year profile scaled by miles", size(vsmall)) ///
    xtitle("Estimated total cost (millions of 2025 USD)", size(small)) ///
    ytitle("Number of chains", size(small)) ///
    xlabel(, labsize(small)) ///
    ylabel(, labsize(small) angle(horizontal)) ///
    note( ///
        "Each county-year's FMIS Interstate Construction spending is split across that county's openings" ///
        "in proportion to miles opened times the single-year event-study profile f(event_time)." ///
        `"Interstate receipts are identified by the "Interstate Construction" funding program code."' ///
        "FMIS data from 1950 to 2000.", ///
         size(vsmall) span ///
    ) ///
    legend(off) ///
    ysize(4) xsize(6)
graph export "$out_dir/pr511_segmentcost_hist_totalcost.png", replace width(2400)
