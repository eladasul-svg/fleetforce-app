# Session: Driver App Document Scan POC (Option A)

**Date:** 2026-11-10  
**Org:** `fleetforce-dev-13` (`00DWm000002fyrtMAA`, namespace `fleetforce`, expires `2026-12-03`)  
**Branch:** `feature/routing-module`  
**Work Order:** `docs/Code Work Orders/driver-doc-scan-poc-plan.md`

## Delivered

- **Apex (`force-app/main/default/classes/`):**
  - `DriverRouteScanService.cls` (`without sharing`):
    - `scanDocument(base64Data, mimeType, fileName)` — calls `AssistantClaudeClient.send(...)` (`claude-opus-5`) with an `image` or `document` (`application/pdf`) content block, extracts structured JSON (skipping `thinking` blocks), and geocodes via `Openrouteservice/geocode/search?boundary.country=IL&size=1` with parenthetical stripping and city-level fallback.
    - `geocodeAddress(address, city)` — re-geocodes driver-edited destinations from the confirmation bottom sheet.
    - `createScannedJob(...)` — inserts `Route_Job__c` (deduping `External_Id__c` on repeat scans), `Job_Visit__c`, and attached `ContentVersion` in a DML-only transaction.
    - `addVisitToRoute(routeId, visitId)` — callout-before-DML route re-optimization (`RouteReplanService` in `USER_MODE` for authenticated users, system-mode path using `RoutePlanService` public helpers for the Motorpool guest user), logs `Stop Added` + `Reoptimized` `Route_Event__c` records, and publishes `Route_Plan_Update__e`.
  - `DriverRouteScanController.cls`: non-cacheable `@AuraEnabled` facade taking primitive/JSON parameters for guest-site compatibility.
  - `DriverRouteController.cls`: added `vehiclePayloadKg` to `DriverRoute` and `address` to `Stop`.
  - `DriverRouteScanControllerTest.cls`: `HttpCalloutMock` coverage for PDF/image Vision scans, city fallback geocoding, validation/error paths, `USER_MODE` replan, and system-mode fallback + unassigned capacity handling.
- **LWC (`force-app/main/default/lwc/driverRoute/`):**
  - Updated `driverRoute.html`, `driverRoute.js`, `driverRoute.css`, and `driverRoute.test.js`: **"Scan delivery note"** picker (canvas 1280px JPEG resize for photos, up to 3.5 MB PDFs), extraction progress state, editable confirmation bottom sheet with **Locate address** re-geocoding, automatic vehicle-capacity check (omits `loadKg` by default when extracted weight exceeds `vehiclePayloadKg`), and stop address display.
- **Guest & Callout Access:**
  - Updated `unpackaged/main/default/profiles/FleetForce Motorpool Profile.profile-meta.xml` with `DriverRouteScanController`.
  - Added `force-app/main/default/permissionsets/FleetforceDriverScanGuest.permissionset-meta.xml` (`DriverRouteController`, `DriverRouteScanController`, `fleetforce__Claude_API-Org`, `fleetforce__Openrouteservice-Org`, no object delete permissions) and assigned it to `FleetForce Motorpool Site Guest User`.
- **Org State & Live Site:**
  - Re-seeded today's demo data (`scripts/apex/seed_routing_demo.apex`) and optimized `Beer Sheva South · morning` (`BSS-01 · Tal Mizrahi`, `BSS-02 · Eden Biton`, `BSS-04 (EV) · Adi Sasson`).
  - Published `FleetForce Motorpool` LWR site (`https://customization-power-6735-dev-ed.scratch.my.site.com/motorpool/driver`) and confirmed live in the browser by the user.

## Gotchas & Design Decisions

- **Guest User `USER_MODE` vs `Delete`:** Salesforce Guest User licenses cannot hold `Delete` on custom objects, so `RouteReplanService` (`WITH USER_MODE` / `AccessLevel.USER_MODE`) fails when invoked by `FleetForce Motorpool Site Guest User`. `DriverRouteScanService` delegates to `RouteReplanService` when `Waypoint__c.isDeletable()` (authenticated users) and uses a system-mode path built on `RoutePlanService` helpers otherwise.
- **External Credential access on Guest:** `Profile` metadata rejects `<externalCredentialPrincipalAccesses>`; a minimal Permission Set (`FleetforceDriverScanGuest`) with only `classAccesses` + `externalCredentialPrincipalAccesses` deploys cleanly and assigns to the Guest User without license errors.
- **Claude Vision `thinking` blocks:** `claude-opus-5` may return a `thinking` content block before `text`; `extractTextContent` scans for `type == 'text'` with `max_tokens = 2048` and strips optional markdown code fences.
- **Hebrew Pelias geocoding & ORS replanning:** Live ORS `/geocode/search` returned 0 hits on `"נצרת שכונת הגליל (אתר 1625800)"` and `"נצרת שכונת הגליל"`, and matched `"נצרת"`, confirming the need for city-level fallback. `ctx.request.fixed` is cleared for `Openrouteservice`/`Mock`, and `Shift_End__c` fallback is extended to `+12h` when the shift end has already passed.
- **LWR bundle cache:** Deploying LWC changes alone leaves the previous `driver_view` bundle cached on `/motorpool/driver`; `sf community publish --name "FleetForce Motorpool"` is required for the updated UI to appear.

## Verification

- `npx eslint "force-app/main/default/lwc/driverRoute/**/*.js"` — 0 errors.
- `npm run test:unit` — 14 suites / 60 tests passed.
- `sf apex run test` (`DriverRouteScanControllerTest`, `DriverRouteControllerTest`, `RouteReplanServiceTest`, `RoutePlanServiceTest`, `RoutingProvidersTest`, `OrsRoutingProviderTest`) — 37/37 passed (`DriverRouteScanService` 88%, `DriverRouteScanController` 76%, `DriverRouteController` 97%).
- Live E2E test against `Claude_API` + `Openrouteservice` on `fleetforce-dev-13` + browser test on `/motorpool/driver` by the user.
