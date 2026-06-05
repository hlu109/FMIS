/*==============================================================================
	FMIS data processing
    This script makes preliminary matches between PR-511 and FMIS, without route.
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

global match_dir "$intermediate_data/PR511_FMIS"
if !direxists("$match_dir") mkdir "$match_dir"


* get matches between PR-511 chains and FMIS receipts
* do a one to many merge of PR-511 and FMIS (where PR-511 chains are duplicated multiple times
* if there are multiple FMIS segments in the county and time window)

* set time window
global post_pr_window = 7 // years after PR-511 open year that we will allow FMIS match
global pre_pr_window = 9 // years before PR-511 open year that we will allow FMIS match
global match_suffix "_pre${pre_pr_window}_post${post_pr_window}"
global match_mode_suffix "_noroute"

* do the matching by state so that the file size doesn't explode

* get list of unique states
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if state_fips <= 56
levelsof state_fips, local(states)
local state_vlab "stateid_lbl"
foreach state of local states {
    local state_name_`state' : label `state_vlab' `state'
    if "`state_name_`state''" == "" local state_name_`state' "`state'"
}

* collect unmatched rows across states
tempfile pr_unmatched_all fmis_unmatched_all
local has_pr_unmatched 0
local has_fmis_unmatched 0

foreach state of local states {
    * state label for readable messages/filenames
    local state_name "`state_name_`state''"
    local state_name_file = subinstr("`state_name'", " ", "", .)

    * PR-511 subset for this state
    use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
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
    * track matching success of PR-511 entries (chain_id uniquely identifies chains)
    keep chain_id state_fips countyid route open_year open_month mp_start mp_end chain_len
    tempfile pr511_state pr511_state_all
    save `pr511_state_all'
    drop if mi(open_year)
    save `pr511_state'

    * FMIS subset for this state
    use "$intermediate_data/project_level_FMIS.dta", clear
    keep if state_fips == `state'
    keep if interstate_syscode == 1 & fp_ic == 1
    rename alltypes all_improv_types
    keep if completion_year <= `pr_max_year' + $post_pr_window & completion_year >= `pr_min_year' - $pre_pr_window
    keep recipientid federal_project_number projecttitle state_fips countyid completedate completion_year total_cost_mills all_improv_types urban_rural region

    * track matching success of FMIS entries (recipientid x federal_project_number uniquely identifies projects)
    tempfile fmis_state_all
    save `fmis_state_all'

    drop if mi(countyid) | countyid == 999
    drop if mi(completedate)
    quietly count
    if r(N) == 0 {
        di as error "Warning: no FMIS projects after filters for `state_name'. Skipping."
        continue
    }

    * merge (many to many), county only (no route)
    joinby countyid using `pr511_state'

    * filter by year window and sort by time gap
    keep if inrange(completion_year, open_year - $pre_pr_window, open_year + $post_pr_window)
    gen yr_gap = completion_year - open_year

    // order all the pr-511 data first then FMIS
    order chain_id state_fips countyid route open_year open_month mp_start mp_end chain_len recipientid federal_project_number projecttitle completion_year total_cost_mills all_improv_types region urban_rural
    sort chain_id yr_gap
    save "$match_dir/PR511_FMIS_match${match_mode_suffix}_`state_name_file'${match_suffix}.dta", replace

    * save projects that weren't matched to anything
    * collect matched IDs from final matched set
    preserve
    keep chain_id
    duplicates drop
    tempfile matched_pr_ids
    save `matched_pr_ids'
    restore

    preserve
    keep recipientid federal_project_number
    duplicates drop
    tempfile matched_fmis_ids
    save `matched_fmis_ids'
    restore

    * PR-511 rows that did not match in this state
    use `pr511_state_all', clear
    merge 1:1 chain_id using `matched_pr_ids', keep(1) nogen
    quietly count
    if r(N) > 0 {
        if `has_pr_unmatched' == 0 {
            save `pr_unmatched_all', replace
            local has_pr_unmatched 1
        }
        else {
            append using `pr_unmatched_all'
            save `pr_unmatched_all', replace
        }
    }

    * FMIS rows that did not match in this state
    use `fmis_state_all', clear
    merge 1:1 recipientid federal_project_number using `matched_fmis_ids', keep(1) nogen
    quietly count
    if r(N) > 0 {
        if `has_fmis_unmatched' == 0 {
            save `fmis_unmatched_all', replace
            local has_fmis_unmatched 1
        }
        else {
            append using `fmis_unmatched_all'
            save `fmis_unmatched_all', replace
        }
    }
}

* save combined unmatched files
if `has_pr_unmatched' == 1 {
    use `pr_unmatched_all', clear
    save "$match_dir/unmatched_PR511${match_mode_suffix}${match_suffix}.dta", replace
}
else {
    di as error "No unmatched PR-511 rows found across states."
}

if `has_fmis_unmatched' == 1 {
    use `fmis_unmatched_all', clear
    save "$match_dir/unmatched_FMIS${match_mode_suffix}${match_suffix}.dta", replace
}
else {
    di as error "No unmatched FMIS rows found across states."
}

* concatenate all the state-level files into a single file
local state_match_files : dir "$match_dir" files "PR511_FMIS_match${match_mode_suffix}_*${match_suffix}.dta"
local n_state_match_files : word count `state_match_files'

local first_file : word 1 of `state_match_files'
use "$match_dir/`first_file'", clear

forvalues i = 2/`n_state_match_files' {
    local f : word `i' of `state_match_files'
    append using "$match_dir/`f'"
}

save "$intermediate_data/PR511_FMIS_match_all${match_mode_suffix}${match_suffix}.dta", replace
