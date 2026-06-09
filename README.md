# FMIS

## Data Overview 

This section documents the data that we use. 

### FMIS 
The primary dataset is FMIS (Financial Management Information System). This is a financial reimbursement system for states to receive reimbursements from the federal government, not a project management system. Data was FOIA'd from the federal DOT. We received the data in raw xml format, then parsed it into csv format, then performed further cleaning and saved the data in .dta files. 

General FMIS variable documentation: see
* `/FHWA cost data/Data/FMIS 5 EDS To States.docx`
* `/FHWA cost data/Data/FMIS5 Data Dictionary-Projects.xlsx`


Raw XML data directory: `/FHWA Cost Data/Data/Raw/FOIA_2025/`

CSV data directory: `/FHWA Cost Data/Data/CSVs/`

Cleaned dta files: `/FHWA Cost Data/Data/Intermediate`
    * `receipt_level_FMIS.data`: rich receipt-level data
    * `receipt_level_FMIS_lite.data`: a smaller 'lite' version of the receipt-level data, with some larger and less-used variables removed for faster data processing 
    * `project_level_FMIS.data`: rich project-level data
    * `project_level_FMIS_lite.data`: a smaller 'lite' version of the project-level data, with some larger and less-used variables removed for faster data processing. 

This diagram provides an overview of the hierarchical structure found in the raw XML data: 

<img width="712" height="472" alt="Image" src="https://github.com/user-attachments/assets/de6e197b-f774-4929-bf72-3b82a5d5bd9f" />

A few notes: 
* A project may have multiple reimbursements. We consider a reimbursement to be identified by a `Detail` object. 
* The `Detail`/reimbursements are uniquely identified by the combination of `line number` and `program code`. (The detail's line number doesn't uniquely identify a reimbursement and we are not sure why.)
* A single reimbursement has nested location data, either in the NonGIS field or GIS field. According to Stephanie/FMIS contacts, the GIS data was only added starting in FMIS version 5 (around 2010). 
* If it has the GIS field, it can have multiple `GISBreakdown` objects. This is where information like state FIPS, county FIPS, congressional district, urban/rural code, etc. are stored. 

The parsed CSV data flattens the XML hierarchy. In general, each row represents one reimbursement. When a reimbursement has multiple GISBreakdown records (i.e., spans multiple counties), each breakdown is expanded to its own row. 





### PR-511 

PR-511 is a historical record of segment-level data on interstate highway construction. This includes information on mile markers and open dates (as well as some sparse data on planning/ROW and construction starts). We are trying to match FMIS project entries to PR-511 segments so that we can link project spending to project mileage. 


### TIGER/Line 
Census geodata, including local roads, used for geocoding. 

### HPMS/NHPN
National geospatial dataset of the highway network. 

### Other 
We use CPI data from FRED: https://fred.stlouisfed.org/series/CPIAUCSL 

County FIPS codes are from the Census: https://www2.census.gov/geo/docs/reference/codes2020/national_county2020.txt 

(Or, go to https://www.census.gov/library/reference/code-lists/ansi.html and navigate to 2020 > County and County Equivalents and in the state dropdown, choose "United States".)


## Setting up GitHub and git 

PLACEHOLDER

### GitHub 


### git 

Recommend HTTPS authentication as it's much easier. It should not be necessary to use SSH (which has better security but is more complicated to set up.)

When you log in to git from the command line for the first time, instead of using your passcode, you'll need to generate a Personal Access Token (since git disabled password login, but never updated the user interface, so it confusingly still asks for password.) 

See instructions: 
https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github#authenticating-with-the-command-line 

- Go to token classic > generate new token 
- add Note/nickname so you remember what it was for 
- expiration: I recommend no expiration (none of what we work on requires high security). 
- Scopes: all you need to select is `repo`. This should be enough to read and write/push code. 








## Using Gemini 
PLACEHOLDER 
* insert instructions on API keys. 