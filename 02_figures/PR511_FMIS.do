/*==============================================================================
 	FMIS data processing 
    This compares PR-511 and FMIS interstate data. 
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
* load receipt-level FMIS data
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear
keep if interstate_syscode == 1

* adjust for inflation 
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_cost_bills_adjusted = total_cost_mills / cpi / 1000

* focus on interstate construction-era spending through 1993
keep if year <= 1993
keep if state_fips <= 56
collapse (sum) cost_bills_2025 = total_cost_bills_adjusted, by(state_fips year)
tempfile fmis_state_year
save `fmis_state_year'

* load and collapse PR-511 interstate openings to state-year miles opened
use "$intermediate_data/PR511_hubbardmazzeo.dta", clear
rename st state_fips
rename open_year year
collapse (sum) interstate_mi = segment_length, by(state_fips year)
tempfile pr511_state_year
save `pr511_state_year'

use `fmis_state_year', clear
merge 1:1 state_fips year using `pr511_state_year'
drop _merge

* fill in a balanced 50-state panel for plotting
keep if year >= 1950 & year <= 1993
fillin state_fips year
replace cost_bills_2025 = 0 if mi(cost_bills_2025)
replace interstate_mi = 0 if mi(interstate_mi)
format cost_bills_2025 %9.2f
format interstate_mi %9.2f
sort state_fips year
decode state_fips, gen(state_name)

* save merged state-year series for reuse
save "$intermediate_data/PR511_FMIS_state_year.dta", replace

// use "$intermediate_data/PR511_FMIS_state_year.dta", clear

* generate figures
capture mkdir "$output/PR511_FMIS"
capture label define stateid_lbl 11 "DC", modify
egen state_order = group(state_fips)
gen page = ceil(state_order / 9)
levelsof page, local(pages)

foreach p of local pages {
    preserve
    keep if page == `p'

    twoway ///
        (line cost_bills_2025 year, ///
            lcolor(navy) lwidth(medthick) yaxis(1)) ///
        (line interstate_mi year, ///
            lcolor(maroon) lpattern(dash) lwidth(medthick) yaxis(2)), ///
        by(state_fips, ///
            cols(3) ///
            compact ///
            legend(position(6)) ///
            note("FMIS data uses project completion year; PR-511 uses segment opening year.", size(vsmall) span) ///
            title("Interstate Spending vs Miles Opened, page `p'", size(small)) ///
            b1title("Year", size(small)) ///
            l1title("2025 USD, billions", size(small)) ///
            r1title("Miles", size(medium)) ///
            subtitle(, size(tiny) bcolor(none) lcolor(none) fcolor(none))) ///
        graphregion(lcolor(none)) ///        
        xlabel(1950(10)1995, labsize(tiny) angle(45)) ///
        ylabel(, axis(1) labsize(small) angle(horizontal)) ///
        ylabel(, axis(2) labsize(small) angle(horizontal)) ///
        yscale(axis(1) range(0 .)) ///
        yscale(axis(2) range(0 .)) ///
        legend( ///
            order(1 "FMIS interstate" "spending" 2 "PR-511 interstate" "miles opened") ///
            rows(1) size(vsmall) ///
        ) ///
        xsize(8) ysize(8)
    graph export "$output/PR511_FMIS/interstate_spend_vs_mi_stategrid_`p'.png", replace width(3200)
    restore
}

preserve
collapse (sum) cost_bills_2025 interstate_mi, by(year)

twoway ///
    (line cost_bills_2025 year, ///
        lcolor(navy) lwidth(medthick) yaxis(1)) ///
    (line interstate_mi year, ///
        lcolor(maroon) lpattern(dash) lwidth(medthick) yaxis(2)), ///
    title("Interstate Spending vs Miles Opened", size(medsmall)) ///
    xtitle("Year") ///
    ytitle("2025 USD, billions", axis(1) size(small)) ///
    ytitle("Miles", axis(2) size(small)) ///
    xlabel(1950(10)1995, labsize(small) angle(45)) ///
    ylabel(, axis(1) labsize(small) angle(horizontal)) ///
    ylabel(, axis(2) labsize(small) angle(horizontal)) ///
    yscale(axis(1) range(0 .)) ///
    yscale(axis(2) range(0 .)) ///
    legend(order(1 "FMIS interstate" "spending" 2 "PR-511 interstate" "miles opened") ///
        rows(1) size(small) position(6) ring(1)) ///
    note("FMIS data uses project completion year; PR-511 uses segment opening year.", size(vsmall) span) ///
    xsize(8) ysize(6)

graph export "$output/PR511_FMIS/interstate_spend_vs_mi_all_states.png", replace width(2400)
restore
