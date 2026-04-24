/*==============================================================================
 	FMIS data exploration
	This script analyzes the share of FMIS projects with valid interstate route numbers. 
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
    global sandbox "$project_root/Data/Hannah sandbox"
}
* add your username and paths here as an else if condition
else {
	 display as error "Set your user"
}
* check that output folders exist and create them if not 
if !direxists("$output") mkdir "$output"
if !direxists("$intermediate_data") mkdir "$intermediate_data"
* ==============================================================================
global out_dir "$output/interstate_route_check"
if !direxists("$out_dir") mkdir "$out_dir"

use "$sandbox/FMIS_interstate_project_titles.dta", clear

* extract route from federal project number
gen route_fpn = substr(strtrim(federal_project_number), 1, 3)
gen byte route_fpn_has_char = regexm(route_fpn, "[A-Za-z]")
gen str3 route_fpn_int = ustrregexra(route_fpn, "[A-Za-z]", "")
destring route_fpn_int, replace

* ==============================================================================
* string regex to extract interstate route numbers from project titles
* ==============================================================================
/*
    Uses ustrregexm() so that \b word boundaries are available;
    this is the key guard against false positives like "VI-40" (Virgin Islands)
    or "RI-6" (Rhode Island state route), where a letter immediately precedes
    the I and blocks the word boundary.

    Patterns matched:
      I-40  I 40  I40          standard I-prefix, with or without separator
      IH-10 IH 10 IH10         IH-prefix (Texas / Wisconsin convention)
      I-70B I-94BL             letter suffixes for business loops / branches
      INTERSTATE 95            spelled out
      FAI-57  FAI 70           Federal Aid Interstate project codes

    Patterns explicitly NOT matched:
      VI-40  VI-70             Virgin Islands routes (\b before I blocked by V)
      RI-6   KY-31             state routes with two-letter prefix
      I/S                      intersection abbreviation (/ not in [-\s]?)
      I-SECTION  ITS           non-digit after I prefix
      BRIDGE NO. I 6-00        bridge IDs (minor residual risk on single-digit
                               routes like I-4 / I-5 / I-8; acceptable tradeoff)
*/

* define regex components
* =======================

* core route: I or IH, optional dash/space, 1-3 digit number, optional letter
* suffix (B = business, L = loop, BL = business loop, etc.)
* \b on both sides prevents matching inside longer tokens (VI-40, ITS, etc.)
local re_route    `"(\bIH?[-\s]?\d{1,3}[A-Z]{0,2}\b)"'

* spelled-out "INTERSTATE" followed by a route number
local re_spelled  `"(\bINTERSTATE\s+\d{1,3}\b)"'

* Federal Aid Interstate project codes (FAI-57, FAI 70, FAI94, etc.)
* note: FAI followed by a US route number (e.g. "FAI US 33") will NOT match
* this pattern since US is not a digit
local re_fai      `"(\bFAI[-\s]?\d{1,3}\b)"'

* combined
local re_all `"`re_route'|`re_spelled'|`re_fai'"'


* apply to data
* =======================
gen str title_upper = upper(projecttitle)

* indicator: 1 if any interstate route reference found
gen byte has_route = ustrregexm(title_upper, `"`re_all'"')

* extract up to 3 interstate route matches per title
* find match, strip it from the string, search for more matches 

* match 1
gen str route_1 = ustrregexs(0) if ustrregexm(title_upper, `"`re_all'"')

* strip route_1 and search remaining string for match 2
gen str _title_s2 = subinstr(title_upper, route_1, "-----", 1) if !mi(route_1)
replace _title_s2 = title_upper if mi(route_1)
gen str route_2 = ustrregexs(0) if ustrregexm(_title_s2, `"`re_all'"')

* strip route_2 and search for match 3
gen str _title_s3 = subinstr(_title_s2, route_2, "-----", 1) if !mi(route_2)
replace _title_s3 = _title_s2 if mi(route_2)
gen str route_3 = ustrregexs(0) if ustrregexm(_title_s3, `"`re_all'"')

drop title_upper _title_s2 _title_s3

* strip prefix leaving only the route number and any trailing letter suffix
local re_prefix `"^(INTERSTATE\s+|FAI[-\s]?|IH?[-\s]?)"'
foreach v in route_1 route_2 route_3 {
    replace `v' = ustrregexra(`v', `"`re_prefix'"', "") if !mi(`v')
}

* add letter flag and convert to numeric
foreach v in route_1 route_2 route_3 {
    gen byte `v'_has_char = regexm(`v', "[A-Za-z]") if !mi(`v')
    gen str20 `v'_int = ustrregexra(`v', "[A-Za-z]", "") if !mi(`v')
    destring `v'_int, replace
}

* check if FPN route matches any of extracted routes
* =======================
gen byte route_fpn_matches_extracted_1 = (route_fpn_int == route_1_int) if !mi(route_1_int)
gen byte route_fpn_matches_extracted_2 = (route_fpn_int == route_2_int) if !mi(route_2_int)
gen byte route_fpn_matches_extracted_3 = (route_fpn_int == route_3_int) if !mi(route_3_int)
gen byte route_fpn_matches_any_extracted = 0
replace route_fpn_matches_any_extracted = 1 if route_fpn_matches_extracted_1 == 1
replace route_fpn_matches_any_extracted = 1 if route_fpn_matches_extracted_2 == 1
replace route_fpn_matches_any_extracted = 1 if route_fpn_matches_extracted_3 == 1
replace route_fpn_matches_any_extracted = . if mi(route_1_int) & mi(route_2_int) & mi(route_3_int)
label define route_fpn_extr_lbl ///
    1 "FPN route matches extracted route from title" ///
    0 "FPN route matches no extracted routes from title"
label value route_fpn_matches_any_extracted route_fpn_extr_lbl


* ==============================================================================
* compare against PR-511 routes
* ==============================================================================

tempfile pr511_county pr511_county_route
preserve
use "$intermediate_data/PR511_hubbardmazzeo_chained.dta", clear
rename st state_fips
rename county countyid
keep if inrange(state_fips, 1, 56)
drop if mi(route)
drop if mi(countyid)
keep state_fips countyid route
duplicates drop
save `pr511_county_route'
keep state_fips countyid
duplicates drop
save `pr511_county'
restore

gen double route = route_fpn_int

* First merge on (state, county) to `pr511_county` tells you the county exists in PR-511;
* then merge the triple to see if the route appears in that county
* Merging only (state, county, route) conflates two failures: no PR-511 in that county vs county in PR-511 but that route not listed there
merge m:1 state_fips countyid using `pr511_county', gen(_match_pr511_cty)
merge m:1 state_fips countyid route using `pr511_county_route', gen(_match_pr511_county_route)

gen byte route_in_pr511_county = .
replace route_in_pr511_county = 1 if _match_pr511_cty == 3 & _match_pr511_county_route == 3 // county found in PR-511 and route found in that county
replace route_in_pr511_county = 0 if _match_pr511_cty == 3 & _match_pr511_county_route == 1 // county found in PR-511 but route not found in that county
replace route_in_pr511_county = . if mi(countyid) | inlist(countyid, 0, 999) // missing, unknown county, or statewide code in FMIS, can't match PR-511 county
replace route_in_pr511_county = . if mi(route) | mi(state_fips) // missing route or state, can't match PR-511 route
replace route_in_pr511_county = . if _match_pr511_cty == 1

label define route_in_pr511_county_lbl ///
    1 "FPN route is valid in PR-511 county" ///
    0 "FPN route not found in PR-511 county"
label value route_in_pr511_county route_in_pr511_county_lbl
drop _match_pr511_cty _match_pr511_county_route


* ==============================================================================
keep if inrange(completion_year, 1950, 2000)
tab route_in_pr511_county [aw=total_cost_bills_adjusted], m sort 
tab route_fpn_matches_any_extracted [aw=total_cost_bills_adjusted], m sort 
tab route_fpn_matches_any_extracted [aw=total_cost_bills_adjusted]
tab route_fpn_matches_extracted_1 [aw=total_cost_bills_adjusted]
tab route_fpn_matches_extracted_2 [aw=total_cost_bills_adjusted]
tab route_fpn_matches_extracted_3 [aw=total_cost_bills_adjusted]

* ==============================================================================
* figures 
* ==============================================================================

* plot validation against PR-511 county 
* plot as total spending 
preserve
// keep if inrange(completion_year, 1950, 2000)
gen double route_matched = total_cost_bills_adjusted * (route_in_pr511_county == 1)
gen double route_unmatched = total_cost_bills_adjusted * (route_in_pr511_county == 0)
gen double route_na = total_cost_bills_adjusted * mi(route_in_pr511_county)
collapse (sum) route_matched route_unmatched route_na, by(completion_year)

gen double route_total = route_matched + route_unmatched + route_na
gen double spend_top1 = route_matched
gen double spend_top2 = route_matched + route_unmatched
gen double spend_top3 = route_total
gen double zero = 0

graph twoway ///
    (rarea zero spend_top1 completion_year) ///
	(rarea spend_top1 spend_top2 completion_year) ///
	(rarea spend_top2 spend_top3 completion_year), ///
	title("Interstate Construction Project Route Validation Against PR-511 County", size(medium)) ///
	subtitle("Project's inferred route compared against routes in PR-511 county", size(small)) ///
	ytitle("Billions of 2025 USD") ///
	xtitle("Completion year") ///
	xlabel(1950(10)2000) ///
	legend(order(3 "Unable to compare*" 2 "Route not found" "in PR-511 county" 1 "Route valid")) ///
	note( ///
		"* This category includes FMIS projects that were missing a state or county label, had the county coded as statewide or" ///
		"unknown, had a county FIPS that wasn't found in PR-511, or had a non-numeric FPN prefix.", ///
		size(small) span ///
	)
graph export "$out_dir/fpn_pr511_route_match_cost.png", replace width(2500)

* plot as share of spending (%)
gen double route_matched_share = cond(route_total == 0, 0, 100 * route_matched / route_total)
gen double route_unmatched_share = cond(route_total == 0, 0, 100 * route_unmatched / route_total)
gen double route_na_share = cond(route_total == 0, 0, 100 * route_na / route_total)
gen double share_top1 = route_matched_share
gen double share_top2 = route_matched_share + route_unmatched_share
gen double share_top3 = cond(route_total == 0, 0, 100)
graph twoway ///
    (rarea zero share_top1 completion_year) ///
	(rarea share_top1 share_top2 completion_year) ///
	(rarea share_top2 share_top3 completion_year), ///
    title("Share of Interstate Construction Project Route Validated Against PR-511 County", size(medium)) ///
    subtitle("Project's inferred route compared against routes in PR-511 county", size(small)) ///
    ytitle("Percent of annual spending") ///
    xtitle("Completion year") ///
	xlabel(1950(10)2000) ///
    ylabel(0(20)100) ///
    legend(order(3 "Unable to compare*" 2 "Route not found" "in PR-511 county" 1 "Route valid")) ///
	note( ///
		"* This category includes FMIS projects that were missing a state or county label, had the county coded as statewide or" ///
		"unknown, had a county FIPS that wasn't found in PR-511, or had a non-numeric FPN prefix.", ///
		size(small) span ///
	)
graph export "$out_dir/fpn_pr511_route_match_costshare.png", replace width(2500)
restore

* plot validation against route extracted from title 
* plot as total spending 
preserve
// keep if inrange(completion_year, 1950, 2000)
gen double route_matched = total_cost_bills_adjusted * (route_fpn_matches_any_extracted == 1)
gen double route_unmatched = total_cost_bills_adjusted * (route_fpn_matches_any_extracted == 0)
gen double route_na = total_cost_bills_adjusted * mi(route_fpn_matches_any_extracted)


collapse (sum) route_matched route_unmatched route_na, by(completion_year)
gen double route_total = route_matched + route_unmatched + route_na
gen double spend_top1 = route_matched
gen double spend_top2 = route_matched + route_unmatched
gen double spend_top3 = route_total
gen double zero = 0
graph twoway ///
    (rarea zero spend_top1 completion_year) ///
	(rarea spend_top1 spend_top2 completion_year) ///
	(rarea spend_top2 spend_top3 completion_year), ///
	title("Interstate Construction Project Route Validation Against Title", size(medium)) ///
	subtitle("Project's inferred route compared against routes extracted from title", size(small)) ///
	ytitle("Billions of 2025 USD") ///
	xtitle("Completion year") ///
	xlabel(1950(10)2000) ///
	legend(order(3 "Unable to compare*" 2 "Route not matched" 1 "Route matched")) ///
	note( ///
		"* This category includes FMIS projects that had a non-numeric FPN prefix or no route could be extracted from the title.", ///
		size(small) span ///
	)
graph export "$out_dir/fpn_title_extract_match_cost.png", replace width(2500)

* plot as share of spending (%)
gen double route_matched_share = cond(route_total == 0, 0, 100 * route_matched / route_total)
gen double route_unmatched_share = cond(route_total == 0, 0, 100 * route_unmatched / route_total)
gen double route_na_share = cond(route_total == 0, 0, 100 * route_na / route_total)
gen double share_top1 = route_matched_share
gen double share_top2 = route_matched_share + route_unmatched_share
gen double share_top3 = cond(route_total == 0, 0, 100)
graph twoway ///
    (rarea zero share_top1 completion_year) ///
	(rarea share_top1 share_top2 completion_year) ///
	(rarea share_top2 share_top3 completion_year), ///
    title("Share of Interstate Construction Project Route Validated Against Title", size(medium)) ///
    subtitle("Project's inferred route compared against routes extracted from title", size(small)) ///
    ytitle("Percent of annual spending") ///
    xtitle("Completion year") ///
	xlabel(1950(10)2000) ///
    ylabel(0(20)100) ///
	legend(order(3 "Unable to compare*" 2 "Route not matched" 1 "Route matched")) ///
	note( ///
		"* This category includes FMIS projects that had a non-numeric FPN prefix or no route could be extracted from the title.", ///
		size(small) span ///
	)
graph export "$out_dir/fpn_title_extract_match_costshare.png", replace width(2500)
restore


