# Digital Glovebox v2: Multi-Tier PM Master Programs, Milestone Roadmaps & Unified Vehicle Documents

**Date:** 2026-11-15  
**Target Org:** `fleetforce-dev-13` (`00DWm000002fyrtMAA`, `test-fubqn3lghmcn@example.com`)  
**Git Branch:** `feature/routing-module`

---

## 1. Architectural Motivation & User Feedback

Following the delivery of the initial Digital Glovebox and Preventive Maintenance foundation, executive feedback requested four critical enhancements:

1. **Compliance Documents Record Navigation:** Add a direct "View Asset Document" button to each compliance document card to navigate to `/lightning/r/fleetforce__Asset_Document__c/{doc.id}/view`.
2. **Preventive Maintenance Master Programs with Milestone Line Items:** Instead of representing a vehicle's multi-year maintenance schedule as a single flat record, introduce a parent-child master program model (`Maintenance_Plan__c` $\rightarrow$ `Maintenance_Plan_Line_Item__c`). A 3-year commercial schedule (e.g. Ford F-150 Commercial 3-Year / 36,000-Mi Program) holds discrete milestone line items (e.g. 5,000 mi, 10,000 mi, 20,000 mi, 30,000 mi) detailing specific serviced components, estimated labor hours, and costs.
3. **Vehicle-Level Plan Overrides:** Enable fleet managers to inspect the active program, override it per vehicle (e.g. assigning a severe-duty schedule), and link each service work order (`Service_Ticket__c`) directly to the specific milestone line item that triggered it.
4. **Next Scheduled PM Milestone Card:** Dynamically compute and surface the next upcoming service milestone, highlighting remaining miles/days, target odometer, and overdue status.
5. **Unified Vehicle Documents Repository Tab:** Introduce a dedicated two-part document repository:
   - **Part A (System-Linked Record Documents):** Automatically aggregates files attached across related Citations (`Citation__c`), Insurance Links (`Asset_Insurance_Link__c`), and Service Tickets (`Service_Ticket__c`) via `ContentDocumentLink`.
   - **Part B (Direct Vehicle Files):** Manages direct files attached to the vehicle asset (`Fleet_Asset__c`) with native drag-and-drop file upload (`lightning-file-upload`).

---

## 2. Data Model Implementation

1. **`Maintenance_Plan_Line_Item__c` Custom Object:**
   - Master-Detail relationship to `Maintenance_Plan__c` (`fleetforce__Maintenance_Plan__c`).
   - Fields:
     - `Milestone_Mileage__c` (Number 18, 0): Odometer threshold (e.g. 5000, 10000, 20000, 30000).
     - `Milestone_Months__c` (Number 18, 0): Calendar month interval.
     - `Sequence__c` (Number 4, 0): Order of service visit in program.
     - `Service_Category__c` (Picklist): Service tier (e.g. A-Service, B-Service, Major Driveline, Inspection).
     - `Components_Serviced__c` (Text 255): Concise comma-separated component list.
     - `Estimated_Cost__c` (Currency 18, 2): Projected milestone parts and consumables cost.
     - `Estimated_Hours__c` (Number 5, 2): Standard labor hours.
     - `SOP_Checklist__c` (Long Text 32768): Step-by-step SOP checklist for technicians.
2. **`Fleet_Asset__c.Assigned_Maintenance_Plan__c` (Lookup to `Maintenance_Plan__c`):**
   - Allows vehicle-specific plan override without altering the model default.
3. **`Service_Ticket__c.Maintenance_Plan_Line_Item__c` (Lookup to `Maintenance_Plan_Line_Item__c`):**
   - Provides explicit audit traceability between a work order and the exact scheduled maintenance milestone.
4. **Permissions:**
   - Updated `FleetAdmin.permissionset-meta.xml` and `FleetforceAdmin.permissionset-meta.xml` with full CRUD, FLS, and object permissions.

---

## 3. Apex Controller & Data Seeding

- **`FleetDigitalGloveboxController.cls` Updates:**
  - Resolved active maintenance plan: checks `Fleet_Asset__c.Assigned_Maintenance_Plan__c` first; falls back to matching `Maintenance_Plan__c` by `Asset_Type__c`.
  - Queried child `Maintenance_Plan_Line_Item__c` records ordered by sequence and mileage.
  - Calculated `nextMilestone`: identified the first uncompleted milestone due after the current odometer; computed remaining miles, remaining days, and status badges (`OVERDUE` error, warning, info).
  - Added `@AuraEnabled public static void assignMaintenancePlan(Id assetId, Id planId)` to save vehicle overrides.
  - Queried `systemLinkedDocuments` across citations, insurance links, and service tickets via `ContentDocumentLink`.
  - Queried `directAssetDocuments` on the vehicle asset.
- **Data Seeding in `fleetforce-dev-13`:**
  - Seeded master program: _Ford F-150 Commercial 3-Year / 36,000-Mi Program_ (`a0RWm000001rrcBMAQ`) with 4 milestones (5k, 10k, 20k, 30k mi).
  - Assigned plan to `2023 Ford F-150 · EG17 JLB` (`a0JWm000000HcNyMAK`).
  - Attached test files to Citation `CIT-LON-2026-981`, Service Ticket `ST-0051`, and Direct Asset.

---

## 4. UI Implementation (`fleetDigitalGlovebox` LWC)

1. **Compliance Documents Tab:**
   - Added "View Asset Document" button with record page navigation.
2. **Vehicle Documents Tab:**
   - Part A: System-Linked documents with source entity badges (Citation, Insurance, Service Ticket), formatted size, and deep links to view source record and download file.
   - Part B: Direct Vehicle Files with file list and inline `lightning-file-upload`.
3. **Maintenance Schedules Tab:**
   - Active Program Banner displaying program name, asset type, and cadence, with "View Program Record" button and "Change Program" button.
   - Change Program Modal: combobox displaying available enterprise programs with save action calling `assignMaintenancePlan`.
   - Next Scheduled PM Milestone Card: displays milestone title, target odometer, remaining miles, service category, serviced components, and estimated cost/labor.
   - Milestone Roadmap: sequenced lifecycle cards with milestone badges, components, and est. costs.

---

## 5. Verification & Test Results

- **Apex Unit Tests (`FleetDigitalGloveboxControllerTest`):** 8/8 tests passed (100% pass rate in 1.9s, Test Run ID `707Wm00000G4Z0X`).
- **Jest Unit Tests (`fleetDigitalGlovebox.test.js`):** 20/20 test suites passed (78/78 tests passed, 0 failures).
- **In-Org End-to-End SOQL Check:** Confirmed `2023 Ford F-150 · EG17 JLB` returns 2 compliance docs, 2 system-linked docs, 1 direct asset doc, active plan _Ford F-150 Commercial 3-Year / 36,000-Mi Program_, next milestone _30,000-Mile Major Transmission & Driveline Service_, and 4 roadmap line items.
