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
gen segment_length = seg / 100 // handwritten annotated documentation notes that seg records 2 decimals  
label variable segment_length "segment length (miles)"
gen mp_end = mp_start + segment_length
label variable mp_end "milepost end"

* handle I-35 E/W which got coded as 351 and 352 in the rtereal variable 
* TODO 

* label counties 
* TODO

* combine consecutive connected segments which opened in the same month
sort st route open_year open_month mp_start

* identify chains (with small tolerance for machine rounding errors)
by st route open_year open_month: ///
    gen byte chain_break = (_n == 1) | (abs(mp_start - mp_end[_n-1]) > 0.01)

by st route open_year open_month: ///
    gen int _chain_seq = sum(chain_break)
drop chain_break

* create a globally unique segment ID across the whole dataset
egen long chain_id = group(st route open_year open_month _chain_seq)
drop _chain_seq

keep chain_id sh st state county region open_year open_month route mp_start mp_end segment_length lane paveway rte rtereal stgp 
save "$intermediate_data/PR511_hubbardmazzeo.dta", replace


* ==============================================================================
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