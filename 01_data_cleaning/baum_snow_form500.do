/*
form500-cons.do
Aug 2005

This program reads in and cleans the form 500 "PR-511" FHWA data.

1. Read in data from .csv files (converted from Excel files)
2. Fix up existing variables a bit
3. Fix roads where segments are missing because of overlaps
4. Flag and delete repeated segments.  Segments are sometimes repeated 
because they were upgraded at different times.
5. Fill in places where there is a gap of over 1 mile.
6a. Do some data consistency checks, especially on the dates 
6b. Merge on data from route log and finder list checking the length of each segment.
7. Put dataset through breakup.do to list roads mile by mile.
8. Do some final data cleaning and variable creation.

*/

clear
set more off

capture log close
log using form500-cons.log,replace text

set mem 40m


************** 1. Read in Raw Data *********************

*read in route log and finder list data
insheet using ../data/routelog.csv
compress

sort statefips intst 
save ../data/routelog.dta,replace
clear

*read in the form 500 data

#delimit ;
infile sh i str5 rte seo st mpost seg str5 check str1 c str4 stgp date1 date2 
date3 date4 date5 date6 date7 date8 date9 using ../data/roads2_final.csv;
gen newrd = 0;
compress;
save ../data/roads2_final.dta,replace;
clear;
infile sh i str5 rte seo st mpost seg str5 check str1 c str4 stgp date1 date2
date3 date4 date5 date6 date7 date8 date9 using ../data/roads1_final.csv;
gen newrd = 0;
save ../data/roads1_final.dta,replace;
clear;
infile sh i str5 rte seo st mpost seg str5 check str1 c str4 stgp date1 date2
date3 date4 date5 date6 date7 date8 date9 using ../data/roads3_final.csv;
gen newrd = 1;

append using ../data/roads2_final.dta;
append using ../data/roads1_final.dta;

#delimit cr

sort st rte
save ../data/roads_final.dta,replace

erase ../data/roads2_final.dta
erase ../data/roads1_final.dta


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
gen d_stgp = date1-100*int(date1/100)
gen d_3to1 = date2-100*int(date2/100)
gen d_2to1 = date3-100*int(date3/100)
gen d_3to2 = date4-100*int(date4/100)
gen d_4to3 = date5-100*int(date5/100)
gen d_4 = date6-100*int(date6/100)
gen d_5to43 = date7-100*int(date7/100)
gen d_5to41 = date8-100*int(date8/100)
gen d_6 = date9-100*int(date9/100)

*change variable names to match other dataset
rename st statefips
rename seg length

*drop Hawaii/Alaska
drop if statefips==15|statefips==2

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

rename mpost mpostb
rename mpost2 mpost

label variable mpost "mile post at end of segment"
label variable mpostb "mile post at beginning of segment before broken up"

keep statefips intst mpost mpostb length d_* stgp gap newrd

sort statefips intst mpost

compress
save tempx.dta,replace


************* 6b. Compare Lengths With Route Log & Finder List ***************

**check for discrepancies with route log and list them
by statefips intst: keep if _n==_N

keep statefips intst mpost length
sort statefips intst

merge statefips intst using ../data/routelog.dta
*should be 2 or 3 ONLY except for 45/326 (see note above)
tab _merge
list if _merge==1

gen mi500 = totmi-nhs

**** Each of these lines is from a manual check against the GIS data

*13 285/85 overlap is OK b/c at end
drop if statefips==13 & intst=="285"
*17 280/74 overlap is OK b/c at end
drop if statefips==17 & intst=="280"
*17 294/80 overlap is OK b/c at end
drop if statefips==17 & intst=="294"
*17 94/80 discrepancy is wrong b/c number in routelog for 94 is wrong
drop if statefips==17 & intst=="94"
*18 90/80 overlap OK b/c at end
drop if statefips==18 & intst=="90"
*19 80/35 mpost 3 mi too long - form 500 data is wrong
*21 71/75 overlap OK b/c at end
drop if statefips==21 & intst=="71"
*29 55/44 at end so OK
drop if statefips==29 & intst=="55"
*39 271/480 is too long in routelog 
drop if statefips==39 & intst=="271"
*54 64/77 too long in routelog
drop if statefips==54 & intst=="64"
*55 94/90 is 7 too long in routelog
drop if statefips==55 & intst=="94"

*6 15 no explanation but small
drop if statefips==6 & intst=="15"
**6 215 is a big discrepancy -- Reason to Use only Fed Funded Rds
**6 305 is a small discrepancy -- hard to find so don't worry about it
drop if statefips==6 & intst=="305"
**6 80 is a small discrepancy -- may be because of uncertainty where it begins in SF
drop if statefips==6 & intst=="80"
**6 880 is a small discrepancy
drop if statefips==6 & intst=="880"
** 13 75 is too short in form 500 data
** 17 39 is too short in route log
drop if statefips==17 & intst=="39"
** 17 55 is too long in route log
drop if statefips==17 & intst=="55"
** 17 57 is too long in route log
drop if statefips==17 & intst=="57"
** 17 70 is too short in route log
drop if statefips==17 & intst=="39"
** 17 90 is too long in route log
drop if statefips==17 & intst=="90"
** 17 72 I don't observe the sec 103 miles in route log
** 20 435 too long in f 500 data
* 21 64 too short in f 500 data
drop if statefips==21 & intst=="64"
* 24 895 discrepancy is from spur I think
drop if statefips==24 & intst=="895"
* 30 15 form 500 data is too short but no msas near the end so OK
** 32 515 don't observe Sec103 miles in form 500 data
** 45 77 has unobserved sec103 miles in form 500 data
** 51 264 has unobserved sec103 miles in form 500 data
** 51 664 has unobserved sec103 miles in form 500 data
** 55 43 has unobserved sc103 miles in form 500 data
** 894 discrepancy not explained (hard to see in mapquest)
** 55 90 doesn't count overlap with 39 in routelog
** 17 155 b/c of sec103
** as are all other . except
** 55 39 is either sec103 (not observed) or observed as 55 90

* 36 495 discrepancy comes because of partially unobserved sec103 miles
* 36 990 discrepancy from sec103 miles
* 39 270 form 500 data is too short inexplicably
* 39 70 too long in form 500 data
* 42 476 discrepancy due to unobserved sec103 miles
* 45 326 was renamed to 45 77 -- I throw this segment out b/c I don't know if relisted in 45/77 

list statefips intst mpost totmi nhs sec103 overlap overrt1 overrt2 if abs(mi500-mpost)>2 & overlap~=.
list statefips intst mpost totmi nhs sec103 if abs(mi500-mpost)>2 & overlap==.


*********** 7. Break Up Dataset into 1 Observation Per Milepost ******************

use tempx.dta,clear
**break up data into milepost by milepost
run breakup.do
log off
breakup form500 0
log on

**load newly created dataset and build a few more variables
use ../data/form500,clear


********* 8. Clean Up the Resulting Data Set *********************************

*fill in missing data for each segment that has been mileposted
sort statefips intst order
qui by statefips intst order: replace gap=gap[1]
qui by statefips intst order: replace d_stgp=d_stgp[1]
qui by statefips intst order: replace d_3to1=d_3to1[1]
qui by statefips intst order: replace d_4to3=d_4to3[1]
qui by statefips intst order: replace d_5to41=d_5to41[1]
qui by statefips intst order: replace mpostb=mpostb[1]
qui by statefips intst order: replace d_2to1=d_2to1[1]
qui by statefips intst order: replace d_4=d_4[1]
qui by statefips intst order: replace stgp=stgp[1]
qui by statefips intst order: replace d_3to2=d_3to2[1]
qui by statefips intst order: replace d_5to43=d_5to43[1]
qui by statefips intst order: replace d_6=d_6[1]
qui by statefips intst order: replace newrd=newrd[1]
replace length = 1 if length==.

rename length seg
drop order

*create local/federal funding dummy
*local is "B" and federal is "A", Howard-Cramer is "H"
gen fedfund = . 
replace fedfund = 1 if substr(stgp,2,1)=="A"
replace fedfund = 0 if substr(stgp,1,1)=="6"
replace fedfund = 0 if substr(stgp,2,1)=="B"
replace fedfund = 2 if substr(stgp,2,1)=="H"

*year of status group 1 or 2 opening
gen d_open=min(d_3to1,d_2to1,d_3to2)
replace d_open=max(d_4to3,d_5to43,d_5to41) if d_open==.
replace d_open=d_6 if d_open==.
replace d_open=d_stgp if d_open==.
replace d_open=99 if real(substr(stgp,1,1))>2 & real(substr(stgp,1,1))<6

gen d_first=min(d_4to3,d_4,d_5to43,d_5to41)
replace d_first=min(d_3to1,d_2to1,d_3to2) if d_first==.
replace d_first=d_6 if d_first==. & real(substr(stgp,1,1))>1 & real(substr(stgp,1,1))~=.
replace d_first=d_stgp if d_first==. & real(substr(stgp,1,1))>1 & real(substr(stgp,1,1))~=.

*drop repeated observations
sort statefips intst mpost
drop if intst==intst[_n+1] & mpost==mpost[_n+1] 

*drop all observations not on integer miles
drop if int(mpost)~=mpost

*This line is needed to get us back to a reasonable length
*of the 1948 highway system
replace newrd=1 if real(intst)>100 & real(intst)~=.

save ../data/form500.dta,replace

* Erase temporary and unneeded datasets
erase temp.dta
erase tempx.dta
erase ../data/roads_final.dta
erase ../data/routelog.dta

log close
