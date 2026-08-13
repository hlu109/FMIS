/*==============================================================================
* PR511_segmentcosts_analysis.do
*
* Companion analysis to PR511_segmentcosts_estimation.do. Two purposes:
*
*   PART A -- Diagnose how the *opening years* of PR-511 are arranged across
*             county and county x route cells. The concern: if a cell opens in
*             a single year (or in years spaced well apart), FMIS spending can
*             be cleanly attributed to one opening. If a cell opens in several
*             years spaced closer together than the width of a project's
*             spending window, the +/- window of one opening overlaps the next
*             and spending cannot be assigned by (open_year, completion_year)
*             linkage alone. We quantify the gap distribution and flag cells.
*
*   PART B -- Describe how interstate spending moves over calendar time
*             (aggregate real outlays by year, by cost component) and the shape
*             of the project-level outlay "S-curve" (cumulative share of dollars
*             as a function of years from construction authorization to receipt
*             completion). The S-curve pins down the effective *width* of a
*             single opening's spending window, which is the yardstick Part A's
*             gaps are compared against.
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

* ------------------------------------------------------------------------------
* Parameters
* ------------------------------------------------------------------------------
* Opening-year window to analyze (interstate build-out era; matches summary figs)
local open_lo 1950
local open_hi 1990

* Half-width of a single opening's spending window, in years. The estimation
* profile PR511_segmentcosts_estimation.do runs event time -5..+5, so a single
* opening's outlays span ~11 calendar years. Two openings whose +/- `win'
* windows do not overlap must be at least `sep' = 2*`win' years apart.
local win 5
local sep = 2*`win'


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

    * -- build the cell identifier ---------------------------------------------
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
            qui count if gap < `sep'
            local nclose = r(N)
            qui count
            local ngaps  = r(N)
            local pctclose : display %4.1f 100*`nclose'/`ngaps'

            histogram gap, discrete frequency ///
                xline(`sep', lpattern(dash) lcolor(red)) ///
                title("Gaps between consecutive PR-511 opening years", size(medsmall)) ///
                subtitle("Within `=lower("`unitlab'")' cells, `open_lo'-`open_hi'; `nclose' of `ngaps' gaps (`pctclose'%) fall below `sep' years", size(vsmall)) ///
                xtitle("Years between successive opening years in the same cell", size(small)) ///
                ytitle("Number of gaps", size(small)) ///
                xlabel(0(5)40, labsize(small)) ///
                ylabel(, labsize(small) angle(horizontal)) ///
                note( ///
                    "Dashed line at `sep' years = twice the +/- `win'-year spending window used in the cost estimation." ///
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

        gen byte cat = .
        replace cat = 1 if n_years == 1
        replace cat = 2 if n_years > 1 & min_gap >= `sep' & !mi(min_gap)
        replace cat = 3 if n_years > 1 & min_gap <  `sep' & !mi(min_gap)
        label define catlab 1 "Single opening year" ///
                            2 "Multiple, all gaps >=`sep'y" ///
                            3 "Multiple, some gap <`sep'y", replace
        label values cat catlab

        * headline shares to the log
        qui count
        local ncells = r(N)
        qui count if cat == 3
        local nhard = r(N)
        local pcthard : display %4.1f 100*`nhard'/`ncells'
        display as text "== `unitlab': `nhard' of `ncells' cells (`pcthard'%) have overlapping spending windows (gap < `sep'y) =="

        gen double _one = 1
        collapse (sum) n_cells = _one (sum) miles = cell_miles, by(cat)
        egen double _tc = total(n_cells)
        egen double _tm = total(miles)
        gen double pct_cells = 100*n_cells/_tc
        gen double pct_miles = 100*miles/_tm
        label variable pct_cells "Share of cells"
        label variable pct_miles "Share of miles"

        graph bar pct_cells pct_miles, over(cat, label(labsize(vsmall))) ///
            bar(1, color(navy)) bar(2, color(orange)) ///
            title("Attribution difficulty by `=lower("`unitlab'")' cell", size(medsmall)) ///
            subtitle("PR-511 openings `open_lo'-`open_hi'", size(vsmall)) ///
            ytitle("Percent", size(small)) ///
            ylabel(0(20)100, labsize(small) angle(horizontal)) ///
            legend(order(1 "Share of cells" 2 "Share of miles") size(vsmall) rows(1)) ///
            blabel(bar, format(%3.0f) size(vsmall)) ///
            note( ///
                "Single opening year: FMIS county-year spending maps to one opening." ///
                "Multiple with all gaps >=`sep'y: openings' +/- `win'y windows do not overlap, still separable in time." ///
                "Multiple with some gap <`sep'y: windows overlap; spending cannot be split by timing alone.", ///
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
        title("Interstate Construction outlays by completion year", size(medsmall)) ///
        subtitle("FMIS receipts, real 2025 USD", size(vsmall)) ///
        xtitle("Completion year", size(small)) ///
        ytitle("Billions of 2025 USD", size(small)) ///
        xlabel(1950(10)2000, labsize(small)) ///
        ylabel(, labsize(small) angle(horizontal) format(%9.1f)) ///
        legend(order(1 "Total" 2 "New construction" 3 "Right-of-way" 4 "Prelim. engineering") ///
               size(vsmall) rows(1)) ///
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
