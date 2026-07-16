local user = c(username)
if "`user'" == "fm557"{
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

global pr511_intermediate "$intermediate_data/PR_511"
if !direxists("$pr511_intermediate") mkdir "$pr511_intermediate"

global out_dir "$output/PR511"
if !direxists("$out_dir") mkdir "$out_dir"

use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear

* create a state-route identifier
// unsure if this is the most accurate way of finding unique mileposts, but most intuitive right now, flag to potentially adjust

gsort state route mp_start

tostring route, replace
gen st_route = state + "_" + route

* check if chain_len corresponds 1:1 with the mp_start and mp_end

keep if open_year != . & open_month != . // quite a few duplicates

replace chain_len = round(float(chain_len), 0.01)
gen chain_len_test = round(float(mp_end - mp_start), 0.01)
gen chain_len_diff = chain_len - chain_len_test
gen chain_len_result = 0
replace chain_len_result = 1 if chain_len_diff > 0.0001

preserve
keep if chain_len_result == 1
codebook chain_len_diff
restore
// seems to be quite accurate, no issues here

drop chain_len_test chain_len_diff chain_len_result

* within state routes, are there missing values in mp start and end chains?

gsort st_route mp_start

bys st_route: egen n_segs = count(st_route)
bysort st_route: egen rt_length_max = max(mp_end)
bysort st_route: egen rt_length_min = min(mp_start)
gen rt_length = rt_length_max - rt_length_min
drop rt_length_max rt_length_min

replace mp_start = round(float(mp_start), 0.001)
replace mp_end = round(float(mp_end), 0.001)

bys st_route (mp_start): gen link_gap = mp_start - mp_end[_n-1] if _n > 1
replace link_gap = 0 if abs(link_gap) < 0.01 // threshold

* replace gap = 0 if they are immediately compensated by a subsequent/preceding gap of roughly equal size (likely accounting error)

gen link_gap_adj = link_gap
replace link_gap_adj = 0 if abs(abs(link_gap[_n-1]) - abs(link_gap)) <= 0.001
replace link_gap_adj = 0 if abs(abs(link_gap[_n+1]) - abs(link_gap)) <= 0.001

bys st_route (mp_start): gen link_gap_year = open_year - open_year[_n-1] if n > 1

* link_gap == 0 means it links cleanly; anything else is a break
gen byte broken = link_gap_adj > 0 if !missing(link_gap_adj)
bys st_route: egen any_broken = max(broken)

gen byte overlap = link_gap_adj < 0 if !missing(link_gap_adj)
bys st_route: egen any_overlap = max(overlap)

gen link_gap_broken = link_gap_adj if broken == 1
bys st_route: egen total_broken = total(link_gap_broken)
drop link_gap_broken

gen link_gap_overlap = link_gap_adj if overlap == 1
bys st_route: egen total_overlap = total(link_gap_overlap)
replace total_overlap = abs(total_overlap)
drop link_gap_overlap

bys st_route: gen total_balance = round(total_broken - total_overlap, 0.001) // check if overlaps and gaps on net cancel each other out

replace total_broken = 0 if total_balance==0
replace total_overlap = 0 if total_balance==0

* get years of construction
bys st_route: egen max_year = max(open_year)
bys st_route: egen min_year = min(open_year)
bys st_route: gen total_years = max_year - min_year


*=======================================
*sum stats
*=======================================

label variable total_broken      "Sum of breaks"
label variable total_overlap  "Sum of overlapped space"
label variable n_segs         "\# of Segments"
label variable rt_length      "Route length"
label define brk 0 "No breaks" 1 "Breaks"
label define ovlp 0 "No overlaps" 1 "Overlaps"
label values any_broken brk
label values any_overlap ovlp
label variable total_years "Timeframe (years)"

preserve
collapse (first) any_broken any_overlap, by(st_route)

count
local total_st_rt = r(N)

count if any_broken == 0 & any_overlap == 0
local total_st_rt_cont = r(N)
local cont_pct = `total_st_rt_cont' / `total_st_rt'

count if any_broken == 1
local total_st_rt_broken = r(N)
local broken_pct = `total_st_rt_broken' / `total_st_rt'
count if any_overlap == 1
local total_st_rt_overlap = r(N)
local overlap_pct = `total_st_rt_overlap' / `total_st_rt'

restore

di `total_st_rt'
di `total_st_rt_cont'
di `cont_pct'
di `total_st_rt_broken'
di `broken_pct'
di `total_st_rt_overlap'
di `overlap_pct'

summarize link_gap_adj if overlap == 1, meanonly
local total_overlap = abs(r(sum))
local total_overlapped_segments = r(N)
display `total_overlap'
display `total_overlapped_segments'

summarize chain_len, meanonly
local total_data_miles = r(sum)

summarize link_gap_adj if broken == 1, meanonly
local total_broken = r(sum)
local total_broken_segments = r(N)

display `total_data_miles'

display `total_overlap'
display `total_overlapped_segments'

display `total_broken'
display `total_broken_segments'

* compare averages across routes with continuity, breaks, and overlaps

preserve

    collapse (first) total_broken total_overlap n_segs rt_length total_years any_broken any_overlap, by(st_route)
	
label variable total_broken      "Sum of breaks"
label variable total_overlap  "Sum of overlapped space"
label variable n_segs         "\# of Segments"
label variable rt_length      "Route length"
label values any_broken brk
label values any_overlap ovlp
label variable total_years "Timeframe (years)"

    eststo clear
	eststo all: estpost summarize total_broken total_overlap n_segs rt_length total_years
    eststo linked: estpost summarize total_broken total_overlap n_segs rt_length total_years if any_broken==0 & any_overlap==0
	eststo broken: estpost summarize total_broken total_overlap n_segs rt_length total_years if any_broken==1
	eststo overlapped: estpost summarize total_broken total_overlap n_segs rt_length total_years if any_overlap==1

    esttab all linked broken overlapped using "$out_dir/sum_stats_by_broken_overlap.tex", replace ///
        cells(`"mean(fmt(%9.2f))"' `"sd(fmt(%9.2f) par)"') ///
        label booktabs nonumber collabels(none) ///
        mtitles("All Routes" "Continuous" "Broken" "Overlapped") ///
        title("Route characteristics by linkage status")
restore

* sum stats for routes with breaks

preserve

    collapse (first) total_broken total_overlap n_segs rt_length any_broken total_years, by(st_route)
    keep if any_broken == 1
	
	label variable total_broken      "Sum of breaks"
	label variable total_overlap  "Sum of overlapped space"
	label variable n_segs         "\# of Segments"
	label variable rt_length      "Route length"
	label values any_broken brk
	label variable total_years "Timeframe (years)"

    eststo clear
    estpost summarize total_broken total_overlap n_segs rt_length total_years, detail

    esttab using "$out_dir/sum_stats_broken_only.tex", replace ///
        cells("mean(fmt(%9.2f)) sd(fmt(%9.2f)) p50(fmt(%9.2f)) min(fmt(%9.2f)) max(fmt(%9.2f)) count(fmt(%9.0g))") ///
        label booktabs nonumber nomtitle collabels("Mean" "SD" "Median" "Min" "Max" "N") ///
        title("Summary statistics: Routes with any breaks")
restore

* sum stats for routes with overlaps

preserve

    collapse (first) total_broken total_overlap n_segs rt_length any_overlap total_years, by(st_route)
    keep if any_overlap == 1
	
	label variable total_broken      "Sum of breaks"
	label variable total_overlap  "Sum of overlapped space"
	label variable n_segs         "\# of Segments"
	label variable rt_length      "Route length"
	label values any_overlap ovlp
	label variable total_years "Timeframe (years)"

    eststo clear
    estpost summarize total_broken total_overlap n_segs rt_length total_years, detail

    esttab using "$out_dir/sum_stats_overlap_only.tex", replace ///
        cells("mean(fmt(%9.2f)) sd(fmt(%9.2f)) p50(fmt(%9.2f)) min(fmt(%9.2f)) max(fmt(%9.2f)) count(fmt(%9.0g))") ///
        label booktabs nonumber nomtitle collabels("Mean" "SD" "Median" "Min" "Max" "N") ///
        title("Summary statistics: Routes with any overlap")
restore

* compare total breaks and total overlap

preserve

drop if total_broken >= 20 | total_overlap >= 20
twoway scatter total_overlap total_broken, ///
title("Total Breaks vs. Total Overlap") ///
subtitle("State route observations where the total breaks and overlap are under 20 miles") ///

graph export "$out_dir/total_breaks_total_overlap_correlation.png", replace
restore