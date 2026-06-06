# Layout Diff — `fleetforce__Telemetry_Violation__c`
_Generated 2026-06-06 18:55 · source: live org (fleetforce-dev-8)_

**2 of 11 custom fields placed · 3 sections across 1 layout(s) · 9 fields missing**

**Layout file(s):** `Telemetry_Violation__c-Telemetry Violation Layout.layout-meta.xml`

## ❌ Fields NOT on layout
_9 field(s) missing:_

| Field API Name | Label | Type | Required |
|----------------|-------|------|----------|
| `Equipment__c` | Equipment | Lookup |  |
| `Is_Ack__c` | Is Acknowledged | Checkbox |  |
| `Limit__c` | Limit / Threshold | Text |  |
| `Location__c` | Location | Location |  |
| `Notes__c` | Review Notes | LongTextArea |  |
| `Severity__c` | Severity | Picklist |  |
| `Timestamp__c` | Timestamp | DateTime |  |
| `Type__c` | Violation Type | Picklist |  |
| `Value__c` | Recorded Value | Text |  |

## Current sections (in order)
1. **Information** (2 columns)
   - `Name`
   - `Fleet_Asset__c` — Fleet Asset
   - `Driver__c` — Driver
   - `OwnerId`
2. **System Information** (2 columns)
   - `CreatedById`
   - `LastModifiedById`
3. **(unlabeled)** (2 columns)

## Full field coverage

| Field API Name | Label | Type | Required | On Layout | Section |
|----------------|-------|------|----------|-----------|---------|
| `Equipment__c` | Equipment | Lookup |  | ✗ | — |
| `Is_Ack__c` | Is Acknowledged | Checkbox |  | ✗ | — |
| `Limit__c` | Limit / Threshold | Text |  | ✗ | — |
| `Location__c` | Location | Location |  | ✗ | — |
| `Notes__c` | Review Notes | LongTextArea |  | ✗ | — |
| `Severity__c` | Severity | Picklist |  | ✗ | — |
| `Timestamp__c` | Timestamp | DateTime |  | ✗ | — |
| `Type__c` | Violation Type | Picklist |  | ✗ | — |
| `Value__c` | Recorded Value | Text |  | ✗ | — |
| `Driver__c` | Driver | Lookup |  | ✓ | Information |
| `Fleet_Asset__c` | Fleet Asset | Lookup |  | ✓ | Information |
