# Layout Diff — `fleetforce__Allocation__c`
_Generated 2026-06-06 19:20 · source: live org (fleetforce-dev-8)_

**19 of 19 custom fields placed · 7 sections across 1 layout(s) · 0 fields missing**

**Layout file(s):** `Allocation__c-Allocation Layout.layout-meta.xml`

## ❌ Fields NOT on layout
_All custom fields are placed on the layout._

## Current sections (in order)
1. **Information** (2 columns)
2. **Trip Status & Identity** (2 columns)
   - `Name`
   - `Fleet_Asset__c` — Fleet Asset
   - `Driver__c` — Driver (Contact)
   - `Reservation__c` — Reservation
   - `Status__c` — Status
   - `Distance_Driven__c` — Trip Distance
   - `Has_New_Damage__c` — Damage Flag
3. **Schedule vs. Reality** (2 columns)
   - `Scheduled_Start__c` — Scheduled Start
   - `Scheduled_End__c` — Scheduled End
   - `Actual_Check_In__c` — Actual Check-In
   - `Actual_Check_Out__c` — Actual Check-Out
4. **Vehicle Health & Custody** (2 columns)
   - `Odometer_Start__c` — Odometer Start
   - `Fuel_Level_Out__c` — Fuel Level Out
   - `Condition_Out__c` — Condition Out
   - `Odometer_End__c` — Odometer End
   - `Fuel_Level_In__c` — Fuel Level In
   - `Condition_In__c` — Condition In
5. **Branch & Logistics** (2 columns)
   - `Origin_Branch__c` — Origin Branch
   - `Return_Branch__c` — Return Branch
   - `Same_Branch_Return__c` — Same Branch Return
6. **System Information** (2 columns)
   - `CreatedById`
   - `LastModifiedById`
7. **Custom Links** (2 columns)

## Full field coverage

| Field API Name | Label | Type | Required | On Layout | Section |
|----------------|-------|------|----------|-----------|---------|
| `Actual_Check_In__c` | Actual Check-In | DateTime |  | ✓ | Schedule vs. Reality |
| `Actual_Check_Out__c` | Actual Check-Out | DateTime |  | ✓ | Schedule vs. Reality |
| `Condition_In__c` | Condition In | LongTextArea |  | ✓ | Vehicle Health & Custody |
| `Condition_Out__c` | Condition Out | LongTextArea |  | ✓ | Vehicle Health & Custody |
| `Distance_Driven__c` | Trip Distance | Number |  | ✓ | Trip Status & Identity |
| `Driver__c` | Driver (Contact) | Lookup |  | ✓ | Trip Status & Identity |
| `Fleet_Asset__c` | Fleet Asset | MasterDetail |  | ✓ | Trip Status & Identity |
| `Fuel_Level_In__c` | Fuel Level In | Percent |  | ✓ | Vehicle Health & Custody |
| `Fuel_Level_Out__c` | Fuel Level Out | Percent |  | ✓ | Vehicle Health & Custody |
| `Has_New_Damage__c` | Damage Flag | Checkbox |  | ✓ | Trip Status & Identity |
| `Odometer_End__c` | Odometer End | Number |  | ✓ | Vehicle Health & Custody |
| `Odometer_Start__c` | Odometer Start | Number |  | ✓ | Vehicle Health & Custody |
| `Origin_Branch__c` | Origin Branch | Lookup |  | ✓ | Branch & Logistics |
| `Reservation__c` | Reservation | Lookup |  | ✓ | Trip Status & Identity |
| `Return_Branch__c` | Return Branch | Lookup |  | ✓ | Branch & Logistics |
| `Same_Branch_Return__c` | Same Branch Return | Checkbox |  | ✓ | Branch & Logistics |
| `Scheduled_End__c` | Scheduled End | DateTime |  | ✓ | Schedule vs. Reality |
| `Scheduled_Start__c` | Scheduled Start | DateTime |  | ✓ | Schedule vs. Reality |
| `Status__c` | Status | Picklist |  | ✓ | Trip Status & Identity |
