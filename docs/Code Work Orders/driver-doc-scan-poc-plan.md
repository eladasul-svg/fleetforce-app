# Driver App Document Scan & Route Add — POC Plan

**Branch:** `feature/routing-module`  
**Target Scratch Org:** `fleetforce-dev-13` (`00DWm000002fyrtMAA`, `https://customization-power-6735-dev-ed.scratch.my.salesforce.com`, namespace `fleetforce`, expires `2026-12-03`)  
**Approach Selected:** **Option A** — Reuse existing `Claude_API` (Vision extraction) + `Openrouteservice` (geocoding & dev routing) Named Credentials, invoked from the Driver LWR app (`driverRoute`).

---

## 1. Prospect Demo Goal

From the Driver App (LWR Experience Cloud site):

1. Driver scans or uploads a delivery document (camera photo, gallery image, or PDF).
2. A multimodal Vision model decodes the document (including handwritten + printed Hebrew) and extracts destination, customer, contact, truck, cargo, and document identifiers.
3. The destination is geocoded to coordinates (`[lat, lon]`).
4. The driver previews/confirms the extracted stop details in a bottom sheet.
5. Apex saves the `Route_Job__c`, `Job_Visit__c`, and attached scan (`ContentVersion`), and inserts/re-optimizes the stop on the driver's active `Route__c`.
6. Both the Driver App (`driverRoute`) and the Dispatcher Board (`routePlanBoard`) reflect the new stop, updated ETAs, and road geometry.

---

## 2. Reference Prospect Sample Scan (2-Page PDF)

### Page 1 — Handwritten Bill of Lading (`שטר מטען להובלה בשכר במשאיות מס' 7998`)

- **Truck plate (`מספר הרכב`):** `28598703`
- **Date (`תאריך`):** `31.8.26` (Loading `31.8.26` → Unloading `1.9.26`)
- **Customer (`שם המזמין`):** `סלע מוצרי ביטון`
- **Origin (`מוצא`):** `אשקלון`
- **Destination (`יעד`):** `נצרת`
- **Carrier (`שם המוביל`):** `מטר`

### Page 2 — Printed Delivery Note (`תעודת משלוח מס' SH26011985 - טיוטה`)

- **Supplier:** `סלע אספקת מוצרי בטון ואנרגיה בע"מ` (`מחסן תוצ"ג אשקלון`)
- **Recipient (`לכבוד`):** `חוליות גפני בע"מ (נצרת שכונת הגליל)` · Customer `#6000423207`
- **Site (`אתר`):** `נצרת 1625800`
- **Contact (`לידי` / `איש קשר`):** `מחבר` · Tel `04-6338381` · Mobile `054-9230336`
- **Truck (`מס' משאית`):** `28598703` (`10 פול טריילר מאשקל`)
- **Line Item:** Order `SO26007097`, SKU `1403`, Product `גלית 30/30/6 אפור`, Qty `237.600 מ"ר` (22 packages × `10.800 מ"ר`)
- **Total Weight (`סה"כ משקל לתעודה`):** `32,076.00` kg

### Extraction Implications

- Cursive Hebrew handwriting + mixed RTL tables make traditional OCR brittle; **Claude Vision** (`callout:Claude_API/v1/messages`) handles both pages cleanly in one structured JSON response.
- Delivery notes often list a city/neighborhood/site code (`נצרת שכונת הגליל`, `אתר: נצרת 1625800`) rather than a street address, so **geocoding is mandatory**—`RoutePlanService` and `RouteReplanService` skip any `Job_Visit__c` missing `Location__Latitude__s` / `Location__Longitude__s`.

---

## 3. Existing Repo Assets & Credentials Used

- **UI:**
  - `force-app/main/default/lwc/driverApp/` (`shrinkImage()` canvas downscaling to 1280px JPEG, bottom sheet pattern `.sheet`)
  - `force-app/main/default/lwc/driverRoute/` (Route tab inside `driverApp`; backed by `DriverRouteController.cls`)
  - `force-app/main/default/lwc/routePlanBoard/` (listens to `Route_Plan_Update__e`)
- **Named / External Credentials (already in metadata):**
  - `Claude_API` → `https://api.anthropic.com` (`Org` principal `x-api-key`)
  - `Openrouteservice` → `https://api.openrouteservice.org` (`Org` principal `Authorization`) — supports both `/geocode/search` and `/optimization`
  - `FleetForce_Routing` → Cloud Run routing service (`services/routing/`)
- **Routing Apex & Data Model:**
  - `Route_Job__c`, `Job_Visit__c`, `Route_Plan__c`, `Route__c`, `Waypoint__c`, `Route_Event__c`
  - `RouteReplanService.cls` (`buildRequest` supports `addVisitIds` to insert a new `Job_Visit__c` into an active `Route__c`, and `apply` updates waypoints + geometry)
  - `RoutingProviders.cls` / `OrsRoutingProvider.cls` / `FleetForceRoutingProvider.cls` / `MockRoutingProvider.cls`
- **Guest Site Profile:**
  - `unpackaged/main/default/profiles/FleetForce Motorpool Profile.profile-meta.xml`

---

## 4. Data Model Mapping

| Extracted Document Data        | FleetForce Object | Field(s)                                          | Notes                                                                                                                         |
| :----------------------------- | :---------------- | :------------------------------------------------ | :---------------------------------------------------------------------------------------------------------------------------- |
| Delivery note / BOL type       | `Route_Job__c`    | `Type__c`                                         | `'Delivery'` (or `'Pickup and Delivery'` if origin is included)                                                               |
| Doc status                     | `Route_Job__c`    | `Status__c`                                       | `'Ready'` → `'Planned'` on apply                                                                                              |
| Service date                   | `Route_Job__c`    | `Service_Date__c`                                 | `Date.today()` for live demo route (or parsed date)                                                                           |
| Depot branch                   | `Route_Job__c`    | `Branch__c`                                       | Inherited from active `Route__c.Route_Plan__r.Depot_Branch__c`                                                                |
| Doc # (`SH26011985` / `7998`)  | `Route_Job__c`    | `External_Id__c`                                  | Unique external ID (dedupe/upsert friendly)                                                                                   |
| Active route                   | `Route_Job__c`    | `Planned_Route__c`                                | Driver's current `Route__c`                                                                                                   |
| Customer, order, cargo summary | `Route_Job__c`    | `Notes__c`                                        | e.g., `חוליות גפני בע"מ · Order SO26007097 · גלית 30/30/6 אפור (237.6 מ"ר)`                                                   |
| Visit role                     | `Job_Visit__c`    | `Role__c`                                         | `'Delivery'`                                                                                                                  |
| Destination / site             | `Job_Visit__c`    | `Address__c`                                      | e.g., `נצרת שכונת הגליל (אתר 1625800)`                                                                                        |
| Geocoded coordinates           | `Job_Visit__c`    | `Location__Latitude__s`, `Location__Longitude__s` | Required by solver (`RouteReplanService` skips visits without coords)                                                         |
| Weight (kg)                    | `Job_Visit__c`    | `Load_1__c`                                       | Optional / editable in confirmation UI so demo van capacity (`Payload_Kg__c`, e.g. 900 kg) doesn't reject a 32-ton truck load |
| Contact & doc ref              | `Job_Visit__c`    | `Access_Notes__c`                                 | e.g., `לידי מחבר · 054-9230336 · תעודה SH26011985`                                                                            |
| Scanned image / PDF            | `ContentVersion`  | `FirstPublishLocationId`, `VersionData`           | Linked to the created `Route_Job__c`                                                                                          |

---

## 5. Implementation Architecture & Key Gotchas

### Multi-Step LWC → Apex Flow (Callout-Before-DML Safe)

Salesforce forbids HTTP callouts after uncommitted DML in the same transaction. Split the UI flow into three clean Apex calls:

1. **`scanDocument(base64Data, mimeType, fileName)`** _(callout only)_
   - Calls `callout:Claude_API/v1/messages` (Claude Vision with `image` or `document` content block) requesting strict JSON extraction.
   - Calls `callout:Openrouteservice/geocode/search?text=...&boundary.country=IL&size=1` to resolve `[lat, lon]` (with city-level fallback if the full neighborhood/site string returns no hits).
   - Returns DTO to `driverRoute` LWC for driver review/edit.
2. **`createScannedJob(routeId, driverId, payloadJson, base64Data, mimeType, fileName)`** _(DML only)_
   - Inserts `Route_Job__c`, `Job_Visit__c`, and `ContentVersion` (scan attached to `Route_Job__c`).
   - Returns `{ jobId, visitId }`.
3. **`addVisitToRoute(routeId, visitId)`** _(callout first, then DML)_
   - Calls `RouteReplanService.buildRequest(routeId, null, 0, new Set<Id>{ visitId }, null)` → `RoutingProviders.forName(provider).optimize(...)` → `RouteReplanService.apply(...)`.
   - Logs `Route_Event__c` (`Stop Added` / `Reoptimized`) and publishes `Route_Plan_Update__e`.

### Critical Constraints to Handle

1. **Guest User / `USER_MODE`:** `driverApp` and `driverRoute` currently run on the Motorpool guest site (`DriverAppController` and `DriverRouteController` use `without sharing`), whereas `RouteReplanService`, `AssistantClaudeClient`, and `RoutingProviders` use `with sharing` / `WITH USER_MODE`. For the guest-site demo:
   - Grant `FleetForce Motorpool Profile` access to the new Apex controller class in `unpackaged/main/default/profiles/FleetForce Motorpool Profile.profile-meta.xml`.
   - Handle Named Credential / system-mode execution cleanly for the demo scan & route-update wrapper (or note whether the demo runs as an authenticated driver/admin user vs guest).
2. **ORS `lockedIds` restriction:** `OrsRoutingProvider` throws if `options.fixed` (`lockedIds`) is non-empty. Pass `lockedIds = null` when re-optimizing on `Openrouteservice` or `Mock`.
3. **Vehicle Payload Capacity:** The prospect's scan is a 32-ton full trailer (`32,076` kg), while Beer Sheva demo vans have `Payload_Kg__c = 700` or `900`. In the driver confirmation sheet, display extracted weight (`32,076 kg`) and allow adjusting/omitting capacity load (or seeding a heavy truck `28598703`) so the solver doesn't mark the stop `Unassigned (capacity)`.
4. **No cacheable callouts:** Never annotate `scanDocument` or `addVisitToRoute` with `@AuraEnabled(cacheable=true)`.

---

## 6. Build & Verification Checklist

- [x] Verify `fleetforce-dev-13` state (`Claude_API` key, `Openrouteservice` key, Motorpool site active, seeded route for today).
- [x] Add `DriverRouteScanService.cls` + `DriverRouteScanController.cls` + Apex tests (`HttpCalloutMock`, targeting 90%+ coverage).
- [x] Update `driverRoute` LWC (`driverRoute.html`, `driverRoute.js`, `driverRoute.css`) with **"Scan delivery note"** button, file/camera/PDF input, extraction progress state, and editable confirmation bottom sheet + Jest tests.
- [x] Update `unpackaged/main/default/profiles/FleetForce Motorpool Profile.profile-meta.xml` with class access for the new controller (+ `FleetforceDriverScanGuest` permission set assigned to `FleetForce Motorpool Site Guest User` for `Claude_API-Org` and `Openrouteservice-Org` External Credential access).
- [x] Deploy to `fleetforce-dev-13`, publish `FleetForce Motorpool` LWR site, run Apex tests + Jest tests, and verify end-to-end (live Apex + browser UI on `/motorpool/driver`).

---

## 7. Kickoff Prompt for the New Chat

Open `/Users/elad.asulin/fleetforce-app` (with the non-existent `/Users/elad.asulin/Documents/FleetForce` folder removed from the workspace), start a new chat, and paste:

```markdown
Read docs/Code Work Orders/driver-doc-scan-poc-plan.md and continue implementing the Driver App Document Scan POC (Option A) on branch feature/routing-module against scratch org fleetforce-dev-13. First verify git status and fleetforce-dev-13 org/credential state, then build and test the Apex + LWC changes and deploy to fleetforce-dev-13.
```
