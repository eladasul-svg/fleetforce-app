import random
import datetime
from simple_salesforce import Salesforce
from faker import Faker

# ==========================================
# ⚙️ CONFIGURATION
# ==========================================
COUNTS = {
    "VENDORS": 6,          
    "BRANCHES": 5,         
    "DRIVERS": 30,         
    "ASSETS": 60,
    "FUEL_CARDS": 40,      # NEW!
    "TICKETS": 40,         
    "RESERVATIONS": 50,    
    "FUEL_LOGS": 100,      
    "VIOLATIONS": 25       
}

# ==========================================
# 🔐 AUTHENTICATION (Dynamic - Safe for Git)
# ==========================================
import subprocess
import json

try:
    print("⏳ Fetching Org Credentials via SF CLI...")
    result = subprocess.run(
        ["sf", "org", "display", "--json"], 
        capture_output=True, 
        text=True, 
        check=True
    )
    data = json.loads(result.stdout)
    SF_SESSION_ID = data['result']['accessToken']
    SF_INSTANCE_URL = data['result']['instanceUrl']
    print(f"   Ref: Access Token found for {data['result'].get('alias', 'Org')}")
except Exception as e:
    print("❌ Failed to fetch credentials automatically.")
    print("   Run 'sf org display' to check your connection.")
    exit()
    
# ⚠️ NAMESPACE HANDLING
NAMESPACE = "fleetforce__" 

def n(api_name):
    """Helper to prepend namespace if the object is custom (__c)"""
    if api_name.endswith("__c"):
        return f"{NAMESPACE}{api_name}"
    return api_name

# ==========================================
# 📦 CONSTANTS
# ==========================================
ASSET_CLASSES = ["Sedan", "SUV", "Truck", "Van"] 
FUEL_TYPES = ["Gasoline", "Diesel", "Electric", "Hybrid"]
COLORS = ["White", "Black", "Silver", "Gray", "Red", "Blue"]
PRIORITIES = ["Low", "Medium", "High", "Critical"]
TICKET_STATUS = ["New", "In Progress", "Parts Ordered", "Completed", "Completed"]
VIOLATION_TYPES = ["Speeding", "Harsh Braking", "Idling", "Geofence Breach"]

fake = Faker()

def get_sf_connection():
    try:
        sf = Salesforce(session_id=SF_SESSION_ID, instance_url=SF_INSTANCE_URL)
        print(f"✅ Connected to Salesforce: {SF_INSTANCE_URL}")
        return sf
    except Exception as e:
        print(f"❌ Connection Failed: {e}")
        exit()

# ==========================================
# 🛠️ HELPER: BATCH CREATE
# ==========================================
def batch_create(sf_object, records, object_name="Records"):
    ids = []
    print(f"   ...Inserting {len(records)} {object_name}...")
    for rec in records:
        try:
            res = sf_object.create(rec)
            if res['success']:
                ids.append(res['id'])
            else:
                print(f"   ⚠️ Failed to create {object_name}: {res['errors']}")
        except Exception as e:
            print(f"   ❌ Error on {object_name}: {e}")
    return ids

# ==========================================
# 🚜 SEEDING FUNCTIONS
# ==========================================

def create_vendors(sf):
    print(f"🚀 Seeding {COUNTS['VENDORS']} Vendors...")
    accounts = []
    for _ in range(COUNTS['VENDORS']):
        accounts.append({
            "Name": f"{fake.company()} Auto Parts",
            "Type": "Vendor",
            "BillingCity": fake.city(),
            "BillingState": fake.state_abbr()
        })
    ids = batch_create(sf.Account, accounts, "Vendors")
    print(f"   Ref: Created {len(ids)} Vendors.")
    return ids

def create_branches(sf, manager_ids):
    print(f"🚀 Seeding {COUNTS['BRANCHES']} Branches...")
    branches = []
    types = ["Hub", "Satellite", "HQ"]
    for _ in range(COUNTS['BRANCHES']):
        branches.append({
            "Name": f"{fake.city()} {random.choice(types)}",
            n("City__c"): fake.city(),
            n("US_State__c"): fake.state_abbr(),
            n("Status__c"): "Active",
            n("Type__c"): random.choice(types),
            n("Capacity__c"): random.randint(50, 500)
        })
    ids = batch_create(getattr(sf, n("Fleet_Branch__c")), branches, "Branches")
    print(f"   Ref: Created {len(ids)} Branches.")
    return ids

def create_drivers(sf):
    print(f"🚀 Seeding {COUNTS['DRIVERS']} Drivers...")
    contacts = []
    for _ in range(COUNTS['DRIVERS']):
        contacts.append({
            "FirstName": fake.first_name(),
            "LastName": fake.last_name(),
            "Email": fake.email(),
            "Phone": fake.phone_number(),
            "MailingCity": fake.city()
        })
    ids = batch_create(sf.Contact, contacts, "Drivers")
    print(f"   Ref: Created {len(ids)} Drivers.")
    return ids

def create_assets(sf, branch_ids, vendor_ids):
    print(f"🚀 Seeding {COUNTS['ASSETS']} Assets...")
    assets = []
    for _ in range(COUNTS['ASSETS']):
        year = random.randint(2018, 2025)
        age = 2025 - year
        mileage = (age * 12000) + random.randint(500, 5000)
        status_roll = random.random()
        status = "Active"
        if status_roll > 0.80: status = "Maintenance"
        
        assets.append({
            "Name": f"{year} {fake.word().capitalize()} {random.choice(ASSET_CLASSES)}", 
            n("VIN__c"): fake.bothify(text='1HG#############').upper(),
            n("License_Plate__c"): fake.bothify(text='???-####').upper(),
            n("Status__c"): status,
            n("Asset_Class__c"): random.choice(ASSET_CLASSES),
            n("Fuel_Type__c"): random.choice(FUEL_TYPES),
            n("Branch__c"): random.choice(branch_ids),
            n("Vendor__c"): random.choice(vendor_ids),
            n("Odometer__c"): mileage,
            n("Purchase_Date__c"): f"{year}-01-15",
            n("Purchase_Price__c"): random.randint(20000, 60000),
            n("Color__c"): random.choice(COLORS)
        })

    ids = batch_create(getattr(sf, n("Fleet_Asset__c")), assets, "Assets")
    print(f"   Ref: Created {len(ids)} Assets.")
    return ids

def create_fuel_cards(sf, asset_ids, driver_ids):
    print(f"🚀 Seeding {COUNTS['FUEL_CARDS']} Fuel Cards...")
    cards = []
    for _ in range(COUNTS['FUEL_CARDS']):
        cards.append({
            "Name": f"FC-{fake.bothify(text='####')}",
            n("Full_Card_Number__c"): fake.credit_card_number(card_type="mastercard"),
            n("Assigned_Driver__c"): random.choice(driver_ids),
            n("Assigned_Asset__c"): random.choice(asset_ids),
            n("Status__c"): "Active",
            n("Daily_Limit__c"): 500
        })
    ids = batch_create(getattr(sf, n("Fuel_Card__c")), cards, "Fuel Cards")
    print(f"   Ref: Created {len(ids)} Fuel Cards.")
    return ids

def create_service_tickets(sf, asset_ids, vendor_ids):
    print(f"🚀 Seeding {COUNTS['TICKETS']} Service Tickets...")
    tickets = []
    for _ in range(COUNTS['TICKETS']):
        if not asset_ids: break
        tickets.append({
            n("Fleet_Asset__c"): random.choice(asset_ids),
            n("Vendor__c"): random.choice(vendor_ids),
            n("Status__c"): random.choice(TICKET_STATUS),
            n("Priority__c"): random.choice(PRIORITIES),
            n("Category__c"): random.choice(["Preventive Maintenance (PM)", "Corrective Repair", "Tire Change"]),
            n("Description__c"): fake.sentence(),
            n("Total_Parts_Cost__c"): random.randint(50, 500),
            n("Total_Labor_Cost__c"): random.randint(100, 800)
        })
    batch_create(getattr(sf, n("Service_Ticket__c")), tickets, "Tickets")
    print(f"   Ref: Created tickets.")

def create_logs_and_violations(sf, asset_ids, driver_ids, card_ids):
    print(f"🚀 Seeding Operational Data...")
    
    # 1. Fuel Logs (Now with Cards!)
    logs = []
    for _ in range(COUNTS['FUEL_LOGS']):
        if not card_ids: break
        logs.append({
            n("Fleet_Asset__c"): random.choice(asset_ids),
            n("Driver__c"): random.choice(driver_ids),
            n("Fuel_Card__c"): random.choice(card_ids), # Linked!
            n("Total_Cost__c"): random.randint(30, 80),
            n("Volume__c"): random.randint(10, 20),
            n("Product_Type__c"): "Petrol",
            n("Transaction_Date__c"): fake.date_this_year().isoformat()
        })
    batch_create(getattr(sf, n("Fuel_Log__c")), logs, "Fuel Logs")

    # 2. Violations (Driver field fixed via Schema update)
    violations = []
    for _ in range(COUNTS['VIOLATIONS']):
        violations.append({
            n("Fleet_Asset__c"): random.choice(asset_ids),
            n("Driver__c"): random.choice(driver_ids), # This will now work!
            n("Type__c"): random.choice(VIOLATION_TYPES),
            n("Severity__c"): random.choice(["High", "Critical", "Medium"]),
            n("Timestamp__c"): fake.date_this_month().isoformat(),
            n("Value__c"): f"{random.randint(85, 120)} MPH"
        })
    batch_create(getattr(sf, n("Telemetry_Violation__c")), violations, "Violations")

    # 3. Reservations
    reservations = []
    for _ in range(COUNTS['RESERVATIONS']):
        is_future = random.choice([True, False])
        status = "Confirmed" if is_future else "Completed (Returned)"
        start = datetime.date.today() if is_future else fake.date_this_year()
        
        reservations.append({
            n("Requestor_Contact__c"): random.choice(driver_ids),
            n("Assigned_Asset__c"): random.choice(asset_ids),
            n("Status__c"): status,
            n("Start_Time__c"): start.isoformat(),
            n("End_Time__c"): (start + datetime.timedelta(days=3)).isoformat(),
        })
    batch_create(getattr(sf, n("Reservation__c")), reservations, "Reservations")

# ==========================================
# 🏁 MAIN EXECUTION FLOW
# ==========================================
if __name__ == "__main__":
    print("--- 🚜 STARTING FLEETFORCE SEEDER V3 ---")
    sf = get_sf_connection()
    
    vendor_ids = create_vendors(sf)
    driver_ids = create_drivers(sf)
    branch_ids = create_branches(sf, driver_ids)
    asset_ids = create_assets(sf, branch_ids, vendor_ids)
    
    # NEW: Create Cards before Logs
    card_ids = create_fuel_cards(sf, asset_ids, driver_ids) 
    
    create_service_tickets(sf, asset_ids, vendor_ids)
    create_logs_and_violations(sf, asset_ids, driver_ids, card_ids)
    
    print("--- ✅ SEEDING COMPLETE ---")