import random
import datetime
from simple_salesforce import Salesforce
from faker import Faker
import subprocess
import json

# ==========================================
# ⚙️ CONFIGURATION
# ==========================================
TARGET_ORG = "fleetforce-dev-3"

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
ASSET_STATUSES   = ["Available", "Available", "Available", "Assigned", "Ordered"]
FUEL_TYPES       = ["Gasoline", "Diesel", "Electric", "Hybrid", "Plug-in Hybrid"]
COLORS           = ["White", "Black", "Gray", "Silver", "Red", "Blue"]
BODY_TYPES       = ["Sedan", "SUV", "Pickup", "Van", "Minivan"]
PRIORITIES       = ["Low", "Medium", "High", "Critical"]
TICKET_STATUSES  = ["Draft", "In-Shop", "In-Shop", "Completed"]
BRANCH_TYPES     = ["Hub", "Satellite", "HQ", "Service Center"]
CARD_STATUSES    = ["Active", "Active", "Active", "Suspended"]
VIOLATION_TYPES  = ["Speeding", "Harsh Braking", "Idling", "Geofence Breach", "Seatbelt"]
SEVERITIES       = ["Low", "Medium", "High", "Critical"]
US_STATES        = ["CA", "TX", "NY", "FL", "IL", "WA", "CO", "GA", "AZ", "OH"]

fake = Faker()

# ==========================================
# 🛠️ HELPERS
# ==========================================
def get_sf():
    sf = Salesforce(session_id=SF_SESSION_ID, instance_url=SF_INSTANCE_URL)
    return sf

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
    print(f"   ✅ Created {len(ids)} {label}")
    return ids

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
    categories = ["Preventive Maintenance", "Corrective Repair", "Inspection", "Tire Change"]
    recs = [{"Name": f"ST-{fake.bothify('####')}",
             n("Fleet_Asset__c"): random.choice(asset_ids),
             n("Vendor__c"): random.choice(vendor_ids),
             n("Status__c"): random.choice(TICKET_STATUSES),
             n("Priority__c"): random.choice(PRIORITIES),
             n("Category__c"): random.choice(categories),
             n("Description__c"): fake.sentence(),
             n("Total_Parts_Cost__c"): random.randint(50, 800),
             n("Total_Labor_Cost__c"): random.randint(100, 600)}
            for _ in range(COUNTS['TICKETS'])]
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

    vendor_ids   = seed_vendors(sf)
    branch_ids   = seed_branches(sf)
    driver_ids   = seed_drivers(sf)
    asset_ids    = seed_assets(sf, branch_ids, vendor_ids)
    card_ids     = seed_fuel_cards(sf, asset_ids, driver_ids)

    seed_service_tickets(sf, asset_ids, vendor_ids)
    seed_fuel_logs(sf, asset_ids, driver_ids, card_ids)
    seed_violations(sf, asset_ids, driver_ids)
    seed_reservations(sf, asset_ids, driver_ids)

    print("\n--- ✅ SEEDING COMPLETE ---")
    print(f"Run 'sf org open --target-org {TARGET_ORG}' to view the data.")
