/*==============================================================================
 	FMIS data exploration
	This script generates summary time-series figures related to reimbursements and projects. 
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
global fig_dir "$output/proj_and_reimb_figs"
if !direxists("$fig_dir") mkdir "$fig_dir"

* time axis: completion year, then construction authorization year
forvalues tpass = 1/2 {
	if `tpass' == 1 {
		local year_var completion_year
		local year_print "Completion Year"
		local year_shorthand completeyr
	}
	if `tpass' == 2 {
		local year_var authconstyear
		local year_print "Construction Authorization Year"
		local year_shorthand authyr
	}

    * ==========================================================================
    * Project-level data
    * ==========================================================================

    /*==========================
    Num projects by year
    ===========================*/
    use "$intermediate_data/project_level_FMIS_lite.dta", clear
    gen int authconstyear = year(authconstdate)
    keep if `year_var' >= 1950 & `year_var' < 2025

    gen n_proj = 1
    gen n_proj_ic = 1 if fp_ic
    gen n_proj_ic_newconstr = 1 if fp_ic == 1 & has_new_construction == 1

    preserve
    collapse (sum) n_proj n_proj_ic n_proj_ic_newconstr, by(`year_var')
    graph twoway line n_proj n_proj_ic n_proj_ic_newconstr `year_var', sort /// 
        title("Number of Projects Over Time") ///
        ytitle("Number of Projects") ///
        ylabel(, format(%9.0fc)) ///
        xtitle("`year_print'") ///
        xlabel(1950(10)2025) ///
        legend(label(1 "All Projects") label(2 "Interstate Construction") label(3 "IC with New Construction")) ///
        note( ///
            "Projects are considered to be interstate if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"New construction is identified by the improvement type code "new construction roadway", "bridge new construction","' ///
            `""maintenance relocation", and "new tunnel"."' ///
            "Projects are considered to be new construction if at least one reimbursement is classified as new construction.", ///
            size(small) span ///
        )
    graph export "$fig_dir/num_projects_by_`year_shorthand'_w_IC.png", replace width(2500)

    * version with IC only 
    graph twoway line n_proj_ic n_proj_ic_newconstr `year_var', sort /// 
        title("Number of Projects Over Time") ///
        subtitle("Interstate Construction Funding Only") ///
        ytitle("Number of Projects") ///
        ylabel(, format(%9.0fc)) ///
        xtitle("`year_print'") ///
        xlabel(1950(10)2025) ///
        lcolor(stc2 stc3) ///
        legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
        note( ///
            "Projects are considered to be interstate if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"New construction is identified by the improvement type code "new construction roadway", "bridge new construction","' ///
            `""maintenance relocation", and "new tunnel"."' ///
            "Projects are considered to be new construction if at least one reimbursement is classified as new construction.", ///
            size(small) span ///
        )
    graph export "$fig_dir/num_projects_by_`year_shorthand'_IC_only.png", replace width(2500)
    restore


    /*=======================
    Num reimbursements per project
    ========================*/
    gen receipts_ic = receipts if fp_ic == 1
    gen receipts_ic_newconstr = receipts if fp_ic == 1 & has_new_construction == 1
    preserve
    collapse (mean) receipts receipts_ic receipts_ic_newconstr, by(`year_var')
    graph twoway line receipts receipts_ic receipts_ic_newconstr `year_var', sort ///
        title("Average Number of Reimbursements per Project") ///
        ytitle("Reimbursements per Project") ///
        ylabel(, format(%9.0fc)) ///
        xtitle("`year_print'") ///
        xlabel(1950(10)2025) ///
        legend(label(1 "All Projects") label(2 "Interstate Construction" "Projects") label(3 "IC with New Construction")) ///
        note( ///
            "Projects are considered to be interstate if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"New construction is identified by the improvement type code "new construction roadway", "bridge new construction","' ///
            `""maintenance relocation", and "new tunnel"."' ///
            "Projects are considered to be new construction if at least one reimbursement is classified as new construction.", ///
            size(small) span ///
        )
    graph export "$fig_dir/reimb_per_proj_by_`year_shorthand'_w_IC.png", replace width(2500)

    * version with IC only 
    graph twoway line receipts_ic receipts_ic_newconstr `year_var', sort ///
        title("Average Number of Reimbursements per Project") ///
        subtitle("Interstate Construction Funding Only") ///
        ytitle("Reimbursements per Project") ///
        ylabel(, format(%9.0fc)) ///
        xtitle("`year_print'") ///
        xlabel(1950(10)2025) ///
        legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
        lcolor(stc2 stc3) ///
        note( ///
            "Projects are considered to be interstate if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"New construction is identified by the improvement type code "new construction roadway", "bridge new construction","' ///
            `""maintenance relocation", and "new tunnel"."' ///
            "Projects are considered to be new construction if at least one reimbursement is classified as new construction.", ///
            size(small) span ///
        )
    graph export "$fig_dir/reimb_per_proj_by_`year_shorthand'_IC_only.png", replace width(2500)

    * version with IC only, cropped to < 2000 
    keep if `year_var' < 2000
    graph twoway line receipts_ic receipts_ic_newconstr `year_var', sort ///
        title("Average Number of Reimbursements per Project") ///
        subtitle("Interstate Construction Funding Only; `year_print' < 2000") ///
        ytitle("Reimbursements per Project") ///
        ylabel(, format(%9.0fc)) ///
        xtitle("`year_print'") ///
        xlabel(1950(10)2000) ///
        legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
        lcolor(stc2 stc3) ///
        note( ///
            "Projects are considered to be interstate if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"New construction is identified by the improvement type code "new construction roadway", "bridge new construction","' ///
            `""maintenance relocation", and "new tunnel"."' ///
            "Projects are considered to be new construction if at least one reimbursement is classified as new construction.", ///
            size(small) span ///
        )
    graph export "$fig_dir/reimb_per_proj_by_`year_shorthand'_IC_only_pre2000.png", replace width(2500)
    restore


    /*===============================
    Average project cost over time 
    ================================*/

    * adjust for inflation
    rename completion_year year // always use completion year to adjust inflation
    merge m:1 year using "$intermediate_data/CPI_2025.dta", keep(3) nogen
    gen double total_mills_all_adj = total_cost_mills / cpi
    gen double total_mills_ic_adj = total_mills_all_adj if fp_ic == 1
    gen double total_mills_ic_newconstr_adj = total_mills_all_adj if fp_ic == 1 & has_new_construction == 1
    rename year completion_year

    preserve
    collapse (mean) total_mills_all_adj total_mills_ic_adj total_mills_ic_newconstr_adj, by(`year_var')

    graph twoway line total_mills_all_adj total_mills_ic_adj total_mills_ic_newconstr_adj `year_var', sort ///
        title("Average Adjusted Project Cost Over Time") ///
        ytitle("Millions of 2025 USD") ///
        ylabel(, format(%9.0fc)) ///
        xtitle("`year_print'") ///
        xlabel(1950(10)2025) ///
        legend(label(1 "All Projects") label(2 "Interstate Construction") label(3 "IC with New Construction")) ///
        note( ///
            "Projects are considered to be interstate if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"New construction is identified by the improvement type code "new construction roadway", "bridge new construction","' ///
            `""maintenance relocation", and "new tunnel"."' ///
            "Projects are considered to be new construction if at least one reimbursement is classified as new construction." ///
            "Costs are adjusted for inflation using completion year.", ///
            size(small) span ///
        )
    graph export "$fig_dir/avg_project_cost_by_`year_shorthand'_w_IC.png", replace width(2500)


    * version with IC only 
    graph twoway line total_mills_ic_adj total_mills_ic_newconstr_adj `year_var', sort ///
        title("Average Adjusted Project Cost Over Time") ///
        subtitle("Interstate Construction Funding Only") ///
        ytitle("Millions of 2025 USD") ///
        ylabel(, format(%9.0fc)) ///
        xtitle("`year_print'") ///
        xlabel(1950(10)2025) ///
        legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
        lcolor(stc2 stc3) ///
        note( ///
            "Projects are considered to be interstate if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"New construction is identified by the improvement type code "new construction roadway", "bridge new construction","' ///
            `""maintenance relocation", and "new tunnel"."' ///
            "Projects are considered to be new construction if at least one reimbursement is classified as new construction." ///
            "Costs are adjusted for inflation using completion year.", ///
            size(small) span ///
        )
    graph export "$fig_dir/avg_project_cost_by_`year_shorthand'_IC_only.png", replace width(2500)

    * version with IC only, cropped to < 2000 
    keep if `year_var' < 2000
    graph twoway line total_mills_ic_adj total_mills_ic_newconstr_adj `year_var', sort ///
        title("Average Adjusted Project Cost Over Time") ///
        subtitle("Interstate Construction Funding Only; `year_print' < 2000") ///
        ytitle("Millions of 2025 USD") ///
        ylabel(, format(%9.0fc)) ///
        xtitle("`year_print'") ///
        xlabel(1950(10)2000) ///
        legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
        lcolor(stc2 stc3) ///
        note( ///
            "Projects are considered to be interstate if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"New construction is identified by the improvement type code "new construction roadway", "bridge new construction","' ///
            `""maintenance relocation", and "new tunnel"."' ///
            "Projects are considered to be new construction if at least one reimbursement is classified as new construction." ///
            "Costs are adjusted for inflation using completion year.", ///
            size(small) span ///
        )
    graph export "$fig_dir/avg_project_cost_by_`year_shorthand'_IC_only_pre2000.png", replace width(2500)
    restore



    * ==========================================================================
    * Reimbursement-level data
    * ==========================================================================

    /*===============================
    Num reimbursements by year 
    ================================*/
    use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
    gen int authconstyear = year(authconstdate)
    keep if `year_var' >= 1950 & `year_var' < 2025 // filter out years without much data
    gen n_reimb = 1
    gen n_reimb_ic = 1 if funding_program == "Interstate Construction"
    gen n_reimb_ic_newconstr = 1 if funding_program == "Interstate Construction" & new_construction

    preserve
    collapse (sum) n_reimb n_reimb_ic n_reimb_ic_newconstr, by(`year_var')
    graph twoway line n_reimb n_reimb_ic n_reimb_ic_newconstr `year_var', sort /// 
        title("Number of Reimbursements Over Time") ///
        ytitle("Number of Reimbursements") ///
        ylabel(, format(%9.0fc)) ///
        xtitle("`year_print'") ///
        xlabel(1950(10)2025) ///
        legend(label(1 "All Reimbursements") label(2 "Interstate Construction") label(3 "IC New Construction")) ///
        note( ///
            "Interstate construction reimbursements are identified by the 'Interstate Construction' funding program codes." ///
            "New construction reimbursements are new construction roadway, bridge new construction," ///
            "maintenance relocation, or new tunnel.", ///
            size(small) span ///
        )
    graph export "$fig_dir/num_reimb_by_`year_shorthand'_w_IC.png", replace width(2500)


    * version with IC only 
    graph twoway line n_reimb_ic n_reimb_ic_newconstr `year_var', sort ///
        title("Number of Reimbursements Over Time") ///
        subtitle("Interstate Construction Funding Only") ///
        ytitle("Number of Reimbursements") ///
        ylabel(, format(%9.0fc)) ///
        xtitle("`year_print'") ///
        xlabel(1950(10)2025) ///
        legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
        lcolor(stc2 stc3) ///
        note( ///
            "Interstate construction reimbursements are identified by the 'Interstate Construction' funding program codes." ///
            "New construction reimbursements are new construction roadway, bridge new construction," ///
            "maintenance relocation, or new tunnel.", ///
            size(small) span ///
        )
    graph export "$fig_dir/num_reimb_by_`year_shorthand'_IC_only.png", replace width(2500)
    restore


    /*===============================
    Average reimbursement cost over time
    ================================*/
    * adjust for inflation
    rename completion_year year // always use completion year to adjust inflation
    merge m:1 year using "$intermediate_data/CPI_2025.dta", nogen
    gen total_mills_all_adj = total_cost_mills / cpi
    gen total_mills_ic_adj = total_mills_all_adj if funding_program == "Interstate Construction"
    gen total_mills_ic_newconstr_adj = total_mills_all_adj if funding_program == "Interstate Construction" & new_construction
    rename year completion_year

    preserve
    collapse (mean) total_mills_all_adj total_mills_ic_adj total_mills_ic_newconstr_adj, by(`year_var')

    graph twoway line total_mills_all_adj total_mills_ic_adj total_mills_ic_newconstr_adj `year_var', sort ///
        title("Average Adjusted Reimbursement Cost Over Time") ///
        ytitle("Millions of 2025 USD") ///
        xtitle("`year_print'") ///
        xlabel(1950(10)2025) ///
        ylabel(, format(%9.0fc)) ///
        legend(label(1 "All Reimbursements") label(2 "Interstate Construction") label(3 "IC with New Construction")) ///
        note( ///
            "Interstate construction reimbursements are identified by the 'Interstate Construction' funding program codes. " ///
            "New construction reimbursements are new construction roadway, bridge new construction," ///
            "maintenance relocation, or new tunnel." ///
            "Costs are adjusted for inflation using completion year.", ///
            size(small) span ///
        )
    graph export "$fig_dir/avg_reimb_cost_by_`year_shorthand'_w_IC.png", replace width(2500)

    * version with IC only 
    graph twoway line total_mills_ic_adj total_mills_ic_newconstr_adj `year_var', sort ///
        title("Average Adjusted Reimbursement Cost Over Time") ///
        subtitle("Interstate Construction Funding Only") ///
        ytitle("Millions of 2025 USD") ///
        ylabel(, format(%9.0fc)) ///
        xtitle("`year_print'") ///
        xlabel(1950(10)2025) ///
        legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
        lcolor(stc2 stc3) ///
        note( ///
            "Interstate construction reimbursements are identified by the 'Interstate Construction' funding program codes." ///
            "New construction reimbursements are new construction roadway, bridge new construction," ///
            "maintenance relocation, or new tunnel." ///
            "Costs are adjusted for inflation using completion year.", ///
            size(small) span ///
        )
    graph export "$fig_dir/avg_reimb_cost_by_`year_shorthand'_IC_only.png", replace width(2500)


    * version with IC only, cropped to < 2000 
    keep if `year_var' < 2000
    graph twoway line total_mills_ic_adj total_mills_ic_newconstr_adj `year_var', sort ///
        title("Average Adjusted Reimbursement Cost Over Time") ///
        subtitle("Interstate Construction Funding Only; `year_print' < 2000") ///
        ytitle("Millions of 2025 USD") ///
        xtitle("`year_print'") ///
        ylabel(, format(%9.0fc)) ///
        xlabel(1950(10)2000) ///
        legend(label(1 "Interstate Construction") label(2 "IC with New Construction")) ///
        lcolor(stc2 stc3) ///
        note( ///
            "Interstate construction reimbursements are identified by the 'Interstate Construction' funding program codes." ///
            "New construction reimbursements are new construction roadway, bridge new construction," ///
            "maintenance relocation, or new tunnel." ///
            "Costs are adjusted for inflation using completion year.", ///
            size(small) span ///
        )
    graph export "$fig_dir/avg_reimb_cost_by_`year_shorthand'_IC_only_pre2000.png", replace width(2500)
    restore
}

// Average number of receipts for each project code (project ID or project work type?). 
// Average number of receipts per project for each project code (project ID or project work type?). (projects usually have multiple work types and sometimes have multiple federal aid system codes, so there isn't a great way to do this.)

* ==============================================================================

