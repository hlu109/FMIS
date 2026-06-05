/*==============================================================================
 	FMIS data processing 
    This script evaluates FMIS project titles for the quality of location descriptions after an intermediate text parsing step using an LLM. 
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
global out_dir "$output/FMIS_title_quality"
if !direxists("$out_dir") mkdir "$out_dir"


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
gen endcnt_b0 = 0

graph twoway ///
    (rarea endcnt_b0 cost_has_2_endps year, lwidth(none)) ///
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
graph export "$out_dir/interstate_title_endp_count.png", replace width(2500)

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
graph export "$out_dir/interstate_title_endp_quality.png", replace width(2500)

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
graph export "$out_dir/interstate_title_match_quality.png", replace width(2500)

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
graph export "$out_dir/interstate_share_title_by_cost.png", replace width(2500)

* same graph but zoomed in to 1955-1965 
preserve
keep if year >= 1950 & year <= 1965
graph twoway line share_has_title year, ///
    title("Share of Annual Interstate Project Costs with Non-Missing Titles") ///
	subtitle("1950-1965") ///
	ytitle("Share of Annual Costs") xtitle("Completion Year") ///
	yscale(titlegap(10)) ///
	xlabel(1950(1)1965)
graph export "$out_dir/interstate_share_title_by_cost_55_65.png", replace width(2500)
restore

* plot comparison of interstate spending by project title quality 
* plot share 
* compare endpoint count 
* stacked rarea: 2-endpoint share + 1-endpoint share = share_has_endps
gen sh_end0 = 0

graph twoway ///
    (rarea sh_end0 share_has_2_endps year, lwidth(none)) ///
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
graph export "$out_dir/interstate_share_title_endp_count.png", replace width(2500)

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
graph export "$out_dir/interstate_share_title_endp_precision.png", replace width(2500)

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
graph export "$out_dir/interstate_share_title_match_quality.png", replace width(2500)

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
// graph export "$out_dir/interstate_match_quality_by_state_hbar.png", replace width(1400) height(3200)


