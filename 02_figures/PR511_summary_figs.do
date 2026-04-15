/*==============================================================================
 	FMIS data processing 
    This script plots the length of PR-511 segments over time. 
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
global out_dir "$output/PR511"
if !direxists("$out_dir") mkdir "$out_dir"

use "$intermediate_data/PR511_hubbardmazzeo_chained.dta", clear
drop if open_year < 1950 | mi(open_year)

* ==============================================================================
* total mileage by year
* ==============================================================================
preserve 
collapse (sum) chain_len, by(open_year)
sort open_year
graph twoway ///
    (line chain_len open_year), ///
    title("Total Miles Opened in PR-511 Each Year") ///
    xtitle("Opening Year") ///
    ytitle("Miles") ///
    legend(off)
graph export "$out_dir/total_mi_by_year.png", width(1000) replace
restore


* ==============================================================================
* average segment length by year
* ==============================================================================
preserve 
collapse (mean) chain_len, by(open_year)
sort open_year

graph twoway ///
    (line chain_len open_year), ///
    title("Average Length of PR-511 Segment-Chains Each Year") ///
    xtitle("Opening Year") ///
    ytitle("Miles") ///
    note( ///
        "Chains are defined as consecutive segments of the same route within the same opening month." ///
    ) ///
    legend(off)
graph export "$out_dir/avg_chain_len_by_year.png", width(1000) replace
restore


* ==============================================================================
* # counties with openings per year 
* ==============================================================================
preserve 
gen county_fips = real(string(st, "%02.0f") + string(county, "%03.0f")) if !mi(st) & !mi(county)
keep open_year county_fips
duplicates drop
collapse (count) county_count = county_fips, by(open_year)
sort open_year
graph twoway ///
    (line county_count open_year), ///
    title("Number of Counties with PR-511 Openings Each Year") ///
    xtitle("Opening Year") ///
    ytitle("Number of Counties") ///
    legend(off)
graph export "$out_dir/counties_by_year.png", width(1000) replace
restore


* ==============================================================================
* # county x route with openings per year 
* ==============================================================================
preserve 
gen county_fips_x_route = real(string(st, "%02.0f") + string(county, "%03.0f") + string(route, "%03.0f")) if !mi(st) & !mi(county) & !mi(route)
keep open_year county_fips_x_route
duplicates drop
collapse (count) obs_count = county_fips_x_route, by(open_year)
sort open_year
graph twoway ///
    (line obs_count open_year), ///
    title("Number of County x Route Cells with PR-511 Openings Each Year") ///
    xtitle("Opening Year") ///
    ytitle("Number of County x Route Cells") ///
    legend(off)
graph export "$out_dir/county_routes_by_year.png", width(1000) replace
restore










