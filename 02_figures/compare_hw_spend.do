/*==============================================================================
 	FMIS data exploration
 	Hannah Lu 
	02/24/2026

	This script generates exploratory figures on highway spending costs.
==============================================================================*/
* Set user
local user = c(username)
if "`user'" == "andersonkovesci" {
	global output "/Users/andersonkovesci/Dropbox/FHWA cost data/FMIS_graphs"
	global raw_data "/Users/andersonkovesci/Dropbox/FHWA cost data/Data/Raw"
	global intermediate_data "/Users/andersonkovesci/Dropbox/FHWA cost data/Data/Intermediate"
}
else if "`user'" == "hl2266" {
    global output "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data/Output/Hannah"
	global raw_data "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data/Data/Raw"
	global intermediate_data "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data/Data/Intermediate"
}
* add your username and paths here as an else if condition
else {
	 display as error "Set your user"
}
* check that output folders exist and create them if not 
if !direxists("$output") mkdir "$output"
if !direxists("$intermediate_data") mkdir "$intermediate_data"
* ==============================================================================
// TODO add note that FMIS year data is all using completion year 


* load FMIS data
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
rename completion_year year
rename total_cost_mills total_fmis_cost_mills
rename federal_funds fmis_fed
rename state_funds fmis_state
rename local_funds fmis_local
rename private_funds fmis_private
rename nonmonetary_funds fmis_nonmonetary
rename other_funds fmis_other
gen interstate_func_cost_mills = total_fmis_cost_mills if interstate_functional == 1
gen interstate_syscode_cost_mills = total_fmis_cost_mills if interstate_syscode == 1
collapse (sum) total_fmis_cost_mills interstate_func_cost_mills interstate_syscode_cost_mills fmis_fed fmis_state fmis_local fmis_private fmis_nonmonetary fmis_other, by(year)
keep year total_fmis_cost_mills interstate_func_cost_mills interstate_syscode_cost_mills fmis_fed fmis_state fmis_local fmis_private fmis_nonmonetary fmis_other

* merge in cpi data and adjust for inflation
merge 1:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_fmis_cost_mills_adj = total_fmis_cost_mills / cpi
gen fmis_fed_adj = fmis_fed / cpi
gen fmis_state_adj = fmis_state / cpi
gen fmis_local_adj = fmis_local / cpi
gen fmis_private_adj = fmis_private / cpi
gen fmis_nonmonetary_adj = fmis_nonmonetary / cpi
gen fmis_other_adj = fmis_other / cpi

gen int_func_cost_mills_adj = interstate_func_cost_mills / cpi
gen int_syscode_cost_mills_adj = interstate_syscode_cost_mills / cpi

* merge in total national highway spending data
merge 1:1 year using "$intermediate_data/FHWA_Highway_Statistics/total_hw_spend.dta", nogen

* convert to billions
gen total_hw_spend_bills_adj = total_hw_spend_mills_adj / 1000
gen total_fmis_cost_bills_adj = total_fmis_cost_mills_adj / 1000
gen fmis_fed_bills_adj = fmis_fed_adj / 1000000000
gen fmis_state_bills_adj = fmis_state_adj / 1000000000
gen fmis_local_bills_adj = fmis_local_adj / 1000000000
gen fmis_private_bills_adj = fmis_private_adj / 1000000000
gen fmis_nonmonetary_bills_adj = fmis_nonmonetary_adj / 1000000000
gen fmis_other_bills_adj = fmis_other_adj / 1000000000

gen int_func_cost_bills_adj = int_func_cost_mills_adj / 1000
gen int_syscode_cost_bills_adj = int_syscode_cost_mills_adj / 1000
gen cap_bills_adj = cap_mills_adj / 1000
gen maint_bills_adj = maint_mills_adj / 1000
gen admin_law_int_bills_adj = admin_law_int_mills_adj / 1000
gen debt_retire_bills_adj = debt_retire_mills_adj / 1000

* drop data from early and late years 
drop if total_hw_spend_bills_adj == . | total_fmis_cost_bills_adj == .

********************************************************************************
* Figures 
********************************************************************************


// /*====
//  Total highway spending in the US (all levels of government)
// ====*/
// graph twoway line total_hw_spend_bills_adj year, ///
// 	title("Total US Highway Spending, All Levels of Government") ///
// 	ytitle("Billions of 2025 USD") ///
// 	xtitle("Year") ///
// 	note( ///
// 		"Includes spending by federal, state, and local governments." ///
// 		"Spending categories encompass capital outlays, maintenance, administrative costs (including general overhead, " ///
// 		"engineering, research, planning, highway litigation, and highway publications), law enforcement, bond " ///
// 		"interest, and debt retirement. " ///
// 		"Source: FHWA Tables DISCHT (1945-2001) and DISB-C (2000-2023).", ///
// 		size(small) span ///
// 	)
// graph export "$output/total_hw_spend.png", replace width(2500)


// /*====
//  Total highway spending in US by category vs federal interstate construction spending only
// ====*/
// graph twoway ///
// 	(line cap_bills_adj year) ///
// 	(line maint_bills_adj year) ///
// 	(line admin_law_int_bills_adj year) ///
// 	(line debt_retire_bills_adj year) ///
// 	(line FED_INT_CONST_EXP_fa3_bills_2025 year), ///
// 	title("US Highway Spending: Total vs. Federal Interstate Construction") ///
// 	ytitle("Billions of 2025 USD", xoffset(-4)) ///
// 	xtitle("Year") ///
// 	legend(label(1 "Total Capital Outlays") label(2 "Total Maintenance") label(3 "Total Administrative," "Law Enforcement," "Bond Interest") label(4 "Total Debt Retirement") label(5 "Federal Interstate" "Construction Only")) ///
// 	note( ///
// 		"Source: Total spending categories from FHWA Tables DISCHT (1945-2001) and DISB-C (2000-2023). " ///
// 		"Federal interstate construction spending from FHWA Table FA3." ///
// 		"Administrative costs include general overhead, engineering, research, planning, litigation, and publications.", ///
// 		size(small) span ///
// 	) ///
// 	graphregion(margin(l=15 r=15))
// graph export "$output/total_hw_spend_by_category_w_fed_interstates.png", replace width(2500)


// /*====
//  Spending captured by FMIS
// ====*/
// graph twoway line total_fmis_cost_bills_adj year, ///
// 	title("Total Spending Captured by FMIS") ///
// 	ytitle("Billions of 2025 USD") ///
// 	xtitle("Completion Year")
// graph export "$output/total_fmis_cost.png", replace width(2500)


// /*====
//  Spending captured by FMIS by source
// ====*/ 
// graph twoway ///
// 	(line fmis_fed_bills_adj year) ///
// 	(line fmis_state_bills_adj year) ///
// 	(line fmis_local_bills_adj year) ///
// 	(line fmis_private_bills_adj year) ///
// 	(line fmis_nonmonetary_bills_adj year) ///
// 	(line fmis_other_bills_adj year), ///
// 	title("Spending Captured by FMIS, by Source") ///
// 	ytitle("Billions of 2025 USD") ///
// 	xtitle("Completion Year") ///
// 	legend(label(1 "Federal") label(2 "State") label(3 "Local") label(4 "Private") label(5 "Non-Monetary") label(6 "Other"))
// graph export "$output/fmis_costs_by_source.png", replace width(2500)


// /*====
//  Federal reimbursement share over time (dollar amounts)
// ====*/
// graph twoway /// 
// 	(line total_fmis_cost_bills_adj year) ///
//     (line fmis_fed_bills_adj year), ///
// 	title("Federal Reimbursement of Projects in FMIS") ///
// 	ytitle("Billions of 2025 USD") ///
// 	xtitle("Completion Year") ///
// 	legend(label(1 "Total Spending") label(2 "Federal Spending"))
// graph export "$output/fed_portion_of_fmis_spending.png", replace width(2500)


// /*====
//  Federal reimbursement share over time (percentage of total)
// ====*/
// preserve 
// gen pct = 100 * fmis_fed_bills_adj / total_fmis_cost_bills_adj
// graph twoway /// 
// 	(line pct year), ///
// 	title("Federal Reimbursement Share of Total FMIS Spending") ///
// 	ytitle("% of Total Spending") ///
// 	xtitle("Completion Year") ///
// 	yscale(range(0 100)) ylabel(0(10)100)
// graph export "$output/fed_portion_of_fmis_spending_pct.png", replace width(2500)
// restore 

// preserve 
// /*====
//  Federal reimbursement share over time (dollar amounts) for interstate 
// ====*/
// * load project-level data 
// use "$intermediate_data/project_level_FMIS_lite.dta", clear
// keep if interstate_syscode == 1
// rename completion_year year
// collapse (sum) total_cost_mills federal_funds state_funds local_funds private_funds nonmonetary_funds other_funds, by(year)
// * adjust for inflation 
// merge 1:1 year using "$intermediate_data/CPI_2025.dta", keep(3) keepusing(cpi) nogen
// gen total_cost_bills_adj = total_cost_mills / cpi / 1000
// gen federal_funds_bills_adj = federal_funds / cpi / 1000000000
// gen state_funds_bills_adj = state_funds / cpi / 1000000000
// gen local_funds_bills_adj = local_funds / cpi / 1000000000
// gen private_funds_bills_adj = private_funds / cpi / 1000000000
// gen nonmonetary_funds_bills_adj = nonmonetary_funds / cpi / 1000000000
// gen other_funds_bills_adj = other_funds / cpi / 1000000000

// graph twoway ///
// 	(line federal_funds_bills_adj year) ///
// 	(line state_funds_bills_adj year) ///
// 	(line local_funds_bills_adj year) ///
// 	(line private_funds_bills_adj year) ///
// 	(line nonmonetary_funds_bills_adj year) ///
// 	(line other_funds_bills_adj year), ///
// 	title("Interstate Spending Captured by FMIS, by Source") ///
// 	ytitle("Billions of 2025 USD") ///
// 	xtitle("Completion Year") ///
// 	legend(label(1 "Federal Spending") label(2 "State Spending") label(3 "Local Spending") label(4 "Private Spending") label(5 "Non-Monetary Spending") label(6 "Other Spending")) ///
// 	note( ///
// 		"Interstate classification is defined by federal aid system code.", ///
// 		size(small) span ///
// 	) ///
// 	graphregion(margin(l=15 r=15))
// graph export "$output/fmis_costs_by_source_interstate.png", replace width(2500)

// /*====
//  Federal reimbursement share over time (dollar amounts) for interstate
// ====*/
// graph twoway /// 
// 	(line total_cost_bills_adj year) ///
//     (line federal_funds_bills_adj year), ///
// 	title("Federal Reimbursement of Interstate Projects in FMIS") ///
// 	ytitle("Billions of 2025 USD") ///
// 	xtitle("Completion Year") ///
// 	legend(label(1 "Total Spending") label(2 "Federal Spending")) ///
// 	note( ///
// 		"Interstate classification is defined by federal aid system code.", ///
// 		size(small) span ///
// 	) ///
// 	graphregion(margin(l=15 r=15))
// graph export "$output/fed_portion_of_fmis_spending_interstate.png", replace width(2500)

// /*====
//  Federal reimbursement share over time (percentage of total)
// ====*/
// gen pct = 100 * federal_funds_bills_adj / total_cost_bills_adj
// graph twoway /// 
// 	(line pct year), ///
// 	title("Federal Reimbursement Share of Interstate" "Projects in FMIS") ///
// 	ytitle("% of Total Interstate Spending") ///
// 	xtitle("Completion Year") ///
// 	yscale(range(0 100)) ylabel(0(10)100) ///
// 	note( ///
// 		"Interstate classification is defined by federal aid system code.", ///
// 		size(small) span ///
// 	) ///
// 	graphregion(margin(l=15 r=15))
// graph export "$output/fed_portion_of_fmis_spending_pct_interstate.png", replace width(2500)

// restore 

/*====
 Federal reimbursement share over time (percentage): combined all FMIS and interstate
====*/
gen pct_all = 100 * fmis_fed_bills_adj / total_fmis_cost_bills_adj

preserve
use "$intermediate_data/project_level_FMIS_lite.dta", clear
keep if interstate_syscode == 1
rename completion_year year
collapse (sum) total_cost_mills federal_funds, by(year)
merge 1:1 year using "$intermediate_data/CPI_2025.dta", keep(3) keepusing(cpi) nogen
gen total_cost_bills_adj = total_cost_mills / cpi / 1000
gen federal_funds_bills_adj = federal_funds / cpi / 1000000000
gen pct_interstate = 100 * federal_funds_bills_adj / total_cost_bills_adj
keep year pct_interstate
tempfile interstate_pct
save `interstate_pct'
restore

merge 1:1 year using `interstate_pct', nogen

graph twoway /// 
	(line pct_all year) ///
	(line pct_interstate year), ///
	title("Federal Reimbursement Share of FMIS Spending") ///
	ytitle("% of Total Spending") ///
	xtitle("Completion Year") ///
	yscale(range(0 100)) ylabel(0(10)100) ///
	legend(order(2 1) label(1 "All FMIS Projects") label(2 "Interstate Projects")) ///
	note("Interstate classification is defined by federal aid system code.", size(small) span) ///
	graphregion(margin(l=15 r=15))
graph export "$output/fed_portion_of_fmis_spending_pct_combined.png", replace width(2500)

drop pct_all pct_interstate

exit 

/*====
 Total spending in the US vs in FMIS
====*/
graph twoway ///
    (line total_fmis_cost_bills_adj year) ///
    (line total_hw_spend_bills_adj year), ///
    title("Total US Highway Spending vs. Spending Captured by FMIS") ///
    ytitle("Billions of 2025 USD") ///
	xtitle("Year") ///
	note( ///
		"Includes spending by federal, state, and local governments." ///
		"Total national spending categories encompass capital outlays, maintenance, administrative costs (including general overhead, " ///
		"engineering, research, planning, highway litigation, and highway publications), law enforcement, bond interest, " ///
		"and debt retirement. " ///
		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year." ///
        "Total national spending data from FHWA Tables DISCHT (1945-2001) and DISB-C (2000-2023).", ///
		size(small) span ///
	) ///
    legend(order(2 "National Total" 1 "FMIS")) ///
    ylabel(, format(%12.0fc)) 
graph export "$output/total_hw_spend_vs_FMIS.png", replace width(2500)


/*====
 Total spending in the US by category vs in FMIS
====*/
graph twoway ///
    (line total_fmis_cost_bills_adj year) ///
    (line cap_bills_adj year) ///
    (line maint_bills_adj year) ///
    (line admin_law_int_bills_adj year) ///
    (line debt_retire_bills_adj year), ///
    title("Total US Highway Spending vs Spending Captured by FMIS") ///
    ytitle("Billions of 2025 USD") ///
	xtitle("Year") ///
	legend(label(1 "FMIS") label(2 "Total Capital Outlays") label(3 "Total Maintenance") label(4 "Total Administrative," "Law Enforcement," "Bond Interest") label(5 "Total Debt Retirement")) ///
	note( ///
        "Total national spending data from FHWA Tables DISCHT (1945-2001) and DISB-C (2000-2023)." ///
		"Administrative costs include general overhead, engineering, research, planning, litigation, and publications." ///
		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year.", ///
		size(small) span ///
	) ///
	graphregion(margin(l=15 r=15))
graph export "$output/total_hw_spend_by_category_vs_FMIS.png", replace width(2500)

/*====
 Total spending in the US by category vs in FMIS vs fed interstate construction
====*/
graph twoway ///
    (line total_fmis_cost_bills_adj year) ///
    (line cap_bills_adj year) ///
    (line maint_bills_adj year) ///
    (line admin_law_int_bills_adj year) ///
    (line debt_retire_bills_adj year) ///
    (line FED_INT_CONST_EXP_fa3_bills_2025 year), ///
    title("US Highway Spending: Total vs Spending Captured by FMIS") ///
    ytitle("Billions of 2025 USD", xoffset(-4)) ///
	xtitle("Year") ///
	legend(label(1 "FMIS*") label(2 "Capital Outlays*") label(3 "Maintenance*") label(4 "Administrative,**" "Law Enforcement," "Bond Interest*") label(5 "Debt Retirement*") label(6 "Interstate Construction," "Federal Expenditures Only***")) ///
	note( ///
        "Total national spending data from FHWA Tables DISCHT (1945-2001) and DISB-C (2000-2023)." ///
		"Federal interstate construction spending from FHWA Table FA3." ///
		"* Totals are for all levels of government." ///
		"**Administrative costs include general overhead, engineering, research, planning, litigation, and publications." ///
		"***Federal interstate expenditures are administered by the FHWA and exclude primary, secondary, and urban" ///
		"roads, as well as planning and research, highway safety, bridge replacement, beautification, and other" ///
		"miscellaneous expenditures. " ///
		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year.", ///
		size(small) span ///
	) ///
	graphregion(margin(l=15 r=15))
graph export "$output/total_hw_spend_by_category_vs_FMIS_w_fed_int.png", replace width(2500)


/*====
 Fed interstate construction vs FMIS interstate (functional class) vs FMIS interstate (system code)
====*/
graph twoway ///
    (line FED_INT_CONST_EXP_fa3_bills_2025 year) ///
    (line int_func_cost_bills_adj year) ///
    (line int_syscode_cost_bills_adj year), ///
    title("Comparison of Interstate Spending between FHWA and FMIS") ///
    ytitle("Billions of 2025 USD", xoffset(-3)) ///
    xtitle("Year") ///
    legend(label(1 "FHWA Federal Interstate" "Construction Expenditures") label(2 "FMIS Interstate" "Functional Class") label(3 "FMIS Interstate" "System Code")) ///
	legend(order(1 3 2)) ///
    note( ///
        "Federal interstate construction spending from FHWA Table FA3." ///
        "FMIS data includes all project costs across multiple levels of government." ///
		"Interstate projects are classified in multiple ways. A functional classification indicates the roadway segment" ///
		"meets the functional definitions of an interstate highway. The system code classification is likely an" ///
		"administrative designation about funding eligibility." ///
		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year.", ///
		size(small) span ///
	) ///
	graphregion(margin(l=15 r=15))
graph export "$output/interstate_comparison.png", replace width(2500)

/*====
 Ratio of FHWA federal interstate spending to FMIS interstate spending (federal aid system code)
====*/
gen fmis_fhwa_interstate_ratio = int_syscode_cost_bills_adj / FED_INT_CONST_EXP_fa3_bills_2025

graph twoway line fmis_fhwa_interstate_ratio year, ///
	title("Ratio of FMIS to FHWA Interstate Spending") ///
	ytitle("Ratio") ///
	xtitle("Year") ///
	note( ///
		"FHWA interstate spending is sourced from Table FA3." ///
		"FMIS interstate classification is defined by federal aid system code." ///
		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year.", ///
		size(small) span ///
	)
graph export "$output/fmis_fhwa_interstate_ratio.png", replace width(2500)


/*====
 Total spending in the US by category vs in FMIS vs interstate only
====*/
graph twoway ///
    (line total_fmis_cost_bills_adj year) ///
    (line cap_bills_adj year) ///
    (line maint_bills_adj year) ///
    (line admin_law_int_bills_adj year) ///
    (line debt_retire_bills_adj year) ///
	(line FED_INT_CONST_EXP_fa3_bills_2025 year) ///
    (line int_syscode_cost_bills_adj year), ///
    title("US Highway Spending Comparisons") ///
    ytitle("Billions of 2025 USD", xoffset(-3)) ///
	xtitle("Year") ///
	legend(label(1 "FMIS Total*") label(2 "Capital Outlays*") label(3 "Maintenance*") label(4 "Administrative,**" "Law Enforcement," "Bond Interest*") label(5 "Debt Retirement*") label(6 "Interstate Construction," "Federal Expenditures Only***") label(7 "FMIS Interstate" "(System Code)****")) ///
	note( ///
        "Total national spending data from FHWA Tables DISCHT (1945-2001) and DISB-C (2000-2023)." ///
		"Federal interstate construction spending from FHWA Table FA3." ///
		"* Totals are for all levels of government." ///
		"** Administrative costs include general overhead, engineering, research, planning, litigation, and publications." ///
		"*** Federal interstate expenditures are administered by the FHWA and exclude primary, secondary, and urban" ///
		"roads, as well as planning and research, highway safety, bridge replacement, beautification, and other" ///
		"miscellaneous expenditures. " ///	
		"**** This FMIS classification of interstate highways is likely based on project funding eligibility rather" "than roadway functionality." ///
		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year.", ///
		size(small) span ///
	) ///
	graphregion(margin(l=10 r=10))
graph export "$output/total_hw_spend_by_category_vs_FMIS_vs_int.png", replace width(2500)


* ==============================================================================
* Compare spending by level of government
* ==============================================================================

* FMIS costs by level of government


* FHWA costs by level of government 