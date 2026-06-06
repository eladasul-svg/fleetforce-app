# Layout Diff — `fleetforce__Reservation__c`
_Generated 2026-06-06 19:16 · source: live org (fleetforce-dev-8)_

**20 of 20 custom fields placed · 6 sections across 1 layout(s) · 0 fields missing**

**Layout file(s):** `Reservation__c-Reservation Layout.layout-meta.xml`

## ❌ Fields NOT on layout
_All custom fields are placed on the layout._

## Current sections (in order)
1. **Request Details** (2 columns)
   - `Name`
   - `Priority__c` — Priority
   - `Requestor_User__c` — Requesting User
   - `Status__c` — Status
   - `Requestor_Contact__c` — Requesting Driver
   - `Cost_Center__c` — Cost Center
2. **Trip & Timing** (2 columns)
   - `Start_Time__c` — Start Time
   - `Origin_Branch__c` — Origin Branch
   - `End_Time__c` — End Time
   - `Destination_Branch__c` — Destination Branch
3. **Vehicle Preferences & Assignment** (2 columns)
   - `Min_Seats__c` — Min Seats
   - `Preferred_Engine__c` — Preferred Engine
   - `Preferred_Body__c` — Preferred Body
   - `Assigned_Asset__c` — Assigned Asset
4. **Approval & Outcome** (2 columns)
   - `Approval_Date__c` — Approval Date
   - `Rejection_Reason__c` — Rejection Reason
   - `Cancel_Reason__c` — Cancellation Reason
5. **Guest Information** (2 columns)
   - `Guest_First_Name__c` — Guest First Name
   - `Guest_Email__c` — Guest Email
   - `Guest_Last_Name__c` — Guest Last Name
   - `Guest_Phone__c` — Guest Phone
6. **System Information** (2 columns)
   - `OwnerId`
   - `CreatedById`
   - `LastModifiedById`

## Full field coverage

| Field API Name | Label | Type | Required | On Layout | Section |
|----------------|-------|------|----------|-----------|---------|
| `Approval_Date__c` | Approval Date | DateTime |  | ✓ | Approval & Outcome |
| `Assigned_Asset__c` | Assigned Asset | Lookup |  | ✓ | Vehicle Preferences & Assignment |
| `Cancel_Reason__c` | Cancellation Reason | Picklist |  | ✓ | Approval & Outcome |
| `Cost_Center__c` | Cost Center | Text |  | ✓ | Request Details |
| `Destination_Branch__c` | Destination Branch | Lookup |  | ✓ | Trip & Timing |
| `End_Time__c` | End Time | DateTime |  | ✓ | Trip & Timing |
| `Guest_Email__c` | Guest Email | Email |  | ✓ | Guest Information |
| `Guest_First_Name__c` | Guest First Name | Text |  | ✓ | Guest Information |
| `Guest_Last_Name__c` | Guest Last Name | Text |  | ✓ | Guest Information |
| `Guest_Phone__c` | Guest Phone | Phone |  | ✓ | Guest Information |
| `Min_Seats__c` | Min Seats | Number |  | ✓ | Vehicle Preferences & Assignment |
| `Origin_Branch__c` | Origin Branch | Lookup |  | ✓ | Trip & Timing |
| `Preferred_Body__c` | Preferred Body | Picklist |  | ✓ | Vehicle Preferences & Assignment |
| `Preferred_Engine__c` | Preferred Engine | Picklist |  | ✓ | Vehicle Preferences & Assignment |
| `Priority__c` | Priority | Picklist |  | ✓ | Request Details |
| `Rejection_Reason__c` | Rejection Reason | Text |  | ✓ | Approval & Outcome |
| `Requestor_Contact__c` | Requesting Driver | Lookup |  | ✓ | Request Details |
| `Requestor_User__c` | Requesting User | Lookup |  | ✓ | Request Details |
| `Start_Time__c` | Start Time | DateTime |  | ✓ | Trip & Timing |
| `Status__c` | Status | Picklist |  | ✓ | Request Details |
