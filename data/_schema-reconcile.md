# Schema Reconcile — FleetForce Demo Dataset vs Live Org (fleetforce-dev-8)
_Generated against live org. Stop-point before dataset generation._

---
## Account → `Account` (10 rows)

### ✅ Direct fields — OK
- `Name` (string) ✓
- `BillingCity` (string) ✓
- `BillingState` (string) ✓
- `Phone` (phone) ✓

### ❌ Issues requiring resolution
- ❌ `fleetforce__Vendor_ID__c` — **NOT FOUND** in org
- ⚠️ `Type` — picklist values not in org: ['Vendor', 'Insurer', 'Customer']
- ⚠️ `Industry` — picklist values not in org: ['Automotive', 'Financial Services', 'Automotive Repair', 'Logistics', 'Fleet Management']

---
## Contact → `Contact` (12 rows)

### ✅ Direct fields — OK
- `FirstName` (string) ✓
- `LastName` (string) ✓
- `Email` (email) ✓
- `Phone` (phone) ✓
- `fleetforce__License_State__c` (picklist) ✓

### 🔗 Ref columns (generator resolves at load)
- `Account__ref` → AccountId (Contact.AccountId)

### ❌ Issues requiring resolution
- ❌ `fleetforce__Contact_Type__c` — **NOT FOUND** in org
- ❌ `fleetforce__Driver_Status__c` — **NOT FOUND** in org
- ❌ `fleetforce__License_Number__c` — **NOT FOUND** in org
- ❌ `fleetforce__License_Class__c` — **NOT FOUND** in org
- ❌ `fleetforce__Safety_Score__c` — **NOT FOUND** in org

---
## Fleet_Schedule → `fleetforce__Fleet_Schedule__c` (3 rows)

### ✅ Direct fields — OK
- `Name` (string) ✓
- `fleetforce__Is_24_7__c` (boolean) ✓
- `fleetforce__Grace_Period_Mins__c` (double) ✓

### ❌ Issues requiring resolution
- ⚠️ `fleetforce__Type__c` — picklist values not in org: ['Standard/Seasonal', 'Extended Hours', 'On-Call']
- ⚠️ `fleetforce__Time_Zone__c` — picklist values not in org: ['UTC-08:00 Pacific', 'UTC-07:00 Mountain']

---
## Fleet_Branch → `fleetforce__Fleet_Branch__c` (5 rows)

### ✅ Direct fields — OK
- `Name` (string) ✓
- `fleetforce__Branch_ID__c` (string) ✓
- `fleetforce__Type__c` (picklist) ✓
- `fleetforce__Status__c` (picklist) ✓
- `fleetforce__Capacity__c` (double) ✓
- `fleetforce__Street__c` (string) ✓
- `fleetforce__City__c` (string) ✓
- `fleetforce__US_State__c` (picklist) ✓
- `fleetforce__Zip_Code__c` (string) ✓
- `fleetforce__Is_Active__c` (boolean) ✓

### 🔗 Ref columns (generator resolves at load)
- `Schedule__ref` → fleetforce__Schedule__c
- `Primary_Contact__ref` → fleetforce__Primary_Contact__c

### 🗺️ Geo columns (generator composes into compound field)
- `Latitude`
- `Longitude`

_No issues — all columns reconciled._

---
## Fleet_Asset → `fleetforce__Fleet_Asset__c` (20 rows)

### ✅ Direct fields — OK
- `Name` (string) ✓
- `fleetforce__VIN__c` (string) ✓
- `fleetforce__License_Plate__c` (string) ✓
- `fleetforce__Status__c` (picklist) ✓
- `fleetforce__Vehicle_Class__c` (picklist) ✓
- `fleetforce__Body_Type__c` (picklist) ✓
- `fleetforce__Engine_Type__c` (picklist) ✓
- `fleetforce__Fuel_Type__c` (picklist) ✓
- `fleetforce__Transmission__c` (picklist) ✓
- `fleetforce__Color__c` (picklist) ✓
- `fleetforce__Ownership__c` (picklist) ✓
- `fleetforce__Registered_State__c` (picklist) ✓
- `fleetforce__Purchase_Date__c` (date) ✓
- `fleetforce__Purchase_Price__c` (currency) ✓
- `fleetforce__Odometer__c` (double) ✓
- `fleetforce__Is_Active__c` (boolean) ✓
- `fleetforce__Seat_Count__c` (double) ✓

### 🔗 Ref columns (generator resolves at load)
- `Branch__ref` → fleetforce__Branch__c
- `Driver__ref` → fleetforce__Driver__c
- `Vendor__ref` → fleetforce__Vendor__c

### 🗺️ Geo columns (generator composes into compound field)
- `Last_Location_Lat`
- `Last_Location_Long`

_No issues — all columns reconciled._

---
## Authorized_Driver → `fleetforce__Authorized_Driver__c` (12 rows)

### ✅ Direct fields — OK
- `fleetforce__Has_Key__c` (boolean) ✓

### 🔗 Ref columns (generator resolves at load)
- `Fleet_Asset__ref` → fleetforce__Fleet_Asset__c
- `Driver__ref` → fleetforce__Driver__c

### 📅 Offset columns (generator resolves to relative dates)
- `Start_Date_Offset` → fleetforce__Start_Date__c (Date) ❌ field missing in org
- `End_Date_Offset` → fleetforce__End_Date__c (Date) ❌ field missing in org

### ❌ Issues requiring resolution
- ⚠️ `fleetforce__Type__c` — picklist values not in org: ['Primary Operator', 'Relief/Secondary Driver']
- ❌ `fleetforce__Restriction_Notes__c` — **NOT FOUND** in org
- ❌ `Start_Date_Offset` offset target `fleetforce__Start_Date__c` — **NOT FOUND** in org
- ❌ `End_Date_Offset` offset target `fleetforce__End_Date__c` — **NOT FOUND** in org

---
## Telemetry_Violation → `fleetforce__Telemetry_Violation__c` (14 rows)

### ✅ Direct fields — OK
- `fleetforce__Value__c` (string) ✓
- `fleetforce__Limit__c` (string) ✓
- `fleetforce__Is_Ack__c` (boolean) ✓
- `fleetforce__Location__c` (location) ✓

### 🔗 Ref columns (generator resolves at load)
- `Fleet_Asset__ref` → fleetforce__Fleet_Asset__c
- `Driver__ref` → fleetforce__Driver__c

### 📅 Offset columns (generator resolves to relative dates)
- `Timestamp_Offset` → fleetforce__Timestamp__c (DateTime) ✓

### ❌ Issues requiring resolution
- ⚠️ `fleetforce__Type__c` — picklist values not in org: ['Lane Drift']
- ⚠️ `fleetforce__Severity__c` — picklist values not in org: ['Warning', 'Info']

---
## Service_Ticket → `fleetforce__Service_Ticket__c` (12 rows)

### ✅ Direct fields — OK
- `fleetforce__Status__c` (picklist) ✓
- `fleetforce__Summary__c` (string) ✓

### 🔗 Ref columns (generator resolves at load)
- `Fleet_Asset__ref` → fleetforce__Fleet_Asset__c
- `Reported_By__ref` → fleetforce__Reported_By__c
- `Vendor__ref` → fleetforce__Vendor__c

### 📅 Offset columns (generator resolves to relative dates)
- `Date_Reported_Offset` → fleetforce__Date_Reported__c (DateTime) ✓
- `Scheduled_Start_Offset` → fleetforce__Scheduled_Start__c (Date) ✓
- `Actual_Start_Offset` → fleetforce__Actual_Start__c (Date) ✓

### ❌ Issues requiring resolution
- ⚠️ `fleetforce__Priority__c` — picklist values not in org: ['Standard']
- ⚠️ `fleetforce__Category__c` — picklist values not in org: ['Preventive Maintenance (PM)', 'Tire Change', 'Recall', 'Glass/Body', 'Software Update']

---
## Reservation → `fleetforce__Reservation__c` (12 rows)

### ✅ Direct fields — OK
- `fleetforce__Min_Seats__c` (double) ✓
- `fleetforce__Preferred_Engine__c` (picklist) ✓
- `fleetforce__Cost_Center__c` (string) ✓
- `fleetforce__Guest_First_Name__c` (string) ✓
- `fleetforce__Guest_Last_Name__c` (string) ✓
- `fleetforce__Guest_Email__c` (email) ✓

### 🔗 Ref columns (generator resolves at load)
- `Requestor_Contact__ref` → fleetforce__Requestor_Contact__c
- `Origin_Branch__ref` → fleetforce__Origin_Branch__c
- `Destination_Branch__ref` → fleetforce__Destination_Branch__c
- `Assigned_Asset__ref` → fleetforce__Assigned_Asset__c

### 📅 Offset columns (generator resolves to relative dates)
- `Start_Time_Offset` → fleetforce__Start_Time__c (DateTime) ✓
- `End_Time_Offset` → fleetforce__End_Time__c (DateTime) ✓
- `Approval_Date_Offset` → fleetforce__Approval_Date__c (DateTime) ✓

### ❌ Issues requiring resolution
- ⚠️ `fleetforce__Status__c` — picklist values not in org: ['Pending Approval']
- ⚠️ `fleetforce__Priority__c` — picklist values not in org: ['Standard', 'VIP', 'Urgent']
- ⚠️ `fleetforce__Preferred_Body__c` — picklist values not in org: ['Any']

---
## Summary

**21 issue(s) to resolve before generating:**

- [Account] ❌ `fleetforce__Vendor_ID__c` — **NOT FOUND** in org
- [Account] ⚠️ `Type` — picklist values not in org: ['Vendor', 'Insurer', 'Customer']
- [Account] ⚠️ `Industry` — picklist values not in org: ['Automotive', 'Financial Services', 'Automotive Repair', 'Logistics', 'Fleet Management']
- [Contact] ❌ `fleetforce__Contact_Type__c` — **NOT FOUND** in org
- [Contact] ❌ `fleetforce__Driver_Status__c` — **NOT FOUND** in org
- [Contact] ❌ `fleetforce__License_Number__c` — **NOT FOUND** in org
- [Contact] ❌ `fleetforce__License_Class__c` — **NOT FOUND** in org
- [Contact] ❌ `fleetforce__Safety_Score__c` — **NOT FOUND** in org
- [Fleet_Schedule] ⚠️ `fleetforce__Type__c` — picklist values not in org: ['Standard/Seasonal', 'Extended Hours', 'On-Call']
- [Fleet_Schedule] ⚠️ `fleetforce__Time_Zone__c` — picklist values not in org: ['UTC-08:00 Pacific', 'UTC-07:00 Mountain']
- [Authorized_Driver] ⚠️ `fleetforce__Type__c` — picklist values not in org: ['Primary Operator', 'Relief/Secondary Driver']
- [Authorized_Driver] ❌ `fleetforce__Restriction_Notes__c` — **NOT FOUND** in org
- [Authorized_Driver] ❌ `Start_Date_Offset` offset target `fleetforce__Start_Date__c` — **NOT FOUND** in org
- [Authorized_Driver] ❌ `End_Date_Offset` offset target `fleetforce__End_Date__c` — **NOT FOUND** in org
- [Telemetry_Violation] ⚠️ `fleetforce__Type__c` — picklist values not in org: ['Lane Drift']
- [Telemetry_Violation] ⚠️ `fleetforce__Severity__c` — picklist values not in org: ['Warning', 'Info']
- [Service_Ticket] ⚠️ `fleetforce__Priority__c` — picklist values not in org: ['Standard']
- [Service_Ticket] ⚠️ `fleetforce__Category__c` — picklist values not in org: ['Preventive Maintenance (PM)', 'Tire Change', 'Recall', 'Glass/Body', 'Software Update']
- [Reservation] ⚠️ `fleetforce__Status__c` — picklist values not in org: ['Pending Approval']
- [Reservation] ⚠️ `fleetforce__Priority__c` — picklist values not in org: ['Standard', 'VIP', 'Urgent']
- [Reservation] ⚠️ `fleetforce__Preferred_Body__c` — picklist values not in org: ['Any']