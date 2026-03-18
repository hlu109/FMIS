/*==============================================================================
 	Total national highway spending
 	Hannah Lu 
	02/24/2026

	This script cleans and merges FHWA Highway Statistics HF-10/HF-210 data from 1921 to 2023.
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

* load 1999-2023 data
import delimited using "$raw_data/FHWA_Highway_Statistics/HF-10 1999-2023.csv", clear

keep if category == "Disbursements for Highways - by Expending Agencies"
drop category

rename item subgroup

// rename recipient agency
// label variable agency "expending agency"

gen agency = 1 if recipient == "Other Federal Funds and Accounts"
replace agency = 1 if recipient == "Highway Trust Fund Highway Account"
replace agency = 2 if recipient == "Local Governments"
replace agency = 3 if recipient == "State Agencies and D.C."
label define agency_lbl 1 "federal" 2 "state" 3 "local"
label values agency agency_lbl
* collapse the two federal recipient rows into one row (sum dollars)
destring dollars, replace ignore(",")
collapse (sum) dollars, by(year group subgroup agency)

gen cost_mills = dollars / 1000000
drop dollars 

tempfile hf10_1999_2023
save `hf10_1999_2023'

* load 1921-1995 data from HF-210 workbook (32 sheets named 1-32)
tempfile hf210_1921_1995
clear

forvalues s = 1/32 {
    di "s = `s'"
	import excel using "$raw_data/FHWA_Highway_Statistics/HF-210 1921-1995.xlsx", ///
		sheet("`s'") clear allstring
	* standardize column names to var1, var2, ... so positional references (var3, var5, etc.) work on every sheet
	ds
	local vlist `r(varlist)'
	local _i = 0
	foreach v of local vlist {
		local ++_i
		rename `v' var`_i'
	}
	* drop all columns after original column Z (keep var1-var26)
    ds
    local vlist `r(varlist)'
    local dropvars
    * build a list of all variables from position 27 onward (if any)
    local k : word count `vlist'
    forvalues j = 27/`k' {
        local dropvars `dropvars' `: word `j' of `vlist''
    }
    * drop them if they exist
    if "`dropvars'" != "" drop `dropvars'

	* keep year row (5) plus group/subgroup block (43-55)
	keep if _n == 5 | inrange(_n, 43, 55)
	* clean whitespace in all cells
	foreach v of varlist _all {
		replace `v' = trim(`v')
	}
	* extract year row (row 5) into a temporary dataset
	preserve
	keep in 1
	tempfile yearrow
	save `yearrow'
	restore

    drop if _n == 1 // drop the year row
    drop if _n == 4 | _n == 8 // drop the subtotals rows

	* define group and subgroup based on row positions 43–55 (same for all sheets)
	gen _rowblock = _n   // 1..11 corresponding to rows 43..55
	gen group = ""
	replace group = "Capital Outlay" if inrange(_rowblock, 1, 3)
	replace group = "Maintenance and Traffic Services" if inrange(_rowblock, 4, 6)
	replace group = "Administration and Research"        if _rowblock == 7
	replace group = "Highway Law Enforcement and Safety" if _rowblock == 8
	replace group = "Interest on Debt"                   if _rowblock == 9
	replace group = "Total Current Disbursements"        if _rowblock == 10
	replace group = "Bond Retirements"                   if _rowblock == 11
    
	gen subgroup = ""
	replace subgroup = "On State-Administered Highways" if inlist(_rowblock, 1, 4)
	replace subgroup = "On Locally Administered Roads"  if inlist(_rowblock, 2, 5)
	replace subgroup = "Not Classified by System"       if inlist(_rowblock, 3, 6)

    gen year = .
    gen htf_hwy_acct = .
    gen other_fed_funds = .
    gen federal = .
    gen state = .
    gen local = .

	* sheets 1–12: three years, gov columns in C/E/G; K/M/O; S/U/W
	if inrange(`s', 1, 12) {
		local yearcols  "3 11 19"
		local fedcols   "3 11 19"
		local statecols "5 13 21"
		local localcols "7 15 23"

		local i = 0
		foreach yc of local yearcols {
			local ++i
			* pick the federal/state/local columns corresponding to the i-th year on this sheet
			local fc : word `i' of `fedcols'
			local sc : word `i' of `statecols'
			local lc : word `i' of `localcols'

			* pull the year from the saved header row
			preserve
			use `yearrow', clear
			local y = ""
			if regexm(var`yc', "([0-9]{4})") local y = regexs(1)
			restore
            
			replace year = real("`y'")
			replace federal = real(var`fc')
			replace state = real(var`sc')
			replace local = real(var`lc')

            preserve
            keep year group subgroup htf_hwy_acct other_fed_funds federal state local
			capture append using `hf210_1921_1995'
			save `hf210_1921_1995', replace
            restore
		}
	}

	* sheets 13–31: two years, different gov column layout
	else if inrange(`s', 13, 31) {
		* first year: C (HTF), E (Other Fed), I state, K local
		* second year: O (HTF), Q (Other Fed), U state, W local
		local yearcols       "3 15"
		local htf_cols       "3 15"
		local other_fed_cols "5 17"
		local statecols "9 21"
		local localcols "11 23"

		forvalues i = 1/2 {
			local yc : word `i' of `yearcols'
			local sc : word `i' of `statecols'
			local lc : word `i' of `localcols'
			local f1 : word `i' of `htf_cols'
			local f2 : word `i' of `other_fed_cols'

			preserve
			use `yearrow', clear
			local y = ""
			if regexm(var`yc', "([0-9]{4})") local y = regexs(1)
			restore

			replace year = real("`y'")
			replace htf_hwy_acct    = real(var`f1')
			replace other_fed_funds = real(var`f2')
			replace federal         = htf_hwy_acct + other_fed_funds
			replace state           = real(var`sc')
			replace local           = real(var`lc')
            preserve
            keep year group subgroup federal htf_hwy_acct other_fed_funds state local
			capture append using `hf210_1921_1995'
			save `hf210_1921_1995', replace
            restore
		}
	}

	* sheet 32: one year, same layout as type-2 first year
	else if `s' == 32 {
		preserve
		use `yearrow', clear
		local y = ""
		if regexm(var3, "([0-9]{4})") local y = regexs(1)
		restore

		replace year = real("`y'")
		replace htf_hwy_acct    = real(var3)
		replace other_fed_funds = real(var5)
		replace federal         = htf_hwy_acct + other_fed_funds
		replace state           = real(var9)
		replace local           = real(var11)
        preserve
        keep year group subgroup federal htf_hwy_acct other_fed_funds state local
		capture append using `hf210_1921_1995'
		save `hf210_1921_1995', replace
        restore
	}
}

* convert agency amounts from wide columns to long format with an "agency" category
use `hf210_1921_1995', clear
drop htf_hwy_acct other_fed_funds

rename federal amount_federal
rename state   amount_state
rename local   amount_local

reshape long amount_, i(year group subgroup) j(agency_str) string
rename amount_ cost_mills
* convert agency to categorical 
gen agency = .
replace agency = 1 if agency_str == "federal"
replace agency = 2 if agency_str == "state"
replace agency = 3 if agency_str == "local"
label define agency_lbl 1 "federal" 2 "state" 3 "local"
label values agency agency_lbl
drop agency_str

* merge with 1999-2023 data
merge 1:1 year group subgroup agency using `hf10_1999_2023', nogen

* load 1996-1998 data individually 
// TODO

save "$intermediate_data/FHWA_Highway_Statistics/HF10_1921_2023.dta", replace