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
use "$intermediate_data/PR511_hubbardmazzeo_chained.dta", clear

global out_dir "$output/PR511_FMIS"

* compute average segment length by year
drop if open_year < 1950 | mi(open_year)
collapse (mean) chain_len, by(open_year)
sort open_year

graph twoway ///
    (line chain_len open_year), ///
    title("Average Length of Interstate Chains in PR-511") ///
    xtitle("Opening Year") ytitle("Miles") ///
    note( ///
        "Chains are defined as consecutive segments of the same route within the same opening month." ///
    ) ///
    legend(off)
graph export "$out_dir/PR511_seglength.png", width(1000) replace