/*==============================================================================
 	FMIS data processing 
    This script generates basic descriptive statistics for PR-511. 
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
global pr511_intermediate "$intermediate_data/PR_511"
if !direxists("$pr511_intermediate") mkdir "$pr511_intermediate"

global out_dir "$output/PR511"
if !direxists("$out_dir") mkdir "$out_dir"


* ==============================================================================
* Basic stats
* ==============================================================================

use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
sum chain_len 
sum open_year
sum mp_start
sum mp_end

* ==============================================================================
* Basic tabulations
* ==============================================================================

* tabulate frequency of counties with X count of segment-chains
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
collapse (count) chain_count = chain_id, by(st county)
label var chain_count "# chains in county"
di _n(2) as result "=== Distribution of chain counts across county observations ==="
tab chain_count, missing 
* alt display that renames the Freq. column 
// contract chain_count, freq(number_of_counties)
// label var number_of_counties "Number of counties"
// list chain_count number_of_counties, clean noobs abbreviate(24)

* same but for county x route 
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
collapse (count) chain_count = chain_id, by(st county route)
label var chain_count "# chains in county x route"
di _n(2) as result "=== Distribution of chain counts across county x route observations ==="
tab chain_count, missing 
* alt display that renames the Freq. column 
// contract chain_count, freq(number_county_routes)
// label var number_county_routes "Number of county-route cells"
// list chain_count number_county_routes, clean noobs abbreviate(24)
