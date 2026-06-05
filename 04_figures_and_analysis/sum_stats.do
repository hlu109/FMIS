/*==============================================================================
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

local pr511_dir "$output/PR511"
if !direxists("`pr511_dir'") mkdir "`pr511_dir'"

use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear

histogram chain_len if inrange(open_year, 1950, 1990), ///
	title("PR-511 Chain Length, 1950-1990") ///
	xtitle("Miles", size(medsmall)) ///
	ytitle("Frequency", size(medsmall))

graph export "`pr511_dir'/hist_chain_len.png", replace

gen double log_chain_len = log(chain_len)

histogram log_chain_len if inrange(open_year, 1950, 1990) & chain_len > 0, ///
	title("Log PR-511 Chain Length, 1950-1990") ///
	xtitle("Log miles", size(medsmall)) ///
	ytitle("Frequency", size(medsmall))

graph export "`pr511_dir'/hist_log_chain_len.png", replace
