# Layout Diff — `fleetforce__Reservation__c`
_Generated 2026-06-06 18:55 · source: live org (fleetforce-dev-8)_

**6 of 21 custom fields placed · 3 sections across 1 layout(s) · 15 fields missing**

**Layout file(s):** `Reservation__c-Reservation Layout.layout-meta.xml`

## ❌ Fields NOT on layout
_15 field(s) missing:_

| Field API Name | Label | Type | Required |
|----------------|-------|------|----------|
| `Approval_Date__c` | Approval Date | DateTime |  |
| `Cancel_Reason__c` | Cancellation Reason | Picklist |  |
| `Cost_Center__c` | Cost Center | Text |  |
| `Dest_Branch__c` | Destination Branch | Lookup |  |
| `End_Time__c` | End Time | DateTime |  |
| `Guest_Email__c` | Guest Email | Email |  |
| `Guest_First_Name__c` | Guest First Name | Text |  |
| `Guest_Last_Name__c` | Guest Last Name | Text |  |
| `Guest_Phone__c` | Guest Phone | Phone |  |
| `Min_Seats__c` | Min Seats | Number |  |
| `Rejection_Reason__c` | Rejection Reason | Text |  |
| `Requestor_Contact__c` | Requesting Driver | Lookup |  |
| `Requestor_User__c` | Requesting User | Lookup |  |
| `Start_Time__c` | Start Time | DateTime |  |
| `Status__c` | Status | Picklist |  |

## Current sections (in order)
1. **Information** (2 columns)
   - `Name`
   - `Origin_Branch__c` — Origin Branch
   - `Destination_Branch__c` — Destination Branch
   - `Assigned_Asset__c` — Assigned Asset
   - `Preferred_Body__c` — Preferred Body
   - `Preferred_Engine__c` — Preferred Engine
   - `Priority__c` — Priority
   - `OwnerId`
2. **System Information** (2 columns)
   - `CreatedById`
   - `LastModifiedById`
3. **(unlabeled)** (2 columns)

## Full field coverage

| Field API Name | Label | Type | Required | On Layout | Section |
|----------------|-------|------|----------|-----------|---------|
| `Approval_Date__c` | Approval Date | DateTime |  | ✗ | — |
| `Cancel_Reason__c` | Cancellation Reason | Picklist |  | ✗ | — |
| `Cost_Center__c` | Cost Center | Text |  | ✗ | — |
| `Dest_Branch__c` | Destination Branch | Lookup |  | ✗ | — |
| `End_Time__c` | End Time | DateTime |  | ✗ | — |
| `Guest_Email__c` | Guest Email | Email |  | ✗ | — |
| `Guest_First_Name__c` | Guest First Name | Text |  | ✗ | — |
| `Guest_Last_Name__c` | Guest Last Name | Text |  | ✗ | — |
| `Guest_Phone__c` | Guest Phone | Phone |  | ✗ | — |
| `Min_Seats__c` | Min Seats | Number |  | ✗ | — |
| `Rejection_Reason__c` | Rejection Reason | Text |  | ✗ | — |
| `Requestor_Contact__c` | Requesting Driver | Lookup |  | ✗ | — |
| `Requestor_User__c` | Requesting User | Lookup |  | ✗ | — |
| `Start_Time__c` | Start Time | DateTime |  | ✗ | — |
| `Status__c` | Status | Picklist |  | ✗ | — |
| `Assigned_Asset__c` | Assigned Asset | Lookup |  | ✓ | Information |
| `Destination_Branch__c` | Destination Branch | Lookup |  | ✓ | Information |
| `Origin_Branch__c` | Origin Branch | Lookup |  | ✓ | Information |
| `Preferred_Body__c` | Preferred Body | Picklist |  | ✓ | Information |
| `Preferred_Engine__c` | Preferred Engine | Picklist |  | ✓ | Information |
| `Priority__c` | Priority | Picklist |  | ✓ | Information |
