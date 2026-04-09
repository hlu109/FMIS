/*==============================================================================
 	FMIS data processing 
    This compares PR-511 and FMIS interstate data. 
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
global match_dir "$intermediate_data/PR511_FMIS_match_by_state"

/* * ==============================================================================
* compare FMIS and PR-511 interstate spending to miles opened to check alignment
* ==============================================================================
* load receipt-level FMIS data
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if interstate_syscode == 1

* adjust for inflation 
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_cost_bills_adjusted = total_cost_mills / cpi / 1000

* focus on interstate construction-era spending through 1993
keep if year <= 1993
keep if state_fips <= 56
collapse (sum) cost_bills_2025 = total_cost_bills_adjusted, by(state_fips year)
tempfile fmis_state_year
save `fmis_state_year'

* load and collapse PR-511 interstate openings to state-year miles opened
use "$intermediate_data/PR511_hubbardmazzeo.dta", clear
rename st state_fips
rename open_year year
collapse (sum) interstate_mi = seg_len, by(state_fips year)
tempfile pr511_state_year
save `pr511_state_year'

use `fmis_state_year', clear
merge 1:1 state_fips year using `pr511_state_year'
drop _merge

* fill in a balanced 50-state panel for plotting
keep if year >= 1950 & year <= 1993
fillin state_fips year
replace cost_bills_2025 = 0 if mi(cost_bills_2025)
replace interstate_mi = 0 if mi(interstate_mi)
format cost_bills_2025 %9.2f
format interstate_mi %9.2f
sort state_fips year
decode state_fips, gen(state_name)

* save merged state-year series for reuse
save "$intermediate_data/PR511_FMIS_state_year.dta", replace

// use "$intermediate_data/PR511_FMIS_state_year.dta", clear

* generate figures
capture label define stateid_lbl 11 "DC", modify
egen state_order = group(state_fips)
gen page = ceil(state_order / 9)
levelsof page, local(pages)

foreach p of local pages {
    preserve
    keep if page == `p'

    twoway ///
        (line cost_bills_2025 year, ///
            lcolor(navy) yaxis(1)) ///
        (line interstate_mi year, ///
            lcolor(maroon) lpattern(dash) yaxis(2)), ///
        by(state_fips, ///
            cols(3) ///
            compact ///
            legend(position(6)) ///
            note("FMIS data uses project completion year; PR-511 uses segment opening year.", size(vsmall) span) ///
            title("Interstate Spending vs Miles Opened, page `p'", size(small)) ///
            b1title("Year", size(vsmall)) ///
            l1title("2025 USD, billions", size(vsmall)) ///
            r1title("Miles", size(small)) ///
            subtitle(, size(tiny) fcolor(white) lcolor(white))) ///
        graphregion(fcolor(white) lcolor(none) margin(tiny)) ///
        xlabel(1950(10)1995, labsize(small) angle(45) grid glcolor(gs14) glwidth(vthin) glpattern(solid)) ///
        xmtick(1955(10)1995, tlength(0) grid glcolor(gs14) glwidth(vthin) glpattern(solid)) ///
        ylabel(, axis(1) labsize(small) angle(horizontal) format(%9.1f) nogrid) ///
        ylabel(, axis(2) labsize(small) angle(horizontal) format(%9.1f) nogrid) ///
        yscale(axis(1) range(0 3)) ///
        yscale(axis(2) range(0 400)) ///
        legend( ///
            order(1 "FMIS interstate spending" 2 "PR-511 interstate miles opened") ///
            rows(1) size(vsmall) ///
        ) ///
        xsize(16) ysize(12)
    graph export "$out_dir/interstate_spend_vs_mi_stategrid_`p'.png", replace width(3200)
    restore
}

preserve
collapse (sum) cost_bills_2025 interstate_mi, by(year)

twoway ///
    (line cost_bills_2025 year, ///
        lcolor(navy) lwidth(medthick) yaxis(1)) ///
    (line interstate_mi year, ///
        lcolor(maroon) lpattern(dash) lwidth(medthick) yaxis(2)), ///
    title("Interstate Spending vs Miles Opened", size(medsmall)) ///
    xtitle("Year") ///
    ytitle("2025 USD, billions", axis(1) size(small)) ///
    ytitle("Miles", axis(2) size(small)) ///
    xlabel(1950(10)1995, labsize(small) angle(45)) ///
    ylabel(, axis(1) labsize(small) angle(horizontal) format(%9.0f)) ///
    ylabel(, axis(2) labsize(small) angle(horizontal) format(%9.0f)) ///
    yscale(axis(1) range(0 .)) ///
    yscale(axis(2) range(0 .)) ///
    legend(order(1 "FMIS interstate" "spending" 2 "PR-511 interstate" "miles opened") ///
        rows(1) size(small) position(6) ring(1)) ///
    note("FMIS data uses project completion year; PR-511 uses segment opening year.", size(vsmall) span) ///
    xsize(8) ysize(6)

graph export "$out_dir/interstate_spend_vs_mi_all_states.png", replace width(2400)
restore */

* ==============================================================================
* plot count of PR-511/FMIS matches over time
* ==============================================================================

use "$intermediate_data/PR511_FMIS_match_all.dta", clear

* count matched FMIS rows per PR-511 chain/project
bysort chain_id: gen int match_count = _N

collapse (firstnm) match_count state_fips countyid route open_year chain_len urban_rural region, by(chain_id)

// collapse by year
preserve
* average number of FMIS matches per PR-511 project by completion year
collapse (mean) avg_match_count = match_count, by(open_year)
drop if mi(open_year)
sort open_year

twoway ///
    (line avg_match_count open_year), ///
    title("Average Number of FMIS Project Matches per PR-511 Chain", size(medsmall)) ///
    subtitle("(0-2 year match window)", size(vsmall)) ///
    xtitle("Opening Year") ///
    ytitle("Project Count") ///
    xlabel(1950(5)2000, labsize(small)) ///
    note( ///
        "Matches are any pair of FMIS projects and PR-511 chains that share the same state, county, route, and time window." ///
        "FMIS project route is crudely inferred from the first three characters of the federal project number." ///
        "Match allows for FMIS project completion year to be 0-2 years after PR-511 open year." ///
        "PR-511 chains are consecutive segments of the same route opened in the same month." ///
        "No filters for detail improvement type used.", ///
        size(vsmall) span ///
    )
graph export "$out_dir/pr511_fmis_avg_matches.png", replace width(2400)
restore 

// preserve
// collapse (mean) avg_match_count = match_count, by(urban_rural open_year)
// drop if mi(open_year) | mi(urban_rural)
// sort urban_rural open_year

// twoway ///
//     (line avg_match_count open_year), ///
//     by(urban_rural, ///
//         compact ///
//         cols(2)) ///
//     title("Average FMIS matches per PR-511 chain by urban/rural status", size(medsmall)) ///
//     subtitle("(0-2 year match window)", size(vsmall)) ///
//     xtitle("Opening Year", size(small)) ///
//     ytitle("Project Count", size(small)) ///
//     xlabel(1950(5)2000, labsize(vsmall)) ///
//     ylabel(, labsize(vsmall) format(%9.2f)) ///
//     note( ///
//         "Matches are any pair of FMIS projects and PR-511 chains that share the same state, county, route, and time window." ///
//         "FMIS project route is crudely inferred from the first three characters of the federal project number." ///
//         "Match allows for FMIS project completion year to be 0-2 years after PR-511 open year." ///
//         "PR-511 chains are consecutive segments of the same route opened in the same month." ///
//         "No filters for detail improvement type used.", ///
//         size(vsmall) span ///
//     )
// // TODO: add legend 
// graph export "$out_dir/pr511_fmis_avg_matches_by_urbanrural.png", replace width(2400)
// restore

// preserve
// collapse (mean) avg_match_count = match_count, by(region open_year)
// drop if mi(open_year)
// sort region open_year

// // TODO: handle missing regions 
// twoway ///
//     (line avg_match_count open_year), ///
//     by(region, ///
//         compact ///
//         cols(3)) ///
//     title("Average FMIS matches per PR-511 chain by geographic region", size(medsmall)) ///
//     subtitle("(0-2 year match window)", size(vsmall)) ///
//     xtitle("Opening Year", size(small)) ///
//     ytitle("Project Count", size(small)) ///
//     xlabel(1950(5)2000, labsize(vsmall)) ///
//     ylabel(, labsize(vsmall) format(%9.2f)) ///
//     note( ///
//         "Matches are any pair of FMIS projects and PR-511 chains that share the same state, county, route, and time window." ///
//         "FMIS project route is crudely inferred from the first three characters of the federal project number." ///
//         "Match allows for FMIS project completion year to be 0-2 years after PR-511 open year." ///
//         "PR-511 chains are consecutive segments of the same route opened in the same month." ///
//         "No filters for detail improvement type used.", ///
//         size(vsmall) span ///
//     )
// // TODO: add legend 
// graph export "$out_dir/pr511_fmis_avg_matches_by_region.png", replace width(2400)
// restore

* ==============================================================================
* Share of PR-511 mileage and FMIS spending matched vs unmatched (time series)
* ==============================================================================

* PR-511 share of mileage, matched vs unmatched
use "$intermediate_data/PR511_FMIS_match_all.dta", clear
bysort chain_id: keep if _n == 1
collapse (sum) mi_matched = chain_len, by(open_year)
tempfile pr_matched
save `pr_matched'

use "$match_dir/unmatched_PR511.dta", clear
collapse (sum) mi_unmatched = chain_len, by(open_year)
tempfile pr_unmatched
save `pr_unmatched'

use `pr_matched', clear
merge 1:1 open_year using `pr_unmatched', nogen
replace mi_matched = 0 if mi(mi_matched)
replace mi_unmatched = 0 if mi(mi_unmatched)
gen double mi_total = mi_matched + mi_unmatched
drop if mi(open_year)
sort open_year
gen zero = 0
// gen double share_mi_matched = mi_matched / mi_total
// gen double share_mi_unmatched = mi_unmatched / mi_total
// gen double share_max = 1 // used for area chart

twoway ///
    (rarea zero mi_matched open_year) ///
    (rarea mi_matched mi_total open_year), ///
    title("Share of PR-511 chain mileage with coarse FMIS match", size(medsmall)) ///
    ytitle("Miles", size(small)) ///
    xtitle("Opening Year", size(small)) ///
    legend(order(1 "Matched" 2 "Unmatched") rows(1) size(small) position(6)) ///
    note( ///
        "Matches are any pair of FMIS projects and PR-511 chains that share the same state, county, route, and time window." ///
        "FMIS project route is crudely inferred from the first three characters of the federal project number." ///
        "Match allows for FMIS project completion year to be 0-2 years after PR-511 open year." ///
        "PR-511 chains are consecutive segments of the same route opened in the same month." ///
        "No filters for detail improvement type used.", ///
        size(vsmall) span ///
    )
graph export "$out_dir/pr511_mi_share_matched.png", replace width(2400)

* FMIS spending share of spending, matched vs unmatched
use "$intermediate_data/PR511_FMIS_match_all.dta", clear
bysort recipientid federal_project_number: keep if _n == 1
rename completion_year year
collapse (sum) cost_matched = total_cost_mills, by(year)
tempfile fmis_matched
save `fmis_matched'

use "$match_dir/unmatched_FMIS.dta", clear
rename completion_year year
collapse (sum) cost_unmatched = total_cost_mills, by(year)
tempfile fmis_unmatched
save `fmis_unmatched'

use `fmis_matched', clear
merge 1:1 year using `fmis_unmatched', nogen
replace cost_matched = 0 if mi(cost_matched)
replace cost_unmatched = 0 if mi(cost_unmatched)

* adjust for inflation
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
drop if mi(cpi)
gen cost_matched_bills_adj = cost_matched / cpi / 1000
gen cost_unmatched_bills_adj = cost_unmatched / cpi / 1000
drop cpi cost_matched cost_unmatched
gen cost_total_bills_adj = cost_matched_bills_adj + cost_unmatched_bills_adj
drop if mi(year) | year > 2001 // 2 years past last PR-511 open year
sort year
gen zero = 0
// gen double sh_fmis_matched = fmis_m_y / fmis_tot
// gen double sh_fmis_unmatched = fmis_u_y / fmis_tot
// gen double cum_fmis_matched = sh_fmis_matched
// gen double cum_fmis_top = 1

twoway ///
    (rarea zero cost_matched_bills_adj year) ///
    (rarea cost_matched_bills_adj cost_total_bills_adj year), ///
    title("Share of FMIS interstate project spending matched to PR-511", size(medsmall)) ///
    ytitle("Billions of 2025 USD", size(small)) ///
    xtitle("Completion Year", size(small)) ///
    xlabel(, labsize(small)) ///
    legend(order(1 "Matched" 2 "Unmatched")) ///
    note( ///
        "Matches are any pair of FMIS projects and PR-511 chains that share the same state, county, route, and time window." ///
        "FMIS project route is crudely inferred from the first three characters of the federal project number." ///
        "Match allows for FMIS project completion year to be 0-2 years after PR-511 open year." ///
        "PR-511 chains are consecutive segments of the same route opened in the same month." ///
        "No filters for detail improvement type used.", ///
        size(vsmall) span ///
    )
graph export "$out_dir/fmis_spend_share_matched.png", replace width(2400)

exit 


* ==============================================================================
* merge FMIS and PR-511 data at county and year level (treating FMIS as a lagged year) and compare spend/mi and mi/spend 
* ==============================================================================

* PR-511: construct panel
* 1. county x year, 2. county x 5-year block, 3. state x 5-year block 
use "$intermediate_data/PR511_hubbardmazzeo.dta", clear

rename st state_fips
rename open_year pr_year
gen long county_fips = real(string(state_fips, "%02.0f") + string(county, "%03.0f")) if !mi(state_fips) & !mi(county)
tempfile pr511_yr_block pr511_cal_yr pr511_state_yr_block

* 1. county x year
preserve
collapse (sum) pr511_interstate_mi = seg_len, by(county_fips pr_year)
save `pr511_cal_yr'
restore

* 2. county x 5-year block
preserve
gen int yr_block = .
replace yr_block = 0 if pr_year < 1960 & !mi(pr_year)
replace yr_block = 1 + floor((pr_year - 1960) / 5) if pr_year >= 1960 & !mi(pr_year)
collapse (sum) pr511_interstate_mi = seg_len, by(county_fips yr_block)
save `pr511_yr_block'
restore

* 3. state x 5-year block 
preserve
gen int yr_block = .
replace yr_block = 0 if pr_year < 1960 & !mi(pr_year)
replace yr_block = 1 + floor((pr_year - 1960) / 5) if pr_year >= 1960 & !mi(pr_year)
collapse (sum) pr511_interstate_mi = seg_len, by(state_fips yr_block)
save `pr511_state_yr_block'
restore

* ===============
* FMIS: construct panel
* 1. county x year, 2. county x 5-year block, 3. state x 5-year block 

use "$intermediate_data/receipt_level_FMIS.dta", clear

drop if completion_year > 1993

keep if interstate_syscode == 1
// TODO: handle statewide or unknown county separately

* adjust for inflation 
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_cost_mills_adjusted = total_cost_mills / cpi

tempfile fmis_yr_block fmis_cal_yr fmis_state_yr_block
tempfile panel_cty_yr panel_cty_5yr panel_state_5yr

gen int pr_year = year - 1

* 1. county x year
preserve
drop if mi(pr_year)
collapse (sum) fmis_interstate_cost_mills = total_cost_mills_adjusted (first) state_fips, by(county_fips pr_year)
save `fmis_cal_yr'
restore

* 2. county x 5-year block
preserve
gen int yr_block = 0 if pr_year < 1960
replace yr_block = 1 + floor((pr_year - 1960) / 5) if pr_year >= 1960 & !mi(pr_year)
collapse (sum) fmis_interstate_cost_mills = total_cost_mills_adjusted (first) state_fips, by(county_fips yr_block)
save `fmis_yr_block'
restore

* 3. state x 5-year block 
preserve
gen int yr_block = 0 if pr_year < 1960
replace yr_block = 1 + floor((pr_year - 1960) / 5) if pr_year >= 1960 & !mi(pr_year)
collapse (sum) fmis_interstate_cost_mills = total_cost_mills_adjusted, by(state_fips yr_block)
save `fmis_state_yr_block'
restore

* ===============
* merge FMIS with PR-511

* 1. county x year
use `fmis_cal_yr', clear
merge 1:1 county_fips pr_year using `pr511_cal_yr', keep(3) nogen
// drop _merge

fillin county_fips pr_year
replace pr511_interstate_mi = 0 if mi(pr511_interstate_mi)
replace fmis_interstate_cost_mills = 0 if mi(fmis_interstate_cost_mills)

gen mi_per_dollar = pr511_interstate_mi / fmis_interstate_cost_mills
gen spend_per_mi = fmis_interstate_cost_mills / pr511_interstate_mi

label var pr511_interstate_mi "Interstate miles opened"
label var fmis_interstate_cost_mills "FMIS interstate spending, millions of 2025 USD"
label var pr_year "PR-511 opening year"

sort county_fips pr_year
save `panel_cty_yr'

* 2. county x 5-year block
use `fmis_yr_block', clear
merge 1:1 county_fips yr_block using `pr511_yr_block', keep(3) nogen
// drop _merge

fillin county_fips yr_block
replace pr511_interstate_mi = 0 if mi(pr511_interstate_mi)
replace fmis_interstate_cost_mills = 0 if mi(fmis_interstate_cost_mills)

gen mi_per_dollar = pr511_interstate_mi / fmis_interstate_cost_mills
gen spend_per_mi = fmis_interstate_cost_mills / pr511_interstate_mi

label var pr511_interstate_mi "Interstate miles opened"
label var fmis_interstate_cost_mills "FMIS interstate spending, millions of 2025 USD"

gen int yr_block_open_lo = .
replace yr_block_open_lo = 1960 + 5 * (yr_block - 1) if yr_block >= 1
label var yr_block_open_lo "First calendar year in PR-511 opening window for this block"

gen int yr_block_open_hi = .
replace yr_block_open_hi = 1959 if yr_block == 0
replace yr_block_open_hi = yr_block_open_lo + 4 if yr_block >= 1 & !mi(yr_block_open_lo)
label var yr_block_open_hi "Last calendar year in PR-511 opening window for this block"

label values yr_block yr_block_lbl

sort county_fips yr_block
save `panel_cty_5yr'

* 3. state x 5-year block
use `fmis_state_yr_block', clear
merge 1:1 state_fips yr_block using `pr511_state_yr_block', keep(3) nogen
// drop _merge

fillin state_fips yr_block
replace pr511_interstate_mi = 0 if mi(pr511_interstate_mi)
replace fmis_interstate_cost_mills = 0 if mi(fmis_interstate_cost_mills)

gen mi_per_dollar = pr511_interstate_mi / fmis_interstate_cost_mills
gen spend_per_mi = fmis_interstate_cost_mills / pr511_interstate_mi

gen int yr_block_open_lo = .
replace yr_block_open_lo = 1960 + 5 * (yr_block - 1) if yr_block >= 1
label var yr_block_open_lo "First calendar year in PR-511 opening window for this block"

gen int yr_block_open_hi = .
replace yr_block_open_hi = 1959 if yr_block == 0
replace yr_block_open_hi = yr_block_open_lo + 4 if yr_block >= 1 & !mi(yr_block_open_lo)
label var yr_block_open_hi "Last calendar year in PR-511 opening window for this block"

label values yr_block yr_block_lbl

sort state_fips yr_block
save `panel_state_5yr'

* ===============
* figures 
* ===============

* county x 5-year block means
use `panel_cty_5yr', clear
// keep if !mi(mi_per_dollar)
collapse (sum) pr511_interstate_mi fmis_interstate_cost_mills (count) n_cty = pr511_interstate_mi, by(yr_block)
gen mi_per_dollar = pr511_interstate_mi / fmis_interstate_cost_mills
gen spend_per_mi = fmis_interstate_cost_mills / pr511_interstate_mi
sort yr_block

* construct labels for year ranges 
gen x_range = ""
replace x_range = "< 1960" if yr_block == 0
gen int _open_lo = 1960 + 5 * (yr_block - 1) if yr_block >= 1
replace x_range = string(_open_lo) + "-" + string(_open_lo + 4) if yr_block >= 1
drop _open_lo

drop if mi(yr_block) | mi(x_range) | x_range == ""

local xlab ""
forvalues i = 1/`=_N' {
    local b = yr_block[`i']
    local t = x_range[`i']
    local xlab `xlab' `b' "`t'"
}

twoway (bar mi_per_dollar yr_block), ///
    title("Mean interstate miles constructed per dollar", size(medsmall)) ///
    subtitle("(Balanced panel of county x 5-year blocks)", size(vsmall)) ///
    xtitle("PR-511 opening year", size(small)) ///
    ytitle("Mean miles per million 2025 USD", size(small)) ///
    legend(off) ///
    xlabel(`xlab', labsize(small) angle(45)) ylabel(, labsize(small) format(%9.3g)) ///
    note( ///
        "FMIS completion year is treated as if lagged one year behind PR-511 opening year.", ///
        size(vsmall) span ///
    )

graph export "$out_dir/avg_mi_per_dollar_yr_block.png", replace width(2400)

twoway (bar spend_per_mi yr_block), ///
    title("Mean interstate spending per mile", size(medsmall)) ///
    subtitle("(Balanced panel of county x 5-year blocks)", size(vsmall)) ///
    xtitle("PR-511 opening year", size(small)) ///
    ytitle("Mean spending per mile (millions of 2025 USD)", size(small)) ///
    legend(off) ///
    xlabel(`xlab', labsize(small) angle(45)) ylabel(, labsize(small) format(%9.3g)) ///
    note( ///
        "FMIS completion year is treated as if lagged one year behind PR-511 opening year.", ///
        size(vsmall) span ///
    )

graph export "$out_dir/avg_spend_per_mi_yr_block.png", replace width(2400)


* ===============
* county x year means
use `panel_cty_yr', clear
drop if pr_year < 1950 | pr_year > 1993
collapse (sum) pr511_interstate_mi fmis_interstate_cost_mills (count) n_cty = pr511_interstate_mi, by(pr_year)
gen mi_per_dollar = pr511_interstate_mi / fmis_interstate_cost_mills
gen spend_per_mi = fmis_interstate_cost_mills / pr511_interstate_mi
sort pr_year

twoway (line mi_per_dollar pr_year), ///
    title("Mean interstate miles constructed per dollar", size(medsmall)) ///
    subtitle("Panel of county x calendar year", size(vsmall)) ///
    xtitle("PR-511 segment opening year", size(small)) ///
    ytitle("Mean miles per million 2025 USD", size(small)) ///
    xlabel(1950(5)1995, labsize(small) angle(45)) ///
    legend(off) ///
    note("FMIS completion year is treated as if lagged one year behind PR-511 opening year.", size(vsmall) span)

graph export "$out_dir/avg_mi_per_dollar_year.png", replace width(2400)

twoway (line spend_per_mi pr_year), ///
    title("Mean interstate spending per mile", size(medsmall)) ///
    subtitle("Panel of county x calendar year", size(vsmall)) ///
    xtitle("PR-511 segment opening year", size(small)) ///
    ytitle("Mean spending per mile (millions of 2025 USD)", size(small)) ///
    xlabel(1950(5)1995, labsize(small) angle(45)) ///
    legend(off) ///
    note("FMIS completion year is treated as if lagged one year behind PR-511 opening year.", size(vsmall) span)

graph export "$out_dir/avg_spend_per_mi_year.png", replace width(2400)


* ===============
* state x 5-year block means

use `panel_state_5yr', clear
collapse (sum) pr511_interstate_mi fmis_interstate_cost_mills (count) n_state = pr511_interstate_mi, by(yr_block)
gen mi_per_dollar = pr511_interstate_mi / fmis_interstate_cost_mills
gen spend_per_mi = fmis_interstate_cost_mills / pr511_interstate_mi

* construct labels for year ranges 
gen x_range = ""
replace x_range = "< 1960" if yr_block == 0
gen int _open_lo = 1960 + 5 * (yr_block - 1) if yr_block >= 1
replace x_range = string(_open_lo) + "-" + string(_open_lo + 4) if yr_block >= 1
drop _open_lo

drop if mi(yr_block) | mi(x_range) | x_range == ""

local xlab ""
forvalues i = 1/`=_N' {
    local b = yr_block[`i']
    local t = x_range[`i']
    local xlab `xlab' `b' "`t'"
}

* plot mi per dollar 
twoway (bar mi_per_dollar yr_block), ///
    title("Mean interstate miles constructed per dollar", size(medsmall)) ///
    subtitle("(Balanced panel of state x 5-year blocks)", size(vsmall)) ///
    xtitle("PR-511 opening year", size(small)) ///
    ytitle("Mean miles per million 2025 USD", size(small)) ///
    legend(off) ///
    xlabel(`xlab', labsize(small) angle(45)) ylabel(, labsize(small) format(%9.3g)) ///
    note( ///
        "FMIS completion year is treated as if lagged one year behind PR-511 opening year.", ///
        size(vsmall) span ///
    )
graph export "$out_dir/avg_mi_per_dollar_state_5yrblock.png", replace width(2400)

* plot spend per mile 
twoway (bar spend_per_mi yr_block), ///
    title("Mean interstate spending per mile", size(medsmall)) ///
    subtitle("(Balanced panel of state x 5-year blocks)", size(vsmall)) ///
    xtitle("PR-511 opening year", size(small)) ///
    ytitle("Mean spending per mile (millions of 2025 USD)", size(small)) ///
    legend(off) ///
    xlabel(`xlab', labsize(small) angle(45)) ylabel(, labsize(small) format(%9.3g)) ///
    note( ///
        "FMIS completion year is treated as if lagged one year behind PR-511 opening year.", ///
        size(vsmall) span ///
    )
graph export "$out_dir/avg_spend_per_mi_state_5yrblock.png", replace width(2400)













