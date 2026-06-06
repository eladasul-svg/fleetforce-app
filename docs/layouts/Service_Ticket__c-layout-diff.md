# Layout Diff — `fleetforce__Service_Ticket__c`
_Generated 2026-06-06 18:55 · source: live org (fleetforce-dev-8)_

**23 of 25 custom fields placed · 5 sections across 1 layout(s) · 2 fields missing**

**Layout file(s):** `Service_Ticket__c-Service Ticket Layout.layout-meta.xml`

## ❌ Fields NOT on layout
_2 field(s) missing:_

| Field API Name | Label | Type | Required |
|----------------|-------|------|----------|
| `Total_Cost__c` | Total Cost | Number |  |
| `Violation_Source__c` | Violation Source | Lookup |  |

## Current sections (in order)
1. **Information** (2 columns)
   - `Name`
   - `Fleet_Asset__c` — Fleet Asset
   - `Status__c` — Status
   - `Priority__c` — Priority
   - `Scheduled_Start__c` — Scheduled Start
   - `Scheduled_End__c` — Scheduled End
   - `Actual_Start__c` — Actual Start
   - `Actual_End__c` — Actual End
   - `In_Shop__c` — In Shop
   - `Reported_By__c` — Reported By
   - `Date_Reported__c` — Date Reported
   - `Odometer__c` — Odometer
   - `Due_Date__c` — Due Date
2. **Diagnosis & Work** (2 columns)
   - `Summary__c` — Summary
   - `Category__c` — Ticket Type
   - `Description__c` — Description
3. **Financials** (2 columns)
   - `Grand_Total__c` — Grand Total
   - `Total_Parts_Cost__c` — Total Parts Cost
   - `Total_Labor_Cost__c` — Total Labor Cost
   - `Misc_Fees__c` — Misc / Fees
   - `Fixed_Cost__c` — Fixed Price
   - `Tax_Rate__c` — Tax Rate
   - `Is_Labor_Taxable__c` — Tax Labor?
   - `Vendor__c` — Vendor
4. **System Information** (2 columns)
   - `CreatedById`
   - `LastModifiedById`
5. **Custom Links** (2 columns)

## Full field coverage

| Field API Name | Label | Type | Required | On Layout | Section |
|----------------|-------|------|----------|-----------|---------|
| `Total_Cost__c` | Total Cost | Number |  | ✗ | — |
| `Violation_Source__c` | Violation Source | Lookup |  | ✗ | — |
| `Actual_End__c` | Actual End | Date |  | ✓ | Information |
| `Actual_Start__c` | Actual Start | Date |  | ✓ | Information |
| `Category__c` | Ticket Type | Picklist |  | ✓ | Diagnosis & Work |
| `Date_Reported__c` | Date Reported | DateTime |  | ✓ | Information |
| `Description__c` | Description | LongTextArea |  | ✓ | Diagnosis & Work |
| `Due_Date__c` | Due Date | Date |  | ✓ | Information |
| `Fixed_Cost__c` | Fixed Price | Currency |  | ✓ | Financials |
| `Fleet_Asset__c` | Fleet Asset | MasterDetail |  | ✓ | Information |
| `Grand_Total__c` | Grand Total | Currency |  | ✓ | Financials |
| `In_Shop__c` | In Shop | Checkbox |  | ✓ | Information |
| `Is_Labor_Taxable__c` | Tax Labor? | Checkbox |  | ✓ | Financials |
| `Misc_Fees__c` | Misc / Fees | Currency |  | ✓ | Financials |
| `Odometer__c` | Odometer | Number |  | ✓ | Information |
| `Priority__c` | Priority | Picklist |  | ✓ | Information |
| `Reported_By__c` | Reported By | Lookup |  | ✓ | Information |
| `Scheduled_End__c` | Scheduled End | Date |  | ✓ | Information |
| `Scheduled_Start__c` | Scheduled Start | Date |  | ✓ | Information |
| `Status__c` | Status | Picklist |  | ✓ | Information |
| `Summary__c` | Summary | Text |  | ✓ | Diagnosis & Work |
| `Tax_Rate__c` | Tax Rate | Percent |  | ✓ | Financials |
| `Total_Labor_Cost__c` | Total Labor Cost | Currency |  | ✓ | Financials |
| `Total_Parts_Cost__c` | Total Parts Cost | Currency |  | ✓ | Financials |
| `Vendor__c` | Vendor | Lookup |  | ✓ | Financials |
