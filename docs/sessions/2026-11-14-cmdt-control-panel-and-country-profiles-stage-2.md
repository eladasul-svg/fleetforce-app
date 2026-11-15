# Stage 2: Custom Metadata (CMDT) Control Panel & Country Profiles

**Date:** November 14, 2026  
**Branch:** `feature/routing-module`  
**Target Scratch Org:** `fleetforce-dev-13`  
**Status:** Complete & Deployed

---

## 1. Context & Objectives

In Stage 1, the FleetForce Admin App (`FleetForce_Admin.app`) was transformed into a modular console with dedicated tabs (`Fleetforce_General_Settings`, `Fleetforce_Brand_Theme`, `Fleetforce_Regional_Settings`, and `Fleetforce_Auto_Naming`).

In Stage 2, our objective was to eliminate the requirement for FleetForce administrators to navigate into Salesforce Setup to manage Custom Metadata Types (such as modifying Country Profile baselines—e.g. changing Spain from `km` to `mi`).

To accomplish this:

1. We adapted the production-tested generic Custom Metadata Type (CMDT) Control Panel architecture from the BR7 PSS project.
2. We supported all 6 FleetForce Custom Metadata Types:
   - `Country_Profile__mdt`
   - `Vehicle_Model__mdt`
   - `Auto_Naming_Rule__mdt`
   - `Routing_Policy_Setting__mdt`
   - `Capacity_Dimension__mdt`
   - `Geotab_Setting__mdt`
3. We created an asynchronous metadata deployment pipeline utilizing `Metadata.Operations.enqueueDeployment` with real-time feedback via Platform Events (`Cmdt_Deploy_Result__e`) and `lightning/empApi`.
4. We created a dedicated `Custom Metadata` tab (`Cmdt_Control_Panel`) in `FleetForce_Admin.app` and linked directly to it from `fleetRegionalSettings`.

---

## 2. Technical Architecture & Components Created

### A. Platform Event (`Cmdt_Deploy_Result__e`)

- **API Name:** `Cmdt_Deploy_Result__e`
- **Fields:**
  - `Cmdt_Type__c` (Text, 255): Custom metadata type API name.
  - `Error_Message__c` (LongTextArea, 32768): Error stack/message upon compile or deploy failures.
  - `Request_Key__c` (Text, 255, Indexed): Correlates client request UUID to async deployment event.
  - `Success__c` (Checkbox): `true` when compilation and metadata deployment succeed.

### B. Apex CMDT Service Framework

1. **`CmdtTypeRegistry.cls`:**
   - Allowlist security guard preventing arbitrary metadata reads/deployments.
   - Dynamic namespace-stripping and friendly type metadata for combobox selectors.
2. **`CmdtSchemaService.cls`:**
   - Dynamic schema inspector fetching field metadata, labels, data types, and active picklist entries.
3. **`CmdtRecordService.cls`:**
   - Dynamic SOQL generator supporting namespaced packaging (`fleetforce__`) and local org execution.
4. **`CmdtDeployCallback.cls`:**
   - Implements `Metadata.DeployCallback` to capture async deployment outcomes and fire `Cmdt_Deploy_Result__e`.
5. **`CmdtDeployService.cls`:**
   - Constructs `Metadata.CustomMetadata` and `Metadata.DeployContainer`.
   - Enqueues deployment via `Metadata.Operations.enqueueDeployment`.

### C. Lightning Web Component: `cmdtControlPanel`

- **Combobox Type Selector:** Populated dynamically from `CmdtTypeRegistry.getSupportedTypes()`.
- **Default Selected Type:** Defaults to `Country_Profile__mdt`, rendering country profiles immediately.
- **Dynamic Datatable:** Lists all records with edit actions. Formats checkboxes, picklists, and text columns dynamically.
- **In-App Record Modal (Edit / Create):**
  - Developer Name (read-only for existing records).
  - Record Label (MasterLabel).
  - Dynamic fields with active picklist comboboxes, checkboxes, numbers, textareas, and text inputs.
- **EmpApi Platform Event Listener:** Subscribes to `/event/Cmdt_Deploy_Result__e` to handle real-time completion without HTTP polling.

### D. Navigation & App Integration

- **FlexiPage:** `Cmdt_Control_Panel.flexipage-meta.xml`
- **Custom Tab:** `Cmdt_Control_Panel.tab-meta.xml` (Label: `Custom Metadata`, Motif: `Custom18: Form`)
- **Admin App Navigation:** Added `Cmdt_Control_Panel` tab to `FleetForce_Admin.app-meta.xml`.
- **Permission Set:** Granted access in `FleetforceAdmin.permissionset-meta.xml` for all 5 Apex classes and the custom tab.
- **Regional Settings Integration:** Added a "Manage & Edit Profiles" direct action button in `fleetRegionalSettings` that navigates immediately to `Cmdt_Control_Panel`.

---

## 3. Verification & Test Results

1. **Apex Unit Tests:**
   - All 16 CMDT Apex tests passed with 100% pass rate (`CmdtTypeRegistryTest`, `CmdtSchemaServiceTest`, `CmdtRecordServiceTest`, `CmdtDeployCallbackTest`, `CmdtDeployServiceTest`).
   - All 8 `FleetDisplaySettingsControllerTest` tests passed with 100% pass rate.
2. **Jest Unit Tests:**
   - All 15 suites passed (62/62 tests passing).
3. **Scratch Org Deployment:**
   - Deployed successfully to `fleetforce-dev-13`.
   - Verified via anonymous Apex that all 10 `fleetforce__Country_Profile__mdt` records load with full field describes and picklist options.
