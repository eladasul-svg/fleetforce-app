# Layout Diff — `fleetforce__Fleet_Asset__c`
_Generated 2026-06-06 18:55 · source: live org (fleetforce-dev-8)_

**35 of 35 custom fields placed · 7 sections across 1 layout(s) · 0 fields missing**

**Layout file(s):** `Fleet_Asset__c-Fleet Asset Layout.layout-meta.xml`

## ❌ Fields NOT on layout
_All custom fields are placed on the layout._

## Current sections (in order)
1. **Information** (2 columns)
2. **Identity & Real-Time Status** (2 columns)
   - `Name`
   - `VIN__c` — VIN
   - `License_Plate__c` — License Plate
   - `Registered_State__c` — Registered State
   - `Status__c` — Status
   - `Is_Active__c` — Active
   - `Odometer__c` — Odometer
   - `Fuel_Energy_Level__c` — Fuel/Energy Level
   - `Last_Location__c` — Last Location
3. **Assignment & Operations** (2 columns)
   - `Branch__c` — Branch
   - `Driver__c` — Driver
   - `Asset_ID__c` — Asset ID
   - `Key_Tag_ID__c` — Key Tag ID
   - `Vehicle_Class__c` — Vehicle Class
4. **Specifications & Performance** (2 columns)
   - `Fuel_Type__c` — Fuel Type
   - `Fuel_Capacity__c` — Fuel Capacity
   - `Transmission__c` — Transmission
   - `Engine_Type__c` — Engine Type
   - `Drive_Type__c` — Drive Type
   - `Max_Range__c` — Max Range
   - `Battery_Capacity_kWh__c` — Battery Capacity (kWh)
   - `Body_Type__c` — Body Type
   - `Gross_Weight__c` — Gross Weight (GVW)
   - `Height__c` — Height
   - `Seat_Count__c` — Seat Count
   - `Color__c` — Color
   - `Paint_Name__c` — Paint Name
5. **Financial & Lifecycle** (2 columns)
   - `Ownership__c` — Ownership
   - `Vendor__c` — Vendor/FMC
   - `Agreement__c` — Agreement
   - `Agreement_Line__c` — Agreement Line Item
   - `Purchase_Date__c` — Purchase Date
   - `Purchase_Price__c` — Purchase Price
   - `Residual_Value__c` — Residual Value
   - `Total_Maintenance_Cost__c` — Total Maintenance Cost
   - `Serial__c` — Serial
6. **System Information** (2 columns)
   - `CreatedById`
   - `LastModifiedById`
7. **Custom Links** (2 columns)

## Full field coverage

| Field API Name | Label | Type | Required | On Layout | Section |
|----------------|-------|------|----------|-----------|---------|
| `Agreement_Line__c` | Agreement Line Item | Lookup |  | ✓ | Financial & Lifecycle |
| `Agreement__c` | Agreement | Lookup |  | ✓ | Financial & Lifecycle |
| `Asset_ID__c` | Asset ID | Text |  | ✓ | Assignment & Operations |
| `Battery_Capacity_kWh__c` | Battery Capacity (kWh) | Number |  | ✓ | Specifications & Performance |
| `Body_Type__c` | Body Type | Picklist |  | ✓ | Specifications & Performance |
| `Branch__c` | Branch | Lookup |  | ✓ | Assignment & Operations |
| `Color__c` | Color | Picklist |  | ✓ | Specifications & Performance |
| `Drive_Type__c` | Drive Type | Picklist |  | ✓ | Specifications & Performance |
| `Driver__c` | Driver | Lookup |  | ✓ | Assignment & Operations |
| `Engine_Type__c` | Engine Type | Picklist |  | ✓ | Specifications & Performance |
| `Fuel_Capacity__c` | Fuel Capacity | Number |  | ✓ | Specifications & Performance |
| `Fuel_Energy_Level__c` | Fuel/Energy Level | Percent |  | ✓ | Identity & Real-Time Status |
| `Fuel_Type__c` | Fuel Type | Picklist |  | ✓ | Specifications & Performance |
| `Gross_Weight__c` | Gross Weight (GVW) | Number |  | ✓ | Specifications & Performance |
| `Height__c` | Height | Number |  | ✓ | Specifications & Performance |
| `Is_Active__c` | Active | Checkbox |  | ✓ | Identity & Real-Time Status |
| `Key_Tag_ID__c` | Key Tag ID | Text |  | ✓ | Assignment & Operations |
| `Last_Location__c` | Last Location | Location |  | ✓ | Identity & Real-Time Status |
| `License_Plate__c` | License Plate | Text |  | ✓ | Identity & Real-Time Status |
| `Max_Range__c` | Max Range | Number |  | ✓ | Specifications & Performance |
| `Odometer__c` | Odometer | Number |  | ✓ | Identity & Real-Time Status |
| `Ownership__c` | Ownership | Picklist |  | ✓ | Financial & Lifecycle |
| `Paint_Name__c` | Paint Name | Text |  | ✓ | Specifications & Performance |
| `Purchase_Date__c` | Purchase Date | Date |  | ✓ | Financial & Lifecycle |
| `Purchase_Price__c` | Purchase Price | Currency |  | ✓ | Financial & Lifecycle |
| `Registered_State__c` | Registered State | Picklist |  | ✓ | Identity & Real-Time Status |
| `Residual_Value__c` | Residual Value | Currency |  | ✓ | Financial & Lifecycle |
| `Seat_Count__c` | Seat Count | Number |  | ✓ | Specifications & Performance |
| `Serial__c` | Serial | Text |  | ✓ | Financial & Lifecycle |
| `Status__c` | Status | Picklist |  | ✓ | Identity & Real-Time Status |
| `Total_Maintenance_Cost__c` | Total Maintenance Cost | Summary |  | ✓ | Financial & Lifecycle |
| `Transmission__c` | Transmission | Picklist |  | ✓ | Specifications & Performance |
| `VIN__c` | VIN | Text |  | ✓ | Identity & Real-Time Status |
| `Vehicle_Class__c` | Vehicle Class | Picklist |  | ✓ | Assignment & Operations |
| `Vendor__c` | Vendor/FMC | Lookup |  | ✓ | Financial & Lifecycle |
