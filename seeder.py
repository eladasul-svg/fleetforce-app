import csv
import random
import os
from datetime import datetime, timedelta

# Output directory
OUTPUT_DIR = "data"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# ---------------------------------------------------------
# 1. CONFIGURATION
# ---------------------------------------------------------
# The prefix found in your error logs. Set to "" if no namespace exists.
NAMESPACE_PREFIX = "fleetforce__" 

# ---------------------------------------------------------
# 2. HELPER FUNCTIONS
# ---------------------------------------------------------
def get_date(offset_days=0):
    return (datetime.now() + timedelta(days=offset_days)).strftime("%Y-%m-%d")

def get_datetime(offset_days=0):
    return (datetime.now() + timedelta(days=offset_days)).isoformat() + "Z"

def write_csv(filename, data, headers):
    filepath = os.path.join(OUTPUT_DIR, filename)
    
    # NAMESPACE LOGIC: Add prefix to custom fields (ending in __c)
    namespaced_headers = []
    for h in headers:
        if h.endswith("__c"):
            namespaced_headers.append(f"{NAMESPACE_PREFIX}{h}")
        else:
            namespaced_headers.append(h)

    # We force 'utf-8' and ensure standard Windows line endings (CRLF) for Salesforce
    with open(filepath, mode='w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=namespaced_headers, lineterminator='\r\n')
        writer.writeheader()
        
        # We must also update the keys in the data dictionaries to match the new headers
        clean_data = []
        for row in data:
            new_row = {}
            for key, value in row.items():
                if key.endswith("__c"):
                    new_row[f"{NAMESPACE_PREFIX}{key}"] = value
                else:
                    new_row[key] = value
            clean_data.append(new_row)
            
        writer.writerows(clean_data)
    print(f"✅ Generated {filename} with {len(data)} rows (Namespace: {NAMESPACE_PREFIX}).")

# ---------------------------------------------------------
# 3. DATA GENERATION
# ---------------------------------------------------------
def generate_data():
    print("--- 🏭 Starting Namespace-Aware Data Factory ---")

    # 1. ACCOUNTS (Roots)
    accounts = [
        {"Name": "Global Fleet Corp", "Type": "Customer - Direct", "Phone": "555-9999"},
        {"Name": "Express Logistics", "Type": "Customer - Channel", "Phone": "555-8888"}
    ]
    write_csv("Account.csv", accounts, ["Name", "Type", "Phone"])

    # 2. CONTACTS (Drivers)
    contacts = [
        {"FirstName": "John", "LastName": "Doe", "Email": "john.doe@example.com"},
        {"FirstName": "Jane", "LastName": "Smith", "Email": "jane.smith@example.com"},
        {"FirstName": "Alice", "LastName": "Driver", "Email": "alice.driver@example.com"}
    ]
    write_csv("Contact.csv", contacts, ["FirstName", "LastName", "Email"])

# 3. BRANCHES
    branches = [
        # Change "State__c" to "State_Province__c" in the data
        {"Name": "Downtown HQ", "City__c": "New York", "State_Province__c": "NY"},
        {"Name": "Airport Hub", "City__c": "Newark", "State_Province__c": "NJ"}
    ]
    # Update the header list to match
    write_csv("Fleet_Branch__c.csv", branches, ["Name", "City__c", "State_Province__c"])

    # 4. ASSETS (The Core)
    assets = [
        {"Name": "Toyota Camry 2024", "Vin__c": "VIN123", "Status__c": "Active", "License_Plate__c": "ABC-1234"},
        {"Name": "Ford F-150", "Vin__c": "VIN456", "Status__c": "Active", "License_Plate__c": "XYZ-5678"},
        {"Name": "Tesla Model 3", "Vin__c": "VIN789", "Status__c": "Maintenance", "License_Plate__c": "EV-9999"}
    ]
    write_csv("Fleet_Asset__c.csv", assets, ["Name", "Vin__c", "Status__c", "License_Plate__c"])

    # 5. MAINTENANCE PLANS
    plans = [
        {"Name": "Standard Oil Change", "Frequency_Months__c": "6", "Mileage_Interval__c": "5000"}
    ]
    write_csv("Maintenance_Plan__c.csv", plans, ["Name", "Frequency_Months__c", "Mileage_Interval__c"])

    # --- CHILDREN (Leaves) ---

    # 6. SERVICE TICKETS
    tickets = []
    for i in range(1, 4):
        tickets.append({
            "Description__c": f"Routine Checkup {i}",
            "Status__c": "New",
            "Priority__c": "Medium"
        })
    write_csv("Service_Ticket__c.csv", tickets, ["Description__c", "Status__c", "Priority__c"])

    # 7. FUEL LOGS
    fuel_logs = []
    for i in range(1, 6):
        fuel_logs.append({
            "Gallons__c": round(random.uniform(5, 15), 1),
            "Cost__c": round(random.uniform(20, 60), 2),
            "Fuel_Type__c": "Regular"
        })
    write_csv("Fuel_Log__c.csv", fuel_logs, ["Gallons__c", "Cost__c", "Fuel_Type__c"])

    # 8. ALLOCATIONS
    allocations = []
    for i in range(1, 4):
        allocations.append({
            "Status__c": "Active",
            "Start_Date__c": get_date(-5),
            "End_Date__c": get_date(5)
        })
    write_csv("Allocation__c.csv", allocations, ["Status__c", "Start_Date__c", "End_Date__c"])

    # 9. CITATIONS
    citations = []
    citations.append({"Fine_Amount__c": "150.00", "Violation_Type__c": "Speeding", "Citation_Date__c": get_date(-2)})
    write_csv("Citation__c.csv", citations, ["Fine_Amount__c", "Violation_Type__c", "Citation_Date__c"])

    print("\n--- 📦 Data Generation Complete in /data folder ---")

if __name__ == "__main__":
    generate_data()