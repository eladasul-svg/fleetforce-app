#!/usr/bin/env python3
"""
Philips Masked Pilot Data Seeder for Fleetforce
Ingests authentic masked data from Philips into Salesforce:
1. Client & Vendor Accounts
2. Cost_Center__c (from Authorisation_Matrix_Sample.xlsx)
3. Contact / Drivers (linked to Cost Centers and Accounts)
4. Fleet_Asset__c (from UK_Fleet_Inventory_Sample.xlsx, with EoC risk metrics)
5. Fleet_Invoice__c & Fleet_Invoice_Line__c (from Invoice_Sample.xlsx)

Connects to the default scratch org (fleetforce-dev-13) using simple_salesforce.
"""

import os
import re
import json
import subprocess
import pandas as pd
from datetime import datetime
from simple_salesforce import Salesforce

BASE_DIR = "/Users/elad.asulin/Fleetforce Docs/Philips Pilot"
AUTH_FILE = os.path.join(BASE_DIR, "Authorisation_Matrix_Sample.xlsx")
FLEET_FILE = os.path.join(BASE_DIR, "UK_Fleet_Inventory_Sample.xlsx")
INV_FILE = os.path.join(BASE_DIR, "Invoice_Sample.xlsx")

print("⏳ Fetching credentials from Salesforce CLI...")
res_org = subprocess.run(["sf", "org", "display", "--json"], capture_output=True, text=True, check=True)
org_data = json.loads(res_org.stdout)["result"]
instance_url = org_data["instanceUrl"]

res_token = subprocess.run(["sf", "org", "auth", "show-access-token", "--json"], capture_output=True, text=True, check=True)
session_id = json.loads(res_token.stdout)["result"]["accessToken"]

print(f"✅ Connected to: {instance_url} ({org_data['username']})")

sf = Salesforce(instance_url=instance_url, session_id=session_id, version="60.0")

# -----------------------------------------------------------------
# 1. Accounts Setup
# -----------------------------------------------------------------
print("\n--- 1. Accounts Setup ---")
client_acc_name = "Northbridge Technologies UK Limited"
vendor_acc_name = "Ayvens UK / FL"

def get_or_create_account(name, acc_type="Customer"):
    query = f"SELECT Id, Name FROM Account WHERE Name = '{name}' LIMIT 1"
    records = sf.query(query)["records"]
    if records:
        print(f"Found existing Account: {name} ({records[0]['Id']})")
        return records[0]["Id"]
    new_acc = sf.Account.create({"Name": name, "Type": acc_type})
    print(f"Created Account: {name} ({new_acc['id']})")
    return new_acc["id"]

client_acc_id = get_or_create_account(client_acc_name, "Customer - Direct")
vendor_acc_id = get_or_create_account(vendor_acc_name, "Vendor")

# -----------------------------------------------------------------
# 2. Cost Centers Setup
# -----------------------------------------------------------------
print("\n--- 2. Cost Centers Setup ---")
auth_df = pd.read_excel(AUTH_FILE)

# Deduplicate by Cost Ctr
cc_grouped = auth_df.drop_duplicates(subset=["Cost Ctr"]).copy()
print(f"Processing {len(cc_grouped)} unique cost centers...")

# Check existing Cost Centers
existing_cc_res = sf.query("SELECT Id, fleetforce__Cost_Center_Code__c FROM fleetforce__Cost_Center__c")
existing_cc_map = {r["fleetforce__Cost_Center_Code__c"]: r["Id"] for r in existing_cc_res["records"] if r.get("fleetforce__Cost_Center_Code__c")}

cost_center_id_map = {}
cc_to_create = []

for _, r in cc_grouped.iterrows():
    cc_code = str(r["Cost Ctr"]).strip()
    if cc_code in existing_cc_map:
        cost_center_id_map[cc_code] = existing_cc_map[cc_code]
        continue
    
    cc_to_create.append({
        "Name": str(r["Cost Center"])[:80],
        "fleetforce__Cost_Center_Code__c": cc_code,
        "fleetforce__Company_Code__c": str(r["CoCd"])[:50] if pd.notnull(r["CoCd"]) else None,
        "fleetforce__Company_Name__c": str(r["Company Code"])[:100] if pd.notnull(r["Company Code"]) else None,
        "fleetforce__Functional_Location__c": str(r["Funloc"])[:50] if pd.notnull(r["Funloc"]) else None,
        "fleetforce__Parent_Account__c": client_acc_id
    })

if cc_to_create:
    print(f"Inserting {len(cc_to_create)} new Cost Centers via Bulk API...")
    res_cc = sf.bulk.fleetforce__Cost_Center__c.insert(cc_to_create)
    for row, item in zip(res_cc, cc_to_create):
        if row.get("success"):
            cost_center_id_map[item["fleetforce__Cost_Center_Code__c"]] = row["id"]
        else:
            print(f"Error inserting CC {item['fleetforce__Cost_Center_Code__c']}: {row.get('errors')}")

print(f"✅ Total Cost Centers ready in map: {len(cost_center_id_map)}")

# -----------------------------------------------------------------
# 3. Contacts / Drivers Setup
# -----------------------------------------------------------------
print("\n--- 3. Drivers Setup ---")
# Create Contacts for the drivers who appear in the invoice file
inv_df = pd.read_excel(INV_FILE)
if pd.isna(inv_df.iloc[-1]["Billing Doc."]) and inv_df.iloc[-1]["Total GROSS"] > 100000:
    inv_df = inv_df.iloc[:-1].copy()

inv_drivers = inv_df["Driver Payroll Id"].dropna().astype(str).str.lstrip("0").str.strip().unique()
print(f"Unique driver payroll IDs on invoices: {len(inv_drivers)}")

existing_contacts = sf.query("SELECT Id, fleetforce__Payroll_ID__c FROM Contact WHERE fleetforce__Payroll_ID__c != null")
contact_map = {r["fleetforce__Payroll_ID__c"]: r["Id"] for r in existing_contacts["records"]}

contacts_to_create = []
for p_id in inv_drivers:
    if p_id in contact_map:
        continue
    # Lookup in auth_df if available
    match_auth = auth_df[auth_df["Pers.No."].astype(str).str.lstrip("0") == p_id]
    dept = match_auth["Company Code"].iloc[0] if len(match_auth) > 0 else "Field Operations"
    
    contacts_to_create.append({
        "FirstName": "Field",
        "LastName": f"Driver {p_id}",
        "fleetforce__Payroll_ID__c": p_id,
        "Department": str(dept)[:80],
        "AccountId": client_acc_id
    })

if contacts_to_create:
    print(f"Inserting {len(contacts_to_create)} new Contacts via Bulk API...")
    res_con = sf.bulk.Contact.insert(contacts_to_create)
    for row, item in zip(res_con, contacts_to_create):
        if row.get("success"):
            contact_map[item["fleetforce__Payroll_ID__c"]] = row["id"]

print(f"✅ Total Contacts ready in map: {len(contact_map)}")

# -----------------------------------------------------------------
# 4. Fleet Assets Setup (from UK_Fleet_Inventory_Sample)
# -----------------------------------------------------------------
print("\n--- 4. Fleet Assets Setup ---")
fleet_df = pd.read_excel(FLEET_FILE)
print(f"Loaded {len(fleet_df)} vehicles from inventory...")

existing_assets = sf.query("SELECT Id, fleetforce__License_Plate__c FROM fleetforce__Fleet_Asset__c WHERE fleetforce__License_Plate__c != null")
asset_map = {r["fleetforce__License_Plate__c"]: r["Id"] for r in existing_assets["records"]}

vin_regex = re.compile(r"^[A-HJ-NPR-Z0-9]{17}$")

assets_to_create = []
PENALTY_PER_MILE = 0.12

for _, r in fleet_df.iterrows():
    plate = str(r["Registration"]).strip().upper() if pd.notnull(r["Registration"]) else None
    if not plate or plate in asset_map:
        continue

    # Sanitize VIN against Salesforce VIN_Format rule
    raw_vin = str(r["VIN chassis"]).strip().upper() if pd.notnull(r["VIN chassis"]) else ""
    clean_vin = raw_vin if vin_regex.match(raw_vin) else None

    # Status mapping
    st = str(r["Contract status"]).strip()
    asset_status = "Assigned" if st == "Live" else "Retired"

    # Powertrain mapping
    energy = str(r["Energy type"]).strip()
    if energy == "BEV":
        engine_type = "Electric"
    elif "PHEV" in energy:
        engine_type = "Plug-In"
    elif energy == "Diesel":
        engine_type = "Diesel"
    elif energy == "Petrol":
        engine_type = "ICE"
    elif "Hybrid" in energy:
        engine_type = "Hybrid"
    else:
        engine_type = "ICE"

    # Odometer and EoC numbers
    odo = float(r["Last mileage"]) if pd.notnull(r["Last mileage"]) else 0.0
    contract_mi = float(r["Contract Mileage"]) if pd.notnull(r["Contract Mileage"]) else 0.0
    eoc_mi = float(r["Expected mileage \"EoC\""]) if pd.notnull(r["Expected mileage \"EoC\""]) else 0.0
    dev_pct = float(r["Deviation (%)"]) if pd.notnull(r["Deviation (%)"]) else 0.0

    penalty = 0.0
    if eoc_mi > contract_mi and dev_pct >= 20.0:
        penalty = round((eoc_mi - contract_mi) * PENALTY_PER_MILE, 2)

    make = str(r["Make"])[:40] if pd.notnull(r["Make"]) else "Vehicle"
    model = str(r["Model"])[:40] if pd.notnull(r["Model"]) else ""
    asset_name = f"{make} {model} ({plate})"[:80]

    asset_payload = {
        "Name": asset_name,
        "fleetforce__License_Plate__c": plate,
        "fleetforce__Status__c": asset_status,
        "fleetforce__Make__c": make,
        "fleetforce__Model__c": model,
        "fleetforce__Engine_Type__c": engine_type,
        "fleetforce__Odometer__c": odo,
        "fleetforce__EoC_Projected_Mileage__c": eoc_mi if eoc_mi > 0 else None,
        "fleetforce__Contract_Mileage_Deviation_Pct__c": dev_pct,
        "fleetforce__EoC_Penalty_Exposure__c": penalty if penalty > 0 else None,
        "fleetforce__Vendor__c": vendor_acc_id
    }
    if clean_vin:
        asset_payload["fleetforce__VIN__c"] = clean_vin

    assets_to_create.append(asset_payload)

if assets_to_create:
    print(f"Inserting {len(assets_to_create)} new Fleet Assets via Bulk API...")
    res_ast = sf.bulk.fleetforce__Fleet_Asset__c.insert(assets_to_create)
    for row, item in zip(res_ast, assets_to_create):
        if row.get("success"):
            asset_map[item["fleetforce__License_Plate__c"]] = row["id"]
        else:
            print(f"Error inserting asset {item['fleetforce__License_Plate__c']}: {row.get('errors')}")

print(f"✅ Total Fleet Assets ready in map: {len(asset_map)}")

# -----------------------------------------------------------------
# 5. Invoices & Invoice Lines Setup (from Invoice_Sample)
# -----------------------------------------------------------------
print("\n--- 5. Fleet Invoices Setup ---")
unique_bills = inv_df["Billing Doc."].dropna().unique()
print(f"Found {len(unique_bills)} distinct Billing Documents on invoices...")

existing_invoices = sf.query("SELECT Id, fleetforce__Billing_Doc_Number__c FROM fleetforce__Fleet_Invoice__c")
invoice_map = {r["fleetforce__Billing_Doc_Number__c"]: r["Id"] for r in existing_invoices["records"]}

invoices_to_create = []
for b_doc in unique_bills:
    b_doc_str = str(int(b_doc))
    if b_doc_str in invoice_map:
        continue
    sample_row = inv_df[inv_df["Billing Doc."] == b_doc].iloc[0]
    b_date = pd.to_datetime(sample_row["Billing Date"]).strftime("%Y-%m-%d") if pd.notnull(sample_row["Billing Date"]) else "2025-01-10"
    p_date = pd.to_datetime(sample_row["Payment Due Date"]).strftime("%Y-%m-%d") if pd.notnull(sample_row["Payment Due Date"]) else "2025-04-03"
    s_date = pd.to_datetime(sample_row["Invoice From Date"]).strftime("%Y-%m-%d") if pd.notnull(sample_row["Invoice From Date"]) else "2025-02-01"
    e_date = pd.to_datetime(sample_row["Invoice To Date"]).strftime("%Y-%m-%d") if pd.notnull(sample_row["Invoice To Date"]) else "2025-02-28"

    invoices_to_create.append({
        "Name": f"Ayvens UK Bill #{b_doc_str}",
        "fleetforce__Billing_Doc_Number__c": b_doc_str,
        "fleetforce__Vendor_Account__c": vendor_acc_id,
        "fleetforce__Billing_Date__c": b_date,
        "fleetforce__Payment_Due_Date__c": p_date,
        "fleetforce__Billing_Period_Start__c": s_date,
        "fleetforce__Billing_Period_End__c": e_date,
        "fleetforce__Status__c": "Audited",
        "fleetforce__Audit_Review_Status__c": "Pending_Review"
    })

if invoices_to_create:
    print(f"Inserting {len(invoices_to_create)} new Fleet Invoices...")
    res_inv = sf.bulk.fleetforce__Fleet_Invoice__c.insert(invoices_to_create)
    for row, item in zip(res_inv, invoices_to_create):
        if row.get("success"):
            invoice_map[item["fleetforce__Billing_Doc_Number__c"]] = row["id"]

print(f"✅ Total Fleet Invoices ready in map: {len(invoice_map)}")

# Insert Invoice Lines
print("\n--- 6. Fleet Invoice Lines Setup ---")
existing_lines_count = sf.query("SELECT count() FROM fleetforce__Fleet_Invoice_Line__c")["totalSize"]
if existing_lines_count > 0:
    print(f"Scratch org already has {existing_lines_count} lines. Purging old lines before re-seeding...")
    # Delete in batches
    old_ids = [r["Id"] for r in sf.query("SELECT Id FROM fleetforce__Fleet_Invoice_Line__c")["records"]]
    sf.bulk.fleetforce__Fleet_Invoice_Line__c.delete([{"Id": i} for i in old_ids])

lines_to_create = []

for _, r in inv_df.iterrows():
    b_doc = str(int(r["Billing Doc."])) if pd.notnull(r["Billing Doc."]) else None
    if not b_doc or b_doc not in invoice_map:
        continue
    inv_id = invoice_map[b_doc]

    # Map Asset
    reg = str(r["Vehicle Reg. No."]).strip().upper() if pd.notnull(r["Vehicle Reg. No."]) else ""
    ast_id = asset_map.get(reg)

    # Map Driver
    p_id = str(r["Driver Payroll Id"]).lstrip("0").strip() if pd.notnull(r["Driver Payroll Id"]) else ""
    drv_id = contact_map.get(p_id)

    # Map Cost Center
    dept_co = str(r["Driver Department Co"]).strip() if pd.notnull(r["Driver Department Co"]) else ""
    cc_id = cost_center_id_map.get(dept_co)

    # Categorization
    inv_desc = str(r["Invoice/Major Cd Des"]).strip()
    if "MONTHLY RENTAL" in inv_desc:
        cat = "Monthly_Lease_Rental"
    elif "MONTHLY PAYMT" in inv_desc:
        cat = "Monthly_Payment"
    elif "RECHARGE" in inv_desc:
        cat = "Recharge"
    elif "CN" in inv_desc or "TERM" in inv_desc:
        cat = "Termination_Credit_Note"
    elif "FIRST" in inv_desc:
        cat = "First_Rental"
    else:
        cat = "Manual_Invoice"

    # Recharge Type
    concerning = str(r["Invoice Concerning"]).strip() if pd.notnull(r["Invoice Concerning"]) else ""
    if "Replacement" in concerning:
        rech_type = "Replacement_Vehicle"
    elif "Fine" in concerning:
        rech_type = "Fine_Admin_Fee"
    elif "Parking" in concerning:
        rech_type = "Parking_Fine"
    elif "Repair" in concerning or "Body" in concerning or "Accident" in concerning:
        rech_type = "Body_Repairs_Damage"
    elif "Service" in concerning:
        rech_type = "Service_Programme"
    elif "Movement" in concerning:
        rech_type = "Vehicle_Movement"
    else:
        rech_type = "Other"

    net_amt = float(r["Total NET"]) if pd.notnull(r["Total NET"]) else 0.0
    vat_amt = float(r["Total VAT"]) if pd.notnull(r["Total VAT"]) else 0.0
    gross_amt = float(r["Total GROSS"]) if pd.notnull(r["Total GROSS"]) else 0.0

    # Audit status
    if gross_amt >= 6000.0:
        audit_st = "Flagged_Over_6k"
        audit_note = "High value expense exceeds €6,000 threshold (US leadership audit)"
    elif not drv_id or not cc_id:
        audit_st = "Unallocated_Driver"
        audit_note = "Missing driver payroll ID or unmapped cost center"
    elif "CN" in inv_desc:
        audit_st = "Clean"
        audit_note = "Termination credit note processed"
    else:
        audit_st = "Clean"
        audit_note = "Standard monthly scheduled charge"

    credit_applied = 0.0
    if cat == "Termination_Credit_Note":
        credit_applied = abs(net_amt)

    line_payload = {
        "fleetforce__Fleet_Invoice__c": inv_id,
        "fleetforce__Invoice_Category__c": cat,
        "fleetforce__Recharge_Type__c": rech_type,
        "fleetforce__Invoice_Concerning__c": concerning[:255] if concerning else None,
        "fleetforce__Net_Amount__c": net_amt,
        "fleetforce__VAT_Amount__c": vat_amt,
        "fleetforce__Gross_Amount__c": gross_amt,
        "fleetforce__Credit_Allowance_Applied__c": credit_applied,
        "fleetforce__Audit_Status__c": audit_st,
        "fleetforce__Audit_Notes__c": audit_note[:255]
    }
    if ast_id:
        line_payload["fleetforce__Fleet_Asset__c"] = ast_id
    if drv_id:
        line_payload["fleetforce__Driver__c"] = drv_id
    if cc_id:
        line_payload["fleetforce__Cost_Center__c"] = cc_id

    lines_to_create.append(line_payload)

print(f"Inserting {len(lines_to_create)} Fleet Invoice Lines via Bulk API...")
res_lines = sf.bulk.fleetforce__Fleet_Invoice_Line__c.insert(lines_to_create)
success_count = sum(1 for r in res_lines if r.get("success"))
print(f"✅ Successfully inserted {success_count} / {len(lines_to_create)} Fleet Invoice Lines into Salesforce!")

print("\n🎉 Seeding completed successfully!")
