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

global fig_height = 384 // 4 inches, so it fits on Google Docs nicely 

* ==============================================================================
global pr511_intermediate "$intermediate_data/PR_511"
if !direxists("$pr511_intermediate") mkdir "$pr511_intermediate"

global out_dir "$output/PR511_FMIS"
if !direxists("$out_dir") mkdir "$out_dir"
global match_dir "$intermediate_data/PR511_FMIS"

* set match time window
global post_pr_window = 2
global pre_pr_window = 0
global match_suffix "_pre${pre_pr_window}_post${post_pr_window}"
global match_window_note ///
    "Match allows FMIS project completion year to be ${pre_pr_window} years before to ${post_pr_window} years after PR-511 open year."

* derive PR-511 year bounds
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
quietly summarize open_year
global pr_open_year_min = r(min)
global pr_open_year_max = r(max)
global fmis_year_min = $pr_open_year_min - $pre_pr_window
global fmis_year_max = $pr_open_year_max + $post_pr_window

// * ==============================================================================
// * compare FMIS and PR-511 interstate spending to miles opened to check alignment
// * ==============================================================================
// * load receipt-level FMIS data
// use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
// // keep if interstate_syscode == 1
// keep if funding_program == "Interstate Construction"

// * adjust for inflation 
// rename completion_year year
// merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
// gen total_cost_bills_adjusted = total_cost_mills / cpi / 1000
// drop cpi total_cost_mills

// * focus on interstate construction-era spending through 1993
// keep if year <= 1993
// collapse (sum) cost_bills_2025 = total_cost_bills_adjusted, by(state_fips year)
// keep if state_fips <= 56
// tempfile fmis_state_year
// save `fmis_state_year'

// * load and collapse PR-511 interstate openings to state-year miles opened
// use "$pr511_intermediate/PR511_hubbardmazzeo.dta", clear
// rename st state_fips
// rename open_year year
// collapse (sum) interstate_mi = seg_len, by(state_fips year)
// tempfile pr511_state_year
// save `pr511_state_year'

// use `fmis_state_year', clear
// merge 1:1 state_fips year using `pr511_state_year'
// drop _merge

// * fill in a balanced 50-state panel for plotting
// keep if year >= 1950 & year <= 1993
// fillin state_fips year
// replace cost_bills_2025 = 0 if mi(cost_bills_2025)
// replace interstate_mi = 0 if mi(interstate_mi)
// format cost_bills_2025 %9.2f
// format interstate_mi %9.2f
// sort state_fips year
// decode state_fips, gen(state_name)

// * save merged state-year series for reuse
// save "$intermediate_data/PR511_FMIS_state_year.dta", replace

// // use "$intermediate_data/PR511_FMIS_state_year.dta", clear

// * generate figures
// capture label define stateid_lbl 11 "DC", modify
// egen state_order = group(state_fips)
// gen page = ceil(state_order / 9)
// levelsof page, local(pages)

// foreach p of local pages {
//     preserve
//     keep if page == `p'

//     twoway ///
//         (line cost_bills_2025 year, ///
//             lcolor(navy) yaxis(1)) ///
//         (line interstate_mi year, ///
//             lcolor(maroon) lpattern(dash) yaxis(2)), ///
//         by(state_fips, ///
//             cols(3) ///
//             compact ///
//             legend(position(6)) ///
//             note("FMIS data uses project completion year; PR-511 uses segment opening year.", size(vsmall) span) ///
//             title("Interstate Spending vs Miles Opened, page `p'", size(small)) ///
//             b1title("Year", size(vsmall)) ///
//             l1title("2025 USD, billions", size(vsmall)) ///
//             r1title("Miles", size(small)) ///
//             subtitle(, size(tiny) fcolor(white) lcolor(white))) ///
//         graphregion(fcolor(white) lcolor(none) margin(tiny)) ///
//         xlabel(1950(5)1995, labsize(small) angle(45) grid glcolor(gs14) glwidth(vthin) glpattern(solid)) ///
//         xmtick(1955(10)1995, tlength(0) grid glcolor(gs14) glwidth(vthin) glpattern(solid)) ///
//         ylabel(, axis(1) labsize(small) angle(horizontal) format(%9.1f) nogrid) ///
//         ylabel(, axis(2) labsize(small) angle(horizontal) format(%9.1f) nogrid) ///
//         yscale(axis(1) range(0 3)) ///
//         yscale(axis(2) range(0 400)) ///
//         legend( ///
//             order(1 "FMIS interstate spending" 2 "PR-511 interstate miles opened") ///
//             rows(1) size(vsmall) ///
//         ) ///
//         xsize(20) ysize(16)
//     graph export "$out_dir/interstate_spend_vs_mi_stategrid_`p'.png", replace width(3200)
//     restore
// }

// preserve
// collapse (sum) cost_bills_2025 interstate_mi, by(year)

// twoway ///
//     (line cost_bills_2025 year, ///
//         lcolor(navy) lwidth(medthick) yaxis(1)) ///
//     (line interstate_mi year, ///
//         lcolor(maroon) lpattern(dash) lwidth(medthick) yaxis(2)), ///
//     title("Interstate Spending vs Miles Opened", size(medsmall)) ///
//     xtitle("Year") ///
//     ytitle("2025 USD, billions", axis(1) size(small)) ///
//     ytitle("Miles", axis(2) size(small)) ///
//     xlabel(1950(10)1995, labsize(small) angle(45)) ///
//     ylabel(, axis(1) labsize(small) angle(horizontal) format(%9.0f)) ///
//     ylabel(, axis(2) labsize(small) angle(horizontal) format(%9.0f)) ///
//     yscale(axis(1) range(0 .)) ///
//     yscale(axis(2) range(0 .)) ///
//     legend(order(1 "FMIS interstate" "spending" 2 "PR-511 interstate" "miles opened") ///
//         rows(1) size(small) position(6) ring(1)) ///
//     note("FMIS data uses project completion year; PR-511 uses segment opening year.", size(vsmall) span) ///
//     xsize(8) ysize(6)

// graph export "$out_dir/interstate_spend_vs_mi_all_states.png", replace width(2400)
// restore
// exit 

// * ==============================================================================
// * ratio of project count to miles opened over time 
// * ==============================================================================
// * compute project count by year
// use "$intermediate_data/project_level_FMIS_lite.dta", clear
// keep if fp_ic == 1
// keep if has_new_construction == 1
// rename completion_year year

// egen project_id = group(recipientid federal_project_number)
// collapse (count) project_count = project_id, by(year)
// tempfile fmis_project_count
// save `fmis_project_count'

// * compute miles opened by year
// use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
// rename open_year year
// collapse (sum) mi_opened = chain_len, by(year)
// keep year mi_opened
// drop if mi(year) | year < 1950
// tempfile pr511_mi
// save `pr511_mi'

// * merge and compute ratio
// merge 1:1 year using `fmis_project_count', keep(3) nogen
// gen proj_to_mi = project_count / mi_opened

// twoway ///
//     (line proj_to_mi year), ///
//     title("Ratio of New Construction Project Count to Miles Opened over Time", size(medium)) ///
//     xtitle("PR-511 Open Year") ///
//     ytitle("Project count per mile opened") ///
//     legend(off) ///
//     note("New construction projects are those with at least one reimbursement with an improvement type of new construction roadway, maintenance relocation, bridge new construction, or new tunnel.", size(vsmall) span)
// graph export "$out_dir/proj_mi_ratio_newconstr.png", replace width(2400)

// * iterate over lag assumptions for FMIS completion year relative to PR-511
// tempfile proj_mi_all_shifts
// * initialize combined file with a 0-year forward shift
// use `fmis_project_count', clear
// tempfile fmis_project_count_shifted
// save `fmis_project_count_shifted'
// use `pr511_mi', clear
// merge 1:1 year using `fmis_project_count_shifted', keep(3) nogen
// gen proj_to_mi = project_count / mi_opened
// keep year proj_to_mi
// gen byte shift_step = 0
// save `proj_mi_all_shifts', replace

// forvalues shift_step = 1/5 {
//     use `fmis_project_count', clear
//     gen int pr_year = year - `shift_step'
//     drop year
//     rename pr_year year
//     tempfile fmis_project_count_shifted
//     save `fmis_project_count_shifted'

//     use `pr511_mi', clear
//     merge 1:1 year using `fmis_project_count_shifted', keep(3) nogen
//     gen proj_to_mi = project_count / mi_opened

//     twoway ///
//         (line proj_to_mi year), ///
//         title("Ratio of New Construction Project Count to Miles Opened over Time", size(medium)) ///
//         subtitle("FMIS Complete Date Shifted `shift_step' Year(s) Forward", size(small)) ///
//         xtitle("PR-511 Open Year") ///
//         ytitle("Project count per mile opened") ///
//         note( ///
//             "FMIS project completion year is shifted `shift_step' year(s) forward to account for lag after PR-511." ///
//             "New construction projects are those with at least one reimbursement with an improvement type of new construction roadway, maintenance relocation, bridge new construction, or new tunnel.", ///
//             size(vsmall) span ///
//         ) ///
//         legend(off)
//     graph export "$out_dir/proj_mi_ratio_newconstr_shifted`shift_step'.png", replace width(2400)

//     keep year proj_to_mi
//     gen byte shift_step = `shift_step'
//     append using `proj_mi_all_shifts'
//     save `proj_mi_all_shifts', replace
// }

// * overlay all shift steps on one graph
// use `proj_mi_all_shifts', clear
// reshape wide proj_to_mi, i(year) j(shift_step)
// twoway ///
//     (line proj_to_mi0 year) ///
//     (line proj_to_mi1 year) ///
//     (line proj_to_mi2 year) ///
//     (line proj_to_mi3 year) ///
//     (line proj_to_mi4 year) ///
//     (line proj_to_mi5 year), ///
//     title("Ratio of New Construction Project Count to Miles Opened over Time", size(medium)) ///
//     subtitle("FMIS Completion Shifted 0 to 5 Years Forward", size(small)) ///
//     xtitle("PR-511 Open Year") ///
//     ytitle("Project count per mile opened") ///
//     legend( ///
//         title("FMIS Forward Shift", size(small)) ///
//         label(1 "0 Years") ///
//         label(2 "1 Year") ///
//         label(3 "2 Years") ///
//         label(4 "3 Years") ///
//         label(5 "4 Years") ///
//         label(6 "5 Years") ///
//     ) ///
//     note( ///
//         "Each line shifts FMIS completion year forward by some number of years to account for lag after PR-511." ///
//         "New construction projects are those with at least one reimbursement with an improvement type of new construction roadway, maintenance relocation, bridge new construction, or new tunnel.", ///
//         size(vsmall) span ///
//     )
// graph export "$out_dir/proj_mi_ratio_newconstr_shifted_overlay.png", replace width(2400)


// * ==============================================================================
// * projects in the same county x year or county x route x year cell
// * ==============================================================================

// * ============
// * for PR-511
// * ============
// use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
// drop if open_year < 1950 | mi(open_year)
// gen county_fips = real(string(st, "%02.0f") + string(county, "%03.0f")) if !mi(st) & !mi(county)
// gen county_fips_x_route = real(string(st, "%02.0f") + string(county, "%03.0f") + string(route, "%03.0f")) if !mi(st) & !mi(county) & !mi(route)

// * county x year, distribution of count 
// preserve 
// collapse (count) chain_count = chain_id, by(county_fips open_year)
// local n_obs = _N
// graph twoway ///
//     (histogram chain_count, frequency), ///
//     title("Distribution of PR-511 Chains by County x Year Cell", size(medsmall)) ///
//     ytitle("Number of cells", size(small)) ///
//     xtitle("Number of PR-511 chains in cell", size(small)) ///
//     note( ///
//         "Chains are defined as consecutive segments of the same route within the same opening month." ///
//         "Number of county x year cells: `n_obs'." ///
// 		, size(small) span ///
//     ) ///
//     legend(off)
// graph export "$out_dir/pr511_distrib_chain_by_ct_yr.png", replace height($fig_height)
// restore

// * county x year, distribution weighted by miles
// preserve
// collapse (count) chain_count = chain_id (sum) cell_chain_len = chain_len, by(county_fips open_year)
// local n_obs = _N
// collapse (sum) weighted_freq_miles = cell_chain_len, by(chain_count)
// twoway ///
//     (bar weighted_freq_miles chain_count), ///
//     title("Distribution of PR-511 Chains by County x Year Cell", size(medsmall)) ///
//     subtitle("Weighted by chain length (miles)", size(small)) ///
//     ytitle("Weighted frequency (sum of chain miles)", size(small)) ///
//     xtitle("Number of PR-511 chains in cell", size(small)) ///
//     note( ///
//         "Chains are defined as consecutive segments of the same route within the same opening month." ///
//         "Number of county x year cells: `n_obs'." ///
//		, size(small) span ///
//     ) ///
//     legend(off)
// graph export "$out_dir/pr511_distrib_chain_by_ct_yr_weighted_miles.png", replace height($fig_height)
// restore

// * count x year, distribution of miles 
// preserve
// collapse (sum) len = chain_len, by(county_fips open_year)
// graph twoway ///
//     (histogram len, frequency), ///
//     title("Distribution of PR-511 Miles by County x Year Cell", size(medsmall)) ///
//     ytitle("Number of cells", size(small)) ///
//     xtitle("Miles of PR-511 chains in cell", size(small)) ///
//     note( ///
//         "Chains are defined as consecutive segments of the same route within the same opening month.", ///
//         size(small) span ///
//     ) ///
//     legend(off)
// graph export "$out_dir/pr511_distrib_mi_by_ct_yr.png", replace height($fig_height)
// restore

// * county x year, count groups over time
// preserve
// collapse (count) chain_count = chain_id, by(county_fips open_year)
// sort county_fips open_year
// sum chain_count, detail

// * compute percentile thresholds 
// egen p25_thresh = pctile(chain_count), p(25)
// egen p50_thresh = pctile(chain_count), p(50)
// egen p75_thresh = pctile(chain_count), p(75)
// egen p90_thresh = pctile(chain_count), p(90)
// egen p95_thresh = pctile(chain_count), p(95)
// quietly summarize p25_thresh, meanonly
// local p25_label = strtrim(string(r(mean), "%9.0f"))
// quietly summarize p50_thresh, meanonly
// local p50_label = strtrim(string(r(mean), "%9.0f"))
// quietly summarize p75_thresh, meanonly
// local p75_label = strtrim(string(r(mean), "%9.0f"))
// quietly summarize p90_thresh, meanonly
// local p90_label = strtrim(string(r(mean), "%9.0f"))
// quietly summarize p95_thresh, meanonly
// local p95_label = strtrim(string(r(mean), "%9.0f"))

// * generate binary flags for percentile groups
// gen le_p25 = (chain_count <= p25_thresh)
// gen le_p50 = (chain_count <= p50_thresh)
// gen le_p75 = (chain_count <= p75_thresh)
// gen le_p90 = (chain_count <= p90_thresh)
// gen le_p95 = (chain_count <= p95_thresh)

// collapse ///
//     (sum) le_p25 le_p50 le_p75 le_p90 le_p95 (count) chain_count ///
//     (firstnm) p25_thresh p50_thresh p75_thresh p90_thresh p95_thresh, by(open_year)

// twoway ///
//     (line le_p25 open_year) ///
//     (line le_p50 open_year) ///
//     (line le_p75 open_year) ///
//     (line le_p90 open_year) ///
//     (line le_p95 open_year) ///
//     (line chain_count open_year), ///
//     title("Distribution of PR-511 Chain Counts by Year", size(medsmall)) ///
//     subtitle("County x year cells", size(small)) ///
//     xtitle("Opening Year", size(small)) ///
//     ytitle("Number of county x year cells", size(small)) ///
//     legend( ///
//         order( ///
//             6 "Total" ///
//             5 "`p95_label' chains in cell" "(95th percentile)" ///
//             4 "`p90_label' chains in cell" "(90th percentile)" ///
//             3 "`p75_label' chains in cell" "(75th percentile)" ///
//             2 "`p50_label' chains in cell" "(50th percentile)" ///
//             1 "`p25_label' chain in cell" "(25th percentile)" ///
//         ) ///
//         size(small)) ///
//     note("Chains are defined as consecutive segments of the same route within the same opening month.", size(small) span)
// graph export "$out_dir/pr511_distrib_chain_by_ct_yr_over_time.png", replace height($fig_height)

// * duplicate as share of county x year cell counts (out of 100)
// gen double sh_le_p25 = 100 * le_p25 / chain_count
// gen double sh_le_p50 = 100 * le_p50 / chain_count
// gen double sh_le_p75 = 100 * le_p75 / chain_count
// gen double sh_le_p90 = 100 * le_p90 / chain_count
// gen double sh_le_p95 = 100 * le_p95 / chain_count

// twoway ///
//     (line sh_le_p25 open_year) ///
//     (line sh_le_p50 open_year) ///
//     (line sh_le_p75 open_year) ///
//     (line sh_le_p90 open_year) ///
//     (line sh_le_p95 open_year), ///
//     title("Distribution of PR-511 Chain Counts by Year", size(medsmall)) ///
//     subtitle("County x year cells", size(small)) ///
//     xtitle("Opening Year", size(small)) ///
//     ytitle("% of county x year cells", size(small)) ///
//     ylabel(0(20)100) ///
//     legend( ///
//         order( ///
//             5 "`p95_label' chains in cell" "(95th percentile)" ///
//             4 "`p90_label' chains in cell" "(90th percentile)" ///
//             3 "`p75_label' chains in cell" "(75th percentile)" ///
//             2 "`p50_label' chains in cell" "(50th percentile)" ///
//             1 "`p25_label' chain in cell" "(25th percentile)" ///
//         ) ///
//         size(small)) ///
//     note("Chains are defined as consecutive segments of the same route within the same opening month.", size(small) span)
// graph export "$out_dir/pr511_distrib_chain_by_ct_yr_over_time_share.png", replace height($fig_height)
// restore

// * count x year, mile groups over time ??



// * county x route x year, distribution of count 
// preserve 
// collapse (count) chain_count = chain_id, by(county_fips route open_year)
// local n_obs = _N
// graph twoway ///
//     (histogram chain_count, frequency), ///
//     title("Distribution of PR-511 Chains by County x Route x Year Cell", size(medsmall)) ///
//     ytitle("Number of cells", size(small)) ///
//     xtitle("Number of PR-511 chains in cell", size(small)) ///
//     note( ///
//         "Chains are defined as consecutive segments of the same route within the same opening month." ///
//         "Number of county x route x year cells: `n_obs'." ///
// 		, size(small) span ///
//     ) ///
//     legend(off)
// graph export "$out_dir/pr511_distrib_chain_by_ct_rt_yr.png", replace height($fig_height)
// restore


// * county x route x year, distribution of miles 
// preserve
// collapse (sum) len = chain_len, by(county_fips route open_year)
// local n_obs = _N
// graph twoway ///
//     (histogram len, frequency), ///
//     title("Distribution of PR-511 Miles by County x Route x Year Cell", size(medsmall)) ///
//     ytitle("Number of cells", size(small)) ///
//     xtitle("Miles of PR-511 chains in cell", size(small)) ///
//     note( ///
//         "Chains are defined as consecutive segments of the same route within the same opening month." ///
//         "Number of county x route x year cells: `n_obs'." ///
// 		, size(small) span ///
//     ) ///
//     legend(off)
// graph export "$out_dir/pr511_distrib_mi_by_ct_rt_yr.png", replace height($fig_height)
// restore

// * county x route x year, count groups over time
// preserve
// collapse (count) chain_count = chain_id, by(county_fips route open_year)
// sum chain_count, detail

// * compute percentile thresholds
// egen p25_thresh = pctile(chain_count), p(25)
// egen p50_thresh = pctile(chain_count), p(50)
// egen p75_thresh = pctile(chain_count), p(75)
// egen p90_thresh = pctile(chain_count), p(90)
// egen p95_thresh = pctile(chain_count), p(95)
// quietly summarize p25_thresh, meanonly
// local p25_label = strtrim(string(r(mean), "%9.0f"))
// quietly summarize p50_thresh, meanonly
// local p50_label = strtrim(string(r(mean), "%9.0f"))
// quietly summarize p75_thresh, meanonly
// local p75_label = strtrim(string(r(mean), "%9.0f"))
// quietly summarize p90_thresh, meanonly
// local p90_label = strtrim(string(r(mean), "%9.0f"))
// quietly summarize p95_thresh, meanonly
// local p95_label = strtrim(string(r(mean), "%9.0f"))

// * generate binary flags for percentile groups
// gen le_p25 = (chain_count <= p25_thresh)
// gen le_p50 = (chain_count <= p50_thresh)
// gen le_p75 = (chain_count <= p75_thresh)
// gen le_p90 = (chain_count <= p90_thresh)
// gen le_p95 = (chain_count <= p95_thresh)

// collapse ///
//     (sum) le_p25 le_p50 le_p75 le_p90 le_p95 (count) chain_count ///
//     (firstnm) p25_thresh p50_thresh p75_thresh p90_thresh p95_thresh, by(open_year)

// twoway ///
//     (line le_p25 open_year) ///
//     (line le_p50 open_year) ///
//     (line le_p75 open_year) ///
//     (line le_p90 open_year) ///
//     (line le_p95 open_year) ///
//     (line chain_count open_year), ///
//     title("Distribution of PR-511 Chain Counts by Year", size(medsmall)) ///
//     subtitle("County x route x year cells", size(small)) ///
//     xtitle("Opening Year", size(small)) ///
//     ytitle("Number of county x route x year cells", size(small)) ///
//     legend( ///
//         order( ///
//             6 "Total" ///
//             5 "`p95_label' chains in cell" "(95th percentile)" ///
//             4 "`p90_label' chains in cell" "(90th percentile)" ///
//             3 "`p75_label' chains in cell" "(75th percentile)" ///
//             2 "`p50_label' chains in cell" "(50th percentile)" ///
//             1 "`p25_label' chain in cell" "(25th percentile)" ///
//         ) ///
//         size(small)) ///
//     note("Chains are defined as consecutive segments of the same route within the same opening month.", size(small) span)
// graph export "$out_dir/pr511_distrib_chain_by_ct_rt_yr_over_time.png", replace height($fig_height)

// * duplicate as share of county x route x year cell counts (out of 100)
// gen double sh_le_p25 = 100 * le_p25 / chain_count if chain_count > 0
// gen double sh_le_p50 = 100 * le_p50 / chain_count if chain_count > 0
// gen double sh_le_p75 = 100 * le_p75 / chain_count if chain_count > 0
// gen double sh_le_p90 = 100 * le_p90 / chain_count if chain_count > 0
// gen double sh_le_p95 = 100 * le_p95 / chain_count if chain_count > 0

// twoway ///
//     (line sh_le_p25 open_year) ///
//     (line sh_le_p50 open_year) ///
//     (line sh_le_p75 open_year) ///
//     (line sh_le_p90 open_year) ///
//     (line sh_le_p95 open_year), ///
//     title("Distribution of PR-511 Chain Counts by Year", size(medsmall)) ///
//     subtitle("County x route x year cells (share of cell count)", size(small)) ///
//     xtitle("Opening Year", size(small)) ///
//     ytitle("Share of county x route x year cells (percent)", size(small)) ///
//     ylabel(0(10)100) ///
//     legend( ///
//         order( ///
//             5 "`p95_label' chains in cell" "(95th percentile)" ///
//             4 "`p90_label' chains in cell" "(90th percentile)" ///
//             3 "`p75_label' chains in cell" "(75th percentile)" ///
//             2 "`p50_label' chains in cell" "(50th percentile)" ///
//             1 "`p25_label' chain in cell" "(25th percentile)" ///
//         ) ///
//         size(small)) ///
//     note("Chains are defined as consecutive segments of the same route within the same opening month.", size(small) span)
// graph export "$out_dir/pr511_distrib_chain_by_ct_rt_yr_over_time_share.png", replace height($fig_height)
// restore



// * ============
// * for FMIS
// * ============
// use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
// keep if funding_program == "Interstate Construction"
// keep if completion_year <= 2000
// gen pseudo_route = substr(strtrim(federal_project_number), 1, 3)
// destring pseudo_route, gen(route) force
// drop if mi(county_fips) | mi(completion_year)
// drop if countyid == 999 | countyid == 0
// keep recipientid federal_project_number county_fips route completion_year total_cost_mills

// * adjust for inflation 
// rename completion_year year
// merge m:1 year using "$intermediate_data/CPI_2025.dta", keep(3) keepusing(cpi) nogen
// gen total_cost_mills_adj = total_cost_mills / cpi
// drop cpi total_cost_mills
// // bysort recipientid federal_project_number county_fips year: keep if _n == 1
// // tempfile fmis_project_base
// // save `fmis_project_base'

// * generate unique project id 
// egen int project_id = group(recipientid federal_project_number)

// * ============
// * county x year, distribution of count
// preserve
// collapse (count) project_count = project_id, by(county_fips year)
// graph twoway ///
//     (histogram project_count, frequency), ///
//     title("Distribution of FMIS Projects by County x Year Cell", size(medsmall)) ///
//     ytitle("Number of cells", size(small)) ///
//     xtitle("Number of FMIS projects in cell", size(small)) ///
//     legend(off)
// graph export "$out_dir/fmis_distrib_count_by_ct_yr.png", replace width(2400)
// restore

// * county x year, distribution of spending

// * county x route x year, distribution of count
// preserve
// drop if mi(route)
// collapse (count) project_count = project_id, by(county_fips route year)
// graph twoway ///
//     (histogram project_count, frequency), ///
//     title("Distribution of FMIS Projects by County x Route x Year Cell", size(medsmall)) ///
//     ytitle("Number of cells", size(small)) ///
//     xtitle("Number of FMIS projects in cell", size(small)) ///
//     legend(off)
// graph export "$out_dir/fmis_distrib_count_by_ct_rt_yr.png", replace width(2400)

// * county x route x year, count groups over time

// // ignore the 25th percentile since its < 1 project/cell 
// // egen p25_thresh = pctile(project_count), p(25)
// egen p50_thresh = pctile(project_count), p(50)
// egen p75_thresh = pctile(project_count), p(75)
// egen p90_thresh = pctile(project_count), p(90)
// egen p95_thresh = pctile(project_count), p(95)
// // quietly summarize p25_thresh, meanonly
// // local p25_label = strtrim(string(r(mean), "%9.0f"))
// quietly summarize p50_thresh, meanonly
// local p50_label = strtrim(string(r(mean), "%9.0f"))
// quietly summarize p75_thresh, meanonly
// local p75_label = strtrim(string(r(mean), "%9.0f"))
// quietly summarize p90_thresh, meanonly
// local p90_label = strtrim(string(r(mean), "%9.0f"))
// quietly summarize p95_thresh, meanonly
// local p95_label = strtrim(string(r(mean), "%9.0f"))

// // gen le_p25 = (project_count <= p25_thresh)
// gen le_p50 = (project_count <= p50_thresh)
// gen le_p75 = (project_count <= p75_thresh)
// gen le_p90 = (project_count <= p90_thresh)
// gen le_p95 = (project_count <= p95_thresh)

// collapse (sum) le_p50 le_p75 le_p90 le_p95 (count) project_count, by(year)
// twoway ///
//     (line le_p50 year) ///
//     (line le_p75 year) ///
//     (line le_p90 year) ///
//     (line le_p95 year) ///
//     (line project_count year), ///
//     title("Distribution of FMIS Project Counts by Year", size(medsmall)) ///
//     subtitle("County x route x year cells", size(small)) ///
//     xtitle("Completion Year", size(small)) ///
//     ytitle("Number of county x route x year cells", size(small)) ///
//     legend( ///
//         order( ///
//             5 "Total" ///
//             4 "`p95_label' projects in cell (95th pctile)" ///
//             3 "`p90_label' projects in cell (90th pctile)" ///
//             2 "`p75_label' projects in cell (75th pctile)" ///
//             1 "`p50_label' projects in cell (50th pctile)" ///
//         ) size(small))
// graph export "$out_dir/fmis_distrib_count_by_ct_rt_yr_over_time.png", replace width(2400)

// * duplicate as share of county x route x year cell counts (out of 100)
// // gen double sh_le_p25 = 100 * le_p25 / project_count if project_count > 0
// gen double sh_le_p50 = 100 * le_p50 / project_count if project_count > 0
// gen double sh_le_p75 = 100 * le_p75 / project_count if project_count > 0
// gen double sh_le_p90 = 100 * le_p90 / project_count if project_count > 0
// gen double sh_le_p95 = 100 * le_p95 / project_count if project_count > 0

// twoway ///
//     (line sh_le_p50 year) ///
//     (line sh_le_p75 year) ///
//     (line sh_le_p90 year) ///
//     (line sh_le_p95 year), ///
//     title("Distribution of FMIS Project Counts by Year", size(medsmall)) ///
//     subtitle("County x route x year cells (share of cell count)", size(small)) ///
//     xtitle("Completion Year", size(small)) ///
//     ytitle("Share of county x route x year cells (percent)", size(small)) ///
//     ylabel(0(10)100) ///
//     legend( ///
//         order( ///
//             4 "`p95_label' projects in cell (95th pctile)" ///
//             3 "`p90_label' projects in cell (90th pctile)" ///
//             2 "`p75_label' projects in cell (75th pctile)" ///
//             1 "`p50_label' projects in cell (50th pctile)" ///
//         ) size(small))
// graph export "$out_dir/fmis_distrib_count_by_ct_rt_yr_over_time_share.png", replace width(2400)
// restore



// * county x year, distribution of count 



// * count x year, distribution of spending 




// * county x route x year, count groups over time





// * duplicate as share of county x route x year cell counts (out of 100)




// * county x route x year, spending groups over time





// * duplicate as share of county x route x year cell spending (out of 100)





// * county x route x year, distribution of count 



// * county x route x year, distribution of spending 




// * county x route x year, count groups over time





// * duplicate as share of county x route x year cell counts (out of 100)




// * county x route x year, spending groups over time





// * duplicate as share of county x route x year cell spending (out of 100)


// exit

// * ==============================================================================
// * plot count of PR-511/FMIS matches over time
// * ==============================================================================

// * number of PR-511 matches per FMIS project
// use "$intermediate_data/PR511_FMIS_match_all${match_suffix}.dta", clear
// bysort recipientid federal_project_number: gen int match_count = _N
// keep recipientid federal_project_number match_count total_cost_mills completion_year
// duplicates drop

// * adjust for inflation 
// rename completion_year year
// merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
// gen total_cost_bills_adj = total_cost_mills / cpi / 1000
// drop cpi total_cost_mills year

// tab match_count, missing
// histogram match_count, frequency width(1) ///
//     title("Number of PR-511 matches per FMIS project", size(medsmall)) ///
//     subtitle("-$pre_pr_window to +$post_pr_window time window; route used for matching", size(vsmall)) ///
//     xtitle("Number of PR-511 matches per FMIS project", size(small)) ///
//     ytitle("Number of FMIS projects", size(small)) ///
//     xlabel(, labsize(small)) ///
//     ylabel(, labsize(small) format(%9.0fc)) ///
//     note( ///
//         "Projects are included only if they have at least one receipt funded by the Interstate Construction funding program and have at least one receipt with a system code of interstate." ///
//         "No further filters for detail improvement type used." ///
//         "Matching is performed using state, county, route, and time window." ///
//         "$match_window_note", ///
//         size(vsmall) span ///
//     )
// graph export "$out_dir/pr511_fmis_match_count_hist${match_suffix}.png", replace width(2400)

// * number of PR-511 matches per FMIS project (weighted by FMIS cost)
// sum total_cost_bills_adj
// collapse (sum) total_cost_bills_adj, by(match_count)
// twoway (bar total_cost_bills_adj match_count), ///
//     title("Cost-weighted share of PR-511 matches per FMIS project", size(medsmall)) ///
//     subtitle("-$pre_pr_window to +$post_pr_window time window; route used for matching", size(vsmall)) ///
//     xtitle("Number of PR-511 matches per FMIS project", size(small)) ///
//     ytitle("Summed cost of FMIS projects (billions of 2025 USD)", size(small)) ///
//     xlabel(, labsize(small)) ///
//     ylabel(, labsize(small) format(%9.1f)) ///
//     note( ///
//         "Projects are included only if they have at least one receipt funded by the Interstate Construction funding program and have at least one receipt with a system code of interstate." ///
//         "No further filters for detail improvement type used." ///
//         "Matching is performed using state, county, route, and time window." ///
//         "$match_window_note", ///
//         size(vsmall) span ///
//     )
// graph export "$out_dir/pr511_fmis_match_cost_hist${match_suffix}.png", replace width(2400)

// * same but without route matching 
// * number of PR-511 matches per FMIS project
// use "$intermediate_data/PR511_FMIS_match_all_noroute${match_suffix}.dta", clear
// bysort recipientid federal_project_number: gen int match_count = _N
// keep recipientid federal_project_number match_count total_cost_mills completion_year
// duplicates drop

// * adjust for inflation 
// rename completion_year year
// merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
// gen total_cost_bills_adj = total_cost_mills / cpi / 1000
// drop cpi total_cost_mills year

// tab match_count, missing
// histogram match_count, frequency ///
//     title("Number of PR-511 matches per FMIS project", size(medsmall)) ///
//     subtitle("-$pre_pr_window to +$post_pr_window time window; route not used for matching", size(vsmall)) ///
//     xtitle("Number of PR-511 matches per FMIS project", size(small)) ///
//     ytitle("Number of FMIS projects", size(small)) ///
//     xlabel(, labsize(small)) ///
//     ylabel(, labsize(small) format(%9.0fc)) ///
//     note( ///
//         "Only Interstate Construction projects included. No further filters for detail improvement type used." ///
//         "Matching is performed using state, county, and time window." ///
//         "$match_window_note", ///
//         size(vsmall) span ///
//     )
// graph export "$out_dir/pr511_fmis_match_count_hist_noroute${match_suffix}.png", replace width(2400)

// * number of PR-511 matches per FMIS project (weighted by FMIS cost)
// sum total_cost_bills_adj
// collapse (sum) total_cost_bills_adj, by(match_count)
// twoway (bar total_cost_bills_adj match_count), ///
//     title("Cost-weighted share of PR-511 matches per FMIS project", size(medsmall)) ///
//     subtitle("-$pre_pr_window to +$post_pr_window time window; route not used for matching", size(vsmall)) ///
//     xtitle("Number of PR-511 matches per FMIS project", size(small)) ///
//     ytitle("Summed cost of FMIS projects (billions of 2025 USD)", size(small)) ///
//     xlabel(, labsize(small)) ///
//     ylabel(, labsize(small) format(%9.1f)) ///
//     note( ///
//         "Only Interstate Construction projects included. No further filters for detail improvement type used." ///
//         "Matching is performed using state, county, and time window." ///
//         "$match_window_note", ///
//         size(vsmall) span ///
//     )
// graph export "$out_dir/pr511_fmis_match_cost_hist_noroute${match_suffix}.png", replace width(2400)

// * count matched FMIS rows per PR-511 chain/project
// use "$intermediate_data/PR511_FMIS_match_all${match_suffix}.dta", clear
// bysort chain_id: gen int match_count = _N
// collapse (firstnm) match_count state_fips countyid route open_year chain_len urban_rural region, by(chain_id)

// // collapse by year
// preserve
// * average number of FMIS matches per PR-511 project by completion year
// collapse (mean) avg_match_count = match_count, by(open_year)
// drop if mi(open_year)
// sort open_year

// twoway ///
//     (line avg_match_count open_year), ///
//     title("Average Number of FMIS Project Matches per PR-511 Chain", size(medsmall)) ///
//     subtitle("(Match window: -$pre_pr_window to +$post_pr_window years)", size(vsmall)) ///
//     xtitle("Opening Year") ///
//     ytitle("Project Count") ///
//     xlabel(1950(5)2000, labsize(small)) ///
//     note( ///
//         "Projects are included only if they have at least one receipt funded by the Interstate Construction funding program and have at least one receipt with a system code of interstate." ///
//         "No further filters for detail improvement type used." ///
//         "Matches are any pair of FMIS projects and PR-511 chains that share the same state, county, route, and time window." ///
//         "FMIS project route is crudely inferred from the first three characters of the federal project number." ///
//         "$match_window_note" ///
//         "PR-511 chains are consecutive segments of the same route opened in the same month." ///
//         "Projects are included only if they have at least one receipt funded by the Interstate Construction funding program and have at least one receipt with a system code of interstate." ///
//         "No filters for detail improvement type used.", ///
//         size(vsmall) span ///
//     )
// graph export "$out_dir/pr511_fmis_avg_matches${match_suffix}.png", replace width(2400)
// restore 

// // preserve
// // collapse (mean) avg_match_count = match_count, by(urban_rural open_year)
// // drop if mi(open_year) | mi(urban_rural)
// // sort urban_rural open_year

// // twoway ///
// //     (line avg_match_count open_year), ///
// //     by(urban_rural, ///
// //         compact ///
// //         cols(2)) ///
// //     title("Average FMIS matches per PR-511 chain by urban/rural status", size(medsmall)) ///
// //     subtitle("(0-2 year match window)", size(vsmall)) ///
// //     xtitle("Opening Year", size(small)) ///
// //     ytitle("Project Count", size(small)) ///
// //     xlabel(1950(5)2000, labsize(vsmall)) ///
// //     ylabel(, labsize(vsmall) format(%9.2f)) ///
// //     note( ///
// //         "Matches are any pair of FMIS projects and PR-511 chains that share the same state, county, route, and time window." ///
// //         "FMIS project route is crudely inferred from the first three characters of the federal project number." ///
// //         "Match allows for FMIS project completion year to be 0-2 years after PR-511 open year." ///
// //         "PR-511 chains are consecutive segments of the same route opened in the same month." ///
// //         "No filters for detail improvement type used.", ///
// //         size(vsmall) span ///
// //     )
// // // TODO: add legend 
// // graph export "$out_dir/pr511_fmis_avg_matches_by_urbanrural.png", replace width(2400)
// // restore

// // preserve
// // collapse (mean) avg_match_count = match_count, by(region open_year)
// // drop if mi(open_year)
// // sort region open_year

// // // TODO: handle missing regions 
// // twoway ///
// //     (line avg_match_count open_year), ///
// //     by(region, ///
// //         compact ///
// //         cols(3)) ///
// //     title("Average FMIS matches per PR-511 chain by geographic region", size(medsmall)) ///
// //     subtitle("(0-2 year match window)", size(vsmall)) ///
// //     xtitle("Opening Year", size(small)) ///
// //     ytitle("Project Count", size(small)) ///
// //     xlabel(1950(5)2000, labsize(vsmall)) ///
// //     ylabel(, labsize(vsmall) format(%9.2f)) ///
// //     note( ///
// //         "Matches are any pair of FMIS projects and PR-511 chains that share the same state, county, route, and time window." ///
// //         "FMIS project route is crudely inferred from the first three characters of the federal project number." ///
// //         "Match allows for FMIS project completion year to be 0-2 years after PR-511 open year." ///
// //         "PR-511 chains are consecutive segments of the same route opened in the same month." ///
// //         "No filters for detail improvement type used.", ///
// //         size(vsmall) span ///
// //     )
// // // TODO: add legend 
// // graph export "$out_dir/pr511_fmis_avg_matches_by_region.png", replace width(2400)
// // restore

// * ==============================================================================
// * Share of PR-511 mileage and FMIS spending matched vs unmatched (time series)
// * ==============================================================================

// * PR-511 share of mileage, matched vs unmatched
// use "$intermediate_data/PR511_FMIS_match_all${match_suffix}.dta", clear
// bysort chain_id: keep if _n == 1
// collapse (sum) mi_matched = chain_len, by(open_year)
// tempfile pr_matched
// save `pr_matched'

// use "$match_dir/unmatched_PR511${match_suffix}.dta", clear
// collapse (sum) mi_unmatched = chain_len, by(open_year)
// tempfile pr_unmatched
// save `pr_unmatched'

// use `pr_matched', clear
// merge 1:1 open_year using `pr_unmatched', nogen
// replace mi_matched = 0 if mi(mi_matched)
// replace mi_unmatched = 0 if mi(mi_unmatched)
// gen double mi_total = mi_matched + mi_unmatched
// drop if mi(open_year)
// sort open_year
// gen zero = 0
// // gen double share_mi_matched = mi_matched / mi_total
// // gen double share_mi_unmatched = mi_unmatched / mi_total
// // gen double share_max = 1 // used for area chart

// twoway ///
//     (rarea zero mi_unmatched open_year) ///
//     (rarea mi_unmatched mi_total open_year), ///
//     title("Share of PR-511 chain mileage with coarse FMIS match", size(medsmall)) ///
//     ytitle("Miles", size(small)) ///
//     xtitle("Opening Year", size(small)) ///
//     legend(order(1 "Unmatched" 2 "Matched") rows(1) size(small) position(6)) ///
//     note( ///
//         "Matches are any pair of FMIS projects and PR-511 chains that share the same state, county, route, and time window." ///
//         "FMIS project route is crudely inferred from the first three characters of the federal project number." ///
//         "$match_window_note" ///
//         "PR-511 chains are consecutive segments of the same route opened in the same month." ///
//         "Projects are included only if they have at least one receipt funded by the Interstate Construction funding program and have at least one receipt with a system code of interstate." ///
//         "No filters for detail improvement type used.", ///
//         size(vsmall) span ///
//     )
// graph export "$out_dir/pr511_mi_share_matched${match_suffix}.png", replace width(2400)

// * FMIS spending share of spending, matched vs unmatched
// use "$intermediate_data/PR511_FMIS_match_all${match_suffix}.dta", clear
// bysort recipientid federal_project_number: keep if _n == 1
// rename completion_year year
// collapse (sum) cost_matched = total_cost_mills, by(year)
// tempfile fmis_matched
// save `fmis_matched'

// use "$match_dir/unmatched_FMIS${match_suffix}.dta", clear
// rename completion_year year
// collapse (sum) cost_unmatched = total_cost_mills, by(year)
// tempfile fmis_unmatched
// save `fmis_unmatched'

// use `fmis_matched', clear
// merge 1:1 year using `fmis_unmatched', nogen
// replace cost_matched = 0 if mi(cost_matched)
// replace cost_unmatched = 0 if mi(cost_unmatched)

// * adjust for inflation
// merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
// drop if mi(cpi)
// gen cost_matched_bills_adj = cost_matched / cpi / 1000
// gen cost_unmatched_bills_adj = cost_unmatched / cpi / 1000
// drop cpi cost_matched cost_unmatched
// gen cost_total_bills_adj = cost_matched_bills_adj + cost_unmatched_bills_adj
// drop if mi(year) | year < $fmis_year_min | year > $fmis_year_max
// sort year
// gen zero = 0
// // gen double sh_fmis_matched = fmis_m_y / fmis_tot
// // gen double sh_fmis_unmatched = fmis_u_y / fmis_tot
// // gen double cum_fmis_matched = sh_fmis_matched
// // gen double cum_fmis_top = 1

// twoway ///
//     (rarea zero cost_matched_bills_adj year) ///
//     (rarea cost_matched_bills_adj cost_total_bills_adj year), ///
//     title("Share of FMIS interstate project spending matched to PR-511", size(medsmall)) ///
//     ytitle("Billions of 2025 USD", size(small)) ///
//     xtitle("Completion Year", size(small)) ///
//     xlabel(, labsize(small)) ///
//     legend(order(1 "Matched" 2 "Unmatched")) ///
//     note( ///
//         "Matches are any pair of FMIS projects and PR-511 chains that share the same state, county, route, and time window." ///
//         "FMIS project route is crudely inferred from the first three characters of the federal project number." ///
//         "$match_window_note" ///
//         "PR-511 chains are consecutive segments of the same route opened in the same month." ///
//         "Projects are included only if they have at least one receipt funded by the Interstate Construction funding program and have at least one receipt with a system code of interstate." ///
//         "No filters for detail improvement type used.", ///
//         size(vsmall) span ///
//     )
// graph export "$out_dir/fmis_spend_share_matched${match_suffix}.png", replace width(2400)

// twoway ///
//     (rarea zero cost_unmatched_bills_adj year) ///
//     (rarea cost_unmatched_bills_adj cost_total_bills_adj year), ///
//     title("Share of FMIS interstate project spending matched to PR-511", size(medsmall)) ///
//     ytitle("Billions of 2025 USD", size(small)) ///
//     xtitle("Completion Year", size(small)) ///
//     xlabel(, labsize(small)) ///
//     legend(order(1 "Unmatched" 2 "Matched")) ///
//     note( ///
//         "Matches are any pair of FMIS projects and PR-511 chains that share the same state, county, route, and time window." ///
//         "FMIS project route is crudely inferred from the first three characters of the federal project number." ///
//         "$match_window_note" ///
//         "PR-511 chains are consecutive segments of the same route opened in the same month." ///
//         "Projects are included only if they have at least one receipt funded by the Interstate Construction funding program and have at least one receipt with a system code of interstate." ///
//         "No filters for detail improvement type used.", ///
//         size(vsmall) span ///
//     )
// graph export "$out_dir/fmis_spend_share_unmatched${match_suffix}.png", replace width(2400)


