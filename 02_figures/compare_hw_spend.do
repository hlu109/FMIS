/*==============================================================================
 	FMIS data exploration
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

// * load FMIS data
// use "$intermediate_data/receipt_level_FMIS_lite_program_codes.dta", clear
// rename completion_year year
// rename total_cost_mills total_fmis_cost_mills
// rename federal_funds fmis_fed
// rename state_funds fmis_state
// rename local_funds fmis_local
// rename private_funds fmis_private
// rename nonmonetary_funds fmis_nonmonetary
// rename other_funds fmis_other
// gen interstate_func_cost_mills = total_fmis_cost_mills if interstate_functional == 1
// gen interstate_syscode_cost_mills = total_fmis_cost_mills if interstate_syscode == 1
// gen fp_ic_cost_mills = total_fmis_cost_mills if funding_program == "Interstate Construction"
// gen fp_im_cost_mills = total_fmis_cost_mills if funding_program == "Interstate Maintenance"
// gen fp_imd_cost_mills = total_fmis_cost_mills if funding_program == "Interstate Maintenance Discretionary"
// gen fp_nhpp_cost_mills = total_fmis_cost_mills if funding_program == "National Highway Performance Program"
// collapse (sum) total_fmis_cost_mills interstate_func_cost_mills interstate_syscode_cost_mills fp_ic_cost_mills fp_im_cost_mills fp_imd_cost_mills fp_nhpp_cost_mills fmis_fed fmis_state fmis_local fmis_private fmis_nonmonetary fmis_other, by(year)
// keep year total_fmis_cost_mills interstate_func_cost_mills interstate_syscode_cost_mills fp_ic_cost_mills fp_im_cost_mills fp_imd_cost_mills fp_nhpp_cost_mills fmis_fed fmis_state fmis_local fmis_private fmis_nonmonetary fmis_other

// * merge in cpi data and adjust for inflation
// merge 1:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
// gen total_fmis_cost_mills_adj = total_fmis_cost_mills / cpi
// gen fmis_fed_adj = fmis_fed / cpi
// gen fmis_state_adj = fmis_state / cpi
// gen fmis_local_adj = fmis_local / cpi
// gen fmis_private_adj = fmis_private / cpi
// gen fmis_nonmonetary_adj = fmis_nonmonetary / cpi
// gen fmis_other_adj = fmis_other / cpi

// gen int_func_cost_mills_adj = interstate_func_cost_mills / cpi
// gen int_syscode_cost_mills_adj = interstate_syscode_cost_mills / cpi
// gen fp_ic_cost_mills_adj = fp_ic_cost_mills / cpi
// gen fp_im_cost_mills_adj = fp_im_cost_mills / cpi
// gen fp_imd_cost_mills_adj = fp_imd_cost_mills / cpi
// gen fp_nhpp_cost_mills_adj = fp_nhpp_cost_mills / cpi

// * merge in total national highway spending data
// merge 1:1 year using "$intermediate_data/FHWA_Highway_Statistics/total_hw_spend.dta", nogen

// * convert to billions
// gen total_hw_spend_bills_adj = total_hw_spend_mills_adj / 1000
// gen total_fmis_cost_bills_adj = total_fmis_cost_mills_adj / 1000
// gen fmis_fed_bills_adj = fmis_fed_adj / 1000000000
// gen fmis_state_bills_adj = fmis_state_adj / 1000000000
// gen fmis_local_bills_adj = fmis_local_adj / 1000000000
// gen fmis_private_bills_adj = fmis_private_adj / 1000000000
// gen fmis_nonmonetary_bills_adj = fmis_nonmonetary_adj / 1000000000
// gen fmis_other_bills_adj = fmis_other_adj / 1000000000

// gen int_func_cost_bills_adj = int_func_cost_mills_adj / 1000
// gen int_syscode_cost_bills_adj = int_syscode_cost_mills_adj / 1000
// gen fp_ic_cost_bills_adj = fp_ic_cost_mills_adj / 1000
// gen fp_im_cost_bills_adj = fp_im_cost_mills_adj / 1000
// gen fp_imd_cost_bills_adj = fp_imd_cost_mills_adj / 1000
// gen fp_nhpp_cost_bills_adj = fp_nhpp_cost_mills_adj / 1000
// gen cap_bills_adj = cap_mills_adj / 1000
// gen maint_bills_adj = maint_mills_adj / 1000
// gen admin_law_int_bills_adj = admin_law_int_mills_adj / 1000
// gen debt_retire_bills_adj = debt_retire_mills_adj / 1000

// * drop data from early and late years 
// drop if total_hw_spend_bills_adj == . | total_fmis_cost_bills_adj == .

// ********************************************************************************
// * Figures 
// ********************************************************************************


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
// 	(line FA3_interstate_adj_bills year), ///
// 	title("US Highway Spending: Total vs. Federal Interstate Construction") ///
// 	ytitle("Billions of 2025 USD", xoffset(-4)) ///
// 	xtitle("Year") ///
// 	legend(label(1 "Total Capital Outlays") label(2 "Total Maintenance") label(3 "Total Administrative," "Law Enforcement," "Bond Interest") label(4 "Total Debt Retirement") label(5 "FHWA Federal Interstate")) ///
// 	note( ///
// 		"Source: Total spending categories from FHWA Tables DISCHT (1945-2001) and DISB-C (2000-2023). " ///
// 		"Federal interstate construction spending from FHWA Table FA3." ///
// 		"Starting in 1992, FA3 data is reported in fiscal years. In 1990-1991, FA3 data is reported in calendar years." ///
// 		"I have not verified calendar vs fiscal year for earlier years of FA3 data." ///
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

// restore 

// /*====
//  Federal reimbursement share over time (percentage): combined all FMIS and interstate
// ====*/
// gen pct_all = 100 * fmis_fed_bills_adj / total_fmis_cost_bills_adj

// preserve
// use "$intermediate_data/project_level_FMIS_lite.dta", clear
// keep if interstate_syscode == 1
// rename completion_year year
// collapse (sum) total_cost_mills federal_funds, by(year)
// merge 1:1 year using "$intermediate_data/CPI_2025.dta", keep(3) keepusing(cpi) nogen
// gen total_cost_bills_adj = total_cost_mills / cpi / 1000
// gen federal_funds_bills_adj = federal_funds / cpi / 1000000000
// gen pct_interstate = 100 * federal_funds_bills_adj / total_cost_bills_adj
// keep year pct_interstate
// tempfile interstate_pct
// save `interstate_pct'
// restore

// merge 1:1 year using `interstate_pct', nogen

// graph twoway /// 
// 	(line pct_all year) ///
// 	(line pct_interstate year), ///
// 	title("Federal Reimbursement Share of FMIS Spending") ///
// 	ytitle("% of Total Spending") ///
// 	xtitle("Completion Year") ///
// 	yscale(range(0 100)) ylabel(0(10)100) ///
// 	legend(order(2 1) label(1 "All FMIS Projects") label(2 "Interstate Projects")) ///
// 	note("Interstate classification is defined by federal aid system code.", size(small) span) ///
// 	graphregion(margin(l=15 r=15))
// graph export "$output/fed_portion_of_fmis_spending_pct_combined.png", replace width(2500)

// drop pct_all pct_interstate


// /*====
//  Total spending in the US vs in FMIS
// ====*/
// graph twoway ///
//     (line total_fmis_cost_bills_adj year) ///
//     (line total_hw_spend_bills_adj year), ///
//     title("Total US Highway Spending vs. Spending Captured by FMIS") ///
//     ytitle("Billions of 2025 USD") ///
// 	xtitle("Year") ///
// 	note( ///
// 		"Includes spending by federal, state, and local governments." ///
// 		"Total national spending categories encompass capital outlays, maintenance, administrative costs (including general overhead, " ///
// 		"engineering, research, planning, highway litigation, and highway publications), law enforcement, bond interest, " ///
// 		"and debt retirement. " ///
// 		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year." ///
//         "Total national spending data from FHWA Tables DISCHT (1945-2001) and DISB-C (2000-2023).", ///
// 		size(small) span ///
// 	) ///
//     legend(order(2 "National Total" 1 "FMIS")) ///
//     ylabel(, format(%12.0fc)) 
// graph export "$output/total_hw_spend_vs_FMIS.png", replace width(2500)


// /*====
//  Total spending in the US by category vs in FMIS
// ====*/
// graph twoway ///
//     (line total_fmis_cost_bills_adj year) ///
//     (line cap_bills_adj year) ///
//     (line maint_bills_adj year) ///
//     (line admin_law_int_bills_adj year) ///
//     (line debt_retire_bills_adj year), ///
//     title("Total US Highway Spending vs Spending Captured by FMIS") ///
//     ytitle("Billions of 2025 USD") ///
// 	xtitle("Year") ///
// 	legend(label(1 "FMIS") label(2 "Total Capital Outlays") label(3 "Total Maintenance") label(4 "Total Administrative," "Law Enforcement," "Bond Interest") label(5 "Total Debt Retirement")) ///
// 	note( ///
//         "Total national spending data from FHWA Tables DISCHT (1945-2001) and DISB-C (2000-2023)." ///
// 		"Administrative costs include general overhead, engineering, research, planning, litigation, and publications." ///
// 		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year.", ///
// 		size(small) span ///
// 	) ///
// 	graphregion(margin(l=15 r=15))
// graph export "$output/total_hw_spend_by_category_vs_FMIS.png", replace width(2500)

// /*====
//  Total spending in the US by category vs in FMIS vs fed interstate construction
// ====*/
// graph twoway ///
//     (line total_fmis_cost_bills_adj year) ///
//     (line cap_bills_adj year) ///
//     (line maint_bills_adj year) ///
//     (line admin_law_int_bills_adj year) ///
//     (line debt_retire_bills_adj year) ///
//     (line FA3_interstate_adj_bills year), ///
//     title("US Highway Spending: Total vs Spending Captured by FMIS") ///
//     ytitle("Billions of 2025 USD", xoffset(-4)) ///
// 	xtitle("Year") ///
// 	legend(label(1 "FMIS*") label(2 "Capital Outlays*") label(3 "Maintenance*") label(4 "Administrative,**" "Law Enforcement," "Bond Interest*") label(5 "Debt Retirement*") label(6 "FHWA Federal Interstate***")) ///
// 	note( ///
//         "Total national spending data from FHWA Tables DISCHT (1945-2001) and DISB-C (2000-2023)." ///
// 		"Federal interstate expenditures from FHWA Table FA3." ///
// 		"Starting in 1992, FA3 data is reported in fiscal years. In 1990-1991, FA3 data is reported in calendar years." ///
// 		"I have not verified calendar vs fiscal year for earlier years of FA3 data." ///
// 		"* Totals are for all levels of government." ///
// 		"**Administrative costs include general overhead, engineering, research, planning, litigation, and publications." ///
// 		"***Federal interstate expenditures are administered by the FHWA and exclude primary, secondary, and urban" ///
// 		"roads, as well as planning and research, highway safety, bridge replacement, beautification, and other" ///
// 		"miscellaneous expenditures. " ///
// 		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year.", ///
// 		size(small) span ///
// 	) ///
// 	graphregion(margin(l=15 r=15))
// graph export "$output/total_hw_spend_by_category_vs_FMIS_w_fed_int.png", replace width(2500)


// /*====
//  Fed interstate construction vs FMIS interstate (functional class) vs FMIS interstate (system code)
// ====*/
// graph twoway ///
//     (line FA3_interstate_adj_bills year) ///
//     (line int_func_cost_bills_adj year) ///
//     (line int_syscode_cost_bills_adj year), ///
//     title("Comparison of Interstate Spending between FHWA and FMIS") ///
//     ytitle("Billions of 2025 USD", xoffset(-3)) ///
//     xtitle("Year") ///
//     legend(label(1 "FHWA Federal Interstate" "(FA3)") label(2 "FMIS Interstate" "Functional Class") label(3 "FMIS Interstate" "System Code")) ///
// 	legend(order(1 3 2)) ///
//     note( ///
//         "Federal interstate expenditures from FHWA Table FA3." ///
//         "FMIS data includes all project costs across multiple levels of government." ///
// 		"Starting in 1992, FA3 data is reported in fiscal years. In 1990-1991, FA3 data is reported in calendar years." ///
// 		"I have not verified calendar vs fiscal year for earlier years of FA3 data." ///
// 		"Interstate projects are classified in multiple ways. A functional classification indicates the roadway segment" ///
// 		"meets the functional definitions of an interstate highway. The system code classification is likely an" ///
// 		"administrative designation about funding eligibility." ///
// 		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year.", ///
// 		size(small) span ///
// 	) ///
// 	graphregion(margin(l=15 r=15))
// graph export "$output/interstate_comparison.png", replace width(2500)


// /*====
//  Interstate construction by FMIS system code, FHWA Highway Statistics, and program codes 
// ====*/
// graph twoway ///
//     (line FA3_interstate_adj_bills year) ///
//     (line fp_ic_cost_bills_adj year) ///
//     (line fp_im_cost_bills_adj year) ///
//     (line fp_imd_cost_bills_adj year) ///
//     (line int_syscode_cost_bills_adj year), ///
//     title("Comparison of Interstate Spending Using Different Indicators") ///
//     ytitle("Billions of 2025 USD", xoffset(-3)) ///
//     xtitle("Year") ///
//     legend(label(1 "FHWA Federal Interstate" "(FA3)") label(2 "Program Code" "Interstate Construction") label(3 "Program Code" "Interstate Maintenance") label(4 "Program Code" "Interstate Maintenance" "Discretionary") label(5 "FMIS Interstate" "System Code")) ///
//     note( ///
//         "Federal interstate expenditures from FHWA Table FA3." ///
//         "FMIS data includes all project costs across multiple levels of government." ///
// 		"Starting in 1992, FA3 data is reported in fiscal years. In 1990-1991, FA3 data is reported in calendar years." ///
// 		"I have not verified calendar vs fiscal year for earlier years of FA3 data." ///
// 		"Interstate projects are classified in multiple ways. The system code classification is likely an" ///
// 		"administrative designation about funding eligibility." ///
// 		"Program codes appear to be actual funding sources." ///
// 		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year.", ///
// 		size(small) span ///
// 	) ///
// 	graphregion(margin(l=15 r=15))
// graph export "$output/interstate_comparison_with_program_codes.png", replace width(2500)

/*====
 Interstate Construction program code costs over time  
====*/
graph twoway ///
    (line fp_ic_cost_bills_adj year), ///
    title("Interstate Construction Funding Program Spending Over Time") ///
    ytitle("Billions of 2025 USD", xoffset(-3)) ///
    xtitle("Year") ///
    legend(off) ///
    note( ///
		"Interstate projects are identified by the 'Interstate Construction' funding program code.", ///
		size(small) span ///
	)
graph export "$output/costs_over_time_IC.png", replace width(2500)


// /*====
//  Ratio of FHWA federal interstate spending to FMIS interstate spending (federal aid system code) - single number 
// ====*/
// preserve
// keep if year >= 1956 & year <= 1993 
// collapse (sum) FA3_interstate_adj_bills int_syscode_cost_bills_adj
// gen fmis_fhwa_interstate_ratio = int_syscode_cost_bills_adj / FA3_interstate_adj_bills
// summarize fmis_fhwa_interstate_ratio
// display "Ratio of FMIS to FHWA interstate spending between 1956 and 1993: " r(mean)
// restore

// /*====
//  Ratio of FHWA federal interstate spending to FMIS interstate spending (federal aid system code)
// ====*/
// gen fmis_fhwa_interstate_ratio = int_syscode_cost_bills_adj / FA3_interstate_adj_bills

// preserve
// drop if year > 1995

// graph twoway line fmis_fhwa_interstate_ratio year, ///
// 	title("Ratio of FMIS to FHWA Interstate Spending") ///
// 	ytitle("Ratio") ///
// 	xtitle("Year") ///
// 	xlabel(1950(10)2000) ///
// 	note( ///
// 		"FHWA interstate spending is sourced from Table FA3." ///
// 		"Starting in 1992, FA3 data is reported in fiscal years. In 1990-1991, FA3 data is reported in calendar years." ///
// 		"I have not verified calendar vs fiscal year for earlier years of FA3 data." ///
// 		"FMIS interstate classification is defined by federal aid system code." ///
// 		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year.", ///
// 		size(small) span ///
// 	)
// graph export "$output/fmis_fhwa_interstate_ratio.png", replace width(2500)


// /*====
//  Total spending in the US by category vs in FMIS vs interstate only
// ====*/
// graph twoway ///
//     (line total_fmis_cost_bills_adj year) ///
//     (line cap_bills_adj year) ///
//     (line maint_bills_adj year) ///
//     (line admin_law_int_bills_adj year) ///
//     (line debt_retire_bills_adj year) ///
// 	(line FA3_interstate_adj_bills year) ///
//     (line int_syscode_cost_bills_adj year), ///
//     title("US Highway Spending Comparisons") ///
//     ytitle("Billions of 2025 USD", xoffset(-3)) ///
// 	xtitle("Year") ///
// 	legend(label(1 "FMIS Total*") label(2 "Capital Outlays*") label(3 "Maintenance*") label(4 "Administrative,**" "Law Enforcement," "Bond Interest*") label(5 "Debt Retirement*") label(6 "Interstate Construction," "FHWA Federal Interstate***") label(7 "FMIS Interstate" "(System Code)****") size(small)) ///
// 	note( ///
//         "Total national spending data from FHWA Tables DISCHT (1945-2001) and DISB-C (2000-2023)." ///
// 		"Federal interstate expenditures from FHWA Table FA3." ///
// 		"Starting in 1992, FA3 data is reported in fiscal years. In 1990-1991, FA3 data is reported in calendar years." ///
// 		"I have not verified calendar vs fiscal year for earlier years of FA3 data." ///
// 		"* Totals are for all levels of government." ///
// 		"** Administrative costs include general overhead, engineering, research, planning, litigation, and publications." ///
// 		"*** Federal interstate expenditures are administered by the FHWA and exclude primary, secondary, and urban" ///
// 		"roads, as well as planning and research, highway safety, bridge replacement, beautification, and other" ///
// 		"miscellaneous expenditures. " ///	
// 		"**** This FMIS classification of interstate highways is likely based on project funding eligibility rather" "than roadway functionality." ///
// 		"FMIS data is plotted using project completion year while FHWA data is plotted using expenditure year.", ///
// 		size(vsmall) span ///
// 	) ///
// 	ysize(10) xsize(12) ///
// 	graphregion(margin(l=10 r=10))
// graph export "$output/total_hw_spend_by_category_vs_FMIS_vs_int.png", replace width(2500)


* ==============================================================================
* Improvement codes within Interstate Construction over time
* ==============================================================================
use "$intermediate_data/receipt_level_FMIS_lite_program_codes.dta", clear
keep if funding_program == "Interstate Construction"
drop if completion_year < 1950 | completion_year > 2000
collapse (sum) total_cost_mills, by(detail_improvementtype completion_year)

* adjust for inflation
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keep(3) keepusing(cpi) nogen
gen total_cost_bills_adj = total_cost_mills / cpi / 1000

graph twoway ///
    (line total_cost_bills_adj year if detail_improvementtype == 1) ///
    (line total_cost_bills_adj year if detail_improvementtype == 8) ///
    (line total_cost_bills_adj year if detail_improvementtype == 16) ///
    (line total_cost_bills_adj year if detail_improvementtype == 7) ///
    (line total_cost_bills_adj year if detail_improvementtype == 2) ///
    (line total_cost_bills_adj year if detail_improvementtype == 15) ///
    (line total_cost_bills_adj year if detail_improvementtype == 21) ///
    (line total_cost_bills_adj year if detail_improvementtype == 5) ///
    (line total_cost_bills_adj year if detail_improvementtype == 3) ///
    (line total_cost_bills_adj year if detail_improvementtype == 43) ///
    (line total_cost_bills_adj year if detail_improvementtype == 12) ///
    (line total_cost_bills_adj year if detail_improvementtype == 17) ///
    (line total_cost_bills_adj year if detail_improvementtype == 40), ///
    title("Interstate Construction Reimbursements by Improvement Type", size(medium)) ///
    ytitle("Billions of 2025 USD") ///
    xtitle("Completion Year") ///
    xlabel(1960(10)2000) ///
    legend( ///
        label(1 "New Construction Roadway") ///
        label(2 "Bridge New Construction") ///
        label(3 "Right of Way") ///
        label(4 "4R Maintenance Relocation") ///
        label(5 "4R Reconstruction (Obsolete)") ///
        label(6 "Preliminary Engineering") ///
        label(7 "Safety") ///
        label(8 "4R Maintenance Resurfacing") ///
        label(9 "4R Added Capacity") ///
        label(10 "Utilities") ///
        label(11 "Bridge Rehabilitation (Obsolete)") ///
        label(12 "Construction Engineering") ///
        label(13 "Special Bridge") ///
    ) ///
    note( ///
        `"Interstate Construction reimbursements are identified by the "Interstate Construction" funding program code."', ///
        size(small) span ///
    ) ///
    graphregion(margin(r=15))
graph export "$output/IC_impvmt_codes.png", replace width(2500)

* same but plot cost share as pct out of 100 
bysort year: egen double total_cost_bills_adj_year = total(total_cost_bills_adj)
gen double cost_share_pct = 100 * total_cost_bills_adj / total_cost_bills_adj_year

graph twoway ///
    (line cost_share_pct year if detail_improvementtype == 1) ///
    (line cost_share_pct year if detail_improvementtype == 8) ///
    (line cost_share_pct year if detail_improvementtype == 16) ///
    (line cost_share_pct year if detail_improvementtype == 7) ///
    (line cost_share_pct year if detail_improvementtype == 2) ///
    (line cost_share_pct year if detail_improvementtype == 15) ///
    (line cost_share_pct year if detail_improvementtype == 21) ///
    (line cost_share_pct year if detail_improvementtype == 5) ///
    (line cost_share_pct year if detail_improvementtype == 3) ///
    (line cost_share_pct year if detail_improvementtype == 43) ///
    (line cost_share_pct year if detail_improvementtype == 12) ///
    (line cost_share_pct year if detail_improvementtype == 17) ///
    (line cost_share_pct year if detail_improvementtype == 40), ///
    title("Interstate Construction Reimbursement Shares by Improvement Type", size(medium)) ///
    ytitle("Percent share of annual spending", size(small)) ///
    xtitle("Completion Year", size(small)) ///
    xlabel(1960(10)2000) ///
    legend( ///
        label(1 "New Construction Roadway") ///
        label(2 "Bridge New Construction") ///
        label(3 "Right of Way") ///
        label(4 "4R Maintenance Relocation") ///
        label(5 "4R Reconstruction (Obsolete)") ///
        label(6 "Preliminary Engineering") ///
        label(7 "Safety") ///
        label(8 "4R Maintenance Resurfacing") ///
        label(9 "4R Added Capacity") ///
        label(10 "Utilities") ///
        label(11 "Bridge Rehabilitation (Obsolete)") ///
        label(12 "Construction Engineering") ///
        label(13 "Special Bridge") ///
        size(small) ///
    ) ///
    note( ///
        `"Interstate Construction reimbursements are identified by the "Interstate Construction" funding program code."', ///
        size(small) span ///
    ) ///
    graphregion(margin(r=15))
graph export "$output/IC_impvmt_codes_share.png", replace width(2500)

* ==============================================================================
* Compare share of interstate spending that is part of a project that does not include construction
* ==============================================================================
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if funding_program == "Interstate Construction"
drop if detail_improvementtype == 5 | detail_improvementtype == 59 // drop maintenance resurfacing and bridge resurfacing
gen new_const_cost_mills = total_cost_mills if new_construction

* collapse to project level with an indicator for whether there is at least one new construction receipt
collapse (sum) total_cost_mills new_const_cost_mills (max) new_construction (firstnm) completedate completion_year, by(recipientid federal_project_number)

gen proj_cost_w_new_constr = total_cost_mills if new_construction == 1
gen proj_cost_wo_new_constr = total_cost_mills if new_construction == 0

collapse (sum) total_cost_mills proj_cost_w_new_constr proj_cost_wo_new_constr, by(completion_year)

* adjust for inflation
rename completion_year year
drop if year > 2025
merge 1:1 year using "$intermediate_data/CPI_2025.dta", keep(3) keepusing(cpi) nogen
gen total_cost_bills_adj = total_cost_mills / cpi / 1000
gen proj_cost_w_new_constr_b_adj = proj_cost_w_new_constr / cpi / 1000
gen proj_cost_wo_new_constr_b_adj = proj_cost_wo_new_constr / cpi / 1000

graph twoway line total_cost_bills_adj proj_cost_w_new_constr_b_adj year, sort /// 
    title("Cost Share of Interstate Projects With At Least One New Construction Receipt", size(medium)) ///
    subtitle("Excluding Resurfacing Receipts", size(small)) ///
    ytitle("Billions of 2025 USD") ///
    xtitle("Completion Year") ///
    legend( ///
        label(1 "Total Interstate" "Construction") ///
        label(2 "Projects with" "New Construction") ///
        size(small) ///
    ) ///
    xlabel(1950(10)2025) ///
	note( ///
		`"Interstate projects are identified by the "Interstate Construction" funding program code."' ///
        "Both variables exclude receipts with an improvement type of maintenance resurfacing or bridge resurfacing." ///
        "Projects with new constructiion are defined as those with at least one receipt with an improvement type of new" "construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel.", ///
		size(small) span ///
	)
graph export "$output/share_interstate_proj_w_newconstr.png", replace width(2500)


graph twoway line total_cost_bills_adj proj_cost_wo_new_constr_b_adj year, sort /// 
    title("Cost Share of Interstate Projects Without New Construction Receipt", size(medium)) ///
    subtitle("Excluding Resurfacing Receipts", size(small)) ///
    ytitle("Billions of 2025 USD") ///
    xtitle("Completion Year") ///
    legend( ///
        label(1 "Total Interstate" "Construction") ///
        label(2 "Projects without" "New Construction") ///
        size(small) ///
    ) ///
    xlabel(1950(10)2025) ///
	note( ///
		`"Interstate projects are identified by the "Interstate Construction" funding program code."' ///
        "Both variables exclude receipts with an improvement type of maintenance resurfacing or bridge resurfacing." ///
        "Projects without new constructiion are defined as those with no receipts with an improvement type of new" "construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel.", ///
		size(small) span ///
	)
graph export "$output/share_interstate_proj_wo_newconstr.png", replace width(2500)


* ==============================================================================
* Compare spending by level of government
* ==============================================================================

* FMIS costs by level of government


* FHWA costs by level of government 
use "$intermediate_data/FHWA_Highway_Statistics/HF10_1921_2023.dta", clear
* adjust for inflation 
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen cost_mills_adj = cost_mills / cpi
gen cost_bills_adj = cost_mills_adj / 1000

collapse (sum) cost_bills_adj, by(year agency)

* fill in missing (year, agency) for selected years so the line graph shows gaps (cost_bills_adj = .)
preserve
clear
set obs 18
gen year = .
gen agency = .
replace year = 1996 in 1/3
replace year = 1997 in 4/6
replace year = 1998 in 7/9
replace year = 2011 in 10/12
replace year = 2013 in 13/15
replace year = 2017 in 16/18
replace agency = mod(_n - 1, 3) + 1 in 1/18
gen cost_bills_adj = .
tempfile gap_years
save `gap_years'
restore
append using `gap_years'
* keep existing values when (year, agency) appears in both; otherwise keep the . row (so line has a gap)
sort year agency cost_bills_adj
bysort year agency: keep if _n == 1
sort agency year

graph twoway ///
    (line cost_bills_adj year if agency == 1, cmissing(n)) ///
    (line cost_bills_adj year if agency == 2, cmissing(n)) ///
    (line cost_bills_adj year if agency == 3, cmissing(n)), ///
    title("FHWA Highway Spending by Level of Government") ///
    ytitle("Billions of 2025 USD") ///
    xtitle("Year") ///
    legend(label(1 "Federal") label(2 "State") label(3 "Local"))
graph export "$output/fhwa_hw_spend_by_level_of_government.png", replace width(2500)