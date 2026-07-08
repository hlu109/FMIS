/*==============================================================================
 	FMIS data processing 
    This script cleans and saves CPI data from FRED. 
    source: https://fred.stlouisfed.org/series/CPIAUCSL
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
* load data 
import delimited "$data/Raw/CPI_2025_indexed.csv", clear
gen year = regexs(1) if regexm(observation_date, "^([0-9]{4})-")
destring year, replace
gen cpi = cpiaucsl / 100
save "$data/Intermediate/CPI_2025.dta", replace
