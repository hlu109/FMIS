# -*- coding: utf-8 -*-
"""
Created on Thu May  1 15:11:15 2025
@author: nw428

IMPORTANT: NEED TO CHECK OUTPUT AGAINST XML BY HAND STILL.

           It looks like it is working but could be some bugs still.
"""

import xml.etree.ElementTree as ET
import pandas as pd
import os
import glob
import re
import getpass

# Add your username and input/output paths
username = getpass.getuser()
if username == "nw428":
    input_dir = "C:/Users/nw428/YLS Dropbox/Nicholas Whitaker/FHWA cost data/Data/Raw/FOIA_2025"
    output_dir = "C:/Users/nw428/YLS Dropbox/Nicholas Whitaker/FHWA cost data/Data/CSVs"
elif username == "andersonkovesci":
    input_dir = "/Users/andersonkovesci/Dropbox/FHWA cost data/Data/Raw/FOIA_2025"
    output_dir = "/Users/andersonkovesci/Dropbox/FHWA cost data/Data/CSVs"
else: 
    raise ValueError("Username not recognized. Please set input/output paths manually.")

#%%
def clean_text(text):
    if text is None:
        return ""
    # Replace newlines/tabs with spaces for csv output
    text = re.sub(r'[\r\n\t]+', ' ', text)
    text = re.sub(r'\s{2,}', ' ', text)
    return text.strip()

def parse_project_details(xml_file):
    tree = ET.parse(xml_file)
    root = tree.getroot()

    rows = []

    for project in root.findall('.//Project'):
        # Extract all project-level fields
        project_data = {}
        for child in project:
            if child.tag not in ['Details', 'Expenditures', 'ProjectGroups', 'RelatedProjects', 
                                  'UserDefinedFields', 'LegacyBridgeInfo']:
                project_data[child.tag] = clean_text(child.text)

        # Process each Detail - ONE ROW PER DETAIL
        for detail in project.findall('Details/Detail'):
            row = project_data.copy()
            
            # Add detail-level fields
            for item in detail:
                if item.tag not in ['Locations', 'UserDefinedFields']:
                    row[f'Detail_{item.tag}'] = clean_text(item.text)
            
            # Initialize all location fields as empty
            # NonGIS fields
            for field in ['StateId', 'CongDistId', 'CountyId', 'UrbanId', 'UrbanOrRural', 
                         'FunctionalSystem', 'SystemCode', 'GeneralOwnership', 'StructureNumber',
                         'PercentFunds', 'ACFunds', 'FederalFunds', 'StateFunds', 'LocalFunds',
                         'PrivateFunds', 'NonMonetaryFunds', 'OtherFunds', 'TotalCost']:
                row[f'NonGIS_{field}'] = ''
            
            # GIS fields
            for field in ['StateId', 'RouteId', 'BeginPoint', 'EndPoint', 'StructureNumber',
                         'PercentFunds', 'ACFunds', 'FederalFunds', 'StateFunds', 'LocalFunds',
                         'PrivateFunds', 'NonMonetaryFunds', 'OtherFunds', 'TotalCost']:
                row[f'GIS_{field}'] = ''
            
            # GISBreakdown fields
            for field in ['CongDistId', 'CountyId', 'UrbanId', 'UrbanOrRural', 'FunctionalSystem',
                         'SystemCode', 'GeneralOwnership', 'ACFunds', 'FederalFunds', 'StateFunds',
                         'LocalFunds', 'PrivateFunds', 'NonMonetaryFunds', 'OtherFunds', 'TotalCost']:
                row[f'GISBreakdown_{field}'] = ''
            
            # Now populate with data if it exists
            locations = detail.find('Locations')
            if locations is not None:
                nongis = locations.find('NonGIS')
                if nongis is not None:
                    for item in nongis:
                        row[f'NonGIS_{item.tag}'] = clean_text(item.text)
                
                gis = locations.find('GIS')
                if gis is not None:
                    for item in gis:
                        if item.tag != 'GISBreakdown':
                            row[f'GIS_{item.tag}'] = clean_text(item.text)
                    
                    breakdown = gis.find('GISBreakdown')
                    if breakdown is not None:
                        for item in breakdown:
                            row[f'GISBreakdown_{item.tag}'] = clean_text(item.text)
            
            rows.append(row)

    return pd.DataFrame(rows)
#%%
# Create output directory if it doesn't exist
os.makedirs(output_dir, exist_ok=True)
combined_data = []
# Loop through all XML files in the input directory
for xml_file in glob.glob(os.path.join(input_dir, "*.xml")):
    if os.path.basename(xml_file).startswith('~$'):
        #skip these, they are not real files
        continue
    try:
        df = parse_project_details(xml_file)
        combined_data.append(df)
        # Generate CSV filename based on the XML filename
        base_name = os.path.basename(xml_file)
        csv_name = os.path.splitext(base_name)[0] + ".csv"
        output_path = os.path.join(output_dir, csv_name)
        df.to_csv(output_path, index=False)
        print(f"Converted {xml_file} to {output_path}")

    except Exception as e:
        print(f"Failed to process {xml_file}: {e}")

# Save combined data to a single CSV
if combined_data:
    combined_df = pd.concat(combined_data, ignore_index=True)
else:
    combined_df = pd.DataFrame()

combined_df.to_csv(os.path.join(output_dir, "combined_data.csv"), index=False)
print("combined data saved to combined_data.csv, obs:", len(combined_df))
