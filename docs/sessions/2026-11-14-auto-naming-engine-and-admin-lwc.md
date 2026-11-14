# Session: Record Auto-Naming Engine & FleetForce Admin LWC

**Date:** 2026-11-14  
**Orgs:** `fleetforce-dev-13` (`customization-power-6735`, `00DWm000002fyrtMAA`)  
**Namespace:** `fleetforce`  
**Status:** Deployed, Verified & Tested

---

## 1. Summary of Delivered Work

Delivered a metadata-driven, enterprise-grade **Record Auto-Naming Engine** and companion **Admin LWC (`fleetAutoNamingAdmin`)** for FleetForce. The solution solves the universal fleet operations challenge where records have fragmented or ambiguous names (e.g. shorthand strings like `BSC-10` or raw Salesforce IDs).

Key highlights:

- **Custom Metadata Type (`Auto_Naming_Rule__mdt`)**: Allows declarative rule configuration per object with subscriber manageability.
- **Packaged Default Rules**: Packaged defaults for `Fleet_Asset__c`, `Citation__c`, `Reservation__c`, and `Driver_Qualification__c`.
- **Apex Domain Engine (`AutoNamingService.cls`)**: Token interpolation (`{Model_Year__c} {Make__c} {Model__c} · {License_Plate__c}`), smart separator pruning, empty token fallback cascade, 80-character boundary truncation, and auto-number object safety guards.
- **Bulk Recalculation Engine (`AutoNamingBatch.cls`)**: Batch Apex job that re-evaluates and standardizes all existing records across any supported object in chunks of 200 in `USER_MODE`.
- **Admin App UI (`fleetAutoNamingAdmin` LWC)**: A 2-step workflow (View Overview $\rightarrow$ Dedicated Edit Mode) embedded directly into the **Settings** tab of FleetForce Admin.
- **Apex Triggers**: Wired into `FleetAssetTrigger` and `CitationTrigger`.
- **Test Coverage**: 11/11 Apex unit tests passing (100%), 14/14 LWC Jest test suites passing (60/60 tests).

---

## 2. Technical Architecture & Component Inventory

### Custom Metadata Schema

- **`Auto_Naming_Rule__mdt`**:
  - `Object_API_Name__c` (Text 100, Required)
  - `Pattern__c` (Text 255, Required)
  - `Is_Active__c` (Checkbox, Default True)
  - `Allow_Manual_Override__c` (Checkbox, Default False)
  - `Description__c` (Text 255)

### Packaged Default Custom Metadata Records

1. `Auto_Naming_Rule.Fleet_Asset`: `{Model_Year__c} {Make__c} {Model__c} · {License_Plate__c}`
2. `Auto_Naming_Rule.Citation`: `{Ticket_Number__c} · {Violation_Type__c}`
3. `Auto_Naming_Rule.Reservation`: `{Preferred_Body__c} ({Status__c})`
4. `Auto_Naming_Rule.Driver_Qualification`: `{Type__c} ({Status__c})`

### Apex Classes & Triggers

- `AutoNamingService.cls`:
  - Token replacer regex: `\{([a-zA-Z0-9_]+)\}`
  - Smart sanitization: strips orphaned separators (`·`, `-`, `/`, `|`), empty brackets `()`, and collapses multiple spaces.
  - Multi-tier fallback cascade: Asset ID $\rightarrow$ VIN $\rightarrow$ Existing Name $\rightarrow$ Object Label.
  - Length guard: Cleanly truncates strings longer than 80 characters to prevent database DML exceptions.
  - AutoNumber guard: Checks `nameDescribe.isCreateable() && nameDescribe.isUpdateable()` to skip objects where `Name` is an AutoNumber (such as `Service_Ticket__c`).
  - Batch recursion guard: `public static Boolean isBypassed`.
- `AutoNamingBatch.cls`:
  - Database.Batchable implementation for bulk recalculations.
  - Sets `AutoNamingService.isBypassed = true` in batch execution to prevent trigger recursion.
- `AutoNamingAdminController.cls`:
  - `getSupportedObjects()`: Discovers eligible objects where `Name` is Text.
  - `getObjectFields()`: Excludes system audit fields (`Id`, `IsDeleted`, `CreatedDate`, `CreatedById`, `SystemModstamp`, etc.) so only clean business fields appear as tokens.
  - `previewPattern()`: Evaluates pattern against actual org records or mock fallback.
  - `saveRule()`: Persists rules directly to Custom Metadata using `Metadata.Operations.enqueueDeployment`.
  - `runRecalculateBatch()` & `getBatchJobStatus()`: Triggers batch job and monitors execution.
- Triggers:
  - `FleetAssetTrigger.trigger`: Added `AutoNamingService.apply(Trigger.new)`.
  - `CitationTrigger.trigger`: Created and deployed for automatic citation naming.

### Lightning Web Component (`fleetAutoNamingAdmin`)

- **View Mode (Default)**:
  - Active formula pattern block.
  - Real-Time Evaluation Preview banner evaluated on actual org data.
  - Badges for status (`Active` / `Inactive`) and override mode (`Enforced` / `Manual Override Allowed`).
  - Action buttons: "Modify Formula" (switches to Edit Mode) and "Recalculate All Records" (triggers bulk backfill modal).
  - Enterprise Safety & Fallbacks info card.
- **Edit Mode**:
  - Toggles for `Active Rule` and `Allow Manual Override`.
  - Formula pattern text input with live character counter (`xx / 80 chars`).
  - Clickable token chips for business fields.
  - Live preview updating in real time.
  - Action footer: "Revert to Default", "Cancel", "Save", and "Save & Recalculate".
- **Integration**:
  - Embedded into `force-app/main/default/lwc/fleetSettings/fleetSettings.html` under the Regional Settings section.

---

## 3. Test & Verification Summary

- **Apex Unit Tests:**
  - `AutoNamingServiceTest`: 6 tests passing (Asset naming, Citation naming, fallback cascades, sanitization & boundary truncation, batch execution, custom pattern evaluation).
  - `AutoNamingAdminControllerTest`: 5 tests passing (Object & field discovery, sample preview, mock fallback preview, batch job execution, metadata saveRule deployment).
  - Total: 11 tests passed in 2.8s.
- **Jest Unit Tests:**
  - All 14 suites passed, 60 tests passed.
- **Scratch Org Verification:**
  - Deployed cleanly to `fleetforce-dev-13`.
