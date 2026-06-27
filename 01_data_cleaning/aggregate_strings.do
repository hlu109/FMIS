/*==============================================================================
	FMIS String Aggregating
	This file aggregates string variables from the "gis breakdown" field to the 
	Reimbursement-level, as well as the project level, and saves an intermediate 
	file for each. This file was created to reduce the runtime of the main cleaning
	file. If changes are made to this file, the main file needs to be re-run after
	uncommmenting the call for this file. 
==============================================================================*/

*  Aggregate strings to the project level
preserve
tostring detail_improvementtype, gen(proj_improv_types)
gen row = _n
sort federal_project_number recipientid row
foreach var of varlist proj_improv_types county_fips county_name {
    replace `var' = "" if `var' == "."
    capture drop `var'_combined
    by federal_project_number recipientid: gen `var'_combined = `var'[1]
	by federal_project_number recipientid: replace `var'_combined = cond( ///
		!regexm(`var'_combined[_n-1], "(^|; )" + `var' + "($|;)"), ///
		cond(`var'_combined[_n-1] == "", `var', `var'_combined[_n-1] + "; " + `var'), ///
    `var'_combined[_n-1]) if _n > 1  
	by federal_project_number recipientid: replace `var' = `var'_combined[_N]
}
bysort recipientid federal_project_number: gen n = _n
keep if n == 1 
keep recipientid federal_project_number proj_improv_types county_fips county_name
save "$intermediate_data/aggregated_proj_strings.dta", replace
restore

* Aggregate strings to the reimbursement level
sort federal_project_number recipientid detail_programcode detail_linenumber gisbreakdown_index
foreach var of varlist county_fips county_name {
    replace `var' = "" if `var' == "."
    capture drop `var'_combined
    by federal_project_number recipientid detail_programcode detail_linenumber: ///
        gen `var'_combined = `var'[1]
    by federal_project_number recipientid detail_programcode detail_linenumber: ///
        replace `var'_combined = cond( ///
            !regexm(`var'_combined[_n-1], "(^|; )" + `var' + "($|;)"), ///
            cond(`var'_combined[_n-1] == "", `var', `var'_combined[_n-1] + "; " + `var'), ///
            `var'_combined[_n-1]) if _n > 1
    by federal_project_number recipientid detail_programcode detail_linenumber: ///
        replace `var' = `var'_combined[_N]
}

* drop to the reimbursement level
keep if gisbreakdown_index == . | gisbreakdown_index == 1
preserve 
keep recipientid federal_project_number detail_linenumber county_fips county_name
save "$intermediate_data/aggregated_reimbursement_strings.dta", replace
restore


