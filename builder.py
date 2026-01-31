import os
import csv
import re
import random
import string

# 1. Configuration & Mappings
NAME_FIXES = {
    "Asset Policy": "Asset_Insurance_Link__c",
    "Telemtry Violation": "Telemetry_Violation__c",
    "Telemetry Violation": "Telemetry_Violation__c",
    "Driver (Contact)": "Contact",
    "Maintenance Plan": "Maintenance_Plan__c",
    "Fleet Asset": "Fleet_Asset__c",
    "Fleet Branch": "Fleet_Branch__c",
    "Service Ticket": "Service_Ticket__c",
    "Telemetry Raw": "Telemetry_Raw__c",
    "Allocation": "Allocation__c",
    "Citation": "Citation__c",
    "Schedule": "Schedule__c",
    "Reservation": "Reservation__c"
}

STANDARD_OBJECTS = ["Contact", "Account", "User", "Event", "Task", "Asset"]

def normalize_name(raw_name):
    clean_name = raw_name.strip()
    if clean_name in NAME_FIXES: return NAME_FIXES[clean_name]
    if clean_name in STANDARD_OBJECTS: return clean_name
    
    clean_name = clean_name.replace("Telemtry", "Telemetry").replace(" ", "_")
    if not clean_name.endswith("__c"): clean_name += "__c"
    return clean_name

def create_object_metadata(obj_api_name, label, sharing_model):
    base_path = "force-app/main/default/objects"
    obj_path = os.path.join(base_path, obj_api_name)
    os.makedirs(os.path.join(obj_path, 'fields'), exist_ok=True)
    
    meta_path = f"{obj_path}/{obj_api_name}.object-meta.xml"
    
    # Don't overwrite if it exists (preserve description/settings from Objects.csv)
    if os.path.exists(meta_path): return

    print(f"Generating missing parent object: {obj_api_name}")
    with open(meta_path, "w") as meta:
        meta.write('<?xml version="1.0" encoding="UTF-8"?>\n<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n')
        meta.write(f'    <deploymentStatus>Deployed</deploymentStatus>\n')
        meta.write(f'    <label>{label}</label>\n')
        meta.write(f'    <pluralLabel>{label}s</pluralLabel>\n')
        meta.write('    <nameField><label>Name</label><type>Text</type></nameField>\n')
        meta.write(f'    <sharingModel>{sharing_model}</sharingModel>\n')
        meta.write('</CustomObject>')

def build_fleetforce():
    base_path = "force-app/main/default/objects"
    md_objects = set()
    md_counter = {}

    # 2. SCAN: Detect Master-Detail relationships first
    if os.path.exists('Fields.csv'):
        with open('Fields.csv', mode='r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if "Master-Detail" in row.get('Data Type', ''):
                    obj_name = normalize_name(row['Object'])
                    md_objects.add(obj_name)

    # 3. BUILD: Process Objects.csv
    with open('Objects.csv', mode='r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        for row in reader:
            api_name = normalize_name(row['FullName'])
            if api_name in STANDARD_OBJECTS: continue
            
            sharing = "ControlledByParent" if api_name in md_objects else "ReadWrite"
            create_object_metadata(api_name, row['Label'], sharing)

    # 4. BUILD: Process Fields.csv (And catch missing objects!)
    with open('Fields.csv', mode='r', encoding='utf-8-sig') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Block invalid fields
            if "Standard Files" in row['Field Label'] or "Standard Files" in row['API Name']: continue

            obj_api_name = normalize_name(row['Object'])
            field_api_name = row['API Name'].strip()
            
            if not obj_api_name or not field_api_name or field_api_name == 'Name': continue 
            
            # SAFETY NET: Ensure Custom Object Metadata exists
            if obj_api_name not in STANDARD_OBJECTS:
                sharing = "ControlledByParent" if obj_api_name in md_objects else "ReadWrite"
                create_object_metadata(obj_api_name, row['Object'], sharing)

            field_path = os.path.join(base_path, obj_api_name, 'fields', f"{field_api_name}.field-meta.xml")
            
            with open(field_path, "w") as f_meta:
                f_meta.write('<?xml version="1.0" encoding="UTF-8"?>\n<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">\n')
                f_meta.write(f'    <fullName>{field_api_name}</fullName>\n')
                f_meta.write(f'    <label>{row["Field Label"]}</label>\n')
                
                rt = row['Data Type'].lower() # Case-insensitive check
                params = re.findall(r'\d+', row['Data Type'])

                # --- Strict Type Logic ---
                if "long text" in rt or "longtextarea" in rt:
                    f_meta.write('    <type>LongTextArea</type>\n    <length>32768</length>\n    <visibleLines>3</visibleLines>\n')
                elif "url" in rt or "contentdoc" in rt:
                    f_meta.write('    <type>Url</type>\n')
                elif "formula" in rt or "roll-up" in rt or "summary" in rt: 
                    f_meta.write('    <type>Number</type>\n    <precision>18</precision>\n    <scale>2</scale>\n')
                elif "lookup" in rt or "master-detail" in rt:
                    is_md = "master-detail" in rt
                    
                    # Downgrade logic
                    if is_md:
                        count = md_counter.get(obj_api_name, 0)
                        if count >= 1: is_md = False
                        md_counter[obj_api_name] = count + 1

                    target_match = re.search(r'\((.*?)\)', row['Data Type'])
                    target = target_match.group(1) if target_match else "Account"
                    target = normalize_name(target)
                    
                    rand_suffix = ''.join(random.choices(string.ascii_uppercase, k=4))
                    base_rel = f"Rel_{field_api_name.replace('__c','')}_{rand_suffix}"
                    rel_name = base_rel[:40]

                    f_meta.write(f'    <type>{"MasterDetail" if is_md else "Lookup"}</type>\n')
                    f_meta.write(f'    <referenceTo>{target}</referenceTo>\n    <relationshipName>{rel_name}</relationshipName>\n')
                    if is_md: f_meta.write('    <writeRequiresMasterRead>false</writeRequiresMasterRead>\n')
                elif "picklist" in rt:
                    f_meta.write('    <type>Picklist</type>\n    <valueSet>\n        <valueSetDefinition>\n            <sorted>false</sorted>\n')
                    vals = row["Picklist Values"].split(',') if row["Picklist Values"] else ["Default"]
                    for v in vals:
                        clean_v = v.strip()
                        if clean_v: f_meta.write(f'            <value><fullName>{clean_v}</fullName><default>false</default><label>{clean_v}</label></value>\n')
                    f_meta.write('        </valueSetDefinition>\n    </valueSet>\n')
                elif "checkbox" in rt:
                    f_meta.write('    <type>Checkbox</type>\n    <defaultValue>false</defaultValue>\n')
                elif "geolocation" in rt:
                    f_meta.write('    <type>Location</type>\n    <displayLocationInDecimal>true</displayLocationInDecimal>\n    <scale>7</scale>\n')
                elif any(x in rt for x in ["number", "currency", "percent"]):
                    f_type = "Percent" if "percent" in rt else "Currency" if "currency" in rt else "Number"
                    f_meta.write(f'    <type>{f_type}</type>\n')
                    f_meta.write(f'    <precision>{params[0] if params else "18"}</precision>\n')
                    f_meta.write(f'    <scale>{params[1] if len(params)>1 else "0"}</scale>\n')
                else:
                    # Default Fallback for Text and unknown types
                    base_type = row['Data Type'].split('(')[0]
                    f_meta.write(f'    <type>{base_type}</type>\n')
                    if params and "text" in rt: f_meta.write(f'    <length>{params[0]}</length>\n')
                
                f_meta.write('</CustomField>')

if __name__ == "__main__":
    build_fleetforce()
    print("Done: Integrity Check Complete. Missing Objects Generated.")