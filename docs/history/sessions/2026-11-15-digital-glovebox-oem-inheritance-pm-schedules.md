# Session Notes: Digital Glovebox, Hierarchical OEM Manual Inheritance & Preventive Maintenance Integration

**Date:** 2026-11-15  
**Target Scratch Org:** `fleetforce-dev-13` (`00DWm000002fyrtMAA`, `test-fubqn3lghmcn@example.com`)  
**Git Branch:** `feature/routing-module`

---

## 1. Problem & Architecture

In commercial fleet operations, fleet managers manage hundreds or thousands of vehicles of the same make and model (e.g. 500 Ford F-150s or 200 Ford E-Transit vans). Forcing operators to upload manufacturer handbooks, roadside guides, and infotainment reset videos per asset record creates severe data bloat and maintenance overhead.

Simultaneously, drivers and fleet dispatchers require instant access to:

1. **Asset-specific compliance documents:** State vehicle registrations, insurance cards, emissions certifications, DOT annual inspection reports.
2. **Model-level OEM documents:** Manufacturer owner's manuals, fuse diagrams, roadside assistance numbers, and tow override instructions.
3. **Driver Infotainment & Data Sanitization videos:** Embedded YouTube walkthroughs demonstrating how to unpair driver mobile devices, clear navigation history, and reset the infotainment head unit upon vehicle return.
4. **Preventive Maintenance (PM) schedules:** Master maintenance plans (`Maintenance_Plan__c`) defining distance/time service intervals and SOP checklists, correlated with recent service ticket executions (`Service_Ticket__c`).

---

## 2. Implementation Summary

### Phase 1: Data Model Updates

- **`Vehicle_Model__mdt`**:
  - `Manufacturer_Handbook_URL__c` (URL(255))
  - `Infotainment_Video_URL__c` (URL(255))
  - `Emergency_Guide_URL__c` (URL(255))
  - Seeded standard URLs on `Ford_F_150_Lariat_4WD`, `Ford_E_Transit_Cargo_Van_EV`, and `Chevrolet_Malibu_LT`.
- **`Maintenance_Plan__c`**:
  - `Calendar_Interval_Months__c` (Number(3, 0))
  - `SOP_Checklist__c` (LongTextArea(32768))
- **`Service_Ticket__c`**:
  - `Maintenance_Plan__c` (Lookup to `Maintenance_Plan__c`)
- **Permissions**: Full FLS updated on `FleetAdmin` and `FleetforceAdmin`.

### Phase 2: Apex Controller (`FleetDigitalGloveboxController.cls`)

- `getGloveboxData(Id assetId)`:
  - Aggregates `AssetSummary`, `ModelResources`, `List<ComplianceDoc>`, and `MaintenanceSummary`.
  - Performs intelligent model matching against `Vehicle_Model__mdt`.
  - Converts standard YouTube watch URLs (`watch?v=...`) into privacy-enhanced embed URLs (`https://www.youtube-nocookie.com/embed/...`).
  - Correlates attached Salesforce Files (`ContentDocumentLink` / `ContentVersion`) and online links.
- `createAssetDocument(...)`:
  - Quick action to add state registrations or insurance policies, computing expiration status (`Current`, `Expiring Soon`, `Expired`).

### Phase 3: LWC Development (`fleetDigitalGlovebox`)

- Built unified LWC with 4 tabs:
  1. **Compliance Documents:** Cards with document numbers, validity dates, status badges, download buttons, and online links.
  2. **Manufacturer Manuals:** One-click links to official OEM handbook and emergency roadside guide, plus EPA MPG / EV range specs.
  3. **Infotainment & Privacy:** Embedded YouTube walkthrough iframe with company privacy protocol warning banner.
  4. **Maintenance Schedules:** Applicable master maintenance plans with SOP checklist previews and recent service ticket execution table.
- Added "Add Document" modal dialog with validation and automatic `refreshApex` execution.

### Phase 4: Integration

- Added "Digital Glovebox" tab to `Fleet_Asset_Record_Page.flexipage-meta.xml`.
- Embedded `<c-fleet-digital-glovebox record-id={vehicle.id}></c-fleet-digital-glovebox>` into `driverApp` (`driverApp.html`) under the Vehicle tab for mobile LWR community drivers.

---

## 3. Verification & Test Results

- **Apex Unit Tests (`FleetDigitalGloveboxControllerTest.cls`):**
  - 6/6 tests passing (100% pass rate in 1.6s).
- **Display Settings Controller Test (`FleetDisplaySettingsControllerTest.cls`):**
  - 8/8 tests passing (100% pass rate in 1.3s).
- **Jest Unit Tests (`fleetDigitalGlovebox.test.js` & suite):**
  - 20/20 test suites passing (75/75 tests passing).
- **Scratch Org Deployment (`fleetforce-dev-13`):**
  - Clean deployment across custom metadata, custom fields, permission sets, Apex classes, LWCs, and flexipages.
