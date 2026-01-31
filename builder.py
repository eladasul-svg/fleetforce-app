import os
import csv
import re

def build_fleetforce():
    base_path = "force-app/main/default/objects"
    obj_mapping = {}
    
    # List of standard objects we don't want to "create" as custom
    standard_objects = ['Contact', 'User', 'Account', 'Asset']

    # 1. Create Objects and build a Map
    with open('Objects.csv', mode='r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        for row in reader:
            api_name = row['FullName'].strip()
            label = row['Label'].strip()
            obj_mapping[label] = api_name
            
            # Only create folders for Custom Objects (__c)
            if api_name.endswith('__c'):
                obj_path = os.path.join(base_path, api_name)
                os.makedirs(os.path.join(obj_path, 'fields'), exist_ok=True)
                
                with open(f"{obj_path}/{api_name}.object-meta.xml", "w") as meta:
                    meta.write('<?xml version="1.0" encoding="UTF-8"?>\n<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n')
                    meta.write(f'    <deploymentStatus>Deployed</deploymentStatus>\n')
                    meta.write(f'    <description>{row["Description"]}</description>\n')
                    meta.write(f'    <label>{label}</label>\n')
                    meta.write(f'    <pluralLabel>{row["PluralLabel"]}</pluralLabel>\n')
                    meta.write(f'    <sharingModel>ReadWrite</sharingModel>\n')
                    meta.write('</CustomObject>')

    # 2. Create Fields
    with open('Fields.csv', mode='r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_obj = row['Object'].strip()
            # Clean up labels like "Driver (Contact)" to just "Contact"
            clean_obj_label = raw_obj.split('(')[-1].replace(')', '') if '(' in raw_obj else raw_obj
            
            # Map to API Name
            obj_api_name = obj_mapping.get(raw_obj, clean_obj_label)
            field_api_name = row['API Name'].strip()
            
            if not obj_api_name or not field_api_name or field_api_name == 'Name': 
                continue 
            
            # Path logic
            obj_folder_path = os.path.join(base_path, obj_api_name)
            
            # Ensure the folder exists (creates folder for standard objects if missing)
            os.makedirs(os.path.join(obj_folder_path, 'fields'), exist_ok=True)
            
            field_path = os.path.join(obj_folder_path, 'fields', f"{field_api_name}.field-meta.xml")
            
            with open(field_path, "w") as f_meta:
                f_meta.write('<?xml version="1.0" encoding="UTF-8"?>\n<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">\n')
                f_meta.write(f'    <fullName>{field_api_name}</fullName>\n')
                f_meta.write(f'    <label>{row["Field Label"]}</label>\n')
                
                raw_type = row['Data Type']
                if "Text" in raw_type:
                    length_match = re.findall(r'\d+', raw_type)
                    length = length_match[0] if length_match else "255"
                    f_meta.write(f'    <type>Text</type>\n    <length>{length}</length>\n')
                elif "Number" in raw_type or "Currency" in raw_type or "Percent" in raw_type:
                    params = re.findall(r'\d+', raw_type)
                    f_meta.write(f'    <type>{"Number" if "Number" in raw_type else "Currency" if "Currency" in raw_type else "Percent"}</type>\n')
                    if params:
                        f_meta.write(f'    <precision>{params[0]}</precision>\n    <scale>{params[1] if len(params)>1 else "0"}</scale>\n')
                elif "Lookup" in raw_type or "Master-Detail" in raw_type:
                    is_md = "Master-Detail" in raw_type
                    target_match = re.search(r'\((.*?)\)', raw_type)
                    target = target_match.group(1) if target_match else "Account"
                    f_meta.write(f'    <type>{"MasterDetail" if is_md else "Lookup"}</type>\n')
                    f_meta.write(f'    <referenceTo>{target}</referenceTo>\n    <relationshipName>{field_api_name.replace("__c","")}</relationshipName>\n')
                    if is_md: f_meta.write('    <writeRequiresMasterRead>false</writeRequiresMasterRead>\n')
                elif "Picklist" in raw_type:
                    f_meta.write('    <type>Picklist</type>\n    <valueSet>\n        <valueSetDefinition>\n            <sorted>false</sorted>\n')
                    for val in row["Picklist Values"].split(','):
                        if val.strip():
                            f_meta.write(f'            <value><fullName>{val.strip()}</fullName><default>false</default><label>{val.strip()}</label></value>\n')
                    f_meta.write('        </valueSetDefinition>\n    </valueSet>\n')
                elif "Checkbox" in raw_type:
                    f_meta.write('    <type>Checkbox</type>\n    <defaultValue>false</defaultValue>\n')
                else:
                    f_meta.write(f'    <type>{raw_type}</type>\n')
                f_meta.write('</CustomField>')

if __name__ == "__main__":
    build_fleetforce()
    print("Done: SFDX Metadata generated.")