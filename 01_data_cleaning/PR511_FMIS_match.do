/*==============================================================================
 	FMIS data processing 
    This script makes preliminary matches between PR-511 and FMIS. 
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
global match_dir "$intermediate_data/PR511_FMIS_match_by_state"
if !direxists("$match_dir") mkdir "$match_dir"


* get matches between PR-511 chains and FMIS receipts 
* do a one to many merge of PR-511 and FMIS (where PR-511 chains are duplicated multiple times if there are multiple FMIS segments in the county and time window)

* let the time window be 0-2 years after PR-511 open month+open year (for now - we can adjust the window later)
global post_pr_window = 2 // years after PR-511 open year that we will allow  FMIS match 
global pre_pr_window = 0 // years before PR-511 open year that we will allow  FMIS match 

* do the matching by state so that the file size doesn't explode

* get list of unique states
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if state_fips <= 56
levelsof state_fips, local(states)

* collect unmatched rows across states
tempfile pr_unmatched_all fmis_unmatched_all
local has_pr_unmatched 0 // binary indicator 
local has_fmis_unmatched 0 // binary indicator 

foreach state of local states {
    * state label for readable messages/filenames
    local state_name : label (state_fips) `state'
    local state_name_file = subinstr("`state_name'", " ", "_", .) // remove spaces for filenames 

    * PR-511 subset for this state
    use "$intermediate_data/PR511_hubbardmazzeo_chained.dta", clear
    quietly summarize open_year
    local pr_min_year = r(min)
    local pr_max_year = r(max)
    rename st state_fips
    rename county countyid
    keep if state_fips == `state'
    quietly count
    if r(N) == 0 {
        di as error "Warning: no PR-511 data in `state_name'. Skipping."
        continue
    }
    * track matching success of PR-511 entries 
    gen long pr_rowid = _n
    keep pr_rowid chain_id state_fips countyid route open_year open_month mp_start mp_end chain_len
    tempfile pr511_state pr511_state_all
    save `pr511_state_all'
    drop if mi(open_year)
    save `pr511_state'

    * FMIS subset for this state
    // TODO: later bring in the detail improvement type as a further filter 
    use "$intermediate_data/project_level_FMIS.dta", clear
    keep if state_fips == `state' & interstate_syscode == 1
    keep if completion_year <= `pr_max_year' + 2 & completion_year >= `pr_min_year'
    keep federal_project_number projecttitle state_fips countyid completedate completion_year total_cost_mills
    
    * Route proxy from first three chars of federal project number
    gen str3 pseudo_route = substr(strtrim(federal_project_number), 1, 3)
    destring pseudo_route, gen(route) force // letters yield missing values, then drop them

    * track matching success of FMIS entries 
    gen long fmis_rowid = _n
    tempfile fmis_state_all
    save `fmis_state_all'
    
    drop if mi(countyid) | countyid == 999
    drop if mi(route)
    drop if mi(completedate)
    quietly count
    if r(N) == 0 {
        di as error "Warning: no FMIS projects after filters for `state_name'. Skipping."
        continue
    }

    * merge (many to many)
    joinby countyid route using `pr511_state'

    * filter by year window and sort by time gap  
    keep if inrange(completion_year, open_year, open_year + 2)
    gen yr_gap = completion_year - open_year
    
    // order all the pr-511 data first then FMIS 
    order chain_id state_fips countyid route open_year open_month mp_start mp_end chain_len federal_project_number projecttitle completion_year total_cost_mills fmis_rowid pr_rowid
    sort chain_id yr_gap
    save "$match_dir/PR511_FMIS_match_`state_name_file'.dta", replace

    * save projects that weren't matched to anything 
    * collect matched IDs from final matched set
    preserve
    keep pr_rowid
    duplicates drop
    tempfile matched_pr_ids
    save `matched_pr_ids'
    restore

    preserve
    keep fmis_rowid
    duplicates drop
    tempfile matched_fmis_ids
    save `matched_fmis_ids'
    restore

    * PR-511 rows that did not match in this state
    use `pr511_state_all', clear
    merge 1:1 pr_rowid using `matched_pr_ids', keep(3) nogen
    quietly count
    if r(N) > 0 {
        if `has_pr_unmatched' == 0 { // if no unmatched PR-511 rows found yet, save the first one
            save `pr_unmatched_all', replace
            local has_pr_unmatched 1
        }
        else { // append to existing file 
            append using `pr_unmatched_all'
            save `pr_unmatched_all', replace
        }
    }

    * FMIS rows that did not match in this state
    use `fmis_state_all', clear
    merge 1:1 fmis_rowid using `matched_fmis_ids', keep(3) nogen
    quietly count
    if r(N) > 0 {
        if `has_fmis_unmatched' == 0 { // if no unmatched FMIS rows found yet, save the first one
            save `fmis_unmatched_all', replace
            local has_fmis_unmatched 1
        }
        else { // append to existing file 
            append using `fmis_unmatched_all'
            save `fmis_unmatched_all', replace
        }
    }
}

* save combined unmatched files
if `has_pr_unmatched' == 1 {
    use `pr_unmatched_all', clear
    save "$match_dir/unmatched_PR511.dta", replace
}
else di as error "No unmatched PR-511 rows found across states."

if `has_fmis_unmatched' == 1 {
    use `fmis_unmatched_all', clear
    save "$match_dir/unmatched_FMIS.dta", replace
}
else di as error "No unmatched FMIS rows found across states."
