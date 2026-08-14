/*==============================================================================
* PR511_segmentcosts_analysis.do
*
*   Part A: determine how PR-511 opening years are arranged in time across county x route cells.
    Trying to see how prevalent the case of loose bunching is that may prevent us from correctly assigning
    FMIS spending
*   
*
*   PART B -- describe how costs evolve over time (spend/mile from the matched PR-511 data)
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

* ==============================================================================
* Parameters
* ==============================================================================

* Opening-year window
local open_lo 1950
local open_hi 2000

* +/- amount for single opening spending window
* Two openings whose +/- `win' windows do not overlap must be at least `sep' = 2*`win' years apart.

// may want to adjust this for what looks to be a -1/+3 around one-year interstate spending,
// run with a loose and narrow window to compare
local win_wide 5
local sep_wide = 2*`win_wide'

local win_narrow 2
local sep_narrow = 2*`win_narrow'

* check what percent of single-year county x route spending is in window

use "$intermediate_data/PR511_FMIS_eventstudy_cty_rt_single_openyr_ever.dta", clear
collapse (mean) total_cost_mills_adj new_construction_cost_mills_adj row_cost_mills_adj pe_cost_mills_adj, by(event_time)

summarize total_cost_mills_adj
di r(sum)

preserve
drop if event_time < -4 | event_time > 6
summarize total_cost_mills_adj
di r(sum)
restore

preserve
drop if event_time < -1 | event_time > 3
summarize total_cost_mills_adj
di r(sum)
restore

* ==============================================================================
* PART A -- Spacing / bunching of PR-511 opening years
* ==============================================================================
* We run the same diagnostic at two units:
*   county      : the level at which FMIS spending is actually resolved in the
*                 estimation pipeline (the binding attribution constraint).
*   cxr         : county x route, the level at which openings are recorded and
*                 the level attribution *could* reach if FMIS receipts were
*                 resolved to route.
* ------------------------------------------------------------------------------

foreach unit in county cxr {

    * make county x route identifier
    use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
    drop if mi(open_year) | open_year < `open_lo' | open_year > `open_hi'

    if "`unit'" == "county" {
        drop if mi(st) | mi(county)
        gen double cellid = st*1000 + county
        local unitlab   "County"
        local unitfile  "county"
    }
    else {
        drop if mi(st) | mi(county) | mi(route)
        gen double cellid = (st*1000 + county)*1000 + route
        local unitlab   "County x route"
        local unitfile  "cxroute"
    }

    * -- one row per cell x opening-year, carrying miles opened -----------------
    collapse (sum) miles = chain_len, by(cellid open_year)

    * distinct opening years, gaps between consecutive years, span, total miles
    bysort cellid (open_year): gen double gap = open_year - open_year[_n-1] if _n > 1
    by cellid: gen long n_years = _N
    by cellid: egen double cell_miles = total(miles)
    by cellid: egen double min_gap   = min(gap)     // missing for single-year cells
    by cellid: egen double ymin       = min(open_year)
    by cellid: egen double ymax       = max(open_year)
    gen double span = ymax - ymin

    * ==========================================================================
    * Figure A1: how many distinct opening years does a cell have?
    * ==========================================================================
    preserve
        bysort cellid: keep if _n == 1
        qui count
        local ncells = r(N)
        qui count if n_years > 1
        local nmulti = r(N)
        local pctmulti : display %4.1f 100*`nmulti'/`ncells'

        histogram n_years, discrete frequency ///
            title("Distinct PR-511 opening years per `=lower("`unitlab'")' cell", size(medsmall)) ///
            subtitle("`open_lo'-`open_hi'; `nmulti' of `ncells' cells (`pctmulti'%) open in more than one year", size(vsmall)) ///
            xtitle("Number of distinct opening years", size(small)) ///
            ytitle("Number of cells", size(small)) ///
            xlabel(1(1)10, labsize(small)) ///
            ylabel(, labsize(small) angle(horizontal)) ///
            note( ///
                "A cell is a `=lower("`unitlab'")'. Opening year is the PR-511 open_year of a chain; chains opening the same year are one opening year." ///
                "Cells with a single opening year admit clean attribution of FMIS spending; multi-year cells are the concern.", ///
                size(vsmall) span ///
            ) ///
            legend(off) ysize(4) xsize(6)
        graph export "$out_dir/pr511_spacing_nyears_`unitfile'.png", replace width(2400)
    restore
	

    * ==========================================================================
    * Figure A2: gaps between consecutive opening years within a cell
    * ==========================================================================
    preserve
        keep if !mi(gap)
        qui count
        if r(N) > 0 {
            qui count if gap < `sep_wide'
            local nclose = r(N)
            qui count
            local ngaps  = r(N)
            local pctclose : display %4.1f 100*`nclose'/`ngaps'

            histogram gap, discrete frequency ///
                title("Gaps between consecutive PR-511 opening years", size(medsmall)) ///
                subtitle("Within `=lower("`unitlab'")' cells, `open_lo'-`open_hi'; `nclose' of `ngaps' gaps (`pctclose'%) fall below `sep_wide' years", size(vsmall)) ///
                xtitle("Years between successive opening years in the same cell", size(small)) ///
                ytitle("Number of gaps", size(small)) ///
                xlabel(0(5)40, labsize(small)) ///
                ylabel(, labsize(small) angle(horizontal)) ///
                note( ///
                    "Dashed line at `sep_wide' years = twice the +/- `win'-year spending window used in the cost estimation." ///
                    "Gaps to the left of the line mean one opening's spending window overlaps the next: attribution by (open_year, completion_year) is ambiguous.", ///
                    size(vsmall) span ///
                ) ///
                legend(off) ysize(4) xsize(6)
            graph export "$out_dir/pr511_spacing_gaps_`unitfile'.png", replace width(2400)
        }
        else {
            display "No multi-year `unitlab' cells in `open_lo'-`open_hi'; skipping gap histogram."
        }
    restore

    * ==========================================================================
    * Figure A3: attribution-difficulty classification of cells
    *   1 = single opening year               -> clean
    *   2 = multiple years, all gaps >= `sep' -> separable (windows don't overlap)
    *   3 = multiple years, some gap < `sep'  -> overlapping windows -> hard
    * Shown as share of cells and share of miles.
    * ==========================================================================
    preserve
    bysort cellid: keep if _n == 1

    * ---- denominators from distinct cells (single counted once) ----
    local Ncells = _N
    egen double _tm = total(cell_miles)
    local Tmiles = _tm[1]
    drop _tm

    * ---- two independent classifications, each in its own var ----
    * wide scheme
    gen byte code_wide = .
    replace code_wide = 1 if n_years == 1
    replace code_wide = 2 if n_years > 1 & !mi(min_gap) & min_gap >= `sep_wide'
    replace code_wide = 3 if n_years > 1 & !mi(min_gap) & min_gap <  `sep_wide'

    * narrow scheme (single handled by the wide var only, so it isn't double-counted)
    gen byte code_narrow = .
    replace code_narrow = 4 if n_years > 1 & !mi(min_gap) & min_gap >= `sep_narrow'
    replace code_narrow = 5 if n_years > 1 & !mi(min_gap) & min_gap <  `sep_narrow'

    * ---- headline share (compute here, while _N = distinct cells) ----
    qui count
    local ncells = r(N)
    qui count if code_wide == 3
    local nhard = r(N)
    local pcthard : display %4.1f 100*`nhard'/`ncells'
    display as text "== `unitlab': `nhard' of `ncells' cells (`pcthard'%) have overlapping spending windows (gap < `sep_wide'y) =="

    * ---- stack the two classifications into one long var ----
    gen long _id = _n
    reshape long code_, i(_id) j(scheme) string
    drop if mi(code_)
    rename code_ cat

    label define catlab 1 `""Single" "opening""' ///
                    2 `""Multi:" "gaps >=`sep_wide'y""' ///
                    3 `""Multi:" "gap <`sep_wide'y""' ///
                    4 `""Multi:" "gaps >=`sep_narrow'y""' ///
                    5 `""Multi:" "gap <`sep_narrow'y""', replace
    label values cat catlab

    * ---- collapse, normalise to the DISTINCT-cell totals ----
    gen double _one = 1
    collapse (sum) n_cells = _one (sum) miles = cell_miles, by(cat)
    gen double pct_cells = 100*n_cells/`Ncells'
    gen double pct_miles = 100*miles /`Tmiles'
    label variable pct_cells "Share of cells"
    label variable pct_miles "Share of miles"

    graph bar pct_cells pct_miles, over(cat, label(labsize(vsmall))) ///
        bar(1, color(navy)) bar(2, color(orange)) ///
        title("Attribution difficulty by `=lower("`unitlab'")' cell", size(medsmall)) ///
        subtitle("PR-511 openings `open_lo'-`open_hi'", size(vsmall)) ///
        ytitle("Percent", size(small)) ///
        ylabel(0(20)100, labsize(small) angle(horizontal)) ///
        legend(order(1 "Share of county-routes" 2 "Share of miles") size(vsmall) rows(2)) ///
        blabel(bar, format(%3.0f) size(vsmall)) ///
		note( ///
                "Single opening year: FMIS county-year spending maps to one opening." ///
                "Multi indicates multiple opening years and whether the gaps between these years fall over or under a specific threshold", /// 
                size(vsmall) span ///
            ) ///
        ysize(4) xsize(6)
    graph export "$out_dir/pr511_spacing_difficulty_`unitfile'.png", replace width(2400)
restore
}

* ==============================================================================
* PART B -- Spending over calendar time and the project outlay S-curve
* ==============================================================================

use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if funding_program == "Interstate Construction"
keep if completion_year <= 2000 & completion_year >= 1950
drop if detail_improvementtype == 5 | detail_improvementtype == 59  // resurfacing

gen double new_construction_cost = total_cost_mills if new_construction == 1
gen double row_cost = total_cost_mills if detail_improvementtype == 16
gen double pe_cost  = total_cost_mills if detail_improvementtype == 15

* inflation-adjust every dollar figure by completion year -> 2025 USD, millions
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) keep(match) nogen
foreach v in total_cost_mills new_construction_cost row_cost pe_cost {
    replace `v' = `v' / cpi
}
drop cpi
rename year completion_year

* ------------------------------------------------------------------------------
* Figure B1: real interstate outlays by calendar (completion) year, by component
* ------------------------------------------------------------------------------
preserve
    collapse (sum) total_cost_mills new_construction_cost row_cost pe_cost, ///
        by(completion_year)
    foreach v of varlist total_cost_mills new_construction_cost row_cost pe_cost {
        replace `v' = 0 if mi(`v')
        replace `v' = `v' / 1000     // millions -> billions
    }

    twoway ///
        (line total_cost_mills      completion_year, lcolor(black) lwidth(medthick)) ///
        (line new_construction_cost completion_year, lcolor(navy)) ///
        (line row_cost              completion_year, lcolor(orange)) ///
        (line pe_cost               completion_year, lcolor(green)), ///
        title("Interstate Construction spending by completion year", size(medsmall)) ///
        subtitle("FMIS receipts, real 2025 USD", size(vsmall)) ///
        xtitle("Completion year", size(small)) ///
        ytitle("Billions of 2025 USD", size(small)) ///
        xlabel(1950(10)2000, labsize(small)) ///
        ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
        legend(order(1 "Total" 2 "New construction" 3 "Right-of-way" 4 "Prelim. engineering") ///
               size(vsmall) row(4)) ///
        note( ///
            "Total excludes maintenance and bridge resurfacing (improvement types 5, 59)." ///
            `"Interstate receipts identified by the "Interstate Construction" funding program code."' ///
            "Dollars adjusted to 2025 USD using the completion-year CPI. FMIS data 1950-2000.", ///
            size(vsmall) span ///
        ) ///
        ysize(4) xsize(6)
    graph export "$out_dir/pr511_outlay_by_completionyear.png", replace width(2400)
restore

* ------------------------------------------------------------------------------
* Figure B2: normalized cumulative outlay S-curve
*   Cumulative share of interstate construction dollars as a function of the lag
*   (in years) from construction authorization to receipt completion. This is
*   the empirical "spend-down" curve and its median is the effective half-life
*   of a project's spending window.
* ------------------------------------------------------------------------------
preserve
    gen double lag_years = (completedate - authconstdate) / 365.25
    drop if mi(lag_years) | lag_years < 0
    keep lag_years total_cost_mills

    sort lag_years
    gen double _cum = sum(total_cost_mills)
    egen double _tot = total(total_cost_mills)
    gen double cum_share = _cum / _tot

    * dollar-weighted median lag
    gen byte _atleast_half = cum_share >= 0.5
    qui summarize lag_years if _atleast_half
    local medlag : display %4.1f r(min)
    qui summarize lag_years if cum_share >= 0.9
    local p90lag : display %4.1f r(min)

    * trim the display tail; the curve is a step function, plot as a line
    keep if lag_years <= 25

    twoway (line cum_share lag_years, lcolor(navy) lwidth(medthick)), ///
        yline(0.5, lpattern(dot) lcolor(gs8)) ///
        xline(`medlag', lpattern(dash) lcolor(red)) ///
        title("Cumulative outlay S-curve for Interstate Construction", size(medsmall)) ///
        subtitle("Share of real dollars completed within t years of construction authorization", size(vsmall)) ///
        xtitle("Years from construction authorization to completion", size(small)) ///
        ytitle("Cumulative share of dollars", size(small)) ///
        xlabel(0(5)25, labsize(small)) ///
        ylabel(0(0.2)1, labsize(small) angle(horizontal) format(%3.1f)) ///
        legend(off) ///
        note( ///
            "Receipt-level; each dollar placed at its authorization-to-completion lag, then cumulated (dollar-weighted)." ///
            "Median lag `medlag' years (red dashed); 90th percentile `p90lag' years." ///
            "A wider spend-down means one opening's spending window overlaps more of a neighboring opening's -- compare to Part A gaps." ///
            "Interstate Construction receipts, real 2025 USD, FMIS 1950-2000.", ///
            size(vsmall) span ///
        ) ///
        ysize(4) xsize(6)
    graph export "$out_dir/pr511_outlay_scurve_auth_to_completion.png", replace width(2400)
restore

* ==============================================================================
* PART C -- Cost per mile over time: ground truth vs estimated windows
* ==============================================================================
* Six mileage-weighted cost/mile series by PR-511 opening year:
*   1. Ground truth  : raw route-resolved FMIS receipts summed within county x
*                      route cells that open in exactly one year ever, over miles.
*   2. Full window   : est_*_full, every segment.
*   3. 11-yr window  : est_*_w11, every segment.
*   4. 11-yr window  : est_*_w11, cells whose openings can't overlap (gap >= 11 or single).
*   5. 5-yr window   : est_*_w5,  every segment.
*   6. 5-yr window   : est_*_w5,  cells whose openings can't overlap (gap >= 5 or single).
* Produced for both total and new-construction cost.
* NOTE: the `exit' in Part A halts a full-file run; run Part C as a selection (or
* comment out that exit) to reach it. Requires the estimation to have been re-run
* with the "full" window so est_*_full exist in PR511_segmentcosts_by_chain.dta.
* ------------------------------------------------------------------------------

* ---- (C0) county x route opening-year spacing -> per-chain clean-sample flags ----

local open_lo 1950
local open_hi 2000

use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
drop if mi(st) | mi(county) | mi(route)
drop if mi(open_year) | open_year < `open_lo' | open_year > `open_hi'

preserve
    collapse (sum) cell_miles = chain_len, by(county_fips route open_year)
    bysort county_fips route (open_year): gen double gap = open_year - open_year[_n-1] if _n > 1
    by county_fips route: gen long n_years = _N
    by county_fips route: egen double min_gap = min(gap)
    * clean = single opening OR every consecutive gap wide enough that the window can't
    * overlap a neighbor. w11 = [-4,6] needs gaps >= 11; w5 = [-1,3] needs gaps >= 5.
    gen byte clean_w11 = (n_years == 1) | (!mi(min_gap) & min_gap >= 11)
    gen byte clean_w5  = (n_years == 1) | (!mi(min_gap) & min_gap >= 5)
    collapse (firstnm) clean_w11 clean_w5, by(county_fips route)
    tempfile cell_flags
    save `cell_flags'
restore

* map each chain to its cell's clean flags (merge back to by-chain on chain_id only)
collapse (firstnm) county_fips route, by(chain_id)
merge m:1 county_fips route using `cell_flags', keep(1 3) nogen
keep chain_id clean_w11 clean_w5
tempfile chain_flags
save `chain_flags'

* ---- (C1) ground truth: raw FMIS receipts in single-open-year county x route cells ----
* single-open-year cells with their PR-511 opening year and miles
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
drop if mi(st) | mi(county) | mi(route)
drop if mi(open_year) | open_year < `open_lo' | open_year > `open_hi'
collapse (sum) cell_miles = chain_len, by(county_fips route open_year)
bysort county_fips route: gen long n_years = _N
keep if n_years == 1
keep county_fips route open_year cell_miles
tempfile gt_cells
save `gt_cells'

* FMIS interstate receipts, route-resolved, inflation-adjusted, summed to county x route
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if funding_program == "Interstate Construction"
keep if completion_year <= 2000 & completion_year >= 1950
drop if detail_improvementtype == 5 | detail_improvementtype == 59
gen double new_construction_cost = total_cost_mills if new_construction == 1

* route from federal project number; county key from state x county (matches PR-511 st*1000+county)
gen str3 fpn_prefix = substr(strtrim(federal_project_number), 1, 3)
gen str3 route_fpn  = ustrregexra(fpn_prefix, "[A-Za-z]", "")
destring route_fpn, replace
rename route_fpn route
capture drop county_fips
gen double county_fips = state_fips*1000 + countyid

* inflation-adjust to 2025 USD by completion year
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) keep(match) nogen
replace total_cost_mills      = total_cost_mills      / cpi
replace new_construction_cost = new_construction_cost / cpi
drop cpi

collapse (sum) gt_total = total_cost_mills gt_newc = new_construction_cost, by(county_fips route)
merge 1:1 county_fips route using `gt_cells', keep(3) nogen
collapse (sum) gt_total gt_newc cell_miles, by(open_year)
gen double cm_gt_total = gt_total / cell_miles
gen double cm_gt_newc  = gt_newc  / cell_miles
keep open_year cm_gt_total cm_gt_newc
tempfile gt_series
save `gt_series'

* ---- (C2) estimated series from the by-chain dataset ----
use "$intermediate_data/PR511_segmentcosts_by_chain.dta", clear
drop if no_open_year == 1
keep if inrange(open_year, `open_lo', `open_hi')
merge m:1 chain_id using `chain_flags', keep(1 3) nogen
recode clean_w11 clean_w5 (. = 0)

foreach meas in total newc {
    gen double c_`meas'_full  = est_`meas'_full
    gen double c_`meas'_w11   = est_`meas'_w11
    gen double c_`meas'_w5    = est_`meas'_w5
    gen double c_`meas'_w11cl = est_`meas'_w11 if clean_w11 == 1
    gen double c_`meas'_w5cl  = est_`meas'_w5  if clean_w5  == 1
}
gen double m_all   = miles
gen double m_w11cl = miles if clean_w11 == 1
gen double m_w5cl  = miles if clean_w5  == 1

collapse (sum) c_total_full c_total_w11 c_total_w5 c_total_w11cl c_total_w5cl ///
               c_newc_full  c_newc_w11  c_newc_w5  c_newc_w11cl  c_newc_w5cl  ///
               m_all m_w11cl m_w5cl, by(open_year)

foreach meas in total newc {
    gen double cm_`meas'_full  = c_`meas'_full  / m_all
    gen double cm_`meas'_w11   = c_`meas'_w11   / m_all
    gen double cm_`meas'_w5    = c_`meas'_w5    / m_all
    gen double cm_`meas'_w11cl = c_`meas'_w11cl / m_w11cl
    gen double cm_`meas'_w5cl  = c_`meas'_w5cl  / m_w5cl
}

merge 1:1 open_year using `gt_series', nogen
sort open_year

* ---- (C3) one time-series figure per cost measure ----
foreach meas in total newc {
    if "`meas'" == "total" local mword "total"
    else                   local mword "new-construction"

    twoway ///
        (line cm_gt_`meas'    open_year, lcolor(black)  lwidth(medthick)) ///
        (line cm_`meas'_full  open_year, lcolor(navy)) ///
        (line cm_`meas'_w11   open_year, lcolor(orange)) ///
        (line cm_`meas'_w11cl open_year, lcolor(orange) lpattern(dash)) ///
        (line cm_`meas'_w5    open_year, lcolor(green)) ///
        (line cm_`meas'_w5cl  open_year, lcolor(green)  lpattern(dash)), ///
        title("PR-511 `mword' cost per mile over time", size(medsmall)) ///
        subtitle("Mileage-weighted, by PR-511 opening year", size(vsmall)) ///
        xtitle("PR-511 opening year", size(small)) ///
        ytitle("Cost per mile (millions of 2025 USD)", size(small)) ///
        xlabel(`open_lo'(10)`open_hi', labsize(small)) ///
        ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
        legend(order( ///
            1 "Ground truth (1-yr cxr, FMIS receipts)" ///
            2 "Full window, all segments" ///
            3 "11-yr window, all segments" ///
            4 "11-yr window, clean (gap >=11)" ///
            5 "5-yr window, all segments" ///
            6 "5-yr window, clean (gap >=5)") size(vsmall) rows(6)) ///
        note( ///
            "Ground truth sums route-resolved FMIS Interstate Construction receipts in county x route cells that open in exactly one year, divided by cell miles." ///
            "Estimated lines use per-chain allocated costs from PR511_segmentcosts_by_chain.dta; clean samples keep cells whose openings cannot overlap under that window." ///
            "Mileage-weighted: sum of cost over sum of miles within each opening year. Real 2025 USD, PR-511 openings `open_lo'-`open_hi'.", ///
            size(vsmall) span ///
        ) ///
        ysize(4) xsize(6)
    graph export "$out_dir/pr511_costpermile_timeseries_`meas'.png", replace width(2400)
}
