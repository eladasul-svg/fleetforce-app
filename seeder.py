import random
import datetime
from simple_salesforce import Salesforce
import subprocess
import json
from faker import Faker

# ==========================================
# ⚙️ CONFIGURATION
# ==========================================
TARGET_ORG = "fleetforce-dev-8"

COUNTS = {
    "VENDORS":      5,
    "BRANCHES":     5,
    "DRIVERS":      10,
    "ASSETS":       10,
    "FUEL_CARDS":   10,
    "TICKETS":      10,
    "RESERVATIONS": 10,
    "FUEL_LOGS":    10,
    "VIOLATIONS":   10,
}

# ==========================================
# 🔐 AUTHENTICATION
# ==========================================
try:
    print(f"⏳ Fetching credentials for {TARGET_ORG}...")
    result = subprocess.run(
        ["sf", "org", "display", "--target-org", TARGET_ORG, "--json"],
        capture_output=True, text=True, check=True
    )
    data = json.loads(result.stdout)
    SF_SESSION_ID = data['result']['accessToken']
    SF_INSTANCE_URL = data['result']['instanceUrl']
    print(f"   ✅ Connected: {SF_INSTANCE_URL}")
except Exception as e:
    print(f"❌ Failed to fetch credentials: {e}")
    exit()

NAMESPACE = "fleetforce__"

def n(api_name):
    return f"{NAMESPACE}{api_name}" if api_name.endswith("__c") else api_name

# ==========================================
# 📦 PICKLIST VALUES (matching deployed schema)
# ==========================================
ASSET_STATUSES  = ["Available", "Available", "Available", "Assigned", "Ordered"]
FUEL_TYPES      = ["Gasoline", "Diesel", "Electric", "Hybrid", "Plug-in Hybrid"]
COLORS          = ["White", "Black", "Gray", "Silver", "Red", "Blue"]
BODY_TYPES      = ["Sedan", "SUV", "Pickup", "Van", "Minivan"]
PRIORITIES      = ["Low", "Medium", "High", "Critical"]
TICKET_STATUSES = ["Draft", "In-Shop", "In-Shop", "Completed"]
BRANCH_TYPES    = ["Hub", "Satellite", "HQ", "Service Center"]
CARD_STATUSES   = ["Active", "Active", "Active", "Suspended"]
VIOLATION_TYPES = ["Speeding", "Harsh Braking", "Idling", "Geofence Breach", "Seatbelt"]
SEVERITIES      = ["Low", "Medium", "High", "Critical"]
US_STATES       = ["CA", "TX", "NY", "FL", "IL", "WA", "CO", "GA", "AZ", "OH"]

fake = Faker()

# ==========================================
# 🛠️ HELPERS
# ==========================================
def get_sf():
    return Salesforce(session_id=SF_SESSION_ID, instance_url=SF_INSTANCE_URL)

def batch_create(sf_object, records, label):
    ids = []
    print(f"   Inserting {len(records)} {label}...")
    for rec in records:
        try:
            res = sf_object.create(rec)
            if res['success']:
                ids.append(res['id'])
            else:
                print(f"   ⚠️  {label}: {res['errors']}")
        except Exception as e:
            print(f"   ❌ {label}: {e}")
    print(f"   ✅ Created {len(ids)}/{len(records)} {label}")
    return ids

def delete_record(sf, object_api, record_id):
    try:
        getattr(sf, object_api).delete(record_id)
    except Exception as e:
        print(f"   ⚠️  Could not delete test record {record_id}: {e}")

def existing_ids(sf, object_api, where=""):
    q = f"SELECT Id FROM {n(object_api)}"
    if where:
        q += f" WHERE {where}"
    q += " LIMIT 200"
    try:
        return [r['Id'] for r in sf.query(q)['records']]
    except:
        return []

# ==========================================
# 🧪 PRE-SEED VALIDATION
# ==========================================
def preseed_validate(sf):
    """
    Insert 1 test record per object in dependency order.
    Collect all failures, clean up test records, then report.
    Aborts the full seed if any object fails.
    """
    print("\n" + "="*55)
    print("  🧪  PRE-SEED VALIDATION (1 record per object)")
    print("="*55)

    failures = []
    created = []  # (sf_object, record_id) for cleanup

    def try_insert(label, sf_object_name, record):
        obj = getattr(sf, sf_object_name)
        try:
            res = obj.create(record)
            if res['success']:
                created.append((sf_object_name, res['id']))
                print(f"  ✅  {label}")
                return res['id']
            else:
                failures.append((label, str(res['errors'])))
                print(f"  ❌  {label}: {res['errors']}")
                return None
        except Exception as e:
            failures.append((label, str(e)))
            print(f"  ❌  {label}: {e}")
            return None

    # --- Tier 0: no fleetforce dependencies ---
    vendor_id = try_insert(
        "Account (Vendor)",
        "Account",
        {"Name": "__TEST__ Vendor", "Type": "Vendor",
         "BillingCity": "Austin", "BillingState": "TX"}
    )

    driver_id = try_insert(
        "Contact (Driver)",
        "Contact",
        {"FirstName": "__TEST__", "LastName": "Driver",
         "Email": "test.driver@example.com"}
    )

    # --- Tier 1: depends on standard objects ---
    branch_id = try_insert(
        "Fleet_Branch__c",
        n("Fleet_Branch__c"),
        {"Name": "__TEST__ Branch",
         n("City__c"): "Austin",
         n("US_State__c"): "TX",
         n("Status__c"): "Active",
         n("Type__c"): "Hub",
         n("Capacity__c"): 50}
    )

    # --- Tier 2: depends on Branch + Vendor ---
    asset_id = try_insert(
        "Fleet_Asset__c",
        n("Fleet_Asset__c"),
        {"Name": "__TEST__ Asset",
         n("VIN__c"): "1TESTVIN000000001",
         n("License_Plate__c"): "TST-0001",
         n("Status__c"): "Available",
         n("Fuel_Type__c"): "Gasoline",
         n("Body_Type__c"): "Sedan",
         n("Color__c"): "White",
         n("Branch__c"): branch_id,
         n("Vendor__c"): vendor_id,
         n("Odometer__c"): 10000,
         n("Purchase_Date__c"): "2023-01-15",
         n("Purchase_Price__c"): 30000}
    ) if branch_id and vendor_id else None

    # --- Tier 3: depends on Asset ---
    fuel_card_id = try_insert(
        "Fuel_Card__c",
        n("Fuel_Card__c"),
        {"Name": "__TEST__ FC-0001",
         n("Assigned_Driver__c"): driver_id,
         n("Assigned_Asset__c"): asset_id,
         n("Status__c"): "Active",
         n("Daily_Limit__c"): 200}
    ) if asset_id and driver_id else None

    ticket_id = try_insert(
        "Service_Ticket__c",
        n("Service_Ticket__c"),
        {"Name": "__TEST__ ST-0001",
         n("Fleet_Asset__c"): asset_id,
         n("Vendor__c"): vendor_id,
         n("Status__c"): "Draft",
         n("Priority__c"): "Medium",
         n("Category__c"): "Preventive Maintenance",
         n("Description__c"): "Pre-seed test ticket"}
    ) if asset_id and vendor_id else None

    reservation_id = try_insert(
        "Reservation__c",
        n("Reservation__c"),
        {"Name": "__TEST__ RES-0001",
         n("Requestor_Contact__c"): driver_id,
         n("Assigned_Asset__c"): asset_id,
         n("Status__c"): "Pending",
         n("Start_Time__c"): datetime.date.today().isoformat(),
         n("End_Time__c"): (datetime.date.today() + datetime.timedelta(days=1)).isoformat()}
    ) if asset_id and driver_id else None

    # --- Tier 4: depends on Asset + Card ---
    try_insert(
        "Fuel_Log__c",
        n("Fuel_Log__c"),
        {"Name": "__TEST__ FL-0001",
         n("Fleet_Asset__c"): asset_id,
         n("Driver__c"): driver_id,
         n("Fuel_Card__c"): fuel_card_id,
         n("Total_Cost__c"): 55.00,
         n("Volume__c"): 15.0,
         n("Product_Type__c"): "Petrol",
         n("Transaction_Date__c"): datetime.date.today().isoformat()}
    ) if asset_id and driver_id and fuel_card_id else None

    try_insert(
        "Telemetry_Violation__c",
        n("Telemetry_Violation__c"),
        {"Name": "__TEST__ VIO-0001",
         n("Fleet_Asset__c"): asset_id,
         n("Driver__c"): driver_id,
         n("Type__c"): "Speeding",
         n("Severity__c"): "Medium",
         n("Timestamp__c"): datetime.datetime.now().isoformat(),
         n("Value__c"): "85 MPH"}
    ) if asset_id and driver_id else None

    # --- Cleanup: delete all test records in reverse order ---
    print(f"\n  🧹  Cleaning up {len(created)} test record(s)...")
    for obj_name, rec_id in reversed(created):
        delete_record(sf, obj_name, rec_id)

    # --- Result ---
    print()
    if failures:
        print(f"  ❌  PRE-SEED FAILED — {len(failures)} object(s) had errors:\n")
        for label, err in failures:
            print(f"      • {label}: {err}")
        print("\n  Fix the above issues before running the full seed.")
        print("  Hint: make sure FleetforceAdmin permission set is assigned.")
        print("="*55 + "\n")
        return False
    else:
        print(f"  ✅  All objects passed — safe to run full seed.")
        print("="*55 + "\n")
        return True

# ==========================================
# 🏭 SEED FUNCTIONS
# ==========================================
def seed_vendors(sf):
    ids = existing_ids(sf, "Account", "Type='Vendor'")
    if ids:
        print(f"   ↩️  Found {len(ids)} Vendors — skipping")
        return ids
    print(f"🚀 Seeding Vendors...")
    recs = [{"Name": f"{fake.company()} Fleet Services", "Type": "Vendor",
             "BillingCity": fake.city(), "BillingState": random.choice(US_STATES)}
            for _ in range(COUNTS['VENDORS'])]
    return batch_create(sf.Account, recs, "Vendors")

def seed_branches(sf):
    ids = existing_ids(sf, "Fleet_Branch__c")
    if ids:
        print(f"   ↩️  Found {len(ids)} Branches — skipping")
        return ids
    print(f"🚀 Seeding Branches...")
    recs = [{"Name": f"{fake.city()} {random.choice(BRANCH_TYPES)}",
             n("City__c"): fake.city(),
             n("US_State__c"): random.choice(US_STATES),
             n("Status__c"): "Active",
             n("Type__c"): random.choice(BRANCH_TYPES),
             n("Capacity__c"): random.randint(20, 200)}
            for _ in range(COUNTS['BRANCHES'])]
    return batch_create(getattr(sf, n("Fleet_Branch__c")), recs, "Branches")

def seed_drivers(sf):
    ids = existing_ids(sf, "Contact")
    if ids:
        print(f"   ↩️  Found {len(ids)} Drivers — skipping")
        return ids
    print(f"🚀 Seeding Drivers...")
    recs = [{"FirstName": fake.first_name(), "LastName": fake.last_name(),
             "Email": fake.email(), "Phone": fake.phone_number(),
             "MailingCity": fake.city(), "MailingState": random.choice(US_STATES)}
            for _ in range(COUNTS['DRIVERS'])]
    return batch_create(sf.Contact, recs, "Drivers")

def seed_assets(sf, branch_ids, vendor_ids):
    ids = existing_ids(sf, "Fleet_Asset__c")
    if ids:
        print(f"   ↩️  Found {len(ids)} Assets — skipping")
        return ids
    print(f"🚀 Seeding Assets...")
    recs = []
    for _ in range(COUNTS['ASSETS']):
        year = random.randint(2019, 2025)
        recs.append({
            "Name": f"{year} {fake.word().capitalize()} {random.choice(BODY_TYPES)}",
            n("VIN__c"): fake.bothify("1HG#############").upper(),
            n("License_Plate__c"): fake.bothify("???-####").upper(),
            n("Status__c"): random.choice(ASSET_STATUSES),
            n("Fuel_Type__c"): random.choice(FUEL_TYPES),
            n("Body_Type__c"): random.choice(BODY_TYPES),
            n("Color__c"): random.choice(COLORS),
            n("Branch__c"): random.choice(branch_ids),
            n("Vendor__c"): random.choice(vendor_ids),
            n("Odometer__c"): random.randint(5000, 120000),
            n("Purchase_Date__c"): f"{year}-{random.randint(1,12):02d}-15",
            n("Purchase_Price__c"): random.randint(22000, 65000),
        })
    return batch_create(getattr(sf, n("Fleet_Asset__c")), recs, "Assets")

def seed_fuel_cards(sf, asset_ids, driver_ids):
    ids = existing_ids(sf, "Fuel_Card__c")
    if ids:
        print(f"   ↩️  Found {len(ids)} Fuel Cards — skipping")
        return ids
    print(f"🚀 Seeding Fuel Cards...")
    recs = [{"Name": f"FC-{fake.bothify('####')}",
             n("Assigned_Driver__c"): random.choice(driver_ids),
             n("Assigned_Asset__c"): random.choice(asset_ids),
             n("Status__c"): random.choice(CARD_STATUSES),
             n("Daily_Limit__c"): random.choice([200, 300, 500])}
            for _ in range(COUNTS['FUEL_CARDS'])]
    return batch_create(getattr(sf, n("Fuel_Card__c")), recs, "Fuel Cards")

def seed_service_tickets(sf, asset_ids, vendor_ids):
    ids = existing_ids(sf, "Service_Ticket__c")
    if ids:
        print(f"   ↩️  Found {len(ids)} Service Tickets — skipping")
        return ids
    print(f"🚀 Seeding Service Tickets...")
    # Category values must match restricted picklist; "Tire Change" is not valid
    categories = ["Preventive Maintenance", "Corrective Repair", "Inspection", "Other"]
    recs = []
    for _ in range(COUNTS['TICKETS']):
        status = random.choice(TICKET_STATUSES)
        rec = {"Name": f"ST-{fake.bothify('####')}",
               n("Fleet_Asset__c"): random.choice(asset_ids),
               n("Vendor__c"): random.choice(vendor_ids),
               n("Status__c"): status,
               n("Priority__c"): random.choice(PRIORITIES),
               n("Category__c"): random.choice(categories),
               n("Description__c"): fake.sentence(),
               n("Total_Parts_Cost__c"): random.randint(50, 800),
               n("Total_Labor_Cost__c"): random.randint(100, 600)}
        # Validation rule: Completed status requires Actual_End__c
        if status == "Completed":
            rec[n("Actual_End__c")] = fake.date_between('-30d', 'today').isoformat()
        recs.append(rec)
    return batch_create(getattr(sf, n("Service_Ticket__c")), recs, "Service Tickets")

def seed_fuel_logs(sf, asset_ids, driver_ids, card_ids):
    ids = existing_ids(sf, "Fuel_Log__c")
    if ids:
        print(f"   ↩️  Found {len(ids)} Fuel Logs — skipping")
        return ids
    print(f"🚀 Seeding Fuel Logs...")
    recs = [{"Name": f"FL-{fake.bothify('####')}",
             n("Fleet_Asset__c"): random.choice(asset_ids),
             n("Driver__c"): random.choice(driver_ids),
             n("Fuel_Card__c"): random.choice(card_ids),
             n("Total_Cost__c"): round(random.uniform(40, 120), 2),
             n("Volume__c"): round(random.uniform(10, 30), 1),
             n("Product_Type__c"): "Petrol",
             n("Transaction_Date__c"): fake.date_between('-90d', 'today').isoformat()}
            for _ in range(COUNTS['FUEL_LOGS'])]
    return batch_create(getattr(sf, n("Fuel_Log__c")), recs, "Fuel Logs")

def seed_violations(sf, asset_ids, driver_ids):
    ids = existing_ids(sf, "Telemetry_Violation__c")
    if ids:
        print(f"   ↩️  Found {len(ids)} Violations — skipping")
        return ids
    print(f"🚀 Seeding Telemetry Violations...")
    recs = [{"Name": f"VIO-{fake.bothify('####')}",
             n("Fleet_Asset__c"): random.choice(asset_ids),
             n("Driver__c"): random.choice(driver_ids),
             n("Type__c"): random.choice(VIOLATION_TYPES),
             n("Severity__c"): random.choice(SEVERITIES),
             n("Timestamp__c"): fake.date_time_between('-30d', 'now').isoformat(),
             n("Value__c"): f"{random.randint(75, 120)} MPH"}
            for _ in range(COUNTS['VIOLATIONS'])]
    return batch_create(getattr(sf, n("Telemetry_Violation__c")), recs, "Violations")

def seed_reservations(sf, asset_ids, driver_ids):
    ids = existing_ids(sf, "Reservation__c")
    if ids:
        print(f"   ↩️  Found {len(ids)} Reservations — skipping")
        return ids
    print(f"🚀 Seeding Reservations...")
    statuses = ["Approved", "Active", "Completed", "Pending"]
    recs = []
    for _ in range(COUNTS['RESERVATIONS']):
        start = fake.date_between('-30d', '+30d')
        recs.append({"Name": f"RES-{fake.bothify('####')}",
                     n("Requestor_Contact__c"): random.choice(driver_ids),
                     n("Assigned_Asset__c"): random.choice(asset_ids),
                     n("Status__c"): random.choice(statuses),
                     n("Start_Time__c"): start.isoformat(),
                     n("End_Time__c"): (start + datetime.timedelta(days=random.randint(1,5))).isoformat()})
    return batch_create(getattr(sf, n("Reservation__c")), recs, "Reservations")

# ==========================================
# 🏁 MAIN
# ==========================================
if __name__ == "__main__":
    print("--- 🚜 FLEETFORCE SEEDER ---")
    sf = get_sf()

    # Pre-seed validation — abort if anything fails
    if not preseed_validate(sf):
        exit(1)

    # Full seed
    vendor_ids  = seed_vendors(sf)
    branch_ids  = seed_branches(sf)
    driver_ids  = seed_drivers(sf)
    asset_ids   = seed_assets(sf, branch_ids, vendor_ids)
    card_ids    = seed_fuel_cards(sf, asset_ids, driver_ids)

    seed_service_tickets(sf, asset_ids, vendor_ids)
    seed_fuel_logs(sf, asset_ids, driver_ids, card_ids)
    seed_violations(sf, asset_ids, driver_ids)
    seed_reservations(sf, asset_ids, driver_ids)

    print("\n--- ✅ SEEDING COMPLETE ---")
    print(f"Run 'sf org open --target-org {TARGET_ORG}' to view the data.")
