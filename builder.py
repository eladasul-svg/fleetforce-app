import os
import csv
import re

def build_fleetforce():
    base_path = "force-app/main/default/objects"
    
    # 1. Create Objects from Objects.csv
    with open('Objects.csv', mode='r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        for row in reader:
            obj_name = row['FullName']
            obj_path = os.path.join(base_path, obj_name)
            os.makedirs(os.path.join(obj_path, 'fields'), exist_ok=True)
            
            with open(f"{obj_path}/{obj_name}.object-meta.xml", "w") as meta:
                meta.write('<?xml version="1.0" encoding="UTF-8"?>\n<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n')
                meta.write(f'    <deploymentStatus>Deployed</deploymentStatus>\n')
                meta.write(f'    <description>{row["Description"]}</description>\n')
                meta.write(f'    <label>{row["Label"]}</label>\n')
                meta.write(f'    <pluralLabel>{row["PluralLabel"]}</pluralLabel>\n')
                meta.write(f'    <sharingModel>ReadWrite</sharingModel>\n')
                meta.write('</CustomObject>')

    # 2. Create Fields from Fields.csv
    with open('Fields.csv', mode='r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        for row in reader:
            obj_name = row['Object']
            field_name = row['API Name']
            if not obj_name or not field_name or field_name == 'Name': continue 
            
            field_path = f"{base_path}/{obj_name}/fields/{field_name}.field-meta.xml"
            with open(field_path, "w") as f_meta:
                f_meta.write('<?xml version="1.0" encoding="UTF-8"?>\n<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">\n')
                f_meta.write(f'    <fullName>{field_name}</fullName>\n')
                f_meta.write(f'    <label>{row["Field Label"]}</label>\n')
                # Handling Data Types
                raw_type = row['Data Type']
                if "Text" in raw_type:
                    length = re.findall(r'\d+', raw_type)[0] if '(' in raw_type else "255"
                    f_meta.write(f'    <type>Text</type>\n    <length>{length}</length>\n')
                elif "Number" in raw_type or "Currency" in raw_type:
                    params = re.findall(r'\d+', raw_type)
                    f_meta.write(f'    <type>{"Number" if "Number" in raw_type else "Currency"}</type>\n')
                    f_meta.write(f'    <precision>{params[0]}</precision>\n    <scale>{params[1]}</scale>\n')
                elif "Lookup" in raw_type or "Master-Detail" in raw_type:
                    is_md = "Master-Detail" in raw_type
                    target = raw_type.split('(')[1].split(')')[0]
                    f_meta.write(f'    <type>{"MasterDetail" if is_md else "Lookup"}</type>\n')
                    f_meta.write(f'    <referenceTo>{target}</referenceTo>\n    <relationshipName>{field_name.replace("__c","")}</relationshipName>\n')
                    if is_md: f_meta.write('    <writeRequiresMasterRead>false</writeRequiresMasterRead>\n')
                elif "Picklist" in raw_type:
                    f_meta.write('    <type>Picklist</type>\n    <valueSet>\n        <valueSetDefinition>\n            <sorted>false</sorted>\n')
                    for val in row["Picklist Values"].split(','):
                        if val.strip():
                            f_meta.write(f'            <value><fullName>{val.strip()}</fullName><default>false</default><label>{val.strip()}</label></value>\n')
                    f_meta.write('        </valueSetDefinition>\n    </valueSet>\n')
                else:
                    f_meta.write(f'    <type>{raw_type}</type>\n')
                f_meta.write('</CustomField>')

if __name__ == "__main__":
    build_fleetforce()