/*==============================================================================
 	FMIS data exploration
 	Andy Kovesci 
	01/15/2026
==============================================================================*/
* Set user
local user = c(username)
if "`user'" == "andersonkovesci"{
	global output "/Users/andersonkovesci/Dropbox/FHWA cost data/Output/Andy"
	global data "/Users/andersonkovesci/Dropbox/FHWA cost data/Data"
}
* add your username and paths here as an else if condition
else {
	 display as error "Set your user"
}
/*==============================================================================
	Save intermediate files
==============================================================================*/
* CPI from FRED: https://fred.stlouisfed.org/series/CPIAUCSL
import delimited "$data/Raw/CPI_2025_indexed.csv", clear
gen year = regexs(1) if regexm(observation_date, "^([0-9]{4})-")
destring year, replace
gen cpi = cpiaucsl / 100
save "$data/Intermediate/CPI_2025.dta", replace

* Population from Macrotrends: https://www.macrotrends.net/global-metrics/countries/usa/united-states/population
import delimited "$data/Raw/US_population_by_year.csv", clear
rename v1 year
gen population_hun_thous = population / 100000
save "$data/Intermediate/US_population_by_year.dta", replace

* Import FMIS data, gen common variables, and save at project level. 
import delimited "$data/CSVs/combined_data.csv", clear bindquote(strict) varnames(1)

* Completion year for grouping projects/reciepts 
gen completion_year = regexs(1) if regexm(completedate, "/([0-9]{4})$")
destring completion_year, replace

rename federalprojectnumber federal_project_number
* In the variable detail_improvementtype, there is a category (15) called preliminary engineering, which is by far the most common.

* Define improvement labels 
global improvement_lbl_def ///
  0  "N/A" ///
  1  "New Construction Roadway" ///
  2  "4R - Reconstruction (Obsolete)" ///
  3  "4R - Added Capacity" ///
  4  "4R - No Added Capacity" ///
  5  "4R - Maintenance Resurfacing" ///
  6  "4R - Restoration & Rehabilitation" ///
  7  "4R - Maintenance Relocation" ///
  8  "Bridge New Construction" ///
  9  "Bridge Replacement (Obsolete)" ///
  10 "Bridge Replacement - Added Capacity" ///
  11 "Bridge Replacement - No Added Capacity" ///
  12 "Bridge Rehabilitation (Obsolete)" ///
  13 "Bridge Rehabilitation - Added Capacity" ///
  14 "Bridge Rehabilitation - No Added Capacity" ///
  15 "Preliminary Engineering" ///
  16 "Right of Way" ///
  17 "Construction Engineering" ///
  18 "Planning" ///
  19 "Research" ///
  20 "Environmental Only" ///
  21 "Safety" ///
  22 "Rail/Hwy Crossing" ///
  23 "Transit" ///
  24 "Traffic Management/Engineering - HOV" ///
  25 "Vehicle Weight Enforcement Program" ///
  26 "Ferry Boats" ///
  27 "Administration" ///
  28 "Facilities for Pedestrians and Bicycles" ///
  29 "Acquisition of Scenic Easements and Scenic/Historic Sites" ///
  30 "Scenic or Historic Highway Programs" ///
  31 "Landscaping and Other Scenic Beautification" ///
  32 "Historic Preservation" ///
  33 "Rehabilitation/Operation of Historic Transportation Buildings etc." ///
  34 "Preservation of Abandoned Railway Corridors" ///
  35 "Control and Removal of Outdoor Advertising" ///
  36 "Archaeological Planning & Research" ///
  37 "Mitigation of Water Pollution due to Highway Runoff" ///
  38 "Safety and Education for Peds/Bicyclists" ///
  39 "Establishment of Transportation Museums" ///
  40 "Special Bridge" ///
  41 "Youth Conservation Service" ///
  42 "Training" ///
  43 "Utilities" ///
  44 "Other" ///
  45 "Debt Service" ///
  46 "Design-Build Contract (Obsolete)" ///
  47 "Bridge Preventive Maintenance" ///
  48 "Bridge Protection" ///
  49 "Bridge Inspection and Bridge Related Training" ///
  50 "New Tunnel" ///
  51 "Tunnel Replacement" ///
  52 "Tunnel Rehabilitation" ///
  53 "Tunnel Preventive Maintenance" ///
  54 "Tunnel Protection" ///
  55 "Tunnel Inspection and Tunnel Related Training" ///
  56 "Other Asset Inspection" ///
  57 "Safety - Non Infrastructure" ///
  58 "Freight" ///
  59 "Bridge Resurfacing" ///
  60 "Highway Infrastructure Preventive Maintenance" ///
  61 "Routine Maintenance" ///
  62 "Operations" ///
  63 "Electric Vehicle & Charging Infrastructure" ///
  64 "Other Alternative Fuel Vehicles & Infrastructure" ///
  65 "Resilience Planning" ///
  66 "Resilience Improvement - Highway Project" ///
  67 "Resilience Improvement - Transit or Port Projects" ///
  68 "Resilience Improvement - Natural Infrastructure" ///
  69 "Community Resilience and Evacuation Routes" ///
  70 "At-Risk Coastal Infrastructure - Highway Project" ///
  71 "At-Risk Coastal Infrastructure - Transit or Port Projects" ///
  72 "At-Risk Coastal Infrastructure - Natural Infrastructure"
label define improvement_lbl $improvement_lbl_def, replace
label values detail_improvementtype improvement_lbl

* Create total cost variable, costs are either gis, or nongis. 
gen total_cost = nongis_totalcost 
replace total_cost = gis_totalcost if total_cost == . 
gen total_cost_mills = total_cost / 1000000 

* Define Regions
gen region = ""
replace region = "Northeast" if inlist(recipientid, 9,23,25,33,44,50,34,36,42)
replace region = "Midwest" if inlist(recipientid, 17,18,26,39,55,19,20,27,29,31,38,46)
replace region = "South" if inlist(recipientid, 10,11,12,13,24,37,45,51,54,1,21,28,47,5,22,40,48)
replace region = "West" if inlist(recipientid, 2,4,6,8,15,16,30,32,35,41,49,53,56)

* Reformat the detail_lastactiondate variable 
gen detail_lastactiondate_temp = regexs(0) if regexm(detail_lastactiondate, "([0-9]{2}/[0-9]{2}/[0-9]{4})")
gen detail_lastactiondate_numeric = date(detail_lastactiondate_temp, "MDY")
format detail_lastactiondate_numeric %tdCCYY-NN-DD
drop detail_lastactiondate_temp detail_lastactiondate
rename detail_lastactiondate_numeric detail_lastactiondate

keep recipientid projectstatus projecttitle projectdescription total_cost_mills detail_lastactiondate completedate authconstdate recipientremarks divisionremarks detail_prefix nongis_countyid gisbreakdown_countyid gis_routeid detail_improvementtype completion_year federal_project_number region
save "$data/Intermediate/receipt_level_FMIS.dta", replace

* Collapse to the project level, and save
* aggregate the improvement types to the project level, and count number of reciepts
tostring detail_improvementtype, gen(proj_improv_types)
bysort federal_project_number recipientid: gen strL alltypes = proj_improv_types[1]
bysort federal_project_number recipientid: replace alltypes = alltypes[_n-1] + "; " + proj_improv_types if _n>1 & proj_improv_types != ""
by federal_project_number recipientid: replace alltypes = alltypes[_N]
	
gen receipts = 1 // this is used for reciept counts

collapse (sum) receipts total_cost_mills (firstnm) region projectstatus projecttitle projectdescription completedate authconstdate recipientremarks divisionremarks detail_prefix nongis_countyid gisbreakdown_countyid gis_routeid (lastnm) alltypes completion_year, by(federal_project_number recipientid)

save "$data/Intermediate/project_level_FMIS.dta", replace

gen num_projects = 1
* Region x Year x Project data aggregated
collapse (sum) num_projects receipts total_cost_mills, by(region completion_year)
save "$data/Intermediate/projects_by_year_region.dta", replace

/*==============================================================================
	Receipt level Graphs
==============================================================================*/

/*===============
 "New" Receipts
================*/
use "$data/Intermediate/receipt_level_FMIS", clear
keep if completion_year >= 1950 & completion_year < 2025
gen new_receipt = inlist(detail_improvementtype, 1, 8, 50) // these are new road, new bridge and new tunnel respectively
gen frequency = 1
collapse (sum) frequency (mean) total_cost_mills, by(new_receipt completion_year)
bysort completion_year: egen total_receipts = total(frequency)
gen new_as_percent_of_total = frequency / total_receipts
keep if new_receipt == 1

* Share of reciepts that are "new"
graph twoway line new_as_percent_of_total completion_year, ///
	title("Percent of Receipts with New Improvement Type Over Time") ///
		ytitle("% of Reciepts") ///
		xtitle("Completion Year")
graph export "$output/new_receipts_over_time.png", replace

* adjusted cost of "new" recipts over time
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
rename completion_year year
merge 1:1 year using "$data/Intermediate/CPI_2025.dta"
gen adjusted_cost = total_cost_mills / cpi
graph twoway line adjusted_cost year, /// 
	title("Adjusted Cost of Receipts with New Improvement Type Over Time") ///
		ytitle("Millions of $ (Indexed to 2025)") ///
		xtitle("Completion Year")
graph export "$output/cost_of_new_receipts_over_time.png", replace

/*=================
 Improvement Types
==================*/
use "$data/Intermediate/receipt_level_FMIS", clear
gen frequency = 1
collapse (sum) frequency (mean) total_cost_mills, by(detail_improvementtype)
egen total_obs = total(frequency)
gsort -frequency 
keep in 1/20
gen percent_share = (frequency / total_obs) * 100
replace total_cost_mills = . if total_cost_mills == 0

* Share of most common improvement types
graph bar percent_share, over(detail_improvementtype, sort(percent_share) descending label(angle(30) labsize(vsmall))) blabel(bar, format(%9.2f)) title("Most Common Improvement Types") ytitle("% of All Observations")
graph export "$output/frequency_by_impvmt_types.png", replace

* Cost of the most common improvement types
graph bar total_cost_mills, over(detail_improvementtype, sort(percent_share) descending label(angle(30) labsize(vsmall))) blabel(bar, format(%9.2f)) title("Average Cost of Most Common Improvement Types") ytitle("Average Cost in Millions of $")
graph export "$output/ave_cost_by_impvmt_types.png", replace

/*========
 Prefixes
=========*/
use "$data/Intermediate/receipt_level_FMIS", clear
gen frequency = 1
collapse (sum) frequency (mean) total_cost_mills, by(detail_prefix)
gsort -frequency 
egen total_obs = total(frequency)
keep in 1/20
gen percent_share = (frequency / total_obs) * 100

* Share of prefixes
graph bar percent_share, over(detail_prefix, sort(percent_share) descending label(angle(30) labsize(vsmall))) blabel(bar, format(%9.2f)) title("Most Common Project ID Prefixes") ytitle("% of All Observations")
graph export "$output/frequency_by_prefixes.png", replace

* Cost of prefixes
graph bar total_cost_mills, over(detail_prefix, sort(percent_share) descending label(angle(30) labsize(vsmall))) blabel(bar, format(%9.2f)) title("Average Cost of by Project ID Prefix") ytitle("Average Cost in Millions of $")
graph export "$output/ave_cost_by_prefixes.png", replace

/*===========
 Total costs
============*/
use "$data/Intermediate/receipt_level_FMIS", clear
* total costs by region over time, adjusted for inflation
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
collapse (sum) total_cost_mills, by(region completion_year)
rename completion_year year
merge m:1 year using "$data/Intermediate/CPI_2025.dta"
gen total_cost_mills_adjusted = total_cost_mills / cpi
graph twoway ///
    (line total_cost_mills_adjusted year if region == "Midwest", sort lcolor(navy)) ///
    (line total_cost_mills_adjusted year if region == "Northeast", sort lcolor(maroon)) ///
    (line total_cost_mills_adjusted year if region == "South", sort lcolor(forest_green)) ///
    (line total_cost_mills_adjusted year if region == "West", sort lcolor(orange)), ///
    title("Total Adjusted Costs by Region and Year") ///
    ytitle(" Cost (Millions of $ Indexed to 2025)") ///
    xtitle("Completion Year") ///
    legend(order(1 "Midwest" 2 "Northeast" 3 "South" 4 "West"))
graph export "$output/total_adjusted_cost_by_region_over_time.png", replace

/*===============================
 Average reciept cost over time
================================*/
use "$data/Intermediate/receipt_level_FMIS", clear

keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
collapse (mean) total_cost_mills, by(region completion_year)
graph twoway ///
    (line total_cost_mills completion_year if region == "Midwest", sort lcolor(navy)) ///
    (line total_cost_mills completion_year if region == "Northeast", sort lcolor(maroon)) ///
    (line total_cost_mills completion_year if region == "South", sort lcolor(forest_green)) ///
    (line total_cost_mills completion_year if region == "West", sort lcolor(orange)), ///
    title("Average Receipt Cost Over Time by Region") ///
    ytitle("Average Cost (Millions of $)") ///
    xtitle("Completion Year") ///
    legend(order(1 "Midwest" 2 "Northeast" 3 "South" 4 "West"))
graph export "$output/ave_receipt_cost_by_region_over_time.png", replace

* Adjust for inflation
rename completion_year year
merge m:1 year using "$data/Intermediate/CPI_2025.dta"
gen total_cost_mills_adjusted = total_cost_mills / cpi
graph twoway ///
    (line total_cost_mills_adjusted year if region == "Midwest", sort lcolor(navy)) ///
    (line total_cost_mills_adjusted year if region == "Northeast", sort lcolor(maroon)) ///
    (line total_cost_mills_adjusted year if region == "South", sort lcolor(forest_green)) ///
    (line total_cost_mills_adjusted year if region == "West", sort lcolor(orange)), ///
    title("Average Adjusted Receipt Cost Over Time by Region") ///
    ytitle("Average Cost (Millions of $ Indexed to 2025)") ///
    xtitle("Completion Year") ///
    legend(order(1 "Midwest" 2 "Northeast" 3 "South" 4 "West"))
graph export "$output/ave_adjusted_receipt_cost_by_region_over_time.png", replace

/*===============================
 Num Receipts over time
================================*/
use "$data/Intermediate/receipt_level_FMIS", clear
gen n_obs = 1
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
collapse (sum) n_obs, by(completion_year)
rename completion_year year
merge 1:1 year using "$data/Intermediate/US_population_by_year.dta"
gen receipts_per_hun_thou = n_obs / population_hun_thous
graph twoway line n_obs year, sort /// 
    title("Number of Receipts by Completion Year") ///
    ytitle("Number of Receipts") ///
    xtitle("Completion Year")
graph export "$output/num_receipts_by_yr.png", replace	

* adjust per 100,000 people
graph twoway line receipts_per_hun_thou year, sort /// 
    title("Number of Receipts Per 100,000 People by Completion Year") ///
    ytitle("Number of Receipts (Per 100,000 People)") ///
    xtitle("Completion Year")
graph export "$output/num_receipts_per_hundred_thousand_by_yr.png", replace

/*===============================
 Receipt date
================================*/
use "$data/Intermediate/receipt_level_FMIS", clear

*First make lets look at how many action dates are different from one another
bysort federal_project_number recipientid: gen num_receipts = _N

bysort federal_project_number recipientid (detail_lastactiondate): gen unique_dates = 1 if _n == 1
bysort federal_project_number recipientid (detail_lastactiondate): replace unique_dates = unique_dates[_n-1] + (detail_lastactiondate != detail_lastactiondate[_n-1]) if _n > 1
bysort federal_project_number recipientid: replace unique_dates = unique_dates[_N]

gen completion_decade = .
replace completion_decade = 1 if completion_year >= 1950 & completion_year <= 1959
replace completion_decade = 2 if completion_year >= 1960 & completion_year <= 1969
replace completion_decade = 3 if completion_year >= 1970 & completion_year <= 1979
replace completion_decade = 4 if completion_year >= 1980 & completion_year <= 1989
replace completion_decade = 5 if completion_year >= 1990 & completion_year <= 1999
replace completion_decade = 6 if completion_year >= 2000 & completion_year <= 2009
replace completion_decade = 7 if completion_year >= 2010 & completion_year <= 2019
replace completion_decade = 8 if completion_year >= 2020 & completion_year <= 2025

preserve
collapse (mean) unique_dates, by(num_receipts completion_decade)
drop if num_receipts > 23

twoway (line unique_dates num_receipts if completion_decade == 1) ///
	(line unique_dates num_receipts if completion_decade == 2) ///
	(line unique_dates num_receipts if completion_decade == 3) ///
	(line unique_dates num_receipts if completion_decade == 4) ///
	(line unique_dates num_receipts if completion_decade == 5) ///
	(line unique_dates num_receipts if completion_decade == 6) ///
	(line unique_dates num_receipts if completion_decade == 7) ///
	(line unique_dates num_receipts if completion_decade == 8) ///
	(function y=x, range(1 23) lpattern(dash) lcolor(black)), ///
	legend(order(1 "1950s" 2 "1960s" 3 "1970s" 4 "1980s" 5 "1990s" ///
				 6 "2000s" 7 "2010s" 8 "2020s" 9 "45 degree line")) /// 
	title("Unique Last Action Dates vs Number of Receipts by Decade") ///
	xtitle("Number of Receipts") ///
	ytitle("Unique Action Dates")
graph export "$output/receipt_dates/unique_receipts_by_decade.png", replace	   
restore

* Compute the share of projects with multiple unique receipt dates conditional on having multiple receipts
gen multiple_dates = (unique_dates > 1)
tab multiple_dates if num_receipts != 1 

* Create a day distance from first receipt date 
bysort federal_project_number recipientid (detail_lastactiondate): gen dist_from_day0 = detail_lastactiondate -detail_lastactiondate[1] 

gen year_bin = 0 if dist_from_day0 == 0
replace year_bin = 1 if dist_from_day0 > 0 & dist_from_day0 <= 365
replace year_bin = 2 if dist_from_day0 > 365 & dist_from_day0 <= 730
replace year_bin = 3 if dist_from_day0 > 730 & dist_from_day0 <= 1095
replace year_bin = 4 if dist_from_day0 > 1095 & dist_from_day0 <= 1460
replace year_bin = 5 if dist_from_day0 > 1460 & dist_from_day0 <= 1825
replace year_bin = 6 if dist_from_day0 > 1825 & dist_from_day0 <= 2190
replace year_bin = 7 if dist_from_day0 > 2190 & dist_from_day0 <= 2555
replace year_bin = 8 if dist_from_day0 > 2555 & dist_from_day0 <= 2920
replace year_bin = 9 if dist_from_day0 > 2920 & dist_from_day0 <= 3285
replace year_bin = 10 if dist_from_day0 > 3285 & dist_from_day0 <= 3650
replace year_bin = 11 if dist_from_day0 > 3650 & dist_from_day0 != .

* graph average distance from start date by common impvmtn types
preserve
collapse (mean) dist_from_day0, by(detail_improvementtype)
graph bar dist_from_day0 ///
	if inlist(detail_improvementtype, 17, 15, 21, 5, 16, 4, 6, 44, 43, 8, 2, 22, 11, 3, 28, 1, 18, 14, 12), /// 
	over(detail_improvementtype, sort(dist_from_day0) label(angle(30) labsize(vsmall))) ///
	blabel(bar, format(%9.0f)) ///
	title("Average Days After Day0 by Impvmt") ///
	ytitle("Average Days After Day0")
graph export "$output/receipt_dates/unfiltered_timeline.png", replace	 
restore 

* Do the same thing but filter out projects before 2000 
preserve
drop if completion_year < 2000
collapse (mean) dist_from_day0, by(detail_improvementtype)
graph bar dist_from_day0 ///
	if inlist(detail_improvementtype, 17, 15, 21, 5, 16, 4, 6, 44, 43, 8, 2, 22, 11, 3, 28, 1, 18, 14, 12), /// 
	over(detail_improvementtype, sort(dist_from_day0) label(angle(30) labsize(vsmall))) ///
	blabel(bar, format(%9.0f)) ///
	title("Average Days After Day0 by Impvmt") ///
	ytitle("Average Days After Day0") /// 
	note("Note: Only receipts with a completion year after 2000 used")
graph export "$output/receipt_dates/filtered_timeline.png", replace	 
restore

* distribution of distance from day 1 var 
label define year_bin_lbl 0 "0" 1 "<1yr" 2 "1-2yr" 3 "2-3yr" 4 "3-4yr" 5 "4-5yr" ///
    6 "5-6yr" 7 "6-7yr" 8 "7-8yr" 9 "8-9yr" 10 "9-10yr" 11 "10yr+"
label values year_bin year_bin_lbl
preserve
collapse (count) dist_from_day0, by(year_bin)
rename dist_from_day0 num_receipts
twoway bar num_receipts year_bin, ///
    xlabel(0 1 2 3 4 5 6 7 8 9 10 11, valuelabel) ///
    title("Number of Receipts by Years After Day0 Binned") ///
    xtitle("Years After Day0") ///
    ytitle("Number of Receipts")
graph export "$output/receipt_dates/receipts_by_year_bin.png", replace
restore

* distribution distance from day 1 var by impvmnt types
gen log_dist = log(dist_from_day0)
joyplot log_dist if inlist(detail_improvementtype, 17, 15, 21, 5, 16), ///
    by(detail_improvementtype) ///
    overlap(3) ///
    title("Distribution of Log Days After Day0 by Improvement Type") ///
    xtitle("Log Days After Day0") ///
	graphregion(margin(l+20))
graph export "$output/receipt_dates/log_dist_by_impvmnt_type_joyplot.png", replace

* not joyplot
twoway ///
	(kdensity log_dist if detail_improvementtype == 17) ///
	(kdensity log_dist if detail_improvementtype == 15) ///
	(kdensity log_dist if detail_improvementtype == 21) ///
	(kdensity log_dist if detail_improvementtype == 5) ///
	(kdensity log_dist if detail_improvementtype == 16), ///
    legend(order(1 "Construction Engineering" 2 "Preliminary Engineering" 3 "Safety" ///
		4 "4R Maintenance Resurfacing" 5 "Right of Way")) ///
    title("Distribution of Log Days After Day0 by Improvement Type") ///
    xtitle("Log Days After Day0") ///
    ytitle("Density") ///
	note("Note: Receipts with no difference in date dropped")
graph export "$output/receipt_dates/log_dist_by_impvmnt_type.png", replace

histogram dist_from_day0 if dist_from_day0 > 0 & dist_from_day0 < 3650 & inlist(detail_improvementtype, 17, 15, 21, 5, 16, 4, 6, 44, 43, 8, 2, 22), ///
    by(detail_improvementtype, title("Distribution of Days After Day0 by Improvement Type") ///
    note("Note: Zero values and observations beyond 10 years excluded")) ///
    xtitle("Days After Day0") ///
    ytitle("Density")
graph export "$output/receipt_dates/dist_by_impvmnt_type.png", replace

/*==============================================================================
	Project-Level Graphs
==============================================================================*/

/*================================
 Average Cost by Region over time
=================================*/
use "$data/Intermediate/project_level_FMIS.dta", clear
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
collapse (mean) total_cost_mills, by(region completion_year)
graph twoway ///
    (line total_cost_mills completion_year if region == "Midwest", sort lcolor(navy)) ///
    (line total_cost_mills completion_year if region == "Northeast", sort lcolor(maroon)) ///
    (line total_cost_mills completion_year if region == "South", sort lcolor(forest_green)) ///
    (line total_cost_mills completion_year if region == "West", sort lcolor(orange)), ///
    title("Average Project Cost Over Time by Region") ///
    ytitle("Average Cost (Millions of $)") ///
    xtitle("Completion Year") ///
    legend(order(1 "Midwest" 2 "Northeast" 3 "South" 4 "West"))
graph export "$output/ave_project_cost_by_region_over_time.png", replace

* Adjust for inflation
rename completion_year year
merge m:1 year using "$data/Intermediate/CPI_2025.dta"
gen total_cost_mills_adjusted = total_cost_mills / cpi
graph twoway ///
    (line total_cost_mills_adjusted year if region == "Midwest", sort lcolor(navy)) ///
    (line total_cost_mills_adjusted year if region == "Northeast", sort lcolor(maroon)) ///
    (line total_cost_mills_adjusted year if region == "South", sort lcolor(forest_green)) ///
    (line total_cost_mills_adjusted year if region == "West", sort lcolor(orange)), ///
    title("Average Adjusted Project Cost Over Time by Region") ///
    ytitle("Average Cost (Millions of $ Indexed to 2025)") ///
    xtitle("Completion Year") ///
    legend(order(1 "Midwest" 2 "Northeast" 3 "South" 4 "West"))
graph export "$output/ave_adjusted_cost_by_region_over_time.png", replace

/*=======================
 Num reciepts per project
========================*/
use "$data/Intermediate/project_level_FMIS.dta", clear
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
collapse (mean) receipts, by(completion_year)
graph twoway line receipts completion_year, ///
	title("Average Number of Receipts per Project by Year") ///
	ytitle("Number of Receipts") ///
	xtitle("Completion Year")
graph export "$output/receipts_per_proj_by_year.png", replace

/*==========================
 Projects per capita by year
===========================*/
use "$data/Intermediate/project_level_FMIS.dta", clear
gen n_obs = 1
keep if completion_year >= 1950 & completion_year < 2025 // filter out years without much data
collapse (sum) n_obs, by(completion_year)
rename completion_year year
merge 1:1 year using "$data/Intermediate/US_population_by_year.dta"
gen projects_per_hun_thou = n_obs / population_hun_thous
graph twoway line n_obs year, sort /// 
    title("Number of Projects by Completion Year") ///
    ytitle("Number of Projects") ///
    xtitle("Completion Year")
graph export "$output/num_projects_by_yr.png", replace	

* Per 100,000 people
graph twoway line projects_per_hun_thou year, sort /// 
    title("Number of Projects Per 100,000 People by Completion Year") ///
    ytitle("Number of Projects (Per 100,000 People)") ///
    xtitle("Completion Year")
graph export "$output/num_projects_per_hundred_thousand_by_yr.png", replace	

*===============================================================================
*	Match with Colorado data
*===============================================================================
import excel "$data/Raw/CO_costs_req2.xlsx", sheet("Project Details") firstrow clear
* Example federal project number in colorado projects data: SHE 160A-031, NHPP 0701-230, BR 1131-006

* Strip CO federal project number to use for matching
split PROJECT, parse(" ")
rename PROJECT1 prefix_from_co
rename PROJECT2 federal_project_number
rename PROJECT orig_PROJECT
replace federal_project_number = subinstr(federal_project_number, "-", "", .)

* Check for duplicates
bysort federal_project_number: gen N = _N
drop if federal_project_number == "0705085"
replace federal_project_number = "242092" if ProjectCode == 23188
replace federal_project_number = "252447" if ProjectCode == 20885
unique federal_project_number
drop N
save "$data/Intermediate/CO_project_data.dta", replace

* Load in the FMIS CO data
use if recipientid == 8 using "$data/Intermediate/project_level_FMIS.dta", clear

* Reformat the authconstdate date from FMIS, and fiter any construction date that 
* starts before 2015
gen authconstdate_numeric = date(authconstdate, "MDY")
drop authconstdate 
rename authconstdate_numeric authconstdate 
drop if authconstdate < 20089 // this is 1/1/2015
 
merge 1:1 federal_project_number using "$data/Intermediate/CO_project_data.dta" 
* 681 of our 1116 proejcts mathced with the FMIS data
unique federal_project_number // unique  
 
* We need to filter out costs in the CO data for projects that are not completed. 
gen completed = 1 if ActualEndDate <= 24027 
replace completed = 0  if ActualEndDate > 24027 & ActualEndDate != . 
replace Expenditure = . if completed != 1

* Also filter out "active" projects in the FMIS data. 
replace total_cost_mills = . if projectstatus == 10

* After a quick look at the project titles from FMIS and the Project names from colorado, it seems like a lot of them are correct. Sometimes they are exact string matches like "I-70 MP 170.5 Essential Wall Repair" other times it is not as clear: I-70 GWC Perm Rockfall Mit vs I-70 GLENWOOD CANYON MP116 TO MP133 IN GARFIELD COUNTY-INSTALLATION OF PERMANENT ROCKFALL MITIGATION FEATURES 
* Sometimes the title runs far longer than the project name, so take the length of the name, create new var that is that length of the title

gen title_start = substr(projecttitle, 1, strlen(ProjectName))
replace title_start = upper(title_start)
replace ProjectName = upper(ProjectName)
strdist title_start ProjectName, gen(title_test)
replace title_test = title_test / strlen(ProjectName)
* after looking closely at observatoins with high scores, it seems like all of these should be matches

*One last way to check the matches is with the construction start data
gen start_date_check = authconstdate - StartDate
*this is extremely unhelpful due to how different these variables can be. 

rename total_cost_mills total_FMIS_cost_mills 
gen EngineersEstimate_mills = EngineersEstimate/1000000
gen WinningBidAmount_mills = WinningBidAmount/1000000
gen Expenditure_mills = Expenditure/1000000

*many projects have 0 total cost for the FMIS. in the recipietn remarks, these projects are often withdrawn or closed. Some of these match with the colorado data.
replace total_FMIS_cost_mills = . if total_FMIS_cost_mills == 0

gen group = 1 if _merge == 1
replace  group = 2 if _merge == 3
replace group = 3 if _merge == 2 // these are going to be used to sort the bars so the matched are in the middle

/*===============
 Cost Comparison
===============*/
preserve 
drop if _merge != 3 
graph bar (mean) total_FMIS_cost_mills EngineersEstimate_mills WinningBidAmount_mills Expenditure_mills, asyvars bar(1, color(navy)) bar(2, color(dkgreen)) bar(3, color(maroon)) bar(4, color(orange)) legend(order(1 "FMIS Total Cost" 2 "CO Engineer Estimate" 3 "CO Winning Bid" 4 "CO Expenditure")) ytitle("Average Cost (Millions of $)") yscale(range(2 6)) title("Average CO/FMIS Project Costs") blabel(bar, format(%9.2f)) graphregion(color(white)) bargap(25)
graph export "$output/FMIS_CO_cost_comparison.png", replace


keep if Expenditure_mills > 10
graph bar (mean) total_FMIS_cost_mills EngineersEstimate_mills WinningBidAmount_mills Expenditure_mills, asyvars bar(1, color(navy)) bar(2, color(dkgreen)) bar(3, color(maroon)) bar(4, color(orange)) legend(order(1 "FMIS Total Cost" 2 "CO Engineer Estimate" 3 "CO Winning Bid" 4 "CO Expenditure")) ytitle("Average Cost (Millions of $)") yscale(range(2 6)) title("Average CO/FMIS Project Costs Greater than 10 Million") blabel(bar, format(%9.2f)) graphregion(color(white)) bargap(25)
graph export "$output/FMIS_CO_cost_comparison_10mill.png", replace
restore

/*=================================
 Cost Comparison by matching groups
=================================*/
graph bar (mean) total_FMIS_cost_mills Expenditure_mills, bar(1, color(maroon)) bar(2, color(navy)) over(group, relabel(1 "FMIS Only" 2 "Matched" 3 "Colorado Only")) legend(order(1 "Total FMIS Cost" 2 "CO Realized Cost")) ytitle("Average Cost (Millions of $)") yscale(range(2 6)) title("Costs by Matching Groups") blabel(bar, format(%9.2f))
graph export "$output/Costs by matching groups.png", replace

* Check the distribution of work types in the FMIS only 
preserve
gen count = 1 
keep if _merge == 1
drop if total_FMIS_cost_mills == . 
forvalues i = 1/72 {
	gen improvement_`i' = regexm(alltypes, "(^|;\s*)`i'(\s*;|$)")
}
egen total_obs = total(count)
collapse (sum) improvement_* count, by (total_obs)
reshape long improvement_, i(total_obs) j(improvement_type)
label values improvement_type improvement_lbl
rename improvement_ frequency
gen percent_share = (frequency / total_obs) * 100
tempfile FMIS_only
save `FMIS_only'
gsort -percent_share
keep in 1/6

label define improvement_lbl $improvement_lbl_def, replace
label values improvement_type improvement_lbl

graph bar percent_share, over(improvement_type, sort(percent_share) descending label(angle(30) labsize(vsmall))) blabel(bar, format(%9.2f)) title("Most Common Improvement Types in FMIS only") ytitle("% of Projects with Improvement Type")
graph export "$output/imprvmt_types_frequency_FMIS_not_matched.png", replace

restore

* Now check the distribution in the matched group
gen count = 1 
keep if _merge == 3
forvalues i = 1/72 {
	gen improvement_`i' = regexm(alltypes, "(^|;\s*)`i'(\s*;|$)")
}
egen total_obs = total(count)
collapse (sum) improvement_* count, by (total_obs)
reshape long improvement_, i(total_obs) j(improvement_type)
label values improvement_type improvement_lbl
rename improvement_ frequency
gen percent_share = (frequency / total_obs) * 100
tempfile matched
save `matched'
gsort -percent_share
keep in 1/6

label define improvement_lbl $improvement_lbl_def, replace
label values improvement_type improvement_lbl

graph bar percent_share, over(improvement_type, sort(percent_share) descending label(angle(30) labsize(vsmall))) blabel(bar, format(%9.2f)) title("Most Common Improvement Types in Matched Data") ytitle("% of Projects with Improvement Type")
graph export "$output/imprvmt_types_frequency_matched.png", replace

* Combined
use `matched', clear
rename percent_share percent_share_matched
merge 1:1 improvement_type using `FMIS_only'
rename percent_share percent_share_FMIS
keep if inlist(improvement_type, 17, 15, 21, 5, 16, 4, 6, 44, 43, 3, 28, 18)

label define improvement_lbl $improvement_lbl_def, replace
label values improvement_type improvement_lbl

graph bar percent_share_FMIS percent_share_matched, ///
    over(improvement_type, sort(percent_share_matched) descending ///
         label(angle(30) labsize(vsmall))) ///
    legend(order(1 "FMIS Only (Unmatched)" 2 "Matched")) ///
    blabel(bar, format(%9.1f) size(vsmall)) ///
	outergap(80) ///
    title("Most Common Improvement Types: FMIS Only vs. Matched") ///
    ytitle("% of Projects with Improvement Type") /// 
	note("Note: The average number of receipts per project in the FMIS only group is 2.15, but is 4.0 for the Matched group")
graph export "$output/imprvmt_types_frequency_combined.png", replace
