"Here is the PROJECT_MEMORY.md file from our last session. Please read it to restore your context, load the included script into your memory, and let's begin Phase 2."
# 🐺 PROJECT MEMORY: Fleetforce Setup
**Status:** Phase 1 (Schema Build) COMPLETE
**Last Successful Deployment:** 0AfWl000000bWgrKAE (307 Components, 0 Errors)
**Current Phase:** Phase 2 (Data Seeding)

---

## 🧠 THE "WOLF STRATEGY" KNOWLEDGE BASE
*These rules are now hard-coded into our architecture. Do not deviate.*

### 1. Naming & Syntax Rules
* **The Suffix Law:** All Custom Objects MUST end in `__c`. Single-word objects (e.g., `Reservation`, `Schedule`) in the CSV are treated as Standard Objects unless we explicitly force the `__c` suffix.
* **Reserved Fields:** The field label "Standard Files" is reserved and cannot be created via Metadata API. It must be explicitly filtered out.
* **Type Sanitization:**
    * "Long Text" -> `LongTextArea` (requires visible lines).
    * "URL" -> `Url`.
    * "Roll-Up Summary" -> Temporarily deployed as `Number` to avoid dependency crashes; convert in UI later.

### 2. Relationship Architecture
* **The 40-Char Limit:** Relationship Names (`relationshipName`) have a hard 40-character limit.
    * *Solution:* We strip the name to 30 chars and append a 4-char random suffix (e.g., `Rel_Insurance_Policy_X9J2`).
* **The Duplicate Trap:** We use random suffixes to guarantee uniqueness and prevent "Duplicate Relationship Name" errors.
* **The "Two Masters" Rule:** An object cannot have two Master-Detail relationships to the same parent, or conflicting Master-Details.
    * *Solution:* Our script detects this. The first M-D is kept; the second is auto-downgraded to a `Lookup`.

### 3. Sharing & Security
* **The Master-Detail Constraint:** Any object with a Master-Detail field *cannot* have a `ReadWrite` sharing model.
    * *Solution:* The script pre-scans for M-D fields. If found, it forces `<sharingModel>ControlledByParent</sharingModel>`.

---

## 🛠️ THE GOLDEN BUILDER SCRIPT
*This script is the only one that works. It includes the logic for all the rules above.*

```python
import os
import csv
import re
import random
import string

# 1. Global Naming & Sanitization
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
    
    # Write metadata (overwrite if exists to ensure latest settings)
    with open(meta_path, "w") as meta:
        meta.write('<?xml version="1.0" encoding="UTF-8"?>\n<CustomObject xmlns="[http://soap.sforce.com/2006/04/metadata](http://soap.sforce.com/2006/04/metadata)">\n')
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
    if os.path.exists('Objects.csv'):
        with open('Objects.csv', mode='r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            for row in reader:
                api_name = normalize_name(row['FullName'])
                if api_name in STANDARD_OBJECTS: continue
                
                sharing = "ControlledByParent" if api_name in md_objects else "ReadWrite"
                create_object_metadata(api_name, row['Label'], sharing)

    # 4. BUILD: Process Fields.csv
    if os.path.exists('Fields.csv'):
        with open('Fields.csv', mode='r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # --- BLOCK INVALID FIELDS ---
                label_check = row['Field Label'].lower()
                if "standard files" in label_check: continue
                if "standard_files" in row['API Name'].lower(): continue

                obj_api_name = normalize_name(row['Object'])
                field_api_name = row['API Name'].strip()
                
                if not obj_api_name or not field_api_name or field_api_name == 'Name': continue 
                
                # SAFETY NET: Ensure Parent Object exists (even if missing from Objects.csv)
                if obj_api_name not in STANDARD_OBJECTS:
                    obj_path = os.path.join(base_path, obj_api_name)
                    if not os.path.exists(obj_path):
                        sharing = "ControlledByParent" if obj_api_name in md_objects else "ReadWrite"
                        create_object_metadata(obj_api_name, row['Object'], sharing)

                field_path = os.path.join(base_path, obj_api_name, 'fields', f"{field_api_name}.field-meta.xml")
                
                with open(field_path, "w") as f_meta:
                    f_meta.write('<?xml version="1.0" encoding="UTF-8"?>\n<CustomField xmlns="[http://soap.sforce.com/2006/04/metadata](http://soap.sforce.com/2006/04/metadata)">\n')
                    f_meta.write(f'    <fullName>{field_api_name}</fullName>\n')
                    f_meta.write(f'    <label>{row["Field Label"]}</label>\n')
                    
                    rt = row['Data Type'].lower()
                    params = re.findall(r'\d+', row['Data Type'])

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
                        
                        # Random Suffix for Relationship Name
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

if __name__ == "__main__":
    build_fleetforce()
    print("Done: Total Rebuild Complete.")

    # 🧠 Fleetforce Project Memory
**Last Updated:** February 3, 2026
**Status:** MVP Deployed / Console App Active
**Current Phase:** Data Loading (Core Objects Complete) & UI Polish

---

## 🏗️ Architecture & Configuration
* **Org Type:** Scratch Org / Developer Edition
* **Namespace:** `fleetforce__` (CRITICAL)
    * All Custom Objects and Fields must be prefixed with `fleetforce__` in CLI commands and CSV headers.
    * *Exception:* The local file names and metadata XML files in `force-app` do NOT use the prefix.
* **App Type:** Lightning Console (`Fleetforce`)
* **Permission Set:** `FleetAdmin`
    * Grants "Modify All" on Objects.
    * Grants "Read/Edit" on all Custom Fields (FLS).
    * Grants Visibility to App and Tabs.

---

## 🛠️ The Toolkit (Scripts)

### 1. `builder.py` (The God Script)
* **Purpose:** Regenerates all Metadata (Objects, Fields, Tabs, App, Permissions) from CSV specs.
* **Key Logic:**
    * **Orphan Handling:** Scans `Fields.csv` for objects missing from `Objects.csv` and forces Tab creation for them.
    * **Standard Objects:** Maps `Contact` -> `standard-Contact` for Tab visibility.
    * **Permissions:** Automatically generates `<fieldPermissions>` for every field to solve "Field Not Found" API errors.

### 2. `seeder.py` (The Data Factory)
* **Purpose:** Generates dummy CSV data for import.
* **Key Logic:**
    * **Namespace Toggle:** `NAMESPACE_PREFIX = "fleetforce__"` is ON.
    * **Field Mapping:**
        * `State__c` → `State_Province__c` (Branch)
        * `Frequency_Months__c` → `Interval_Value__c` + `Frequency_Type__c` (Maintenance Plan)

---

## 💾 Data State
| Object | Status | Notes |
| :--- | :--- | :--- |
| **Fleet_Branch__c** | ✅ Loaded | 2 Records (NY, NJ) |
| **Fleet_Asset__c** | ✅ Loaded | Vehicles (Camry, F-150) |
| **Maintenance_Plan__c** | ✅ Loaded | Standard Oil Change, etc. |
| **Service_Ticket__c** | ⏳ Pending | Needs Parent IDs (Asset) |
| **Fuel_Log__c** | ⏳ Pending | Needs Parent IDs (Asset) |
| **Allocation__c** | ⏳ Pending | Needs Parent IDs (Asset, Driver) |

---

## 🚨 Known "Gotchas" (Do Not Forget)
1.  **The "Field Not Found" Error:** Usually means **Permissions**, not a missing field. Always redeploy `FleetAdmin` if this happens.
2.  **The "InvalidBatch" Error:** Usually means **Namespace**. Ensure CSV headers have `fleetforce__`.
3.  **Master-Detail Fields:** Cannot be assigned Permissions (they are universally required). `builder.py` filters them out to avoid deployment errors.
4.  **Tab Deployment:** If an Object exists but the Tab is missing, the App deployment will fail. `builder.py` now runs a "Tab Sweep" to prevent this.

---

## ⏭️ Next Session Goals
1.  **UI Design:** Build the "Fleetforce Command Center" Home Page (Lightning App Builder).
2.  **Data Linking:** Update `seeder.py` to fetch real IDs from Salesforce (Assets/Contacts) so we can upload Children (Tickets/Logs).
3.  **Automation:** Create a flow/trigger for "Maintenance Due" status.