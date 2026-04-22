/*==============================================================================
 	FMIS data processing 
    This script cleans the PR-511 highway segment opening data. 
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
* start with the Hubbard Mazzeo data which already includes their hand-merged county data 
use "$raw_data/PR_511/hubbard_mazzeo/openings/highway10122.dta", clear

* parse opening date
gen int open_year = (open / 100) + 1900 // first two digits of "open" var 
gen int open_month = mod(open, 100)

* parse route 
* drop trailing zeros; the leading zeros are already dropped 
gen int route = rte / 10 

gen mp_start = mpdst / 100 // assuming data records 2 decimals, otherwise the scale would be unrealistic 
label variable mp_start "milepost start"
gen seg_len = seg / 100 // handwritten annotated documentation notes that seg records 2 decimals  
label variable seg_len "segment length (miles)"
gen mp_end = mp_start + seg_len
label variable mp_end "milepost end"

* handle I-35 E/W which got coded as 351 and 352 in the rtereal variable 
* TODO 

* label counties 
* TODO

* combine consecutive connected segments which opened in the same month
sort st route open_year open_month mp_start county

* identify chains (with small tolerance for machine rounding errors)
bysort st route open_year open_month county: ///
    gen byte chain_break = (_n == 1) | (abs(mp_start - mp_end[_n-1]) > 0.01)

bysort st route open_year open_month county: ///
    gen int _chain_seq = sum(chain_break)
drop chain_break

* create a globally unique segment ID across the whole dataset
egen long chain_id = group(st route open_year open_month county _chain_seq)
drop _chain_seq

keep chain_id sh st state county region open_year open_month route mp_start mp_end seg_len lane paveway rte rtereal stgp 
save "$intermediate_data/PR511_hubbardmazzeo.dta", replace

* also save as csv 
export delimited using "$intermediate_data/PR511_hubbardmazzeo.csv", replace

* save another copy of just the chain-level data
collapse (sum) chain_len = seg_len (first) sh st state county route region open_year open_month (min) mp_start (max) mp_end, by(chain_id)
save "$intermediate_data/PR511_hubbardmazzeo_chained.dta", replace

* also save as csv 
export delimited using "$intermediate_data/PR511_hubbardmazzeo_chained.csv", replace
exit 

* ==============================================================================
* Nate Baum PR-511 data
* ==============================================================================
// "C:\Users\hl2266\YLS Dropbox\Hannah Lu\shared\FHWA cost data\Data\Raw\PR_511\baum_snow\roads1_final.xls"
// "C:\Users\hl2266\YLS Dropbox\Hannah Lu\shared\FHWA cost data\Data\Raw\PR_511\baum_snow\roads2_final.xls"
// "C:\Users\hl2266\YLS Dropbox\Hannah Lu\shared\FHWA cost data\Data\Raw\PR_511\baum_snow\roads3_final.xls"

import excel using "$raw_data/PR_511/baum_snow/roads1_final.xls", firstrow clear
// convert all variables to string
foreach var of varlist * {
    tostring `var', replace
}
tempfile baum_snow
save `baum_snow'

import excel using "$raw_data/PR_511/baum_snow/roads2_final.xls", firstrow clear
foreach var of varlist * {
	tostring `var', replace
}
tempfile r2
save `r2'

use `baum_snow', clear
append using `r2'
save `baum_snow', replace

import excel using "$raw_data/PR_511/baum_snow/roads3_final.xls", firstrow clear
foreach var of varlist * {
	tostring `var', replace
}
tempfile r3
save `r3'
use `baum_snow', clear

* clean data --- 

destring RTE MPOST SEG, replace ignore(",") force
recast int RTE MPOST SEG

* drop trailing zeros; the leading zeros are already dropped 
gen int route = RTE / 10 

gen mp_start = MPOST / 100 // assuming data records 2 decimals, otherwise the scale would be unrealistic 
label variable mp_start "milepost start"
gen seg_len = SEG / 100 // handwritten annotated documentation notes that seg records 2 decimals  
label variable seg_len "segment length (miles)"
gen mp_end = mp_start + seg_len
label variable mp_end "milepost end"

save "$intermediate_data/PR511_baumsnow.dta", replace

drop SH I RTE MPOST SEG
keep if route == 78
order ST route mp_start mp_end seg_len
sort ST mp_start


* ==============================================================================
use "$intermediate_data/PR511_hubbardmazzeo.dta", clear
keep if st == 6
keep if county == 85 | county == 81 // santa clara and san mateo
global county_lbl_def ///
    85 "Santa Clara" ///
    81 "San Mateo"
label define county_lbl $county_lbl_def, replace
label values county county_lbl
sort open_year open_month mp_start
drop st state region rtereal stgp sh rte
// keep if route == 280

save "$data/Hannah sandbox/PR511_sanmateo_santaclara.dta", replace



* ==============================================================================
* Basic stats
* ==============================================================================

* tabulate frequency of counties with X count of segment-chains
use "$intermediate_data/PR511_hubbardmazzeo_chained.dta", clear
collapse (count) chain_count = chain_id, by(st county)
label var chain_count "# chains in county"
di _n(2) as result "=== Distribution of chain counts across county observations ==="
tab chain_count, missing 
* alt display that renames the Freq. column 
// contract chain_count, freq(number_of_counties)
// label var number_of_counties "Number of counties"
// list chain_count number_of_counties, clean noobs abbreviate(24)

* same but for county x route 
use "$intermediate_data/PR511_hubbardmazzeo_chained.dta", clear
collapse (count) chain_count = chain_id, by(st county route)
label var chain_count "# chains in county x route"
di _n(2) as result "=== Distribution of chain counts across county x route observations ==="
tab chain_count, missing 
* alt display that renames the Freq. column 
// contract chain_count, freq(number_county_routes)
// label var number_county_routes "Number of county-route cells"
// list chain_count number_county_routes, clean noobs abbreviate(24)
