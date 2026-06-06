# Layout Diff — `fleetforce__Authorized_Driver__c`
_Generated 2026-06-06 19:22 · source: live org (fleetforce-dev-8)_

**5 of 5 custom fields placed · 3 sections across 1 layout(s) · 0 fields missing**

**Layout file(s):** `Authorized_Driver__c-Authorized Driver Layout.layout-meta.xml`

## ❌ Fields NOT on layout
_All custom fields are placed on the layout._

## Current sections (in order)
1. **Authorization** (2 columns)
   - `Name`
   - `Fleet_Asset__c` — Fleet Asset
   - `Type__c` — Authorization Type
   - `Driver__c` — Driver (Contact)
   - `Is_Active__c` — Is Active
   - `Has_Key__c` — Key Access
2. **System Information** (2 columns)
   - `CreatedById`
   - `LastModifiedById`
3. **(unlabeled)** (2 columns)

## Full field coverage

| Field API Name | Label | Type | Required | On Layout | Section |
|----------------|-------|------|----------|-----------|---------|
| `Driver__c` | Driver (Contact) | Lookup |  | ✓ | Authorization |
| `Fleet_Asset__c` | Fleet Asset | MasterDetail |  | ✓ | Authorization |
| `Has_Key__c` | Key Access | Checkbox |  | ✓ | Authorization |
| `Is_Active__c` | Is Active | Checkbox |  | ✓ | Authorization |
| `Type__c` | Authorization Type | Picklist |  | ✓ | Authorization |
