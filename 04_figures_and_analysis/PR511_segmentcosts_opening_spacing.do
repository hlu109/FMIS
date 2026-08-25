/*==============================================================================
*   determine how PR-511 opening years are arranged in time across county x route cells.
    Trying to see how prevalent the case of loose bunching is that may prevent us from correctly assigning
    FMIS spending
==============================================================================*/

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
	*global output "C:/Users/fm557/Documents/FMIS Workspace/figures"
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
* Multi-opening collapses
* ==============================================================================

* look at how multiple-opening distributions appear in time series

use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear

collapse (sum) chain_len, by(open_year)
keep if open_year <= 2000 & open_year >= 1950
rename open_year completion_year

tempfile pr511_year
save `pr511_year'

use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if funding_program == "Interstate Construction"
keep if completion_year <= 2000 & completion_year >= 1950

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

preserve
collapse (sum) total_cost_mills, by(completion_year)
merge 1:1 completion_year using `pr511_year', nogen
sort completion_year

twoway (line chain_len completion_year, yaxis(1)) ///
       (line total_cost_mills completion_year, yaxis(2)), ///
    title("Total PR-511 Miles and FMIS Spending per Year") ///
    xtitle("Opening Year") ///
    ytitle("Total PR-511 Miles", axis(1)) ///
    ytitle("Total FMIS Spending (millions)", axis(2)) ///
	legend(position(6) rows(1) label(1 "PR-511 Miles") label(2 "FMIS Spending"))

graph export "$out_dir/pr511_total_miles_per_year.png", replace width(2400)
restore

/*
egen cxr = group(county_fips route)
bys cxr open_year: gen byte unq = (_n == 1)
by cxr: egen n_unq = sum(unq)
collapse (max) n_unq (first) county_fips (first) route, by(cxr)
*/

* pr-511 project collapse
* collapse if consecutive years and mile posts

local mp_tol   0.5     // milepost adjacency tolerance (miles)

foreach yeartol in 1 2 {
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear

drop if mi(st) | mi(county) | mi(route) | mi(open_year) | mi(mp_start) | mi(mp_end)
qui count
local n_in = r(N)

sort county_fips route mp_start open_year

by county_fips route: gen byte proj_break = (_n == 1) ///
    | (abs(mp_start - mp_end[_n-1]) > `mp_tol') ///
    | (abs(open_year - open_year[_n-1]) > `yeartol')

by county_fips route: gen long _proj_seq = sum(proj_break)

* globally unique project id
egen long project_id = group(county_fips route _proj_seq)
drop proj_break _proj_seq

* collapse chains into projects
collapse (max) open_year_max = open_year ///
         (min) open_year_min = open_year ///
         (sum) chain_len_total = chain_len ///
         (min) mp_start = mp_start ///
         (max) mp_end = mp_end ///
         (count) n_chains = chain_id ///
         (first) st county county_fips route, ///
    by(project_id)

gen int duration_years = open_year_max - open_year_min

order project_id county_fips st county route open_year_min open_year_max ///
    duration_years chain_len_total n_chains mp_start mp_end
sort county_fips route open_year_max project_id

save "$pr511_intermediate/PR511_condensed_consec_`yeartol'years_mps.dta", replace

* condensation summary
qui count
local n_out = r(N)
display as text "== Condensed PR-511 projects =="
display as text "Input chains (valid geometry & timing): `n_in'"
display as text "Condensed projects: `n_out'"
display as text "Average chains per project: " %5.2f `n_in'/`n_out'
tabulate n_chains
summarize duration_years chain_len_total, detail
}

* collapse only if consecutive years

foreach yeartol in 1 2 {
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
drop if mi(st) | mi(county) | mi(route) | mi(open_year) | mi(mp_start) | mi(mp_end)
qui count
local n_in = r(N)

sort county_fips route open_year mp_start

by county_fips route: gen byte proj_break = (_n == 1) ///
    | (abs(open_year - open_year[_n-1]) > `yeartol')
	
by county_fips route: gen long _proj_seq = sum(proj_break)

* globally unique project id
egen long project_id = group(county_fips route _proj_seq)
drop proj_break _proj_seq

* collapse chains into projects
collapse (max) open_year_max = open_year ///
         (min) open_year_min = open_year ///
         (sum) chain_len_total = chain_len ///
         (count) n_chains = chain_id ///
         (first) st county county_fips route, ///
    by(project_id)

gen int duration_years = open_year_max - open_year_min

order project_id county_fips st county route open_year_min open_year_max ///
    duration_years chain_len_total n_chains
sort county_fips route open_year_max project_id

save "$pr511_intermediate/PR511_condensed_consec_`yeartol'years.dta", replace

* condensation summary
qui count
local n_out = r(N)
display as text "== Condensed PR-511 projects =="
display as text "Input chains (valid geometry & timing): `n_in'"
display as text "Condensed projects: `n_out'"
display as text "Average chains per project: " %5.2f `n_in'/`n_out'
tabulate n_chains
summarize duration_years chain_len_total, detail
}

* ==============================================================================
* Figures for pacing / bunching of PR-511 opening years
* ==============================================================================
* Run the spacing diagnostic at the county x route level for three inputs:
*   baseline    : raw chained PR-511 segments (one row per chain).
*   consec_mps  : projects collapsed on consecutive years AND adjacent mileposts.
*   consec_yr   : projects collapsed on consecutive years only.
* For the condensed inputs a project's opening year is open_year_max and its
* mileage is chain_len_total; for the baseline they are open_year and chain_len.
* ------------------------------------------------------------------------------

foreach ds in baseline consec_1years consec_1years_mps consec_2years consec_2years_mps {

    * -- select dataset and its opening-year / mileage variables ----------------
    if "`ds'" == "baseline" {
        local dsfile   "PR511_hubbardmazzeo_chained"
        local yvar     open_year
        local milesvar chain_len
        local dslab    "Baseline chains"
        local dstag    "baseline"
    }
    else if "`ds'" == "consec_1years_mps" {
        local dsfile   "PR511_condensed_consec_1years_mps"
        local yvar     open_year_max
        local milesvar chain_len_total
        local dslab    "Consecutive-year + milepost projects"
        local dstag    "consec_1years_mps"
    }
    else if "`ds'" == "consec_1years" {
        local dsfile   "PR511_condensed_consec_1years"
        local yvar     open_year_max
        local milesvar chain_len_total
        local dslab    "Consecutive-year projects"
        local dstag    "consec_1years"
    }
	else if "`ds'" == "consec_2years_mps" {
        local dsfile   "PR511_condensed_consec_2years_mps"
        local yvar     open_year_max
        local milesvar chain_len_total
        local dslab    "Succesive-year (2 year max gap) + milepost projects"
        local dstag    "consec_2years_mps"
    }
    else if "`ds'" == "consec_2years" {
        local dsfile   "PR511_condensed_consec_2years"
        local yvar     open_year_max
        local milesvar chain_len_total
        local dslab    "Successive-year (2 year max gap) projects"
        local dstag    "consec_2years"
    }
    local unitlab "County x route"

    use "$pr511_intermediate/`dsfile'.dta", clear
    drop if mi(county_fips) | mi(route)
    drop if mi(`yvar') | `yvar' < `open_lo' | `yvar' > `open_hi'

    * county x route cell id
    gen double cellid = county_fips*1000 + route
	
	if "`ds'" == "baseline" {
	* entry/segment-row level: keep every chain row as its own opening (no
	* collapse to distinct opening years), so two entries opening the same year
	* count as two openings and produce a within-year gap of 0.
	gen double miles = `milesvar'

	bysort cellid (open_year): gen double gap = open_year - open_year[_n-1] if _n > 1
    by cellid: gen long n_years = _N
    by cellid: egen double cell_miles = total(miles)
    by cellid: egen double min_gap   = min(gap)     // missing for single-entry cells
    by cellid: egen double ymin       = min(open_year)
    by cellid: egen double ymax       = max(open_year)
    gen double span = ymax - ymin

    * wording: A1/A2 describe openings at the entry level for the baseline input
    local a1_title  "PR-511 openings (entries) per `=lower("`unitlab'")' cell"
    local a1_xtitle "Number of openings (segment entries)"
    local a1_multiword "have more than one opening"
    local a1_note1  "A cell is a `=lower("`unitlab'")'. Each PR-511 segment entry counts as one opening; two entries opening the same year count as two openings (gap 0)."
    local a1_note2  "Cells with a single opening admit clean attribution of FMIS spending; multi-opening cells are the concern."
    local a2_title  "Gaps between consecutive PR-511 openings (entries)"
    local a2_xtitle "Years between successive segment entries in the same cell"
	}
        
	else {
	collapse (sum) miles = `milesvar', by(cellid open_year_min open_year_max)
	
	bysort cellid (open_year_max): gen double gap = open_year_min - open_year_max[_n-1] if _n > 1
	by cellid: gen long n_years = _N
	by cellid: egen double cell_miles = total(miles)
    by cellid: egen double min_gap   = min(gap)     // missing for single-year cells
    by cellid: egen double ymin       = min(open_year_min)
    by cellid: egen double ymax       = max(open_year_max)
	gen double span = ymax - ymin

    * wording: A1/A2 describe openings at the distinct opening-year level
    local a1_title  "Distinct PR-511 opening years per `=lower("`unitlab'")' cell"
    local a1_xtitle "Number of distinct opening years"
    local a1_multiword "open in more than one year"
    local a1_note1  "A cell is a `=lower("`unitlab'")'. Opening year is the entry's opening year; entries opening the same year count as one opening year."
    local a1_note2  "Cells with a single opening year admit clean attribution of FMIS spending; multi-year cells are the concern."
    local a2_title  "Gaps between consecutive PR-511 opening years"
    local a2_xtitle "Years between successive opening years in the same cell"
	}

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

        * miles-weighted: share of cell miles by number of openings
        collapse (sum) _w = cell_miles, by(n_years)
        egen double _tot = total(_w)
        gen double pct_miles = 100*_w/_tot

        twoway bar pct_miles n_years, barwidth(0.9) color(navy) ///
            title("`a1_title'", size(medsmall)) ///
            subtitle("`dslab' | `open_lo'-`open_hi'", size(vsmall)) ///
            xtitle("`a1_xtitle'", size(small)) ///
            ytitle("Percent of miles", size(small)) ///
            xlabel(1(1)10, labsize(small)) ///
            ylabel(, labsize(small) angle(horizontal)) ///
            note( ///
                "`a1_note1'" ///
                "`a1_note2'", ///
                size(vsmall) span ///
            ) ///
            legend(off) ysize(4) xsize(6)
        graph export "$out_dir/pr511_spacing_nyears_`dstag'.png", replace width(2400)
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

            * miles-weighted: share of opening miles by gap length
            collapse (sum) _w = miles, by(gap)
            egen double _tot = total(_w)
            gen double pct_miles = 100*_w/_tot

            twoway bar pct_miles gap, barwidth(0.9) color(navy) ///
                xline(`sep_wide', lpattern(dash) lcolor(red)) ///
                title("`a2_title'", size(medsmall)) ///
                subtitle("`dslab' | within `=lower("`unitlab'")' cells, `open_lo'-`open_hi'", size(vsmall)) ///
                xtitle("`a2_xtitle'", size(small)) ///
                ytitle("Percent of miles", size(small)) ///
                xlabel(0(5)40, labsize(small)) ///
                ylabel(, labsize(small) angle(horizontal)) ///
                note( ///
                    "Dashed line at `sep_wide' years = twice the +/- `win_wide'-year spending window used in the cost estimation." ///
                    "Gaps to the left of the line mean one opening's spending window overlaps the next: attribution by (open_year, completion_year) is ambiguous.", ///
                    size(vsmall) span ///
                ) ///
                legend(off) ysize(4) xsize(6)
            graph export "$out_dir/pr511_spacing_gaps_`dstag'.png", replace width(2400)
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
    display as text "== `dslab' (`unitlab'): `nhard' of `ncells' cells (`pcthard'%) have overlapping spending windows (gap < `sep_wide'y) =="

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
        subtitle("`dslab' | PR-511 openings `open_lo'-`open_hi'", size(vsmall)) ///
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
    graph export "$out_dir/pr511_spacing_difficulty_`dstag'.png", replace width(2400)
restore
}

* ==============================================================================
* Figures A4-A6: baseline gap distributions by exact number of openings (entries)
* ------------------------------------------------------------------------------
* Baseline chains at the entry/segment-row level: each chain row is one opening,
* so two entries opening the same year count as two openings and produce a
* within-cell gap of 0. County x route cells; openings restricted to
* `open_lo'-`open_hi'. Gap k within a cell = (opening k+1's year) - (opening k's year).
*   A4: cells with exactly 2 openings -> the single gap
*   A5: cells with exactly 3 openings -> the 1st gap (opening2 - opening1)
*   A6: cells with exactly 3 openings -> the 2nd gap (opening3 - opening2)
* ==============================================================================

use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
drop if mi(county_fips) | mi(route)
drop if mi(open_year) | open_year < `open_lo' | open_year > `open_hi'

gen double cellid = county_fips*1000 + route

bysort cellid (open_year): gen long open_ord = _n
by cellid: gen long n_open = _N
by cellid: egen double cell_miles = total(chain_len)
by cellid: gen double gap = open_year - open_year[_n-1] if _n > 1
* index of each gap: the 1st gap lands on open_ord==2, the 2nd on open_ord==3, ...
gen long gap_index = open_ord - 1 if _n > 1

* ---- A4: county x routes with exactly 2 openings -> the single gap ----
preserve
    keep if n_open == 2 & gap_index == 1
    qui count
    local ncell = r(N)
    if `ncell' > 0 {
        qui count if gap < `sep_wide'
        local nclose = r(N)
        local pctclose : display %4.1f 100*`nclose'/`ncell'
        * miles-weighted: share of cell miles by gap length
        collapse (sum) _w = cell_miles, by(gap)
        egen double _tot = total(_w)
        gen double pct_miles = 100*_w/_tot

        twoway bar pct_miles gap, barwidth(0.9) color(navy) ///
            xline(`sep_wide', lpattern(dash) lcolor(red)) ///
            title("Gap distribution: county x routes with exactly 2 PR-511 openings", size(medsmall)) ///
            subtitle("Baseline entries | `open_lo'-`open_hi'", size(vsmall)) ///
            xtitle("Years between the two openings in the cell", size(small)) ///
            ytitle("Percent of miles", size(small)) ///
            xlabel(0(5)40, labsize(small)) ///
            ylabel(, labsize(small) angle(horizontal)) ///
            note( ///
                "Cells with exactly two baseline segment entries (openings). Two entries opening the same year give a gap of 0." ///
                "Dashed line at `sep_wide' years = twice the +/- `win_wide'-year spending window; gaps left of it mean overlapping windows.", ///
                size(vsmall) span ///
            ) ///
            legend(off) ysize(4) xsize(6)
        graph export "$out_dir/pr511_spacing_gap_2openings_baseline.png", replace width(2400)
    }
    else display "No baseline cells with exactly 2 openings in `open_lo'-`open_hi'; skipping A4."
restore

* ---- A5: county x routes with exactly 3 openings -> the first gap ----
preserve
    keep if n_open == 3 & gap_index == 1
    qui count
    local ncell = r(N)
    if `ncell' > 0 {
        qui count if gap < `sep_wide'
        local nclose = r(N)
        local pctclose : display %4.1f 100*`nclose'/`ncell'
        * miles-weighted: share of cell miles by gap length
        collapse (sum) _w = cell_miles, by(gap)
        egen double _tot = total(_w)
        gen double pct_miles = 100*_w/_tot

        twoway bar pct_miles gap, barwidth(0.9) color(navy) ///
            xline(`sep_wide', lpattern(dash) lcolor(red)) ///
            title("First-gap distribution: county x routes with exactly 3 PR-511 openings", size(medsmall)) ///
            subtitle("Baseline entries | `open_lo'-`open_hi'", size(vsmall)) ///
            xtitle("Years between the 1st and 2nd openings in the cell", size(small)) ///
            ytitle("Percent of miles", size(small)) ///
            xlabel(0(5)40, labsize(small)) ///
            ylabel(, labsize(small) angle(horizontal)) ///
            note( ///
                "Cells with exactly three baseline segment entries (openings), ordered by opening year." ///
                "Dashed line at `sep_wide' years = twice the +/- `win_wide'-year spending window; gaps left of it mean overlapping windows.", ///
                size(vsmall) span ///
            ) ///
            legend(off) ysize(4) xsize(6)
        graph export "$out_dir/pr511_spacing_gap1_3openings_baseline.png", replace width(2400)
    }
    else display "No baseline cells with exactly 3 openings in `open_lo'-`open_hi'; skipping A5."
restore

* ---- A6: county x routes with exactly 3 openings -> the second gap ----
preserve
    keep if n_open == 3 & gap_index == 2
    qui count
    local ncell = r(N)
    if `ncell' > 0 {
        qui count if gap < `sep_wide'
        local nclose = r(N)
        local pctclose : display %4.1f 100*`nclose'/`ncell'
        * miles-weighted: share of cell miles by gap length
        collapse (sum) _w = cell_miles, by(gap)
        egen double _tot = total(_w)
        gen double pct_miles = 100*_w/_tot

        twoway bar pct_miles gap, barwidth(0.9) color(navy) ///
            xline(`sep_wide', lpattern(dash) lcolor(red)) ///
            title("Second-gap distribution: county x routes with exactly 3 PR-511 openings", size(medsmall)) ///
            subtitle("Baseline entries | `open_lo'-`open_hi'", size(vsmall)) ///
            xtitle("Years between the 2nd and 3rd openings in the cell", size(small)) ///
            ytitle("Percent of miles", size(small)) ///
            xlabel(0(5)40, labsize(small)) ///
            ylabel(, labsize(small) angle(horizontal)) ///
            note( ///
                "Cells with exactly three baseline segment entries (openings), ordered by opening year." ///
                "Dashed line at `sep_wide' years = twice the +/- `win_wide'-year spending window; gaps left of it mean overlapping windows.", ///
                size(vsmall) span ///
            ) ///
            legend(off) ysize(4) xsize(6)
        graph export "$out_dir/pr511_spacing_gap2_3openings_baseline.png", replace width(2400)
    }
    else display "No baseline cells with exactly 3 openings in `open_lo'-`open_hi'; skipping A6."
restore