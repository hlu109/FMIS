/*==============================================================================
 	FMIS data processing 
    This script plots spend/mi and mi/spend for PR-511 and FMIS interstate data linked at the spatial and year level. 
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
global out_dir "$output/PR511_FMIS"
if !direxists("$out_dir") mkdir "$out_dir"
global match_dir "$intermediate_data/PR511_FMIS"
global pr511_intermediate "$intermediate_data/pr_511"
if !direxists("$pr511_intermediate") mkdir "$pr511_intermediate"

// foreach subsample in full cty_per_yr cty_rt_per_yr cty_life cty_rt_life cty_openyr_ever cty_rt_openyr_ever {
foreach subsample in cty_openyr_ever cty_rt_openyr_ever {
	if "`subsample'" == "full" {
		local fig_suffix "_full"
		local subtitle_note ""
		local sample_note ""
	}
	else if "`subsample'" == "cty_per_yr" {
		local fig_suffix "_pr511_cty_max1chain_per_yr"
		local subtitle_note "Counties with unique chains within year"
		local sample_note "Sample restricted to counties with at most one PR-511 chain per opening year."
	}
	else if "`subsample'" == "cty_rt_per_yr" {
		local fig_suffix "_pr511_cty_rt_max1chain_per_yr"
		local subtitle_note "County x route cells with unique chains within year"
		local sample_note "Sample restricted to county x route cells with at most one PR-511 chain per opening year."
	}
	else if "`subsample'" == "cty_life" {
		local fig_suffix "_pr511_cty_1chain_ever"
		local subtitle_note "Counties with unique chains across all years"
		local sample_note "Sample restricted to counties with only one PR-511 chain across all years."
	}
	else if "`subsample'" == "cty_rt_life" {
		local fig_suffix "_pr511_cty_rt_1chain_ever"
		local subtitle_note "County x route cells with unique chains across all years"
		local sample_note "Sample restricted to county x route cells with only one PR-511 chain across all years."
	}
	else if "`subsample'" == "cty_openyr_ever" {
		local fig_suffix "_pr511_cty_1openyr_ever"
		local subtitle_note "Counties with unique chains within year"
		local sample_note "Sample restricted to counties where all chains opened in a single year."
	}
	else if "`subsample'" == "cty_rt_openyr_ever" {
		local fig_suffix "_pr511_cty_rt_1openyr_ever"
		local subtitle_note "County x route cells with unique chains within year"
		local sample_note "Sample restricted to county x route cells where all chains opened in a single year."
	}


	* ==========================================================================
	* merge FMIS and PR-511 data at spatial and year level (treating FMIS as a lagged year) and compare spend/mi and mi/spend 
	* ==========================================================================
	use "$intermediate_data/PR511_hubbardmazzeo_chained.dta", clear
	drop if open_year < 1960
	drop if open_year > 1995 

	rename st state_fips
	rename open_year pr_year
	gen long county_fips = real(string(state_fips, "%02.0f") + string(county, "%03.0f")) if !mi(state_fips) & !mi(county)

	if "`subsample'" == "cty_per_yr" {
		merge m:1 county_fips using "$pr511_intermediate/pr511_cty_max_one_chain_per_yr.dta", keep(3) nogen
		drop if pr_year >= 1985 
	}
	else if "`subsample'" == "cty_rt_per_yr" {
		merge m:1 county_fips route using "$pr511_intermediate/pr511_cty_rt_max_one_chain_per_yr.dta", keep(3) nogen
		drop if pr_year >= 1985
	}
	else if "`subsample'" == "cty_life" {
		merge m:1 county_fips using "$pr511_intermediate/pr511_cty_single_chain_ever.dta", keep(3) nogen
		drop if pr_year >= 1985 
	}
	else if "`subsample'" == "cty_rt_life" {
		merge m:1 county_fips route using "$pr511_intermediate/pr511_cty_rt_single_chain_ever.dta", keep(3) nogen
		drop if pr_year >= 1985 
	}
	else if "`subsample'" == "cty_openyr_ever" {
		merge m:1 county_fips using "$pr511_intermediate/pr511_cty_single_openyr_ever.dta", keep(3) nogen
		drop if pr_year >= 1985 
	}
	else if "`subsample'" == "cty_rt_openyr_ever" {
		merge m:1 county_fips route using "$pr511_intermediate/pr511_cty_rt_single_openyr_ever.dta", keep(3) nogen
		drop if pr_year >= 1985 
	}

	tempfile pr511_yr_block pr511_cal_yr pr511_state_yr_block pr511_nat_yr pr511_nat_block

	* PR-511: construct panel
	* 1. county x year, 2. county x 5-year block, 3. state x 5-year block, 4. national x year, 5. national x 5-year block

	* 1. county x year
	preserve
	collapse (sum) pr511_mi = chain_len, by(county_fips pr_year)
	save `pr511_cal_yr'
	restore

	* 2. county x 5-year block
	preserve
	gen int yr_block = .
	replace yr_block = 0 if pr_year < 1960 & !mi(pr_year)
	replace yr_block = 1 + floor((pr_year - 1960) / 5) if pr_year >= 1960 & !mi(pr_year)
	collapse (sum) pr511_mi = chain_len, by(county_fips yr_block)
	save `pr511_yr_block'
	restore

	* 3. state x 5-year block 
	preserve
	gen int yr_block = .
	replace yr_block = 0 if pr_year < 1960 & !mi(pr_year)
	replace yr_block = 1 + floor((pr_year - 1960) / 5) if pr_year >= 1960 & !mi(pr_year)
	collapse (sum) pr511_mi = chain_len, by(state_fips yr_block)
	save `pr511_state_yr_block'
	restore

	* 4. national x year 
	// all segments; don't get rid of missing counties or states
	preserve
	collapse (sum) pr511_mi = chain_len, by(pr_year)
	save `pr511_nat_yr'
	restore

	* 5. national x 5-year block
	// all segments; don't get rid of missing counties or states
	preserve
	gen int yr_block = .
	replace yr_block = 0 if pr_year < 1960 & !mi(pr_year)
	replace yr_block = 1 + floor((pr_year - 1960) / 5) if pr_year >= 1960 & !mi(pr_year)
	collapse (sum) pr511_mi = chain_len, by(yr_block)
	save `pr511_nat_block'
	restore

	* ===============
	* FMIS: construct panel
	* 1. county x year, 2. county x 5-year block, 3. state x 5-year block 

	use "$intermediate_data/receipt_level_FMIS_lite.dta", clear

	// drop if completion_year > 2000
	// drop if completion_year < 1960

	keep if funding_program == "Interstate Construction"
	// TODO: handle statewide or unknown county separately

	* adjust for inflation 
	rename completion_year year
	merge m:1 year using "$intermediate_data/CPI_2025.dta", keep(3) keepusing(cpi) nogen
	gen total_cost_mills_adj = total_cost_mills / cpi

	* track spending for different improvement types
	gen new_construction_cost = total_cost_mills_adj if new_construction
	gen row_cost = total_cost_mills_adj if detail_improvementtype == 16
	gen pe_cost = total_cost_mills_adj if detail_improvementtype == 15

	tempfile fmis_yr_block fmis_cal_yr fmis_state_yr_block fmis_nat_yr fmis_nat_block
	tempfile panel_cty_yr panel_cty_5yr panel_state_5yr panel_nat_yr panel_nat_5yr

	gen int pr_year = year - 1

	if "`subsample'" == "full" {
		local sample_size_note = ""
	}
	else if "`subsample'" == "cty_per_yr" {
		merge m:1 county_fips using "$pr511_intermediate/pr511_cty_max_one_chain_per_yr.dta", keep(3) nogen
		* count unique number of counties
		preserve
		keep county_fips
		duplicates drop
		local sample_size_note = "Number of unique counties: `=string(_N, "%9.0fc")'."
		restore
	}
	else if "`subsample'" == "cty_life" {
		merge m:1 county_fips using "$pr511_intermediate/pr511_cty_single_chain_ever.dta", keep(3) nogen
		* count unique number of counties
		preserve
		keep county_fips
		duplicates drop
		local sample_size_note = "Number of unique counties: `=string(_N, "%9.0fc")'."
		restore
	}
	else if "`subsample'" == "cty_rt_per_yr" {
		gen str3 fpn_prefix = substr(strtrim(federal_project_number), 1, 3)
		gen strL route = ustrregexra(fpn_prefix, "[^0-9]", "")
		destring route, replace 
		merge m:1 county_fips route using "$pr511_intermediate/pr511_cty_rt_max_one_chain_per_yr.dta", keep(3) nogen
		drop fpn_prefix
		* count unique number of county x route cells
		preserve
		keep county_fips route
		duplicates drop
		local sample_size_note = "Number of unique county x route cells: `=string(_N, "%9.0fc")'."
		restore
	}
	else if "`subsample'" == "cty_rt_life" {
		gen str3 fpn_prefix = substr(strtrim(federal_project_number), 1, 3)
		gen strL route = ustrregexra(fpn_prefix, "[^0-9]", "")
		destring route, replace
		merge m:1 county_fips route using "$pr511_intermediate/pr511_cty_rt_single_chain_ever.dta", keep(3) nogen
		drop fpn_prefix route
		* count unique number of county x route cells
		preserve
		keep county_fips route
		duplicates drop
		local sample_size_note = "Number of unique county x route cells: `=string(_N, "%9.0fc")'."
		restore
	}
	else if "`subsample'" == "cty_openyr_ever" {
		merge m:1 county_fips using "$pr511_intermediate/pr511_cty_single_openyr_ever.dta", keep(3) nogen
		* count unique number of counties
		preserve
		keep county_fips
		duplicates drop
		local sample_size_note = "Number of unique counties: `=string(_N, "%9.0fc")'."
		restore
	}
	else if "`subsample'" == "cty_rt_openyr_ever" {
		gen str3 fpn_prefix = substr(strtrim(federal_project_number), 1, 3)
		gen strL route = ustrregexra(fpn_prefix, "[^0-9]", "")
		destring route, replace
		merge m:1 county_fips route using "$pr511_intermediate/pr511_cty_rt_single_openyr_ever.dta", keep(3) nogen
		drop fpn_prefix
		* count unique number of county x route cells
		preserve
		keep county_fips route
		duplicates drop
		local sample_size_note = "Number of unique county x route cells: `=string(_N, "%9.0fc")'."
		restore
	}

	* 1. county x year
	preserve
	drop if mi(pr_year)
	drop if countyid == 999 | countyid == 0
	collapse (sum) total_cost_mills_adj new_construction_cost row_cost pe_cost (first) state_fips, by(county_fips pr_year)
	save `fmis_cal_yr'
	restore

	* 2. county x 5-year block
	preserve
	gen int yr_block = 0 if pr_year < 1960
	replace yr_block = 1 + floor((pr_year - 1960) / 5) if pr_year >= 1960 & !mi(pr_year)
	drop if countyid == 999 | countyid == 0
	collapse (sum) total_cost_mills_adj new_construction_cost row_cost pe_cost (first) state_fips, by(county_fips yr_block)
	save `fmis_yr_block'
	restore

	* 3. state x 5-year block 
	preserve
	gen int yr_block = 0 if pr_year < 1960
	replace yr_block = 1 + floor((pr_year - 1960) / 5) if pr_year >= 1960 & !mi(pr_year)
	collapse (sum) total_cost_mills_adj new_construction_cost row_cost pe_cost, by(state_fips yr_block)
	save `fmis_state_yr_block'
	restore

	* 4. national x year 
	// all segments; don't get rid of missing counties or states
	preserve
	drop if mi(pr_year)
	collapse (sum) total_cost_mills_adj new_construction_cost row_cost pe_cost, by(pr_year)
	save `fmis_nat_yr'
	restore

	* 5. national x 5-year block
	// all segments; don't get rid of missing counties or states
	preserve
	gen int yr_block = 0 if pr_year < 1960
	replace yr_block = 1 + floor((pr_year - 1960) / 5) if pr_year >= 1960 & !mi(pr_year)
	collapse (sum) total_cost_mills_adj new_construction_cost row_cost pe_cost, by(yr_block)
	save `fmis_nat_block'
	restore

	* ===============
	* merge FMIS with PR-511

	* 1. county x year
	use `fmis_cal_yr', clear
	merge 1:1 county_fips pr_year using `pr511_cal_yr', keep(3) nogen
	fillin county_fips pr_year
	replace pr511_mi = 0 if mi(pr511_mi)
	replace total_cost_mills_adj = 0 if mi(total_cost_mills_adj)
	replace new_construction_cost = 0 if mi(new_construction_cost)
	replace row_cost = 0 if mi(row_cost)
	replace pe_cost = 0 if mi(pe_cost)
	sort county_fips pr_year
	save `panel_cty_yr'

	* 2. county x 5-year block
	use `fmis_yr_block', clear
	merge 1:1 county_fips yr_block using `pr511_yr_block', keep(3) nogen
	fillin county_fips yr_block
	replace pr511_mi = 0 if mi(pr511_mi)
	replace total_cost_mills_adj = 0 if mi(total_cost_mills_adj)
	replace new_construction_cost = 0 if mi(new_construction_cost)
	replace row_cost = 0 if mi(row_cost)
	replace pe_cost = 0 if mi(pe_cost)
	gen int yr_block_open_lo = .
	replace yr_block_open_lo = 1960 + 5 * (yr_block - 1) if yr_block >= 1
	gen int yr_block_open_hi = .
	replace yr_block_open_hi = 1959 if yr_block == 0
	replace yr_block_open_hi = yr_block_open_lo + 4 if yr_block >= 1 & !mi(yr_block_open_lo)
	sort county_fips yr_block
	save `panel_cty_5yr'

	* 3. state x 5-year block
	use `fmis_state_yr_block', clear
	merge 1:1 state_fips yr_block using `pr511_state_yr_block', keep(3) nogen
	fillin state_fips yr_block
	replace pr511_mi = 0 if mi(pr511_mi)
	replace total_cost_mills_adj = 0 if mi(total_cost_mills_adj)
	replace new_construction_cost = 0 if mi(new_construction_cost)
	replace row_cost = 0 if mi(row_cost)
	replace pe_cost = 0 if mi(pe_cost)

	gen int yr_block_open_lo = .
	replace yr_block_open_lo = 1960 + 5 * (yr_block - 1) if yr_block >= 1
	gen int yr_block_open_hi = .
	replace yr_block_open_hi = 1959 if yr_block == 0
	replace yr_block_open_hi = yr_block_open_lo + 4 if yr_block >= 1 & !mi(yr_block_open_lo)
	sort state_fips yr_block
	save `panel_state_5yr'

	* 4. national x calendar year
	use `fmis_nat_yr', clear
	merge 1:1 pr_year using `pr511_nat_yr', keep(3) nogen

	replace pr511_mi = 0 if mi(pr511_mi)
	replace total_cost_mills_adj = 0 if mi(total_cost_mills_adj)
	replace new_construction_cost = 0 if mi(new_construction_cost)
	replace row_cost = 0 if mi(row_cost)
	replace pe_cost = 0 if mi(pe_cost)

	sort pr_year
	save `panel_nat_yr'

	* 5. national x 5-year block
	use `fmis_nat_block', clear
	merge 1:1 yr_block using `pr511_nat_block', keep(3) nogen

	replace pr511_mi = 0 if mi(pr511_mi)
	replace total_cost_mills_adj = 0 if mi(total_cost_mills_adj)
	replace new_construction_cost = 0 if mi(new_construction_cost)
	replace row_cost = 0 if mi(row_cost)
	replace pe_cost = 0 if mi(pe_cost)

	gen int yr_block_open_lo = .
	replace yr_block_open_lo = 1960 + 5 * (yr_block - 1) if yr_block >= 1
	gen int yr_block_open_hi = .
	replace yr_block_open_hi = 1959 if yr_block == 0
	replace yr_block_open_hi = yr_block_open_lo + 4 if yr_block >= 1 & !mi(yr_block_open_lo)
	capture label values yr_block yr_block_lbl

	sort yr_block
	save `panel_nat_5yr'

	* ===============
	* figures 
	* ===============

	* county x 5-year block means
	use `panel_cty_5yr', clear
	// keep if !mi(mi_per_dollar)
	collapse (sum) pr511_mi total_cost_mills_adj new_construction_cost row_cost pe_cost, by(yr_block)

	gen mi_per_dollar = pr511_mi / total_cost_mills_adj
	gen new_construction_mi_per_dollar = pr511_mi / new_construction_cost
	gen row_mi_per_dollar = pr511_mi / row_cost
	gen pe_mi_per_dollar = pr511_mi / pe_cost
	gen spend_per_mi = total_cost_mills_adj / pr511_mi
	gen new_construction_spend_per_mi = new_construction_cost / pr511_mi
	gen row_spend_per_mi = row_cost / pr511_mi
	gen pe_spend_per_mi = pe_cost / pr511_mi
	sort yr_block

	* construct labels for year ranges 
	gen x_range = ""
	replace x_range = "< 1960" if yr_block == 0
	gen int _open_lo = 1960 + 5 * (yr_block - 1) if yr_block >= 1
	replace x_range = string(_open_lo) + "-" + string(_open_lo + 4) if yr_block >= 1
	drop _open_lo

	drop if mi(yr_block) | mi(x_range) | x_range == ""

	local xlab ""
	forvalues i = 1/`=_N' {
		local b = yr_block[`i']
		local t = x_range[`i']
		local xlab `xlab' `b' "`t'"
	}

	* add offset to the twoway bar charts so the bars are side by side 
	gen double _x_all = yr_block - 0.15
	gen double _x_newc = yr_block + 0.15

	twoway ///
		(bar mi_per_dollar _x_all, barwidth(0.3)) ///
		(bar new_construction_mi_per_dollar _x_newc, barwidth(0.3)) ///
		, ///
		title("Mean interstate miles constructed per dollar of IC spending", size(medsmall)) ///
		subtitle("Balanced panel of county x 5-year blocks" "`subtitle_note'", size(vsmall)) ///
		xtitle("PR-511 opening year", size(small)) ///
		ytitle("Mean miles per million 2025 USD", size(small)) ///
		legend(order(1 "All" 2 "New construction")) ///
		xlabel(`xlab', labsize(small) angle(45)) ylabel(, labsize(small) format(%9.3g)) ///
		yscale(range(0 .)) ///
		note( ///
			"FMIS completion year is treated as if lagged one year behind PR-511 opening year." ///
			"Interstate receipts are identified by the Interstate Construction funding program code." ///
			"FMIS projects with an unknown county or statewide classification are excluded. Counties that did not appear in both FMIS and PR-511 are also excluded." ///
			"New construction includes reimbursements for new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
			"`sample_note'" ///
			`"`sample_size_note'"' ///
			, size(vsmall) span ///
		)
	graph export "$out_dir/avg_mi_per_dollar_yr_block`fig_suffix'.png", replace width(2400)

	twoway ///
		(bar spend_per_mi _x_all, barwidth(0.3)) ///
		(bar new_construction_spend_per_mi _x_newc, barwidth(0.3)) ///
		, ///
		title("Mean IC spending per mile of interstate opened", size(medsmall)) ///
		subtitle("Balanced panel of county x 5-year blocks" "`subtitle_note'", size(vsmall)) ///
		xtitle("PR-511 opening year", size(small)) ///
		ytitle("Mean spending per mile (millions of 2025 USD)", size(small)) ///
		legend(order(1 "All" 2 "New construction")) ///
		xlabel(`xlab', labsize(small) angle(45)) ylabel(, labsize(small) format(%9.3g)) ///
		yscale(range(0 .)) ///
		note( ///
			"FMIS completion year is treated as if lagged one year behind PR-511 opening year." ///
			"Interstate receipts are identified by the Interstate Construction funding program code." ///
			"FMIS projects with an unknown county or statewide classification are excluded. Counties that did not appear in both FMIS and PR-511 are also excluded." ///
			"New construction includes reimbursements for new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
			"`sample_note'" ///
			`"`sample_size_note'"' ///
			, size(vsmall) span ///
		)
	graph export "$out_dir/avg_spend_per_mi_yr_block`fig_suffix'.png", replace width(2400)

	use `panel_cty_yr', clear
	// drop if pr_year < 1950 // | pr_year > 1993
	collapse (sum) pr511_mi total_cost_mills_adj new_construction_cost row_cost pe_cost, by(pr_year)

	gen mi_per_dollar = pr511_mi / total_cost_mills_adj
	gen new_construction_mi_per_dollar = pr511_mi / new_construction_cost
	gen row_mi_per_dollar = pr511_mi / row_cost
	gen pe_mi_per_dollar = pr511_mi / pe_cost
	gen spend_per_mi = total_cost_mills_adj / pr511_mi
	gen new_construction_spend_per_mi = new_construction_cost / pr511_mi
	gen row_spend_per_mi = row_cost / pr511_mi
	gen pe_spend_per_mi = pe_cost / pr511_mi
	sort pr_year

	twoway (line mi_per_dollar new_construction_mi_per_dollar pr_year), ///
		title("Mean interstate miles constructed per dollar", size(medsmall)) ///
		subtitle("Balanced panel of county x calendar year" "`subtitle_note'", size(vsmall)) ///
		xtitle("PR-511 segment opening year", size(small)) ///
		ytitle("Mean miles per million 2025 USD", size(small)) ///
		xlabel(1960(5)1995, labsize(small) angle(45)) ///
		legend(order(1 "All" 2 "New construction")) ///
		note( ///
			"FMIS completion year is treated as if lagged one year behind PR-511 opening year." ///
			"Interstate receipts are identified by the Interstate Construction funding program code." ///
			"FMIS projects with an unknown county or statewide classification are excluded. Counties that did not appear in both FMIS and PR-511 are also excluded." ///
			"New construction includes reimbursements for new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
			"`sample_note'" ///
			`"`sample_size_note'"' ///
			, size(vsmall) span ///
		)
	graph export "$out_dir/avg_mi_per_dollar_year`fig_suffix'.png", replace width(2400)

	twoway (line spend_per_mi new_construction_spend_per_mi pr_year), ///
		title("Mean IC spending per mile of interstate opened", size(medsmall)) ///
		subtitle("Balanced panel of county x calendar year" "`subtitle_note'", size(vsmall)) ///
		xtitle("PR-511 segment opening year", size(small)) ///
		ytitle("Mean spending per mile (millions of 2025 USD)", size(small)) ///
		xlabel(1960(5)1995, labsize(small) angle(45)) ///
		legend(order(1 "All" 2 "New construction")) ///
		note( ///
			"FMIS completion year is treated as if lagged one year behind PR-511 opening year." ///
			"Interstate receipts are identified by the Interstate Construction funding program code." ///
			"FMIS projects with an unknown county or statewide classification are excluded. Counties that did not appear in both FMIS and PR-511 are also excluded." ///
			"New construction includes reimbursements for new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
			"`sample_note'" ///
			`"`sample_size_note'"' ///
			, size(vsmall) span ///
		)
	graph export "$out_dir/avg_spend_per_mi_year`fig_suffix'.png", replace width(2400)

	use `panel_state_5yr', clear
	collapse (sum) pr511_mi total_cost_mills_adj new_construction_cost row_cost pe_cost (count) n_state = pr511_mi, by(yr_block)

	gen mi_per_dollar = pr511_mi / total_cost_mills_adj
	gen new_construction_mi_per_dollar = pr511_mi / new_construction_cost
	gen row_mi_per_dollar = pr511_mi / row_cost
	gen pe_mi_per_dollar = pr511_mi / pe_cost
	gen spend_per_mi = total_cost_mills_adj / pr511_mi
	gen new_construction_spend_per_mi = new_construction_cost / pr511_mi
	gen row_spend_per_mi = row_cost / pr511_mi
	gen pe_spend_per_mi = pe_cost / pr511_mi

	* construct labels for year ranges 
	gen x_range = ""
	replace x_range = "< 1960" if yr_block == 0
	gen int _open_lo = 1960 + 5 * (yr_block - 1) if yr_block >= 1
	replace x_range = string(_open_lo) + "-" + string(_open_lo + 4) if yr_block >= 1
	drop _open_lo

	drop if mi(yr_block) | mi(x_range) | x_range == ""

	local xlab ""
	forvalues i = 1/`=_N' {
		local b = yr_block[`i']
		local t = x_range[`i']
		local xlab `xlab' `b' "`t'"
	}

	gen double _x_all = yr_block - 0.15
	gen double _x_newc = yr_block + 0.15

	* plot mi per dollar 
	twoway ///
		(bar mi_per_dollar _x_all, barwidth(0.3)) ///
		(bar new_construction_mi_per_dollar _x_newc, barwidth(0.3)) ///
		, ///
		title("Mean interstate miles constructed per dollar of IC spending", size(medsmall)) ///
		subtitle("Balanced panel of state x 5-year blocks" "`subtitle_note'", size(vsmall)) ///
		xtitle("PR-511 opening year", size(small)) ///
		ytitle("Mean miles per million 2025 USD", size(small)) ///
		legend(order(1 "All" 2 "New construction")) ///
		xlabel(`xlab', labsize(small) angle(45)) ylabel(, labsize(small) format(%9.3g)) ///
		yscale(range(0 .)) ///
		note( ///
			"FMIS completion year is treated as if lagged one year behind PR-511 opening year." ///
			"Interstate receipts are identified by the Interstate Construction funding program code." ///
			"New construction includes reimbursements for new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
			"`sample_note'" ///
			`"`sample_size_note'"' ///
			, size(vsmall) span ///
		)
	graph export "$out_dir/avg_mi_per_dollar_state_5yrblock`fig_suffix'.png", replace width(2400)

	* plot spend per mile 
	twoway ///
		(bar spend_per_mi _x_all, barwidth(0.3)) ///
		(bar new_construction_spend_per_mi _x_newc, barwidth(0.3)) ///
		, ///
		title("Mean IC spending per mile of interstate opened", size(medsmall)) ///
		subtitle("Balanced panel of state x 5-year blocks" "`subtitle_note'", size(vsmall)) ///
		xtitle("PR-511 opening year", size(small)) ///
		ytitle("Mean spending per mile (millions of 2025 USD)", size(small)) ///
		legend(order(1 "All" 2 "New construction")) ///
		xlabel(`xlab', labsize(small) angle(45)) ///
		ylabel(, labsize(small) format(%9.3g)) ///
		yscale(range(0 .)) ///
		note( ///
			"FMIS completion year is treated as if lagged one year behind PR-511 opening year." ///
			"Interstate receipts are identified by the Interstate Construction funding program code." ///
			"New construction includes reimbursements for new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
			"`sample_note'" ///
			`"`sample_size_note'"' ///
			, size(vsmall) span ///
		)
	graph export "$out_dir/avg_spend_per_mi_state_5yrblock`fig_suffix'.png", replace width(2400)

	* ===============
	* national x calendar year 
	use `panel_nat_yr', clear

	gen mi_per_dollar = pr511_mi / total_cost_mills_adj
	gen new_construction_mi_per_dollar = pr511_mi / new_construction_cost
	gen row_mi_per_dollar = pr511_mi / row_cost
	gen pe_mi_per_dollar = pr511_mi / pe_cost
	gen spend_per_mi = total_cost_mills_adj / pr511_mi
	gen new_construction_spend_per_mi = new_construction_cost / pr511_mi
	gen row_spend_per_mi = row_cost / pr511_mi
	gen pe_spend_per_mi = pe_cost / pr511_mi
	sort pr_year

	twoway (line mi_per_dollar new_construction_mi_per_dollar pr_year), ///
		title("Interstate miles constructed per dollar of IC spending", size(medsmall)) ///
		subtitle("National aggregate x calendar year" "`subtitle_note'", size(vsmall)) ///
		xtitle("PR-511 segment opening year", size(small)) ///
		ytitle("Miles per million 2025 USD", size(small)) ///
		xlabel(1960(5)1995, labsize(small) angle(45)) ///
		legend(order(1 "All" 2 "New construction")) ///
		yscale(range(0 .)) ///
		note( ///
			"FMIS completion year is treated as if lagged one year behind PR-511 opening year." ///
			"Interstate receipts are identified by the Interstate Construction funding program code." ///
			"National totals include counties coded as statewide or unknown in FMIS." ///
			"New construction includes reimbursements for new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
			"`sample_note'" ///
			`"`sample_size_note'"' ///
			, size(vsmall) span ///
		)
	graph export "$out_dir/agg_mi_per_dollar_natl_yr`fig_suffix'.png", replace width(2400)

	twoway (line spend_per_mi new_construction_spend_per_mi pr_year), ///
		title("IC spending per mile of interstate opened", size(medsmall)) ///
		subtitle("National aggregate x calendar year" "`subtitle_note'", size(vsmall)) ///
		xtitle("PR-511 segment opening year", size(small)) ///
		ytitle("Spending per mile (millions of 2025 USD)", size(small)) ///
		xlabel(1960(5)1995, labsize(small) angle(45)) ///
		legend(order(1 "All" 2 "New construction")) ///
		yscale(range(0 .)) ///
		note( ///
			"FMIS completion year is treated as if lagged one year behind PR-511 opening year." ///
			"Interstate receipts are identified by the Interstate Construction funding program code." ///
			"National totals include counties coded as statewide or unknown in FMIS." ///
			"New construction includes reimbursements for new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
			"`sample_note'" ///
			`"`sample_size_note'"' ///
			, size(vsmall) span ///
		)
	graph export "$out_dir/agg_spend_per_mi_natl_yr`fig_suffix'.png", replace width(2400)

	* ===============
	* national x 5-year block 
	use `panel_nat_5yr', clear

	gen mi_per_dollar = pr511_mi / total_cost_mills_adj
	gen new_construction_mi_per_dollar = pr511_mi / new_construction_cost
	gen row_mi_per_dollar = pr511_mi / row_cost
	gen pe_mi_per_dollar = pr511_mi / pe_cost
	gen spend_per_mi = total_cost_mills_adj / pr511_mi
	gen new_construction_spend_per_mi = new_construction_cost / pr511_mi
	gen row_spend_per_mi = row_cost / pr511_mi
	gen pe_spend_per_mi = pe_cost / pr511_mi
	sort yr_block

	gen x_range = ""
	replace x_range = "< 1960" if yr_block == 0
	gen int _open_lo = 1960 + 5 * (yr_block - 1) if yr_block >= 1
	replace x_range = string(_open_lo) + "-" + string(_open_lo + 4) if yr_block >= 1
	drop _open_lo

	drop if mi(yr_block) | mi(x_range) | x_range == ""

	local xlab ""
	forvalues i = 1/`=_N' {
		local b = yr_block[`i']
		local t = x_range[`i']
		local xlab `xlab' `b' "`t'"
	}

	gen double _x_all = yr_block - 0.15
	gen double _x_newc = yr_block + 0.15

	twoway ///
		(bar mi_per_dollar _x_all, barwidth(0.3)) ///
		(bar new_construction_mi_per_dollar _x_newc, barwidth(0.3)) ///
		, ///
		title("Interstate miles constructed per dollar of IC spending", size(medsmall)) ///
		subtitle("National aggregate x 5-year block" "`subtitle_note'", size(vsmall)) ///
		xtitle("PR-511 opening year", size(small)) ///
		ytitle("Miles per million 2025 USD", size(small)) ///
		legend(order(1 "All" 2 "New construction")) ///
		xlabel(`xlab', labsize(small) angle(45)) ylabel(, labsize(small) format(%9.3g)) ///
		yscale(range(0 .)) ///
		note( ///
			"FMIS completion year is treated as if lagged one year behind PR-511 opening year." ///
			"Interstate receipts are identified by the Interstate Construction funding program code." ///
			"National totals include counties coded as statewide or unknown in FMIS." ///
			"New construction includes reimbursements for new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
			"`sample_note'" ///
			`"`sample_size_note'"' ///
			, size(vsmall) span ///
		)
	graph export "$out_dir/agg_mi_per_dollar_natl_5yrblock`fig_suffix'.png", replace width(2400)


	twoway ///
		(bar spend_per_mi _x_all, barwidth(0.3)) ///
		(bar new_construction_spend_per_mi _x_newc, barwidth(0.3)) ///
		, ///
		title("IC spending per mile of interstate opened", size(medsmall)) ///
		subtitle("National aggregate x 5-year block" "`subtitle_note'", size(vsmall)) ///
		xtitle("PR-511 opening year", size(small)) ///
		ytitle("Spending per mile (millions of 2025 USD)", size(small)) ///
		legend(order(1 "All" 2 "New construction")) ///
		xlabel(`xlab', labsize(small) angle(45)) ylabel(, labsize(small) format(%9.3g)) ///
		yscale(range(0 .)) ///
		note( ///
			"FMIS completion year is treated as if lagged one year behind PR-511 opening year." ///
			"Interstate receipts are identified by the Interstate Construction funding program code." ///
			"National totals include counties coded as statewide or unknown in FMIS." ///
			"New construction includes reimbursements for new construction roadway, maintenance relocation, bridge new construction, construction engineering, or new tunnel." ///
			"`sample_note'" ///
			`"`sample_size_note'"' ///
			, size(vsmall) span ///
		)
	graph export "$out_dir/agg_spend_per_mi_natl_5yrblock`fig_suffix'.png", replace width(2400)
}
