/*==============================================================================
 	FMIS data processing 
    This script cleans the PR-511 highway segment opening data. 
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

* ==============================================================================
global pr511_intermediate "$intermediate_data/PR_511"
if !direxists("$pr511_intermediate") mkdir "$pr511_intermediate"

* start with the Hubbard Mazzeo data which already includes their hand-merged county data 
use "$raw_data/PR_511/hubbard_mazzeo/openings/highway10122.dta", clear

* parse opening date
gen int open_year = (open / 100) + 1900 // first two digits of "open" var 
gen int open_month = mod(open, 100)

* parse route 
* drop trailing zeros; the leading zeros are already dropped 
gen int route = rte / 10 

gen mp_start = mpdst / 100 // assuming data records 2 decimals, otherwise the scale would be unrealistic 
label variable mp_start "milepost start"
gen seg_len = seg / 100 // handwritten annotated documentation notes that seg records 2 decimals  
label variable seg_len "segment length (miles)"
gen mp_end = mp_start + seg_len
label variable mp_end "milepost end"

* handle I-35 E/W which got coded as 351 and 352 in the 'rtereal' variable 
* TODO 

* label counties 
* TODO

* combine consecutive connected segments which opened in the same month
sort st route open_year open_month county mp_start

* segments with missing values shouldn't get pooled in bysort - give unique chain ids 
gen byte _chain_solo = missing(st) | missing(route) | missing(open_year) | missing(open_month) | missing(county)

* identify chains (with small tolerance for machine rounding errors)
bysort st route open_year open_month county: ///
    gen byte chain_break = (_n == 1) | (abs(mp_start - mp_end[_n-1]) > 0.01) if _chain_solo == 0

bysort st route open_year open_month county: ///
    gen int _chain_seq = sum(chain_break) if _chain_solo == 0
drop chain_break

* create a globally unique segment ID across the whole dataset
egen long chain_id = group(st route open_year open_month county _chain_seq) if _chain_solo == 0

* assign unique chain ids to segments with missing values (set the chain ids to increment starting from the current max chain id)
quietly summarize chain_id, meanonly
local max_chain = cond(r(N) == 0, 0, r(max))
egen long _solo_id = seq() if _chain_solo == 1
replace chain_id = `max_chain' + _solo_id if _chain_solo == 1

drop _chain_solo _chain_seq _solo_id

keep chain_id sh st state county region open_year open_month route mp_start mp_end seg_len lane paveway rte rtereal stgp 

* construct a county fips variable for convenience
gen long county_fips = real(string(st, "%02.0f") + string(county, "%03.0f")) if !mi(st) & !mi(county)

save "$pr511_intermediate/PR511_hubbardmazzeo.dta", replace

* also save as csv 
export delimited using "$pr511_intermediate/PR511_hubbardmazzeo.csv", replace

* save another copy of just the chain-level data
collapse (sum) chain_len = seg_len (first) sh st state county county_fips route region open_year open_month (min) mp_start (max) mp_end, by(chain_id)
save "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", replace

* also save as csv 
export delimited using "$pr511_intermediate/PR511_hubbardmazzeo_chained.csv", replace

* ==============================================================================
* Nate Baum PR-511 data
* ==============================================================================

// the majority of this code comes from NBS's .do file - a copy is stored in baum_snow_form500.do

************** 1. Read in Raw Data *********************

clear
*read in route log and finder list data
insheet using "$raw_data/PR_511/baum_snow/routelog.csv"
compress
sort statefips intst
save "$raw_data/PR_511/baum_snow/routelog.dta", replace
clear

*read in the form 500 data

infile sh i str5 rte seo st mpost seg str5 check str1 c str4 stgp date1 date2 date3 date4 date5 date6 date7 date8 date9 using "$raw_data/PR_511/baum_snow/roads1_final.csv"
gen newrd = 0
compress
save "$raw_data/PR_511/baum_snow/roads1_final.dta"
clear

infile sh i str5 rte seo st mpost seg str5 check str1 c str4 stgp date1 date2 date3 date4 date5 date6 date7 date8 date9 using "$raw_data/PR_511/baum_snow/roads2_final.csv"
gen newrd = 0
save "$raw_data/PR_511/baum_snow/roads2_final.dta",replace
clear

infile sh i str5 rte seo st mpost seg str5 check str1 c str4 stgp date1 date2 date3 date4 date5 date6 date7 date8 date9 using "$raw_data/PR_511/baum_snow/roads3_final.csv"
gen newrd = 1

append using "$raw_data/PR_511/baum_snow/roads1_final.dta"
append using "$raw_data/PR_511/baum_snow/roads2_final.dta"

sort st rte
save "$raw_data/PR_511/baum_snow/roads_final.dta",replace

erase "$raw_data/PR_511/baum_snow/roads1_final.dta"
erase "$raw_data/PR_511/baum_snow/roads2_final.dta"

************** 2. Clean Up Variables **************************

*These are completely empty observations
sum if st==.
tab rte if st==.
drop if st==.

keep rte st mpost seg check stgp date* newrd

*fix up intst
replace rte = trim(rte)
gen RTE = real(rte)
replace RTE = RTE/10
replace rte = "35E" if rte=="035E"
replace rte = "35W" if rte=="035W"
replace rte = "35W" if rte=="03SW"
replace rte = string(RTE) if rte~="35E" & rte~="35W"
gen str3 intst = trim(rte)

*fix mpost flag variable
replace check = "0" if trim(check)=="ERROR"
gen chck = real(check)
drop check
rename chck check

*make dates reals in the year only
/*
gen d_stgp = date1-100*int(date1/100)
gen d_3to1 = date2-100*int(date2/100)
gen d_2to1 = date3-100*int(date3/100)
gen d_3to2 = date4-100*int(date4/100)
gen d_4to3 = date5-100*int(date5/100)
gen d_4 = date6-100*int(date6/100)
gen d_5to43 = date7-100*int(date7/100)
gen d_5to41 = date8-100*int(date8/100)
gen d_6 = date9-100*int(date9/100)
*/

local names d_stgp d_3to1 d_2to1 d_3to2 d_4to3 d_4 d_5to43 d_5to41 d_6

local i = 1
foreach date of varlist date1-date9 {
    local nm : word `i' of `names'
    gen str s = string(`date', "%04.0f")
    gen `nm'_m = real(substr(s, 1, 2))
	gen `nm'_y = real(substr(s, 3, 4))
    gen `nm' = string(`nm'_y, "%02.0f") + string(`nm'_m, "%02.0f")
	destring `nm', replace force
	drop s `nm'_m `nm'_y
    local ++i
}

*change variable names to match other dataset
rename st statefips
rename seg length

// removing this right now, can go back to and change
*drop Hawaii/Alaska
*drop if statefips==15|statefips==2

*fix stgp
tab stgp
replace stgp = "2A1F" if stgp=="2A1P"
replace stgp = "1A1F" if stgp=="1AIF"
replace stgp = "6B1" if stgp=="6BI"
replace stgp = "1A3F" if stgp=="IA3F"
replace stgp = "1A1F" if stgp=="IAIF"
replace stgp = "3A2" if stgp=="BA2"


***************** 3. Fix Up Milepost Numbers **********************

/*Fix the mposts on roads to match gisdat.dta.  In the form500 data,
it sets 35E and 35W in Texas and Minnesota with mposts as continuations
of 35.  35 officially continues along with 35E in both cases.  Similar situations
occur for other highways that overlap.  Also 3-digit highways are numbered
according to their milepost of the master 2-digit highway and are
converted to a milepost system commensurate with gisdat.dta.*/

sort statefips intst mpost

**These are local interstates that start at nonzero numbers
gen x = 0
by statefips intst: replace x = mpost[1] if real(intst)>100 & real(intst)~=.
replace mpost=mpost-x
drop x

/** These are gaps due to dual-numbered highways:
Each of these lines of code come from investigation of 
each highway separately in the data **/
replace mpost=mpost-8827 if statefips==27 & intst=="35E"
replace mpost=mpost-37051 if statefips==48 & intst=="35W"
replace mpost=mpost-37051 if statefips==48 & intst=="35E"
replace mpost=mpost-30121 if statefips==48 & intst=="27"
* fix 1 20 that has 130 miles of overlap at the beginning
replace mpost = mpost+13010 if statefips==1 & intst=="20"
* 6 80 is listed as starting at 530 and is too long so removing the 530
replace mpost = mpost-530 if statefips==6 & intst=="80"
* fix 18 465: roads_final3 mposts are inconsistent with 1 and 2
replace mpost = mpost-10139 if mpost>503 & statefips==18 & intst=="465"
replace mpost = mpost-557 if mpost>=14482 & statefips==18 & intst=="465"
* fix 20 435 No evidence of this portion found on map, but in f 500 data
replace mpost = mpost-5546 if mpost>=7580 & statefips==20 & intst=="435"
* fix 27 494
replace mpost = mpost-3016 if mpost>2800 & statefips==27 & intst=="494"
* fix 28 20/55
replace mpost = mpost+2520 if mpost>4400 & statefips==28 & intst=="20"
* fix 29 29/35
replace mpost = mpost+550 if statefips==29 & intst=="29"
* fix 29 64 first segment of highway (mi 0-11) never built
replace mpost = mpost-1110 if statefips==29 & intst=="64"
* fix 34 76
replace mpost = mpost-2800 if statefips==34 & intst=="76"
* fix 39 70: if make this fix then matches up to observed length
replace mpost = mpost-609 if mpost> 10121 & statefips==39 & intst=="70"
* fix 39 271/480
replace mpost = mpost+584 if mpost>2070 & statefips==39 & intst=="271"
* fix 39 275/74
replace mpost = mpost+345 if mpost>1000 & statefips==39 & intst=="275"
* fix 39 90 for 143 mi of overlap at the beginning
replace mpost = mpost+14280 if statefips==39 & intst=="90"
* fix 41 84: 3 mi too long in form 500 and 3 mi gap, so erase gap
replace mpost = mpost-232 if mpost>=1007 & statefips==41 & intst=="84"
* fix 42 79: matches if take out this part for which no form500 data
replace mpost = mpost-555 if mpost>6769 & statefips==42 & intst=="79"
* fix 45 526
replace mpost = mpost+898 if statefips==45 & intst=="526" & stgp=="1B1F"
* fix 47 65/40
replace mpost = mpost+100 if mpost>8250 & statefips==47 & intst=="65"
* fix 48 44
replace mpost = mpost-20000 if statefips==48 & intst=="44"
* fix 49 80/15
replace mpost = mpost+331 if mpost>12050 & statefips==49 & intst=="80"
* fix 49 84, insert record (which is duplicate of 15) from 41 to 77
replace mpost = mpost+3598 if mpost>4100 & statefips==49 & intst=="84"
* fix 47 75, insert record (which duplicates I 40) from 84 to 104
replace mpost = mpost+1960 if mpost>8400 & statefips==47 & intst=="75"
* 51 64 insert for duplicate of 81
replace mpost = mpost+3040 if mpost>5600 & statefips==51 & intst=="64"
* 51 77 insert for duplicate of 81
replace mpost = mpost+880 if mpost>3200 & statefips==51 & intst=="77"
* 42 70 insert for duplicate of 76 (calculated with Arcview and printed guide)
replace mpost = mpost+8722 if mpost>5864 & statefips==42 & intst=="70"


*************** 4. Flag and Fix Repeated Segments *************************

sort statefips intst mpost
*check0 flags problem obs off by 1 mi or more from next obs
*check1 flags problem obs off by any amount from next obs
gen check0 = 0
gen check1 = 0
qui by statefips intst: replace check0 = 1 if abs(mpost[_n+1]-mpost-length)<100
qui by statefips intst: replace check1 = 1 if mpost[_n+1]==mpost+length

/*drop repeated segments (with improvements at different dates)
do it several times to delete several segments in a row
The routine below flags all overlapping observations and then 
deletes the second one covering the same mileage*/
gen flag = 0
local i = 1
while `i'<=_N {
  *disp `i'
  if check0[`i']==0 & intst[`i']==intst[`i'+1] {
    local ref = mpost[`i']+length[`i']
    local i = `i'+1    
      if `ref'>mpost[`i']-50 {
        if abs(mpost[`i'+1]-`ref')<abs(mpost[`i']-`ref') {
          replace flag=1 if _n==`i'
          local i = `i'+1
        }
        if abs(mpost[`i'+1]-`ref')<abs(mpost[`i']-`ref') {
          replace flag=1 if _n==`i'
          local i = `i'+1
        }
        if abs(mpost[`i'+1]-`ref')<abs(mpost[`i']-`ref') {
          replace flag=1 if _n==`i'
          local i = `i'+1
        }
        if abs(mpost[`i'+1]-`ref')<abs(mpost[`i']-`ref') {
          replace flag=1 if _n==`i'
          local i = `i'+1
        }
        if abs(mpost[`i'+1]-`ref')<abs(mpost[`i']-`ref') {
          replace flag=1 if _n==`i'
          local i = `i'+1
        }
      }
  }
  local i = `i'+1
}
drop if flag==1


***************** 5. Flag and Fix Gaps ***********************

*now flag situations in which there is a gap of over 1 mile
gen gap = 0
sort statefips intst mpost
replace gap = 1 if mpost-mpost[_n-1]-length[_n-1]>100
by statefips intst: replace gap = 0 if _n==1
by statefips intst: replace gap = 1 if mpost~=0 & _n==1
list statefips intst mpost if gap==1

label variable gap "observation that is a gap in the form 500 data"

*create new observations to fill in missing ones
gen mpostm1 = mpost[_n-1]
gen lengthm1 = length[_n-1]
by statefips intst: replace mpostm1 = 0 if _n==1 
by statefips intst: replace lengthm1 = 0 if _n==1
save temp.dta,replace
keep if gap==1
*length is difference between beg of this seg and end of last seg
replace length = mpost-(mpostm1+lengthm1)
*mpost is end of last segment
replace mpost = mpostm1+lengthm1
replace check0 = 1
replace check1 = 1
replace stgp = "" 
replace d_stgp = .
replace d_3to1 = .
replace d_2to1 = .
replace d_3to2 = .
replace d_4to3 = .
replace d_4 = .
replace d_5to43 = .
replace d_5to41 = .
replace d_6 = .

*append back on -- missing values will be created for date variables
append using temp.dta
drop mpostm1 lengthm1
sort statefips intst mpost

*make mposts for ends of segment
gen mpost2 = .
replace mpost2 = mpost+length

*put mposts in whole miles so that gisdat can be merged on
replace mpost = mpost/100
replace mpost2 = mpost2/100
replace length = length/100


************************ 6a. Check Data ***************************

*do data checks 
/*
list statefips intst mpost d_3to2 d_2to1 if d_3to2>d_2to1 & d_3to2~=.

list statefips intst mpost d_stgp if (d_stgp>92 | d_stgp<40) & d_stgp~=.
list statefips intst mpost d_2to1 if (d_2to1>92 | d_2to1<40) & d_2to1~=.
list statefips intst mpost d_3to1 if (d_3to1>92 | d_3to1<40) & d_3to1~=.
list statefips intst mpost d_3to2 if (d_3to2>92 | d_3to2<40) & d_3to2~=.
list statefips intst mpost d_4to3 if (d_4to3>92 | d_4to3<40) & d_4to3~=.
list statefips intst mpost d_4 if (d_4>92 | d_4<40) & d_4~=.
list statefips intst mpost d_5to43 if (d_5to43>92 | d_5to43<40) & d_5to43~=.
list statefips intst mpost d_5to41 if (d_5to41>92 | d_5to41<40) & d_5to41~=.
list statefips intst mpost d_6 if (d_6>92 | d_6<40) & d_6~=.

list statefips intst mpost date1 if (date1>1292 | date1<136) & date1~=.
list statefips intst mpost date2 if (date2>1292 | date2<136) & date2~=.
list statefips intst mpost date3 if (date3>1292 | date3<136) & date3~=.
list statefips intst mpost date4 if (date4>1292 | date4<136) & date4~=.
list statefips intst mpost date5 if (date5>1292 | date5<136) & date5~=.
list statefips intst mpost date6 if (date6>1292 | date6<136) & date6~=.
list statefips intst mpost date7 if (date7>1292 | date7<136) & date7~=.
list statefips intst mpost date8 if (date8>1292 | date8<136) & date8~=.
list statefips intst mpost date9 if (date9>1292 | date9<136) & date9~=.

list statefips intst mpost length if length==.
list statefips intst mpost length if mpost==.
*/

rename mpost mpostb
rename mpost2 mpost

label variable mpost "mile post at end of segment"
label variable mpostb "mile post at beginning of segment before broken up"

keep statefips intst mpost mpostb length d_* stgp gap newrd

sort statefips intst mpost

************* NOTE - Baum Snow exact replication stops here, and our own design decisions enter

// these lines taken from below

*create local/federal funding dummy
*local is "B" and federal is "A", Howard-Cramer is "H"
gen fedfund = . 
replace fedfund = 1 if substr(stgp,2,1)=="A"
replace fedfund = 0 if substr(stgp,1,1)=="6"
replace fedfund = 0 if substr(stgp,2,1)=="B"
replace fedfund = 2 if substr(stgp,2,1)=="H"

drop if fedfund == 0
drop fedfund

* year of status group 1 or 2 opening -- do not perform the Brooks Liscow override of 2>1 for 3>2
gen d_open=min(d_3to1,d_2to1,d_3to2)
replace d_open=max(d_4to3,d_5to43,d_5to41) if d_open==.
replace d_open=d_6 if d_open==.
replace d_open=d_stgp if d_open==.
gen open_year = int(d_open/100)
replace open_year=99 if real(substr(stgp,1,1))>2 & real(substr(stgp,1,1))<6
gen open_month = mod(d_open, 100) if d_open!=99

gen d_first=min(d_4to3,d_4,d_5to43,d_5to41)
replace d_first=min(d_3to1,d_2to1,d_3to2) if d_first==.
replace d_first=d_6 if d_first==. & real(substr(stgp,1,1))>1 & real(substr(stgp,1,1))~=.
replace d_first=d_stgp if d_first==. & real(substr(stgp,1,1))>1 & real(substr(stgp,1,1))~=.
gen first_year = int(d_first/100)
gen first_month = mod(d_open, 100)
drop d_open d_first

drop if open_year == 99 | missing(open_year)

*manual recodes
* Arkansas
replace open_year = 69 if open_year==89 & statefips==5  & intst=="40" & round(mpostb,0.01) == 109.13
replace open_year = 65 if open_year==85 & statefips==5  & intst=="55" & round(mpostb,0.01) == 67.31
* Kansas
replace open_year = 68 if open_year==88 & statefips==20 & intst=="70" & round(mpostb,0.01) == 19.5
replace open_year = 65 if open_year==85 & statefips==20 & intst=="70" & round(mpostb,0.01) == 143.75
* Nebraska
replace open_year = 69 if open_year==89 & statefips==31 & intst=="80" & round(mpostb,0.01) == 94.56

*drop repeated observations
sort statefips intst mpost
drop if intst==intst[_n+1] & mpost==mpost[_n+1] 
duplicates drop statefips intst mpost mpostb, force
rename (mpostb mpost) (mp_start mp_end)
keep statefips stgp intst gap mp_start mp_end length open_year open_month

save "$pr511_intermediate/PR511_baumsnow.dta", replace  

exit

* ==============================================================================
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
keep if st == 6
keep if county == 85 | county == 81 // santa clara and san mateo
global county_lbl_def ///
    85 "Santa Clara" ///
    81 "San Mateo"
label define county_lbl $county_lbl_def, replace
label values county county_lbl
sort open_year open_month mp_start
drop st state region sh
keep if route == 280

save "$data/Hannah sandbox/PR511_sanmateo_santaclara.dta", replace

// keep if county == 81 
// sort mp_start 
// exit
