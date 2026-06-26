/*==============================================================================
    This script analyzes the location variables in FMIS. 
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
else if "`user'" == "fm557"{
    global project_root "C:/Users/fm557/YLS Dropbox/Finn Meffe/FHWA cost data"
    global output "$project_root/Output/Finn"
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

global out_dir "$output/multicounty"
if !direxists("$out_dir") mkdir "$out_dir"

*==============================================================================
* analyze prevalence of multiple counties 
*==============================================================================

use "$intermediate_data/project_level_FMIS_lite.dta", clear

rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_cost_bills_adjusted = total_cost_mills / cpi / 1000
rename year completion_year

replace county_fips = subinstr(county_fips, " ", "", .)
gen n_counties = length(county_fips) - length(subinstr(county_fips, ";", "", .)) + 1


* plot distribution of number of counties in all FMIS projects 
tab n_counties, mi 
quietly count
local n_obs = r(N)
histogram n_counties, discrete frequency ///
    title("Number of Counties per Project") ///
    ytitle("Number of Projects") ///
    xtitle("Number of Counties") ///
    note( ///
        `"N = `n_obs' projects."' ///
        , size(small) span ///
    )
graph export "$out_dir/n_county_distrib.png", replace width(2500)

preserve
contract n_counties, freq(count)
drop if count == 0
replace count = log(count)

twoway bar count n_counties, ///
    title("Number of Counties per Project") ///
    ytitle("Log Number of Projects") ///
    xtitle("Number of Counties") ///
    note(`"N = `n_obs' projects."', size(small) span)
	
graph export "$out_dir/n_county_distrib_log.png", replace width(2500)
restore

* plot distribution of number of counties in Interstate Construction-funded projects
preserve 
    keep if interstate_syscode == 1
    tab n_counties, mi 
    quietly count
    local n_ic = r(N)
    histogram n_counties, discrete frequency  ///
        title("Number of Counties per Interstate Construction-funded Project") ///
        ytitle("Number of Projects") ///
        xtitle("Number of Counties") ///
        note( ///
            "Projects are included if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"N = `n_ic' projects."' ///
            , size(small) span ///
        )
    graph export "$out_dir/n_county_distrib_ic.png", replace width(2500)
	
contract n_counties, freq(count)
drop if count == 0
replace count = log(count)

twoway bar count n_counties,  ///
        title("Number of Counties per Interstate Construction-funded Project") ///
        ytitle("Log Number of Projects") ///
        xtitle("Number of Counties") ///
        note( ///
            "Projects are included if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"N = `n_ic' projects."' ///
            , size(small) span ///
        )
    graph export "$out_dir/n_county_distrib_ic_log.png", replace width(2500)
restore

preserve 
    keep if interstate_syscode == 1
    tab n_counties, mi 
    quietly count
    local n_ic = r(N)
    histogram n_counties, discrete frequency  ///
        title("Number of Counties per Interstate Construction-funded Project") ///
        ytitle("Number of Projects") ///
        xtitle("Number of Counties") ///
        note( ///
            "Projects are included if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"N = `n_ic' projects."' ///
            , size(small) span ///
        )
    graph export "$out_dir/n_county_distrib_ic.png", replace width(2500)
	
contract n_counties, freq(count)
drop if count == 0
replace count = log(count)

twoway bar count n_counties,  ///
        title("Number of Counties per Interstate Construction-funded Project") ///
        ytitle("Log Number of Projects") ///
        xtitle("Number of Counties") ///
        note( ///
            "Projects are included if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"N = `n_ic' projects."' ///
            , size(small) span ///
        )
    graph export "$out_dir/n_county_distrib_ic_log.png", replace width(2500)
restore

* plot cost-weighted distribution of number of counties in all FMIS projects 
* note the histogram function doesn't accept aweights so we have to do that manually with a bar chart

* seems that there are some negative values in total_cost_bills_adjusted

replace total_cost_bills_adjusted = abs(total_cost_bills_adjusted)

preserve
    tab n_counties [aw = total_cost_bills_adjusted], mi 
    collapse (sum) total_cost_bills_adjusted, by(n_counties)
    twoway (bar total_cost_bills_adjusted n_counties), ///
        title("Number of Counties per Project (Cost-Weighted)") ///
        ytitle("Billions of 2025 USD") ///
        xtitle("Number of Counties") ///
        note( ///
            `"N = `n_obs' projects."' ///
            , size(small) span ///
        )
    graph export "$out_dir/n_county_distrib_cost_wgt.png", replace width(2500)
	
	replace total_cost_bills_adjusted = log(total_cost_bills_adjusted)
	twoway (bar total_cost_bills_adjusted n_counties), ///
        title("Number of Counties per Project (Cost-Weighted)") ///
        ytitle("Log Billions of 2025 USD") ///
        xtitle("Number of Counties") ///
        note( ///
            `"N = `n_obs' projects."' ///
            , size(small) span ///
        )
    graph export "$out_dir/n_county_distrib_cost_wgt_log.png", replace width(2500)
restore

* plot spending over time for multi-county projects

gen multicounty = 0
replace multicounty = 1 if n_counties > 1

preserve
keep if multicounty == 1
collapse (sum) total_cost_bills_adjusted, by(completion_year)
keep if completion_year <= 2020 & completion_year >= 1950
twoway line total_cost_bills_adjusted completion_year, ///
	title("Total Spending Over Time in Multi-County Projects") ///
	ytitle("Billions of 2025 USD") ///
	xtitle("Completion Year") ///
	note("Period from 1950 to 2020", size(small) span)
	
	graph export "$out_dir/multicounty_total_timeseries.png", replace width(2500)
	
restore

preserve
keep if multicounty == 1 & interstate_syscode == 1
collapse (sum) total_cost_bills_adjusted, by(completion_year)
keep if completion_year <= 2000 & completion_year >= 1950
twoway line total_cost_bills_adjusted completion_year, ///
	title("Total Spending Over Time in Multi-County Interstate Construction-funded Projects", ///
	size(medium)) ///
	ytitle("Billions of 2025 USD") ///
	xtitle("Completion Year") ///
	note( ///
            "Projects are included if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            "Period from 1950 to 2000." ///
            , size(small) span ///
        )
	
	graph export "$out_dir/multicounty_total_timeseries_ic.png", replace width(2500)
	
restore

* total spending over time in single and multicounty projects

preserve
collapse (sum) total_cost_bills_adjusted, by(completion_year multicounty)
keep if completion_year <= 2020 & completion_year >= 1950

separate(total_cost_bills_adjusted), by(multicounty)
twoway ///
    (line total_cost_bills_adjusted0 completion_year) ///
    (line total_cost_bills_adjusted1 completion_year), ///
    title("Total Spending Over Time in Single and Multi-County Projects") ///
    legend(order(1 "Single County" 2 "Multi-County")) ///
    ytitle("Billions of 2025 USD") ///
    xtitle("Completion Year")
	
	graph export "$out_dir/multi_single_total_timeseries.png", replace width(2500)

restore

* average spending over time in single and multicounty projects

preserve
collapse (mean) total_cost_bills_adjusted, by(completion_year multicounty)
keep if completion_year <= 2020 & completion_year >= 1950

separate(total_cost_bills_adjusted), by(multicounty)
twoway ///
    (line total_cost_bills_adjusted0 completion_year) ///
    (line total_cost_bills_adjusted1 completion_year), ///
    title("Average Spending Over Time in Single and Multi-County Projects") ///
    legend(order(1 "Single County" 2 "Multi-County")) ///
    ytitle("Billions of 2025 USD") ///
    xtitle("Completion Year")
	
	graph export "$out_dir/multicounty_average_timeseries.png", replace width(2500)

restore

* total funding between both single and multi county interstate projects

preserve
keep if interstate_syscode == 1
collapse (sum) total_cost_bills_adjusted, by(completion_year multicounty)
keep if completion_year <= 2000 & completion_year >= 1950

separate(total_cost_bills_adjusted), by(multicounty)
twoway ///
    (line total_cost_bills_adjusted0 completion_year) ///
    (line total_cost_bills_adjusted1 completion_year), ///
    title("Total Spending Over Time in Single and Multi-County"  "Interstate Construction-Funded Projects", ///
	size(medium)) ///
    legend(order(1 "Single County" 2 "Multi-County")) ///
    ytitle("Billions of 2025 USD") ///
    xtitle("Completion Year")
	
	graph export "$out_dir/multi_single_total_timeseries_ic.png", replace width(4000)

restore

* average spending in interstates

preserve
keep if interstate_syscode == 1
collapse (mean) total_cost_bills_adjusted, by(completion_year multicounty)
keep if completion_year <= 2000 & completion_year >= 1950

separate(total_cost_bills_adjusted), by(multicounty)
twoway ///
    (line total_cost_bills_adjusted0 completion_year) ///
    (line total_cost_bills_adjusted1 completion_year), ///
    title("Average Spending Over Time in Single and Multi-County"  "Interstate Construction-Funded Projects", ///
	size(medium)) ///
    legend(order(1 "Single County" 2 "Multi-County")) ///
    ytitle("Billions of 2025 USD") ///
    xtitle("Completion Year")
	
	graph export "$out_dir/multicounty_average_timeseries_ic.png", replace width(4000)

restore
exit

* plot cost-weighted distribution of number of counties in Interstate Construction-funded projects
* note the histogram function doesn't accept aweights so we have to do that manually with a bar chart
preserve 
    keep if interstate_syscode == 1
    tab n_counties [aw = total_cost_bills_adjusted], mi 
    collapse (sum) total_cost_bills_adjusted, by(n_counties)
    twoway (bar total_cost_bills_adjusted n_counties), ///
        title("Number of Counties per Interstate Construction-funded Project (Cost-Weighted)") ///
        ytitle("Billions of 2025 USD") ///
        xtitle("Number of Counties") ///
        note( ///
            "Projects are included if at least one reimbursement is funded by the 'Interstate Construction' program." ///
            `"N = `n_ic' projects."' ///
            , size(small) span ///
        )
    graph export "$out_dir/n_county_distrib_ic_cost_wgt.png", replace width(2500)
restore


exit

* ==============================================================================
* old analysis of county types (currently broken since adding new counties was not backwards compatible)
* ==============================================================================
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear

* adjust for inflation 
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_cost_mills_adjusted = total_cost_mills / cpi
gen total_cost_bills_adjusted = total_cost_mills_adjusted / 1000

* identify state capitals 
tempfile state_caps
preserve
    import delimited using "$intermediate_data/state_capitals_FIPS.csv", varnames(1) clear
    keep county_fips
    save `state_caps'
restore

merge m:1 county_fips using `state_caps', keep(master match)
gen byte state_capital_county = (_merge == 3)
drop _merge

replace state_capital_county = 0 if missing(state_capital_county)

gen county_status = countyid
replace county_status = 1 if state_capital_county == 1
replace county_status = 2 if countyid != 999 & countyid != 0 & state_capital_county == 0 & !missing(countyid)
replace county_status = 0 if missing(countyid)
global county_status_lbl_def ///
    999  "Statewide" ///
    0  "Unknown/Missing" ///
    1  "State Capital" ///
    2  "Non-State Capital"
label define county_status_lbl $county_status_lbl_def, replace
label values county_status county_status_lbl


* get per capita costs 

* ==============================================================================
* Figures
* ==============================================================================
drop if year < 1950 | year > 2025

* figure legend labels 
local leg0 : label county_status_lbl 0
local leg1 : label county_status_lbl 1
local leg2 : label county_status_lbl 2
local leg999 : label county_status_lbl 999

* plot costs of projects by county type
preserve
collapse (sum) total_cost_bills_adjusted, by(year county_status)

graph twoway ///
    (line total_cost_bills_adjusted year if county_status == 0) ///
    (line total_cost_bills_adjusted year if county_status == 1) ///
    (line total_cost_bills_adjusted year if county_status == 2) ///
    (line total_cost_bills_adjusted year if county_status == 999), ///
    title("Total FMIS Expenditures by County Status") ///
    ytitle("Billions of 2025 USD") xtitle("Completion Year") ///
    xlabel(1950(10)2020) ///
    legend(title("County Type") order(3 "`leg2'" 2 "`leg1'" 4 "`leg999'" 1 "`leg0'")) ///
    note( ///
        "Some state capitals intersect with multiple counties. In such cases, the county with the largest overlap is" ///
        `"identified as the "state capital county"."', ///
        size(small) span ///
    )
graph export "$output/costs_by_county_status.png", replace width(2500)
restore

* same plot but interstate only 
preserve
keep if interstate_syscode == 1
collapse (sum) total_cost_bills_adjusted, by(year county_status)

graph twoway ///
    (line total_cost_bills_adjusted year if county_status == 0) ///
    (line total_cost_bills_adjusted year if county_status == 1) ///
    (line total_cost_bills_adjusted year if county_status == 2) ///
    (line total_cost_bills_adjusted year if county_status == 999), ///
    title("Total FMIS Interstate Expenditures by County Status") ///
    ytitle("Billions of 2025 USD") xtitle("Completion Year") ///
    xlabel(1950(10)2020) ///
    legend(title("County Type") order(3 "`leg2'" 2 "`leg1'" 4 "`leg999'" 1 "`leg0'")) ///
    note( ///
        "Some state capitals intersect with multiple counties. In such cases, the county with the largest overlap is" ///
        `"identified as the "state capital county"."', ///
        size(small) span ///
    )

graph export "$output/costs_by_county_status_interstate.png", replace width(2500)
restore