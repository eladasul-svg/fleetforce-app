import os
import csv
import re
import random
import string

# ---------------------------------------------------------
# 1. CONFIGURATION
# ---------------------------------------------------------
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

# ---------------------------------------------------------
# 2. METADATA GENERATORS
# ---------------------------------------------------------

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
    # Only create if doesn't exist to preserve any manual edits (though we usually overwrite in this workflow)
    with open(meta_path, "w") as meta:
        meta.write('<?xml version="1.0" encoding="UTF-8"?>\n<CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">\n')
        meta.write(f'    <deploymentStatus>Deployed</deploymentStatus>\n')
        meta.write(f'    <label>{label}</label>\n')
        meta.write(f'    <pluralLabel>{label}s</pluralLabel>\n')
        meta.write('    <nameField><label>Name</label><type>Text</type></nameField>\n')
        meta.write(f'    <sharingModel>{sharing_model}</sharingModel>\n')
        meta.write('</CustomObject>')

def create_tab_metadata(obj_api_name):
    # Standard objects do not get custom tabs generated
    if obj_api_name in STANDARD_OBJECTS: return

    tab_path = f"force-app/main/default/tabs/{obj_api_name}.tab-meta.xml"
    os.makedirs(os.path.dirname(tab_path), exist_ok=True)
    
    # Random icon selection
    icon_num = random.randint(1, 100)
    
    with open(tab_path, "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write('<CustomTab xmlns="http://soap.sforce.com/2006/04/metadata">\n')
        f.write(f'    <customObject>true</customObject>\n')
        f.write(f'    <motif>Custom{icon_num}: Globe</motif>\n')
        f.write('</CustomTab>')

def create_app_metadata(app_name, tab_list):
    app_path = f"force-app/main/default/applications/{app_name}.app-meta.xml"
    os.makedirs(os.path.dirname(app_path), exist_ok=True)
    
    with open(app_path, "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        f.write('<CustomApplication xmlns="http://soap.sforce.com/2006/04/metadata">\n')
        f.write(f'    <brand>\n        <headerColor>#0070D2</headerColor>\n        <shouldOverrideOrgTheme>false</shouldOverrideOrgTheme>\n    </brand>\n')
        f.write(f'    <formFactors>Small</formFactors>\n    <formFactors>Large</formFactors>\n')
        f.write(f'    <isNavAutoTempTabsDisabled>false</isNavAutoTempTabsDisabled>\n')
        f.write(f'    <isNavPersonalizationDisabled>false</isNavPersonalizationDisabled>\n')
        f.write(f'    <label>{app_name}</label>\n')
        f.write(f'    <navType>Console</navType>\n') 
        f.write(f'    <uiType>Lightning</uiType>\n')
        
        # Tabs
        f.write('    <tabs>standard-home</tabs>\n')
        f.write('    <tabs>standard-Account</tabs>\n')
        f.write('    <tabs>standard-Contact</tabs>\n')
        for tab in sorted(tab_list):
            f.write(f'    <tabs>{tab}</tabs>\n')
            
        f.write('</CustomApplication>')

def create_permission_set(custom_objects, custom_fields, app_name):
    perm_path = "force-app/main/default/permissionsets"
    os.makedirs(perm_path, exist_ok=True)
    
    with open(f"{perm_path}/FleetAdmin.permissionset-meta.xml", "w") as p:
        p.write('<?xml version="1.0" encoding="UTF-8"?>\n<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">\n')
        p.write('    <label>Fleet Admin</label>\n    <hasActivationRequired>false</hasActivationRequired>\n')
        
        # 1. App Visibility
        p.write('    <applicationVisibilities>\n')
        p.write(f'        <application>{app_name}</application>\n')
        p.write('        <visible>true</visible>\n')
        p.write('    </applicationVisibilities>\n')

        # 2. Tab Visibility
        for obj in custom_objects:
            # Handle Standard Objects for Tab Settings
            tab_name = obj
            if obj in ["Account", "Contact", "Asset", "User"]:
                tab_name = f"standard-{obj}"
            
            p.write('    <tabSettings>\n')
            p.write(f'        <tab>{tab_name}</tab>\n')
            p.write('        <visibility>Visible</visibility>\n')
            p.write('    </tabSettings>\n')

        # 3. Object Permissions
        for obj in custom_objects:
            p.write('    <objectPermissions>\n')
            p.write(f'        <object>{obj}</object>\n')
            p.write('        <allowCreate>true</allowCreate>\n        <allowDelete>true</allowDelete>\n')
            p.write('        <allowEdit>true</allowEdit>\n        <allowRead>true</allowRead>\n')
            p.write('        <viewAllRecords>true</viewAllRecords>\n        <modifyAllRecords>true</modifyAllRecords>\n')
            p.write('    </objectPermissions>\n')

        # 4. Field Permissions
        for field_ref in custom_fields:
            p.write('    <fieldPermissions>\n')
            p.write(f'        <editable>true</editable>\n')
            p.write(f'        <field>{field_ref}</field>\n')
            p.write(f'        <readable>true</readable>\n')
            p.write('    </fieldPermissions>\n')
            
        p.write('</PermissionSet>')
    print("✅ Generated FleetAdmin Permissions (App + Tabs + Objects + Fields).")

# ---------------------------------------------------------
# 3. MAIN BUILD ROUTINE
# ---------------------------------------------------------
def build_fleetforce():
    base_path = "force-app/main/default/objects"
    md_objects = set()
    md_counter = {} 
    all_custom_objects = set()
    all_custom_fields = set()

    # PHASE 1: Scan for Master-Detail (Sharing Rules)
    if os.path.exists('Fields.csv'):
        with open('Fields.csv', mode='r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if "Master-Detail" in row.get('Data Type', ''):
                    obj_name = normalize_name(row['Object'])
                    md_objects.add(obj_name)

    # PHASE 2: Create Objects (From Objects.csv)
    if os.path.exists('Objects.csv'):
        with open('Objects.csv', mode='r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            for row in reader:
                api_name = normalize_name(row['FullName'])
                if api_name in STANDARD_OBJECTS: continue
                all_custom_objects.add(api_name)
                
                sharing = "ControlledByParent" if api_name in md_objects else "ReadWrite"
                create_object_metadata(api_name, row['Label'], sharing)
                # Note: Tab creation moved to forced sweep at end

    # PHASE 3: Create Fields & Orphans
    if os.path.exists('Fields.csv'):
        with open('Fields.csv', mode='r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if "Standard Files" in row['Field Label'] or "Standard Files" in row['API Name']: continue

                obj_api_name = normalize_name(row['Object'])
                field_api_name = row['API Name'].strip()
                if not obj_api_name or not field_api_name or field_api_name == 'Name': continue 
                
                # Register for Permissions
                rt = row['Data Type'].lower()
                is_md = "master-detail" in rt
                if not is_md:
                    all_custom_fields.add(f"{obj_api_name}.{field_api_name}")
                
                # CATCH ORPHANS
                if obj_api_name not in STANDARD_OBJECTS:
                    all_custom_objects.add(obj_api_name)
                    obj_path = os.path.join(base_path, obj_api_name)
                    if not os.path.exists(obj_path):
                        sharing = "ControlledByParent" if obj_api_name in md_objects else "ReadWrite"
                        create_object_metadata(obj_api_name, row['Object'], sharing)

                field_path = os.path.join(base_path, obj_api_name, 'fields', f"{field_api_name}.field-meta.xml")
                os.makedirs(os.path.dirname(field_path), exist_ok=True)
                
                with open(field_path, "w") as f_meta:
                    f_meta.write('<?xml version="1.0" encoding="UTF-8"?>\n<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">\n')
                    f_meta.write(f'    <fullName>{field_api_name}</fullName>\n')
                    f_meta.write(f'    <label>{row["Field Label"]}</label>\n')
                    
                    params = re.findall(r'\d+', row['Data Type'])
                    # Field type logic...
                    if "long text" in rt or "longtextarea" in rt:
                        f_meta.write('    <type>LongTextArea</type>\n    <length>32768</length>\n    <visibleLines>3</visibleLines>\n')
                    elif "url" in rt or "contentdoc" in rt:
                        f_meta.write('    <type>Url</type>\n')
                    elif "formula" in rt or "roll-up" in rt or "summary" in rt: 
                        f_meta.write('    <type>Number</type>\n    <precision>18</precision>\n    <scale>2</scale>\n')
                    elif "lookup" in rt or is_md:
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
                        base_type = row['Data Type'].split('(')[0]
                        f_meta.write(f'    <type>{base_type}</type>\n')
                        if params and "text" in rt: f_meta.write(f'    <length>{params[0]}</length>\n')
                    f_meta.write('</CustomField>')

    # PHASE 4: THE TAB SWEEP (Bulldozer Fix)
    print(f"🧹 Performing Tab Sweep on {len(all_custom_objects)} objects...")
    for obj in all_custom_objects:
        create_tab_metadata(obj)

    # PHASE 5: Create Console App
    create_app_metadata("Fleetforce", all_custom_objects)
    print("✅ Generated Fleetforce Console App.")

    # PHASE 6: Create Permissions
    all_objects_for_perms = all_custom_objects.union({"Account", "Contact"})
    create_permission_set(all_objects_for_perms, all_custom_fields, "Fleetforce")

if __name__ == "__main__":
    build_fleetforce()