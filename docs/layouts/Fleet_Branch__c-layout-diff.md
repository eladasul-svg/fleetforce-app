# Layout Diff — `fleetforce__Fleet_Branch__c`
_Generated 2026-06-06 18:55 · source: live org (fleetforce-dev-8)_

**19 of 19 custom fields placed · 5 sections across 1 layout(s) · 0 fields missing**

**Layout file(s):** `Fleet_Branch__c-Fleet Branch Layout.layout-meta.xml`

## ❌ Fields NOT on layout
_All custom fields are placed on the layout._

## Current sections (in order)
1. **Information** (2 columns)
   - `Name`
   - `Branch_ID__c` — Branch ID
   - `Status__c` — Status
   - `Type__c` — Location Type
   - `Primary_Contact__c` — Primary Contact
   - `Approving_Manager__c` — Approving Manager
   - `Capacity__c` — Parking Capacity
   - `Phone__c` — Phone
   - `Email__c` — Email
   - `Website__c` — Website
2. **Location & Address** (2 columns)
   - `Street__c` — Street Address
   - `City__c` — City
   - `US_State__c` — State
   - `Zip_Code__c` — Zip/Postal Code
   - `County_Province__c` — County/Province
   - `Country__c` — Country
   - `Location__c` — Geo Location
3. **Operations** (2 columns)
   - `Schedule__c` — Schedule
   - `Time_Zone__c` — Time Zone
   - `Is_Active__c` — Is Active
4. **System Information** (2 columns)
   - `CreatedById`
   - `LastModifiedById`
5. **Custom Links** (2 columns)

## Full field coverage

| Field API Name | Label | Type | Required | On Layout | Section |
|----------------|-------|------|----------|-----------|---------|
| `Approving_Manager__c` | Approving Manager | Lookup |  | ✓ | Information |
| `Branch_ID__c` | Branch ID | Text |  | ✓ | Information |
| `Capacity__c` | Parking Capacity | Number |  | ✓ | Information |
| `City__c` | City | Text |  | ✓ | Location & Address |
| `Country__c` | Country | Picklist |  | ✓ | Location & Address |
| `County_Province__c` | County/Province | Text |  | ✓ | Location & Address |
| `Email__c` | Email | Email |  | ✓ | Information |
| `Is_Active__c` | Is Active | Checkbox |  | ✓ | Operations |
| `Location__c` | Geo Location | Location |  | ✓ | Location & Address |
| `Phone__c` | Phone | Phone |  | ✓ | Information |
| `Primary_Contact__c` | Primary Contact | Lookup |  | ✓ | Information |
| `Schedule__c` | Schedule | Lookup |  | ✓ | Operations |
| `Status__c` | Status | Picklist |  | ✓ | Information |
| `Street__c` | Street Address | Text |  | ✓ | Location & Address |
| `Time_Zone__c` | Time Zone | Picklist |  | ✓ | Operations |
| `Type__c` | Location Type | Picklist |  | ✓ | Information |
| `US_State__c` | State | Picklist |  | ✓ | Location & Address |
| `Website__c` | Website | Url |  | ✓ | Information |
| `Zip_Code__c` | Zip/Postal Code | Text |  | ✓ | Location & Address |
