/*==============================================================================
 	FMIS data processing 
    This script evaluates FMIS project titles for the quality of location descriptions after an intermediate text parsing step using an LLM. 
==============================================================================*/
* package installs (uncomment first time running if needed)
// ssc install heatplot, replace
// ssc install palettes, replace // needed for heatplot
// ssc install colrspace, replace // needed for heatplot

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
global geocoding_dir "$intermediate_data/geocoding"
global gemini_dir "$geocoding_dir/title_parsing_gemini_output"

global out_dir_regex "$output/FMIS_title_quality_regex"
if !direxists("$out_dir_regex") mkdir "$out_dir_regex"
global out_dir_gemini "$output/FMIS_title_quality_gemini"
if !direxists("$out_dir_gemini") mkdir "$out_dir_gemini"

* logical gates for code to avoid running full script 
global run_part1 = 0
global run_part2 = 1
global run_part3 = 0

* ==============================================================================
* PART 1
* Analysis of first-pass title parsing using regex developed by Claude.
* ==============================================================================
if $run_part1 == 1 {
	* load FMIS data
	import delimited using "$data/Hannah sandbox/FMIS_title_quality_claude.csv", clear

	* extra screening step for "statewide" or "various locations" because it doesn't seem like the Claude regex script handled these super well 
	gen is_statewide = regexm(projecttitle, "STATEWIDE") 
	gen is_various_locations = regexm(projecttitle, "VARIOUS") 

	* useful indicator variables for project quality 
	gen has_title = !missing(projecttitle)
	gen endp_count = (endpoint_a_raw != "" & precision_a >= 2) + (endpoint_b_raw != "" & precision_b >= 2)
	replace endp_count = 0 if is_statewide == 1 | is_various_locations == 1
	gen has_2_endps = endp_count == 2
	gen has_1_endp = endp_count == 1

	* generate max and min precisions 
	gen max_precision = max(precision_a, precision_b)
	gen min_precision = .
	replace min_precision = min(precision_a, precision_b) if has_2_endps == 1

	preserve 
	keep if has_1_endp == 1
	tab max_precision, m
	restore
	preserve 
	keep if has_2_endps == 1
	tab max_precision, m
	tab min_precision, m
	restore


	* compute share (by cost) of projects by title quality 
	gen cost_has_title = (has_title == 1) * total_cost_bills_adjusted
	gen cost_has_2_endps = (has_2_endps == 1) * total_cost_bills_adjusted
	gen cost_has_1_endp = (has_1_endp == 1) * total_cost_bills_adjusted
	gen cost_has_endps = cost_has_2_endps + cost_has_1_endp

	* has 2 endpoints and precision 4-6 for both
	gen cost_2_endp_prec46x2 = (has_2_endps == 1 & min_precision >= 4) * total_cost_bills_adjusted
	* has 2 endpoints with one precision 4-6 and one precision 2-3
	gen cost_2_endp_prec46x1 = (has_2_endps == 1 & max_precision >= 4 & min_precision >= 2 & min_precision <= 3) * total_cost_bills_adjusted
	* has 1 endpoint and precision 4-6
	gen cost_1_endp_prec46 = (has_1_endp == 1 & max_precision >= 4) * total_cost_bills_adjusted
	* has 2 endpoints and precision 2-3 for both
	gen cost_2_endp_prec3x2 = (has_2_endps == 1 & min_precision >= 2 & max_precision <= 3) * total_cost_bills_adjusted
	* has 1 endpoint and precision 2-3
	gen cost_1_endp_prec3 = (has_1_endp == 1 & max_precision >= 2 & max_precision <= 3) * total_cost_bills_adjusted

	keep if year >= 1950 & year < 2025

	// * state-level totals 
	// * TODO: @HANNAH review 
	// tempfile fmis_state_match_bars
	// preserve
	// 	collapse (sum) total_cost_bills_adjusted cost_2_endp_prec46x2 cost_2_endp_prec46x1 cost_1_endp_prec46, by(state_fips)
	// 	drop if missing(state_fips)
	// 	replace state_fips = int(round(state_fips))
	// 	gen double maybe_match_cost = cost_2_endp_prec46x2
	// 	gen double hard_match_cost = cost_2_endp_prec46x2 + cost_2_endp_prec46x1 + cost_1_endp_prec46
	// 	gen double pct_maybe_match = 100 * maybe_match_cost / total_cost_bills_adjusted
	// 	gen double pct_hard_match = 100 * (hard_match_cost - maybe_match_cost) / total_cost_bills_adjusted
	// 	gen double pct_unlikely = 100 - pct_maybe_match - pct_hard_match
	// 	replace pct_maybe_match = 0 if total_cost_bills_adjusted == 0
	// 	replace pct_hard_match = 0 if total_cost_bills_adjusted == 0
	// 	replace pct_unlikely = 0 if total_cost_bills_adjusted == 0
	// 	capture label drop stfips_match_lbl
	// 	#delimit ;
	// 	label define stfips_match_lbl
	// 		1 "Alabama" 2 "Alaska" 4 "Arizona" 5 "Arkansas" 6 "California"
	// 		8 "Colorado" 9 "Connecticut" 10 "Delaware" 11 "District of Columbia"
	// 		12 "Florida" 13 "Georgia" 15 "Hawaii" 16 "Idaho" 17 "Illinois"
	// 		18 "Indiana" 19 "Iowa" 20 "Kansas" 21 "Kentucky" 22 "Louisiana"
	// 		23 "Maine" 24 "Maryland" 25 "Massachusetts" 26 "Michigan" 27 "Minnesota"
	// 		28 "Mississippi" 29 "Missouri" 30 "Montana" 31 "Nebraska" 32 "Nevada"
	// 		33 "New Hampshire" 34 "New Jersey" 35 "New Mexico" 36 "New York"
	// 		37 "North Carolina" 38 "North Dakota" 39 "Ohio" 40 "Oklahoma" 41 "Oregon"
	// 		42 "Pennsylvania" 44 "Rhode Island" 45 "South Carolina" 46 "South Dakota"
	// 		47 "Tennessee" 48 "Texas" 49 "Utah" 50 "Vermont" 51 "Virginia"
	// 		53 "Washington" 54 "West Virginia" 55 "Wisconsin" 56 "Wyoming"
	// 		69 "Northern Mariana Islands" 72 "Puerto Rico", replace ;
	// 	#delimit cr
	// 	label values state_fips stfips_match_lbl
	// 	decode state_fips, gen(state_name)
	// 	replace state_name = "FIPS " + string(state_fips) if missing(state_name) | state_name == ""
	// 	save `fmis_state_match_bars', replace
	// restore

	collapse (sum) total_cost_bills_adjusted cost_has_title cost_has_endps cost_has_2_endps cost_has_1_endp cost_2_endp_prec46x2 cost_2_endp_prec46x1 cost_1_endp_prec46 cost_2_endp_prec3x2 cost_1_endp_prec3, by(year)

	* compute shares
	gen share_has_title = cost_has_title / total_cost_bills_adjusted
	gen share_has_2_endps = cost_has_2_endps / total_cost_bills_adjusted
	gen share_has_1_endp = cost_has_1_endp / total_cost_bills_adjusted
	gen share_has_endps = cost_has_endps / total_cost_bills_adjusted
	gen share_2_endp_prec46x2 = cost_2_endp_prec46x2 / total_cost_bills_adjusted
	gen share_2_endp_prec46x1 = cost_2_endp_prec46x1 / total_cost_bills_adjusted
	gen share_1_endp_prec46 = cost_1_endp_prec46 / total_cost_bills_adjusted
	gen share_2_endp_prec3x2 = cost_2_endp_prec3x2 / total_cost_bills_adjusted
	gen share_1_endp_prec3 = cost_1_endp_prec3 / total_cost_bills_adjusted

	* plot comparison of interstate spending by project title quality 
	* plot costs 
	* compare endpoint counts 
	gen zero = 0

	graph twoway ///
		(rarea zero cost_has_2_endps year, lwidth(none)) ///
		(rarea cost_has_2_endps cost_has_endps year, lwidth(none)) ///
		(line total_cost_bills_adjusted year, lcolor(black) lwidth(medthin)), ///
		title("Interstate Spending by Endpoint Count", size(medium)) ///
		ytitle("Billions of 2025 USD") xtitle("Completion Year") ///
		yscale(titlegap(10)) ///
		xlabel(1950(10)2025) ///
		xmlabel(1950(5)2025, grid glcolor(gs14) glwidth(vthin) noticks nolabel) ///
		legend( ///
			order(3 2 1) ///
			label(1 "Projects with 2 Endpoints") ///
			label(2 "Projects with 1 Endpoint") ///
			label(3 "All Interstate Projects") ///
		) ///
		note( ///
			"Interstate projects are those with at least one receipt coded as interstate by the federal aid system code." ///
			"Endpoints with a precision of 0-1 are re-classified as not being an endpoint." ///
			`"Project titles containing "statewide" or "various" as keywords considered not to have endpoints."' ///
			, size(small) span ///
		)
	graph export "$out_dir_regex/interstate_title_endp_count.png", replace width(2500)

	* plot comparison of interstate spending by project title quality 
	* plot costs 
	* compare endpoint precision 
	* cumulative y-bounds for stacked areas (rarea avoids area ..., stack with overlaid line)
	gen epq_s0 = 0
	gen epq_s1 = epq_s0 + cost_2_endp_prec46x2
	gen epq_s2 = epq_s1 + cost_2_endp_prec46x1
	gen epq_s3 = epq_s2 + cost_1_endp_prec46
	gen epq_s4 = epq_s3 + cost_2_endp_prec3x2
	gen epq_s5 = epq_s4 + cost_1_endp_prec3

	graph twoway ///
		(rarea epq_s0 epq_s1 year, lwidth(none)) ///
		(rarea epq_s1 epq_s2 year, lwidth(none)) ///
		(rarea epq_s2 epq_s3 year, lwidth(none)) ///
		(rarea epq_s3 epq_s4 year, lwidth(none)) ///
		(rarea epq_s4 epq_s5 year, lwidth(none)) ///
		(line total_cost_bills_adjusted year, lcolor(black) lwidth(medthin)), ///
		title("Interstate Spending by Endpoint Precision", size(medium)) ///
		ytitle("Billions of 2025 USD") xtitle("Completion Year") ///
		yscale(titlegap(10)) ///
		xlabel(1950(10)2025) ///
		xmlabel(1950(5)2025, grid glcolor(gs14) glwidth(vthin) noticks nolabel) ///
		legend(order(6 5 4 3 2 1) ///
			label(1 "2 Endpoints," "Both Prec. 4-6") ///
			label(2 "2 Endpoints," "One Prec. 4-6," "One Prec. 2-3") ///
			label(3 "1 Endpoint," "Prec. 4-6") ///
			label(4 "2 Endpoints," "Both Prec. 2-3") ///
			label(5 "1 Endpoint," "Prec. 2-3") ///
			label(6 "All Interstate Projects")) ///
		note( ///
			"Interstate projects are those with at least one receipt coded as interstate by the federal aid system code." ///
			"Endpoints with a precision of 0-1 are re-classified as not being an endpoint." ///
			`"Project titles containing "statewide" or "various" as keywords considered not to have endpoints."' ///
			, size(small) span ///
		)
	graph export "$out_dir_regex/interstate_title_endp_quality.png", replace width(2500)

	* plot what can be matched 
	gen possible_match = cost_2_endp_prec46x2
	gen maybe_match = cost_2_endp_prec46x1 + cost_1_endp_prec46
	gen unlikely_match = cost_2_endp_prec3x2 + cost_1_endp_prec3
	gen impossible_match = total_cost_bills_adjusted - possible_match - maybe_match - unlikely_match
	gen match_b0 = 0
	gen match_s1 = possible_match
	gen match_s2 = match_s1 + maybe_match
	gen match_s3 = match_s2 + unlikely_match
	gen match_s4 = match_s3 + impossible_match

	graph twoway ///
		(rarea match_b0 match_s1 year, lwidth(none)) ///
		(rarea match_s1 match_s2 year, lwidth(none)) ///
		(rarea match_s2 match_s3 year, lwidth(none)) ///
		(rarea match_s3 match_s4 year, lwidth(none)) ///
		(line total_cost_bills_adjusted year, lcolor(black) lwidth(medthin)), ///
		title("Interstate Spending by Anticipated Match Feasibility", size(medium)) ///
		ytitle("Billions of 2025 USD") xtitle("Completion Year") ///
		yscale(titlegap(10)) ///
		xlabel(1950(10)2025) ///
		xmlabel(1950(5)2025, grid glcolor(gs14) glwidth(vthin) noticks nolabel) ///
		legend(order(5 4 3 2 1) ///
			label(1 "Possible" "(2 endpoints prec. 4-6)") ///
			label(2 "Maybe" "(max 1 endpoint prec. 4-6)") ///
			label(3 "Unlikely" "(max 1 endpoint prec. 2-3)") ///
			label(4 "Impossible" "(0 endpoints)") ///
			label(5 "All Interstate Projects") ///
		) ///
		note( ///
			"Interstate projects are those with at least one receipt coded as interstate by the federal aid system code." ///
			"Endpoints with a precision of 0-1 are re-classified as not being an endpoint." ///
			`"Project titles containing "statewide" or "various" as keywords considered not to have endpoints."' ///
			, size(small) span ///
		) ///
		graphregion(margin(l=15 r=15))
	graph export "$out_dir_regex/interstate_title_match_quality.png", replace width(2500)

	* plot comparison of interstate spending by title existence
	* plot share 
	graph twoway ///
		(line share_has_title year), ///
		title("Share of Annual Interstate Project Costs with Non-Missing Titles") ///
		ytitle("Share of Annual Costs") xtitle("Completion Year") ///
		yscale(titlegap(10)) ///
		xlabel(1950(10)2025) ///
		xmlabel(1950(5)2025, grid glcolor(gs14) glwidth(vthin) noticks nolabel) ///
		graphregion(margin(l=15 r=15))
	graph export "$out_dir_regex/interstate_share_title_by_cost.png", replace width(2500)

	* same graph but zoomed in to 1955-1965 
	preserve
	keep if year >= 1950 & year <= 1965
	graph twoway line share_has_title year, ///
		title("Share of Annual Interstate Project Costs with Non-Missing Titles") ///
		subtitle("1950-1965") ///
		ytitle("Share of Annual Costs") xtitle("Completion Year") ///
		yscale(titlegap(10)) ///
		xlabel(1950(1)1965)
	graph export "$out_dir_regex/interstate_share_title_by_cost_55_65.png", replace width(2500)
	restore

	* plot comparison of interstate spending by project title quality 
	* plot share 
	* compare endpoint count 
	* stacked rarea: 2-endpoint share + 1-endpoint share = share_has_endps
	gen zero = 0

	graph twoway ///
		(rarea zero share_has_2_endps year, lwidth(none)) ///
		(rarea share_has_2_endps share_has_endps year, lwidth(none)) ///
		(line share_has_title year, lwidth(medthin) lcolor(black)), ///
		title("Share of Annual Interstate Project Costs by Endpoint Count") ///
		ytitle("Share of Annual Costs") xtitle("Completion Year") ///
		yscale(titlegap(10)) ///
		xlabel(1950(10)2025) ///
		xmlabel(1950(5)2025, grid glcolor(gs14) glwidth(vthin) noticks nolabel) ///
		legend( ///
			order(3 2 1) ///
			label(1 "Projects with 2 Endpoints") ///
			label(2 "Projects with 1 Endpoint") ///
			label(3 "Projects with Titles") ///
		) ///
		note( ///
			"Interstate projects are those with at least one receipt coded as interstate by the federal aid system code." ///
			"Endpoints with a precision of 0-1 are re-classified as not being an endpoint." ///
			`"Project titles containing "statewide" or "various" as keywords considered not to have endpoints."' ///
			, size(small) span ///
		) ///
		graphregion(margin(l=15 r=15))
	graph export "$out_dir_regex/interstate_share_title_endp_count.png", replace width(2500)

	* plot comparison of interstate spending by project title quality 
	* plot share 
	* compare endpoint precision 
	* cumulative shares for stacked rarea (five precision buckets; sum may be < 1)
	gen sh_prec0 = 0
	gen sh_prec1 = sh_prec0 + share_2_endp_prec46x2
	gen sh_prec2 = sh_prec1 + share_2_endp_prec46x1
	gen sh_prec3 = sh_prec2 + share_1_endp_prec46
	gen sh_prec4 = sh_prec3 + share_2_endp_prec3x2
	gen sh_prec5 = sh_prec4 + share_1_endp_prec3

	graph twoway ///
		(rarea sh_prec0 sh_prec1 year, lwidth(none)) ///
		(rarea sh_prec1 sh_prec2 year, lwidth(none)) ///
		(rarea sh_prec2 sh_prec3 year, lwidth(none)) ///
		(rarea sh_prec3 sh_prec4 year, lwidth(none)) ///
		(rarea sh_prec4 sh_prec5 year, lwidth(none)) ///
		(line share_has_title year, lwidth(medthin) lcolor(black)), ///
		title("Share of Annual Interstate Project Costs by Endpoint Precision") ///
		ytitle("Share of Annual Costs") xtitle("Completion Year") ///
		yscale(titlegap(10)) ///
		xlabel(1950(10)2025) ///
		xmlabel(1950(5)2025, grid glcolor(gs14) glwidth(vthin) noticks nolabel) ///
		legend( ///
			order(6 5 4 3 2 1) ///
			label(1 "2 Endpoints," "Both Prec. 4-6") ///
			label(2 "2 Endpoints," "One Prec. 4-6," "One Prec. 2-3") ///
			label(3 "1 Endpoint," "Prec. 4-6") ///
			label(4 "2 Endpoints," "Both Prec. 2-3") ///
			label(5 "1 Endpoint," "Prec. 2-3") ///
			label(6 "Projects with Titles") ///
		) ///
		note( ///
			"Interstate projects are those with at least one receipt coded as interstate by the federal aid system code." ///
			"Endpoints with a precision of 0-1 are re-classified as not being an endpoint." ///
			`"Project titles containing "statewide" or "various" as keywords considered not to have endpoints."' ///
			, size(small) span ///
		) ///
		graphregion(margin(l=15 r=15))
	graph export "$out_dir_regex/interstate_share_title_endp_precision.png", replace width(2500)

	* same match-quality breakdown as interstate_title_match_quality.png, but as shares of annual cost
	gen share_possible_match = share_2_endp_prec46x2
	gen share_maybe_match = share_2_endp_prec46x1 + share_1_endp_prec46
	gen share_unlikely_match = share_2_endp_prec3x2 + share_1_endp_prec3
	gen share_impossible_match = 1 - share_possible_match - share_maybe_match - share_unlikely_match
	gen share_full = 1
	gen share_match_s1 = share_possible_match
	gen share_match_s2 = share_match_s1 + share_maybe_match
	gen share_match_s3 = share_match_s2 + share_unlikely_match
	gen share_match_s4 = share_match_s3 + share_impossible_match

	graph twoway ///
		(rarea match_b0 share_match_s1 year, lwidth(none)) ///
		(rarea share_match_s1 share_match_s2 year, lwidth(none)) ///
		(rarea share_match_s2 share_match_s3 year, lwidth(none)) ///
		(rarea share_match_s3 share_match_s4 year, lwidth(none)) ///
		(line share_has_title year, lcolor(black) lwidth(medthin)), ///
		title("Share of Annual Interstate Project Costs by Anticipated Match Feasibility", size(medium)) ///
		ytitle("Share of Annual Costs") xtitle("Completion Year") ///
		yscale(titlegap(10)) ///
		xlabel(1950(10)2025) ///
		xmlabel(1950(5)2025, grid glcolor(gs14) glwidth(vthin) noticks nolabel) ///
		legend(order(5 4 3 2 1) ///
			label(1 "Possible" "(2 endpoints prec. 4-6)") ///
			label(2 "Maybe" "(max 1 endpoint prec. 4-6)") ///
			label(3 "Unlikely" "(max 1 endpoint prec. 2-3)") ///
			label(4 "Impossible" "(0 endpoints)") ///
			label(5 "Projects with Titles") ///
		) ///
		note( ///
			"Interstate projects are those with at least one receipt coded as interstate by the federal aid system code." ///
			"Endpoints with a precision of 0-1 are re-classified as not being an endpoint." ///
			`"Project titles containing "statewide" or "various" as keywords considered not to have endpoints."' ///
			, size(small) span ///
		) ///
		graphregion(margin(l=15 r=15))
	graph export "$out_dir_regex/interstate_share_title_match_quality.png", replace width(2500)

	// * ------------------------------------------------------------------------------
	// * horizontal stacked bars by state (match buckets as % of state interstate cost)
	// * ------------------------------------------------------------------------------
	// * TODO: review 
	// use `fmis_state_match_bars', clear

	// graph hbar pct_maybe_match pct_hard_match pct_unlikely, ///
	// 	over(state_name, sort(total_cost_bills_adjusted) descending label(labsize(*0.42))) ///
	// 	stack ///
	// 	yscale(reverse) ///
	// 	title("Interstate Cost by Title / Endpoint Match Quality, by State", size(medium)) ///
	// 	xtitle("Percent of state interstate cost") ///
	// 	xlabel(0(20)100, nogrid) ///
	// 	legend( ///
	// 		pos(12) cols(3) ///
	// 		label(1 "Maybe match") label(2 "Hard match") label(3 "Unlikely") ///
	// 		region(lcolor(white)) ///
	// 	) ///
	// 	bar(1, fcolor(teal) lcolor(gs8) lwidth(vthin)) ///
	// 	bar(2, fcolor(maroon) lcolor(gs8) lwidth(vthin)) ///
	// 	bar(3, fcolor(gs14) lcolor(gs8) lwidth(vthin)) ///
	// 	blabel(bar, format(%9.0f) size(tiny) color(white) pos(center)) ///
	// 	note( ///
	// 		"Maybe match: 2 endpoints, both precision >= 4. Hard match: add'l 2 ep (one >=4) or 1 ep >=4." ///
	// 		" Unlikely: remaining cost. Interstate = federal aid system code.", ///
	// 		size(vsmall) span ///
	// 	) ///
	// 	graphregion(color(white) margin(r=15)) plotregion(margin(zero))
	// graph export "$out_dir_regex/interstate_match_quality_by_state_hbar.png", replace width(1400) height(3200)
}

* ==============================================================================
* PART 2
* Analysis of semantic title parsing with rich location extraction using Gemini.
* Sample of 1000 projects funded by Interstate Construction and containing at least one reimbursement for new construction. Randomly sampled with stratification by state, binary indicator for pre/post 1970 construction authorization, and binary indicator for below/above median inflation-adjusted cost.

* NOTE: anchors are already sorted by largest to smallest precision, hence any time we want to pick the most precise anchor, we can just use the first one.
* ==============================================================================
if $run_part2 == 1 {
    * specify which sample/run to use
    import delimited "$gemini_dir/fmis_interstate_parsed_titles_new_constr_v3_20260522_165917.csv", clear

	* merge back with cost data 
	rename recipient_id recipientid
	merge 1:1 recipientid federal_project_number using "$geocoding_dir/FMIS_interstate_project_titles.dta", keepusing(total_cost_bills_adjusted) nogen keep(match)
	* merge back with dates data 
	merge 1:1 recipientid federal_project_number using "$intermediate_data/project_level_FMIS_lite.dta", keepusing(completion_year completedate authconstdate) nogen keep(match)

	* filter time range
	keep if completion_year >= 1950 & completion_year <= 2000

	keep if ep_a_ref0_anchor_type == "other_landmark"
	exit 

	* convert data types 
	gen byte is_statewide = (statewide == "True")
	gen byte is_various = (various_locs_unspecified == "True")
	gen byte is_multi_locs_specified = (multi_locs_specified == "True")
	drop statewide various_locs_unspecified multi_locs_specified


	* construct offset precision groups 
	replace ep_a_ref0_precision = 3 if ep_a_ref0_precision == 4 & ep_a_ref0_rel_type == "offset"
	replace ep_a_ref0_precision = 2 if ep_a_ref0_precision == 1 & ep_a_ref0_rel_type == "offset"
	replace ep_b_ref0_precision = 3 if ep_b_ref0_precision == 4 & ep_b_ref0_rel_type == "offset"
	replace ep_b_ref0_precision = 2 if ep_b_ref0_precision == 1 & ep_b_ref0_rel_type == "offset"

	* label precision categories  
	label define precision_lbl ///
		6 "6 Mile markers" ///
		5 "5 Exit number" ///
		4 "4 Intersections" ///
		3 "3 Offset from Intersection" ///
		2 "2 Offset from Named Place" ///
		1 "1 Named city/town/region"
	foreach v of varlist ///
		ep_a_ref0_precision ep_a_ref1_precision ep_a_ref2_precision ///
		ep_b_ref0_precision ep_b_ref1_precision ep_b_ref2_precision {
		label values `v' precision_lbl
	}

	* get some tabs on how many endpoints have offsets 
	gen ep_a_ref0_offset =(ep_a_ref0_rel_type == "offset")
	gen ep_a_ref1_offset =(ep_a_ref1_rel_type == "offset")
	gen ep_a_ref2_offset =(ep_a_ref2_rel_type == "offset")
	gen ep_b_ref0_offset =(ep_b_ref0_rel_type == "offset")
	gen ep_b_ref1_offset =(ep_b_ref1_rel_type == "offset")
	// gen ep_b_ref2_offset =(ep_b_ref2_rel_type == "offset") // all missing 

	label variable ep_a_ref0_precision "Endpt A, 1st Anchor Precision"
	label variable ep_a_ref0_rel_type "Endpt A, 1st Anchor Offset Type"
	label variable ep_b_ref0_precision "Endpt B, 1st Anchor Precision"
	label variable ep_b_ref0_rel_type "Endpt B, 1st Anchor Offset Type"

	* cross-tab of anchor types by relation type to check frequency of offsets 
	tab ep_a_ref0_precision ep_a_ref0_rel_type, mi 
	tab ep_b_ref0_precision ep_b_ref0_rel_type, mi 
	tab ep_a_ref0_precision ep_b_ref0_precision, mi 

	* cross-tab of precisions by endpoint pairs 
	tab ep_a_ref0_precision ep_b_ref0_precision, cell nofreq mi
	tab ep_a_ref0_precision ep_b_ref0_precision [aw = total_cost_bills_adjusted], mi // counts, weighted by cost
	tab ep_a_ref0_precision ep_b_ref0_precision [aw = total_cost_bills_adjusted], cell nofreq mi // pcts, weighted by cost

	* check if there are any cases with multiple counties or multiple cities (both per endpoint and across two endpoints)
	// compute number of cities and counties per endpoint and extract city/county names 
	// TODO: review below 
	// foreach ep in a b {
	// 	gen ep_`ep'_n_cities = (ep_`ep'_ref0_anchor_type == "city") + ///
	// 		(ep_`ep'_ref1_anchor_type == "city") + (ep_`ep'_ref2_anchor_type == "city")
	// 	gen ep_`ep'_n_counties = (ep_`ep'_ref0_anchor_type == "county") + ///
	// 		(ep_`ep'_ref1_anchor_type == "county") + (ep_`ep'_ref2_anchor_type == "county")
	// 	gen ep_`ep'_city1 = ep_`ep'_ref0_feature_name if ep_`ep'_ref0_anchor_type == "city"
	// 	replace ep_`ep'_city1 = ep_`ep'_ref1_feature_name if ep_`ep'_city1 == "" & ep_`ep'_ref1_anchor_type == "city"
	// 	replace ep_`ep'_city1 = ep_`ep'_ref2_feature_name if ep_`ep'_city1 == "" & ep_`ep'_ref2_anchor_type == "city"
	// 	gen ep_`ep'_county1 = ep_`ep'_ref0_feature_name if ep_`ep'_ref0_anchor_type == "county"
	// 	replace ep_`ep'_county1 = ep_`ep'_ref1_feature_name if ep_`ep'_county1 == "" & ep_`ep'_ref1_anchor_type == "county"
	// 	replace ep_`ep'_county1 = ep_`ep'_ref2_feature_name if ep_`ep'_county1 == "" & ep_`ep'_ref2_anchor_type == "county"
	// }

	// gen byte mult_cities_per_ep = ep_a_n_cities > 1 | ep_b_n_cities > 1
	// gen byte mult_counties_per_ep = ep_a_n_counties > 1 | ep_b_n_counties > 1
	// gen byte mult_cities_across = ep_a_city1 != "" & ep_b_city1 != "" & ep_a_city1 != ep_b_city1
	// gen byte mult_counties_across = ep_a_county1 != "" & ep_b_county1 != "" & ep_a_county1 != ep_b_county1
	// gen byte mult_cities = mult_cities_per_ep | mult_cities_across
	// gen byte mult_counties = mult_counties_per_ep | mult_counties_across

	// foreach ep in a b {
	// 	display _newline "Endpoint `=upper("`ep'")': city anchor count (ref0-ref2)"
	// 	tab ep_`ep'_n_cities if ep_`ep'_n_cities > 0
	// 	display _newline "Endpoint `=upper("`ep'")': county anchor count (ref0-ref2)"
	// 	tab ep_`ep'_n_counties if ep_`ep'_n_counties > 0
	// }

	// display _newline "Multiple city anchors"
	// count if mult_cities_per_ep
	// display "  Per endpoint (A or B has >1 city anchor): " r(N)
	// count if mult_cities_across
	// display "  Across endpoints (different city on A vs B): " r(N)
	// count if mult_cities
	// display "  Either: " r(N)

	// display _newline "Multiple county anchors"
	// count if mult_counties_per_ep
	// display "  Per endpoint (A or B has >1 county anchor): " r(N)
	// count if mult_counties_across
	// display "  Across endpoints (different county on A vs B): " r(N)
	// count if mult_counties
	// display "  Either: " r(N)

	// list recipientid federal_project_number ep_a_n_cities ep_a_city1 ep_b_n_cities ep_b_city1 ///
	// 	ep_a_ref0_anchor_type ep_a_ref0_feature_name ep_a_ref1_anchor_type ep_a_ref1_feature_name ///
	// 	ep_a_ref2_anchor_type ep_a_ref2_feature_name ///
	// 	ep_b_ref0_anchor_type ep_b_ref0_feature_name ep_b_ref1_anchor_type ep_b_ref1_feature_name ///
	// 	ep_b_ref2_anchor_type ep_b_ref2_feature_name ///
	// 	if mult_cities, abbrev(24) sep(0)

	// list recipientid federal_project_number ep_a_n_counties ep_a_county1 ep_b_n_counties ep_b_county1 ///
	// 	ep_a_ref0_anchor_type ep_a_ref0_feature_name ep_a_ref1_anchor_type ep_a_ref1_feature_name ///
	// 	ep_a_ref2_anchor_type ep_a_ref2_feature_name ///
	// 	ep_b_ref0_anchor_type ep_b_ref0_feature_name ep_b_ref1_anchor_type ep_b_ref1_feature_name ///
	// 	ep_b_ref2_anchor_type ep_b_ref2_feature_name ///
	// 	if mult_counties, abbrev(24) sep(0)

	// drop ep_a_n_cities ep_b_n_cities ep_a_n_counties ep_b_n_counties ///
	// 	ep_a_city1 ep_b_city1 ep_a_county1 ep_b_county1 ///
	// 	mult_cities_per_ep mult_counties_per_ep mult_cities_across mult_counties_across ///
	// 	mult_cities mult_counties

	* get the highest precision for each endpoint 
	* (TODO: remove this section later since we are adding it to the title parsing pipeline in step 02)
	// gen ep_a_max_precision = ep_a_ref0_precision
	// gen ep_b_max_precision = ep_b_ref0_precision
	// label values ep_a_max_precision ep_b_max_precision precision_lbl

	
	* compute number of endpoints 
	gen endp_count = (ep_a_n_refs > 0 & !mi(ep_a_n_refs)) + (ep_b_n_refs > 0 & !mi(ep_b_n_refs))
	replace endp_count = 0 if is_statewide == 1 | is_various == 1 | is_multi_locs_specified == 1
	gen has_2_endps = endp_count == 2
	gen has_1_endp = endp_count == 1

	* compute max and min precision
	// missing values are automatically handled by max and min functions
	gen max_precision = max(ep_a_ref0_precision, ep_b_ref0_precision)
	gen min_precision = .
	replace min_precision = min(ep_a_ref0_precision, ep_b_ref0_precision) if has_2_endps
	label values max_precision min_precision precision_lbl

	* compute costs associated with endpoint/precision groups 
	gen cost_has_2_endps = (has_2_endps == 1) * total_cost_bills_adjusted
	gen cost_has_1_endp = (has_1_endp == 1) * total_cost_bills_adjusted
	gen cost_has_endps = cost_has_2_endps + cost_has_1_endp

	gen cost_2_endp_prec36x2 = (has_2_endps == 1 & min_precision >= 3) * total_cost_bills_adjusted
	// in graphs, combine the cases with 1 endpoint precision 4-6
	gen cost_2_endp_prec36x1 = (has_2_endps == 1 & max_precision >= 3 & min_precision < 3) * total_cost_bills_adjusted
	gen cost_1_endp_prec36 = (has_1_endp == 1 & max_precision >= 3) * total_cost_bills_adjusted

	gen cost_2_endp_prec12x2 = (has_2_endps == 1 & max_precision <= 2) * total_cost_bills_adjusted
	gen cost_1_endp_prec12 = (has_1_endp == 1 & max_precision <= 2) * total_cost_bills_adjusted

    * ==========================================================================
	* Figures 
    * ==========================================================================
	local n_obs = _N
	local fnote_sample1 `"Sample of `n_obs' FMIS projects with at least one reimbursement funded by the Interstate Construction program and"'
	local fnote_sample2 `"at least one new-construction reimbursement."'
	local fnote_strata `"Sample is stratified by state, pre/post-1970 construction authorization, and below/above median inflation-adjusted cost."'
	local fnote_gemini `"Location information extracted by Gemini."'
	local fnote_statewide_multi `"Titles that Gemini flagged as statewide or having multiple sites are classified as having 0 endpoints for now."'

	*** plot bar chart of anchor types by cost ***
	replace ep_a_ref0_anchor_type = "(missing)" if ep_a_ref0_anchor_type == ""
	replace ep_b_ref0_anchor_type = "(missing)" if ep_b_ref0_anchor_type == ""

	preserve 
	// by endpoint A
	// keep if completion_year >= 1950 & completion_year <= 2000
	collapse (sum) anchor_cost = total_cost_bills_adjusted, by(ep_a_ref0_anchor_type)
	gsort -anchor_cost
	graph hbar anchor_cost, over(ep_a_ref0_anchor_type, sort(anchor_cost) descending label(labsize(small))) ///
		title("Distribution of Spending by Highest Precision Anchor Type (Endpoint A), 1950-2000", size(medium)) ///
		subtitle("Gemini 1k New-Construction Sample", size(small)) ///
		ytitle("Billions of 2025 USD") ///
		note( ///
			`"`fnote_sample1'"' ///
			`"`fnote_sample2'"' ///
			`"`fnote_strata'"' ///
			`"`fnote_gemini'"' ///
			`"`fnote_statewide_multi'"' ///
			, size(small) span ///
		) ///
		graphregion(margin(l=15 r=15))
	graph export "$out_dir_gemini/cost_by_anchor_epA_1k_IC_new_constr.png", replace width(2500)
	restore 
	preserve 
	// by endpoint B
	// keep if completion_year >= 1950 & completion_year <= 2000
	collapse (sum) anchor_cost = total_cost_bills_adjusted, by(ep_b_ref0_anchor_type)
	gsort -anchor_cost
	graph hbar anchor_cost, over(ep_b_ref0_anchor_type, sort(anchor_cost) descending label(labsize(small))) ///
		title("Distribution of Spending by Highest Precision Anchor Type (Endpoint B), 1950-2000", size(medium)) ///
		subtitle("Gemini 1k New-Construction Sample", size(small)) ///
		ytitle("Billions of 2025 USD") ///
		note( ///
			`"`fnote_sample1'"' ///
			`"`fnote_sample2'"' ///
			`"`fnote_strata'"' ///
			`"`fnote_gemini'"' ///
			`"`fnote_statewide_multi'"' ///
			, size(small) span ///
		) ///
		graphregion(margin(l=15 r=15))
	graph export "$out_dir_gemini/cost_by_anchor_epB_1k_IC_new_constr.png", replace width(2500)
	restore 

	*** plot spending over time by number of endpoints ***
	preserve 
		// keep if completion_year >= 1950 & completion_year <= 2000

		collapse (sum) total_cost_bills_adjusted cost_has_2_endps cost_has_1_endp cost_has_endps cost_2_endp_prec36x2 cost_2_endp_prec36x1 cost_1_endp_prec36 cost_2_endp_prec12x2 cost_1_endp_prec12, by(completion_year)

		gen share_has_2_endps = cost_has_2_endps / total_cost_bills_adjusted
		gen share_has_1_endp = cost_has_1_endp / total_cost_bills_adjusted
		gen share_has_endps = cost_has_endps / total_cost_bills_adjusted
		gen share_2_endp_prec36x2 = cost_2_endp_prec36x2 / total_cost_bills_adjusted
		gen share_2_endp_prec36x1 = cost_2_endp_prec36x1 / total_cost_bills_adjusted
		gen share_1_endp_prec36 = cost_1_endp_prec36 / total_cost_bills_adjusted
		gen share_2_endp_prec12x2 = cost_2_endp_prec12x2 / total_cost_bills_adjusted
		gen share_1_endp_prec12 = cost_1_endp_prec12 / total_cost_bills_adjusted

		gen zero = 0

		graph twoway ///
			(rarea zero cost_has_2_endps completion_year, lwidth(none)) ///
			(rarea cost_has_2_endps cost_has_endps completion_year, lwidth(none)) ///
			(line total_cost_bills_adjusted completion_year, lcolor(black) lwidth(medthin)), ///
			title("Interstate Spending by Endpoint Count, 1950-2000", size(medium)) ///
			subtitle("Gemini 1k New-Construction Sample", size(small)) ///
			ytitle("Billions of 2025 USD") xtitle("Completion Year") ///
			yscale(titlegap(10)) ///
			xlabel(1950(10)2000) ///
			legend( ///
				order(3 2 1) ///
				label(1 "Projects with 2 Endpoints") ///
				label(2 "Projects with 1 Endpoint") ///
				label(3 "All Projects in Sample") ///
			) ///
			note( ///
				`"`fnote_sample1'"' ///
				`"`fnote_sample2'"' ///
				`"`fnote_strata'"' ///
				`"`fnote_gemini'"' ///
				`"`fnote_statewide_multi'"' ///
				, size(small) span ///
			)
		graph export "$out_dir_gemini/ep_count_1k_IC_new_constr.png", replace width(2500)

	    * plot SHARE of spending over time by number of endpoints
		graph twoway ///
			(rarea zero share_has_2_endps completion_year, lwidth(none)) ///
			(rarea share_has_2_endps share_has_endps completion_year, lwidth(none)) ///
			, /// 
			title("Share of Interstate Spending by Endpoint Count, 1950-2000", size(medium)) ///
			subtitle("Gemini 1k New-Construction Sample", size(small)) ///
			ytitle("Share of Annual Costs") xtitle("Completion Year") ///
			yscale(titlegap(10)) ///
			xlabel(1950(10)2000) ///
			legend( ///
				order(3 2 1) ///
				label(1 "Projects with 2 Endpoints") ///
				label(2 "Projects with 1 Endpoint") ///
			) ///
			note( ///
				`"`fnote_sample1'"' ///
				`"`fnote_sample2'"' ///
				`"`fnote_strata'"' ///
				`"`fnote_gemini'"' ///
				`"`fnote_statewide_multi'"' ///
				, size(small) span ///
			) ///
			graphregion(margin(l=15 r=15))
		graph export "$out_dir_gemini/ep_count_share_1k_IC_new_constr.png", replace width(2500)


	* plot spending over time by endpoint precision
		// keep if completion_year >= 1950 & completion_year <= 2000
		// version with raw spending 
		// construct cumulative spending by endpoint precision groups 
		gen epq_s0 = 0
		gen epq_s1 = epq_s0 + cost_2_endp_prec36x2
		gen epq_s2 = epq_s1 + cost_2_endp_prec36x1
		gen epq_s3 = epq_s2 + cost_1_endp_prec36
		gen epq_s4 = epq_s3 + cost_2_endp_prec12x2
		gen epq_s5 = epq_s4 + cost_1_endp_prec12

		graph twoway ///
			(rarea epq_s0 epq_s1 completion_year, lwidth(none)) ///
			(rarea epq_s1 epq_s2 completion_year, lwidth(none)) ///
			(rarea epq_s2 epq_s3 completion_year, lwidth(none)) ///
			(rarea epq_s3 epq_s4 completion_year, lwidth(none)) ///
			(rarea epq_s4 epq_s5 completion_year, lwidth(none)) ///
			(line total_cost_bills_adjusted completion_year, lcolor(black) lwidth(medthin)), ///
			title("Interstate Spending by Endpoint Precision, 1950-2000", size(medium)) ///
			subtitle("Gemini 1k New-Construction Sample", size(small)) ///
			ytitle("Billions of 2025 USD") xtitle("Completion Year") ///
			yscale(titlegap(10)) ///
			xlabel(1950(10)2000) ///
			legend(order(6 5 4 3 2 1) ///
				label(1 "2 Endpoints," "Both Prec. 3-6") ///
				label(2 "2 Endpoints," "One Prec. 3-6," "One Prec. 1-2") ///
				label(3 "1 Endpoint," "Prec. 3-6") ///
				label(4 "2 Endpoints," "Both Prec. 1-2") ///
				label(5 "1 Endpoint," "Prec. 1-2") ///
				label(6 "All Sample Projects")) ///
			note( ///
				`"`fnote_sample1'"' ///
				`"`fnote_sample2'"' ///
				`"`fnote_strata'"' ///
				`"`fnote_gemini'"' ///
				`"`fnote_statewide_multi'"' ///
				, size(small) span ///
			)
		graph export "$out_dir_gemini/ep_precision_1k_IC_new_constr.png", replace width(2500)
		
		// version with share of spending 
		// construct cumulative share of spending by endpoint precision groups 
		gen sh_prec0 = 0
		gen sh_prec1 = sh_prec0 + share_2_endp_prec36x2
		gen sh_prec2 = sh_prec1 + share_2_endp_prec36x1
		gen sh_prec3 = sh_prec2 + share_1_endp_prec36 
		gen sh_prec4 = sh_prec3 + share_2_endp_prec12x2
		gen sh_prec5 = sh_prec4 + share_1_endp_prec12

		graph twoway ///
			(rarea sh_prec0 sh_prec1 completion_year, lwidth(none)) ///
			(rarea sh_prec1 sh_prec2 completion_year, lwidth(none)) ///
			(rarea sh_prec2 sh_prec3 completion_year, lwidth(none)) ///
			(rarea sh_prec3 sh_prec4 completion_year, lwidth(none)) ///
			(rarea sh_prec4 sh_prec5 completion_year, lwidth(none)) ///
			, /// 
			title("Share of Interstate Spending by Endpoint Precision, 1950-2000", size(medium)) ///
			subtitle("Gemini 1k New-Construction Sample", size(small)) ///
			ytitle("Share of Annual Costs") xtitle("Completion Year") ///
			yscale(titlegap(10)) ///
			xlabel(1950(10)2000) ///
			legend( ///
				order(6 5 4 3 2 1) ///
				label(1 "2 Endpoints," "Both Prec. 3-6") ///
				label(2 "2 Endpoints," "One Prec. 3-6," "One Prec. 1-2") ///
				label(3 "1 Endpoint," "Prec. 3-6") ///
				label(4 "2 Endpoints," "Both Prec. 1-2") ///
				label(5 "1 Endpoint," "Prec. 1-2") ///
			) ///
			note( ///
				`"`fnote_sample1'"' ///
				`"`fnote_sample2'"' ///
				`"`fnote_strata'"' ///
				`"`fnote_gemini'"' ///
				`"`fnote_statewide_multi'"' ///
				, size(small) span ///
			) ///
			graphregion(margin(l=15 r=15))
		graph export "$out_dir_gemini/ep_precision_share_1k_IC_new_constr.png", replace width(2500)
	restore
	

	* plot heatmap of ep A precision X ep B precision (including missing values)
	preserve
	// keep if completion_year >= 1950 & completion_year <= 2000
	replace ep_a_ref0_precision = 0 if missing(ep_a_ref0_precision)
	replace ep_b_ref0_precision = 0 if missing(ep_b_ref0_precision)
	collapse (sum) cell_cost = total_cost_bills_adjusted, by(ep_a_ref0_precision ep_b_ref0_precision)
	tempfile precision_cells
	save `precision_cells'

	* construct full 7x7 grid and merge back with precision cells so that we have a full grid including zero cell values 
	clear
	set obs 49
	gen ep_a_ref0_precision = ceil(_n/7) - 1
	gen ep_b_ref0_precision = mod(_n-1, 7)
	merge 1:1 ep_a_ref0_precision ep_b_ref0_precision using `precision_cells', nogen
	replace cell_cost = 0 if missing(cell_cost)
	label copy precision_lbl prec_heat_lbl, replace
	label define prec_heat_lbl 0 "0 (Missing/Unknown)", modify
	label values ep_a_ref0_precision ep_b_ref0_precision prec_heat_lbl

	// // get axis labels from the precision value labels 
	// forvalues p = 0/6 {
	// 	local lbl : label prec_heat_lbl `p'
	// 	local xlabels `"`xlabels' `p' "`lbl'""'
	// 	local ylabels `"`ylabels' `p' "`lbl'""'
	// }

	// version with raw spending 
	heatplot cell_cost ep_a_ref0_precision ep_b_ref0_precision, ///
		discrete ///
		values(format(%9.2f) color(red)) ///
		xtitle("Endpoint B Precision") ///
		ytitle("Endpoint A Precision") ///
		xlabel(0(1)6, angle(45) labsize(small)) ///
		ylabel(0(1)6, labsize(small)) ///
		xscale(range(-0.5 6.5)) ///
		yscale(range(-0.5 6.5)) ///
		title("Interstate Spending by Endpoint Precision Pair, 1950-2000 (Billions of 2025 USD)", size(medium)) ///
		subtitle("Gemini 1k New-Construction Sample", size(small)) ///
		legend(off) ///
		aspectratio(1) ///
		note( ///
			`"`fnote_sample1'"' ///
			`"`fnote_sample2'"' ///
			`"`fnote_strata'"' ///
			`"`fnote_gemini'"' ///
			`"`fnote_statewide_multi'"' ///
			, size(small) span ///
		)
	graph export "$out_dir_gemini/precision_heatmap_1k_IC_new_constr.png", replace width(2500)

	// version with pct share of spending 
	egen total_cost = total(cell_cost)
	gen cell_pct = 100 * cell_cost / total_cost

	heatplot cell_pct ep_a_ref0_precision ep_b_ref0_precision, ///
		discrete ///
		values(format(%9.1f) color(red)) ///
		xtitle("Endpoint B Precision") ///
		ytitle("Endpoint A Precision") ///
		xlabel(0(1)6, angle(45) labsize(small)) ///
		ylabel(0(1)6, labsize(small)) ///
		xscale(range(-0.5 6.5)) ///
		yscale(range(-0.5 6.5)) ///
		title("Interstate Spending by Endpoint Precision Pair, 1950-2000 (Cost-Weighted Percentages)", size(medium)) ///
		subtitle("Gemini 1k New-Construction Sample", size(small)) ///
		legend(off) ///
		aspectratio(1) ///
		note( ///
			`"`fnote_sample1'"' ///
			`"`fnote_sample2'"' ///
			`"`fnote_strata'"' ///
			`"`fnote_gemini'"' ///
			`"`fnote_statewide_multi'"' ///
			, size(small) span ///
		)
	graph export "$out_dir_gemini/precision_heatmap_share_1k_IC_new_constr.png", replace width(2500)
	restore

}

* ==============================================================================
* PART 3
* Analysis of semantic title parsing with rich location extraction using Gemini.
* All projects funded by Interstate Construction and containing at least one reimbursement for new construction.
* (Same as part 2 but for full set of projects.)
* ==============================================================================

if $run_part3 == 1 {
* PLACEHOLDER

}