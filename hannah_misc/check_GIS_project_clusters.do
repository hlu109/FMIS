/*==============================================================================
    This script filters the FMIS GIS data so I can check what are appropriate clustering and stratification variables to use for val/test random sampling while avoiding leakage issues. 
==============================================================================*/
* Set user
local user = c(username)
if "`user'" == "andersonkovesci"{
	global code "/Users/andersonkovesci/Dropbox/FHWA cost data/Code/FMIS_andy"
	global output "/Users/andersonkovesci/Dropbox/FHWA cost data/Output/Andy"
	global data "/Users/andersonkovesci/Dropbox/FHWA cost data/Data"
	global raw_data "$data/Raw"
	global intermediate_data "$data/Intermediate"
}
else if "`user'" == "hl2266"{
    global project_root "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data"
	global code "$project_root/Code/FMIS_hannah"
    global output "$project_root/Output/Hannah"
    global data "$project_root/Data"
	global raw_data "$data/Raw"
	global intermediate_data "$data/Intermediate"
}
else if "`user'" == "fm557"{
    global project_root "C:/Users/fm557/YLS Dropbox/Finn Meffe/FHWA cost data"
	global code "$project_root/Code/FMIS_finn"
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
use "$intermediate_data/project_level_FMIS_w_GIS.dta" , clear

* build a unique project id from recipientid + federal_project_number
tostring recipientid, gen(recipientid_str)
gen pid = recipientid_str + "_" + federal_project_number
drop recipientid_str

* count number of distinct pids within each projecttitle
bysort projecttitle pid: gen byte _first_pid = (_n == 1)
bysort projecttitle: egen num_ids = total(_first_pid)
drop _first_pid

* count number of distinct county_fips within each projecttitle
bysort projecttitle county_fips: gen byte _first_cty = (_n == 1)
bysort projecttitle: egen num_county_x_title = total(_first_cty)
drop _first_cty

* unique group id for projecttitle x county_fips
egen cluster_id = group(projecttitle county_fips)

* compare identical GIS endpoints 
egen gis_endpoint_id = group(gis_beginpoint gis_endpoint)
duplicates tag cluster_id, gen(title_x_cty_cluster_sizes)
replace title_x_cty_cluster_sizes = 1 + title_x_cty_cluster_sizes
duplicates tag gis_endpoint_id, gen(dup_gis_endpoint_id)

* if we use project title x county for clustering, check the size of the clusters 
preserve
duplicates drop cluster_id, force
tab title_x_cty_cluster_sizes
restore

order projecttitle projectdescription num_ids num_county_x_title cluster_id title_x_cty_cluster_sizes gis_endpoint_id gis_begin gis_endpoint dup_gis_endpoint_id completion_year
tab dup_gis 


preserve
keep if title_x_cty_cluster_sizes > 10
gsort -title_x_cty_cluster_sizes
restore 

preserve 
drop if title_x_cty_cluster_sizes == 1
tab dup_gis 
exit
restore 
// preserve
keep if title_x_cty_cluster_sizes == 1
tab dup_gis 
keep if dup_gis_endpoint_id != 0
sort gis_endpoint_id
// restore 

// gsort -cluster_id // -num_ids 