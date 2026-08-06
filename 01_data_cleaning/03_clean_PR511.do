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
global pr511_intermediate "$intermediate_data/PR_511"
if !direxists("$pr511_intermediate") mkdir "$pr511_intermediate"

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

* handle I-35 E/W which got coded as 351 and 352 in the 'rtereal' variable 
* TODO 

* label counties 
* TODO

* combine consecutive connected segments which opened in the same month
sort st route open_year open_month county mp_start

* segments with missing values shouldn't get pooled in bysort - give unique chain ids 
gen byte _chain_solo = missing(st) | missing(route) | missing(open_year) | missing(open_month) | missing(county)

* identify chains (with small tolerance for machine rounding errors)
bysort st route open_year open_month county: ///
    gen byte chain_break = (_n == 1) | (abs(mp_start - mp_end[_n-1]) > 0.01) if _chain_solo == 0

bysort st route open_year open_month county: ///
    gen int _chain_seq = sum(chain_break) if _chain_solo == 0
drop chain_break

* create a globally unique segment ID across the whole dataset
egen long chain_id = group(st route open_year open_month county _chain_seq) if _chain_solo == 0

* assign unique chain ids to segments with missing values (set the chain ids to increment starting from the current max chain id)
quietly summarize chain_id, meanonly
local max_chain = cond(r(N) == 0, 0, r(max))
egen long _solo_id = seq() if _chain_solo == 1
replace chain_id = `max_chain' + _solo_id if _chain_solo == 1

drop _chain_solo _chain_seq _solo_id

keep chain_id sh st state county region open_year open_month route mp_start mp_end seg_len lane paveway rte rtereal stgp 

* construct a county fips variable for convenience
gen long county_fips = real(string(st, "%02.0f") + string(county, "%03.0f")) if !mi(st) & !mi(county)

save "$pr511_intermediate/PR511_hubbardmazzeo.dta", replace

* also save as csv 
export delimited using "$pr511_intermediate/PR511_hubbardmazzeo.csv", replace

* save another copy of just the chain-level data
collapse (sum) chain_len = seg_len (first) sh st state county county_fips route region open_year open_month (min) mp_start (max) mp_end, by(chain_id)
save "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", replace

* also save as csv 
export delimited using "$pr511_intermediate/PR511_hubbardmazzeo_chained.csv", replace

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

save "$pr511_intermediate/PR511_baumsnow.dta", replace

drop SH I RTE MPOST SEG
keep if route == 78
order ST route mp_start mp_end seg_len
sort ST mp_start


* ==============================================================================
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
keep if st == 6
keep if county == 85 | county == 81 // santa clara and san mateo
global county_lbl_def ///
    85 "Santa Clara" ///
    81 "San Mateo"
label define county_lbl $county_lbl_def, replace
label values county county_lbl
sort open_year open_month mp_start
drop st state region sh
keep if route == 280

save "$data/Hannah sandbox/PR511_sanmateo_santaclara.dta", replace

// keep if county == 81 
// sort mp_start 
// exit
