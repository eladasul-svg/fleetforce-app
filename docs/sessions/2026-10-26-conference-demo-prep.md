# Session: Conference demo prep (dev-11)
**Date:** 2026-10-26 / 2026-10-27
**Org:** `fleetforce-dev-11` (scratch, expires 2026-11-20). Goal: a running demo for the conference on 27-28 Oct.

## Delivered (all committed to main; latest `d7c5793`)
- **Seeding:** dev-11 spun up and seeded. Re-runnable scripts in `scripts/apex/`: `seed_tasks`, `seed_events` (today..+7, always covers the 27/28), `seed_lisbon_locations`, `seed_motorpool_bookings`, `seed_driver_app`.
- **Home page:** cleaned up; Today's Tasks / Today's Events now populated; maintenance alerts have priority/issue and wrapped text; KPI tabs.
- **Vehicle visuals:** silhouettes + icon styles (Classic/Modern/Futuristic/Flat) driven by `Fleet_Display_Setting__c` (org-wide) and `Vehicle_Model__mdt` (34 records, EPA MPG). Components: `fleetVehicleImage`, `fleetVehicleStyles`, `fleetSettings`, `fleetVehicleSummary`.
- **Fleet Map Explorer:** Lisbon-centred, list synced to the map, large-map page.
- **Booking portal:** LWR Experience Cloud site (`unpackaged/`), Waypoint brand + favicon, date-only picker with optional times. See `docs/motorpool-portal.md`.
- **Live tracker:** `fleetMapTracker` is a "right now" board with a client-side demo simulation (`fleetDemoRoutes`, OSRM routes), car-shaped heading-aware markers, double-buffered cross-fade instead of pin-drop.
- **Driver app:** mobile-first at `/driver` on the same site (`driverApp`, `DriverAppController`): trips, pre-trip check, etc. Demo driver picker, no login, no push (deliberate).
- **Branding:** new `Fleetforce_Waypoint_Logo` content asset; Fleet Ops and FleetForce Admin use it with Ink `#0F1E33` and `shouldOverrideOrgTheme=true` (the org theme was showing the Salesforce cloud).
- **App Launcher:** trimmed to Fleet Ops + FleetForce Admin via `scripts/hide_standard_apps.sh <org>` (deploys only app visibility; see lessons).
- Walkthrough MP4 produced (posted to LinkedIn by the user).

## Lessons / gotchas
- Standard apps in profile `applicationVisibilities` need the `standard__` prefix (`standard__Service`); `Force_com` is bare. The full `unpackaged` Admin profile does NOT deploy standalone (references missing `Contact-Driver Layout`), so the launcher trim uses a minimal metadata-dir package in `scripts/launcher/`.
- `scripts/deploy.sh` is still broken (circular deps); use `sf project deploy start --source-dir force-app`.
- Guest users: simple Apex params only, cannot own records, need class access in the guest profile.
- lightning-map: 16:9 of width, ignores height; markers are replaced (drop animation) on every update.
- LWR: routes need `__c`, viewType must match routeType, `styles.css` not redeployable (headMarkup used), publish with `sf community publish`.
- `sf org display user` redacts the password; use `sf org auth show-user-password`. Salesforce mobile app intercepts Chrome login links on a tablet.

## Not done / open
- `docs/media/` (demo MP4 + poster) left untracked on purpose (large binary).
- Package version not created ("can wait"); real telemetry switch; push notifications / login for the driver app; branches are still US cities while vehicles are in Lisbon; `FleetforceAssistantUser` not assigned by setup scripts; Fleetforce theme activation and Home page activation are manual UI.
