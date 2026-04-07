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
* load FMIS data
import delimited using "$data/Hannah sandbox/FMIS_title_quality_claude.csv", clear

* useful indicator variables for project quality 
gen has_title = !missing(projecttitle)
gen endpoint_count = (endpoint_a_raw != "") + (endpoint_b_raw != "")
gen has_2_endpoints = endpoint_count == 2
gen has_1_endpoint = endpoint_count == 1



* compute share (by cost) of projects by title quality 
gen cost_has_title = has_title * total_cost_bills_adjusted
gen cost_has_2_endpoints = has_2_endpoints * total_cost_bills_adjusted
gen cost_has_1_endpoint = has_1_endpoint * total_cost_bills_adjusted
gen cost_has_endpoints = cost_has_2_endpoints + cost_has_1_endpoint

* has 2 endpoints and precision >= 4 for both - most likely we can match 
gen cost_2_endp_prec46x2 = (has_2_endpoints & precision_a >= 4 & precision_b >= 4) * total_cost_bills_adjusted
* has 2 endpoints and precision >= 4 for one - maybe match 
gen cost_2_endp_prec46x1 = (has_2_endpoints & precision_a >= 4 & precision_b <= 3) * total_cost_bills_adjusted
* has 1 endpoint and precision >= 4 - maybe match (e.g. as point-type project geometry, like intersection, bridge, ramp, etc.)
gen cost_1_endp_prec46 = (has_1_endpoint & precision_a >= 4) * total_cost_bills_adjusted
* has 2 endpoints and precision <= 3 for both - unlikely to match
gen cost_2_endp_prec3x2 = (has_2_endpoints & precision_a <= 3 & precision_b <= 3) * total_cost_bills_adjusted
* has 1 endpoint and precision <= 3 - unlikely to match
gen cost_1_endp_prec3 = (has_1_endpoint & precision_a <= 3) * total_cost_bills_adjusted

keep if year >= 1950 & year < 2025

* state-level totals for horizontal stacked bar (match buckets); used at end of script
* TODO: review 
tempfile fmis_state_match_bars
preserve
	collapse (sum) total_cost_bills_adjusted cost_2_endp_prec46x2 cost_2_endp_prec46x1 cost_1_endp_prec46, by(state_fips)
	drop if missing(state_fips)
	replace state_fips = int(round(state_fips))
	gen double maybe_match_cost = cost_2_endp_prec46x2
	gen double hard_match_cost = cost_2_endp_prec46x2 + cost_2_endp_prec46x1 + cost_1_endp_prec46
	gen double pct_maybe_match = 100 * maybe_match_cost / total_cost_bills_adjusted
	gen double pct_hard_match = 100 * (hard_match_cost - maybe_match_cost) / total_cost_bills_adjusted
	gen double pct_unlikely = 100 - pct_maybe_match - pct_hard_match
	replace pct_maybe_match = 0 if total_cost_bills_adjusted == 0
	replace pct_hard_match = 0 if total_cost_bills_adjusted == 0
	replace pct_unlikely = 0 if total_cost_bills_adjusted == 0
	capture label drop stfips_match_lbl
	#delimit ;
	label define stfips_match_lbl
		1 "Alabama" 2 "Alaska" 4 "Arizona" 5 "Arkansas" 6 "California"
		8 "Colorado" 9 "Connecticut" 10 "Delaware" 11 "District of Columbia"
		12 "Florida" 13 "Georgia" 15 "Hawaii" 16 "Idaho" 17 "Illinois"
		18 "Indiana" 19 "Iowa" 20 "Kansas" 21 "Kentucky" 22 "Louisiana"
		23 "Maine" 24 "Maryland" 25 "Massachusetts" 26 "Michigan" 27 "Minnesota"
		28 "Mississippi" 29 "Missouri" 30 "Montana" 31 "Nebraska" 32 "Nevada"
		33 "New Hampshire" 34 "New Jersey" 35 "New Mexico" 36 "New York"
		37 "North Carolina" 38 "North Dakota" 39 "Ohio" 40 "Oklahoma" 41 "Oregon"
		42 "Pennsylvania" 44 "Rhode Island" 45 "South Carolina" 46 "South Dakota"
		47 "Tennessee" 48 "Texas" 49 "Utah" 50 "Vermont" 51 "Virginia"
		53 "Washington" 54 "West Virginia" 55 "Wisconsin" 56 "Wyoming"
		69 "Northern Mariana Islands" 72 "Puerto Rico", replace ;
	#delimit cr
	label values state_fips stfips_match_lbl
	decode state_fips, gen(state_name)
	replace state_name = "FIPS " + string(state_fips) if missing(state_name) | state_name == ""
	save `fmis_state_match_bars', replace
restore

collapse (sum) total_cost_bills_adjusted cost_has_title cost_has_endpoints cost_has_2_endpoints cost_has_1_endpoint cost_2_endp_prec46x2 cost_2_endp_prec46x1 cost_1_endp_prec46 cost_2_endp_prec3x2 cost_1_endp_prec3, by(year)

* compute shares
gen share_has_title = cost_has_title / total_cost_bills_adjusted
gen share_has_2_endpoints = cost_has_2_endpoints / total_cost_bills_adjusted
gen share_has_1_endpoint = cost_has_1_endpoint / total_cost_bills_adjusted
gen share_has_endpoints = cost_has_endpoints / total_cost_bills_adjusted
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
    (rarea endcnt_b0 cost_has_2_endpoints year, lwidth(none)) ///
    (rarea cost_has_2_endpoints cost_has_endpoints year, lwidth(none)) ///
    (line total_cost_bills_adjusted year, lcolor(black) lwidth(medthin)), ///
    title("Comparison of Interstate Spending by Project Title Quality (Endpoint Count)", size(medium)) ///
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
		"Interstate projects are those with at least one receipt coded as interstate by the federal aid system code.", ///
		size(small) span ///
	) ///
	graphregion(margin(l=30 r=15))
graph export "$output/interstate_title_endpoint_count.png", replace width(2500)

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
    title("Comparison of Interstate Spending by Project Title Quality (Endpoint Quality)", size(medium)) ///
	ytitle("Billions of 2025 USD") xtitle("Completion Year") ///
	yscale(titlegap(10)) ///
	xlabel(1950(10)2025) ///
	xmlabel(1950(5)2025, grid glcolor(gs14) glwidth(vthin) noticks nolabel) ///
	legend(order(6 5 4 3 2 1) ///
		label(1 "2 Endpoints," "Both Precision >= 4") ///
		label(2 "2 Endpoints," "One Precision >= 4") ///
		label(3 "1 Endpoint," "Precision >= 4") ///
		label(4 "2 Endpoints," "Both Precision <= 3") ///
		label(5 "1 Endpoint," "Precision <= 3") ///
		label(6 "All Interstate Projects")) ///
	note( ///
		"Interstate projects are those with at least one receipt coded as interstate by the federal aid system code.", ///
		size(small) span ///
	) ///
	graphregion(margin(l=15 r=15))
graph export "$output/interstate_title_endpoint_quality.png", replace width(2500)

* plot what can be matched 
gen maybe_match = cost_2_endp_prec46x2 
gen hard_match = cost_2_endp_prec46x2 + cost_2_endp_prec46x1 + cost_1_endp_prec46
gen match_b0 = 0

graph twoway ///
	(rarea maybe_match hard_match year, lwidth(none)) ///
	(rarea hard_match total_cost_bills_adjusted year, lwidth(none)) ///
	(rarea match_b0 maybe_match year, lwidth(none)) ///
	(line total_cost_bills_adjusted year, lcolor(black) lwidth(medthin)), ///
    title("Comparison of Interstate Spending by Project Title Quality", size(medium)) ///
	ytitle("Billions of 2025 USD") xtitle("Completion Year") ///
	yscale(titlegap(10)) ///
	xlabel(1950(10)2025) ///
	xmlabel(1950(5)2025, grid glcolor(gs14) glwidth(vthin) noticks nolabel) ///
	legend(order(4 2 1 3) ///
		label(3 "Possible Match" "(2 endpoints, both" "precision >= 4)") ///
		label(1 "Unlikely but Possible Match" "(At least one endpoint" "with precision >= 4)") ///
		label(2 "Likely Unusable") ///
		label(4 "All Interstate Projects") ///
	) ///
	note( ///
		"Interstate projects are those with at least one receipt coded as interstate by the federal aid system code.", ///
		size(small) span ///
	) ///
	graphregion(margin(l=15 r=15))
graph export "$output/interstate_title_match_quality.png", replace width(2500)

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
graph export "$output/interstate_share_title_by_cost.png", replace width(2500)

* same graph but zoomed in to 1955-1965 
preserve
keep if year >= 1950 & year <= 1965
graph twoway line share_has_title year, ///
    title("Share of Annual Interstate Project Costs with Non-Missing Titles") ///
	ytitle("Share of Annual Costs") xtitle("Completion Year") ///
	yscale(titlegap(10)) ///
	xlabel(1950(1)1965)
graph export "$output/interstate_share_title_by_cost_55_65.png", replace width(2500)
restore

* plot comparison of interstate spending by project title quality 
* plot share 
* compare endpoint count 
* stacked rarea: 2-endpoint share + 1-endpoint share = share_has_endpoints
gen sh_end0 = 0

graph twoway ///
    (rarea sh_end0 share_has_2_endpoints year, lwidth(none)) ///
    (rarea share_has_2_endpoints share_has_endpoints year, lwidth(none)) ///
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
		"Interstate projects are those with at least one receipt coded as interstate by the federal aid system code.", ///
		size(small) span ///
	) ///
	graphregion(margin(l=15 r=15))
graph export "$output/interstate_share_title_endpoint_count.png", replace width(2500)

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
		label(1 "2 Endpoints," "Both Precision >= 4") ///
		label(2 "2 Endpoints," "One Precision >= 4") ///
		label(3 "1 Endpoint," "Precision >= 4") ///
		label(4 "2 Endpoints," "Both Precision <= 3") ///
		label(5 "1 Endpoint," "Precision <= 3") ///
		label(6 "Projects with Titles") ///
	) ///
	note( ///
		"Interstate projects are those with at least one receipt coded as interstate by the federal aid system code.", ///
		size(small) span ///
	) ///
	graphregion(margin(l=15 r=15))
graph export "$output/interstate_share_title_endpoint_precision.png", replace width(2500)

* same match-quality breakdown as interstate_title_match_quality.png, but as shares of annual cost
gen share_maybe_match = share_2_endp_prec46x2
gen share_hard_match = share_2_endp_prec46x2 + share_2_endp_prec46x1 + share_1_endp_prec46
gen share_full = 1

graph twoway ///
	(rarea share_maybe_match share_hard_match year, lwidth(none)) ///
	(rarea share_hard_match share_full year, lwidth(none)) ///
	(rarea match_b0 share_maybe_match year, lwidth(none)) ///
	(line share_has_title year, lcolor(black) lwidth(medthin)), ///
    title("Share of Annual Interstate Project Costs by Title / Endpoint Match Quality", size(medium)) ///
	ytitle("Share of Annual Costs") xtitle("Completion Year") ///
	yscale(titlegap(10)) ///
	xlabel(1950(10)2025) ///
	xmlabel(1950(5)2025, grid glcolor(gs14) glwidth(vthin) noticks nolabel) ///
	legend(order(4 2 1 3) ///
		label(3 "Possible Match" "(2 endpoints, both" "precision >= 4)") ///
		label(1 "Unlikely but Possible Match" "(At least one endpoint" "with precision >= 4)") ///
		label(2 "Likely Unusable") ///
		label(4 "Projects with Titles") ///
	) ///
	note( ///
		"Interstate projects are those with at least one receipt coded as interstate by the federal aid system code.", ///
		size(small) span ///
	) ///
	graphregion(margin(l=15 r=15))
graph export "$output/interstate_share_title_match_quality.png", replace width(2500)

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
// graph export "$output/interstate_match_quality_by_state_hbar.png", replace width(1400) height(3200)


