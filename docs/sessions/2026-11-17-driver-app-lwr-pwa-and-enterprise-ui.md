# Session Log — 2026-11-17: Dedicated Driver LWR Site, PWA, Enterprise Admin Mode & Mobile UX Polish

**Branch:** `feature/routing-module`  
**Target Org:** `fleetforce-dev-13` (`00DWm000002fyrtMAA`, `test-fubqn3lghmcn@example.com`)  
**Live Site URL:** `https://customization-power-6735-dev-ed.scratch.my.site.com/driver/`  
**Components:** `driverApp` (LWC), `fleetDigitalGlovebox` (LWC), `fleetGeneralSettings` (LWC), `DriverAppController.cls`, `FleetDisplaySettingsController.cls`, `Trip__c` (Custom Object & Metadata), `FleetForce_Driver1` (LWR Digital Experience Site), `fleetforce_driver_pwa` (Static Resource).

---

## 1. Summary of Changes

### A. Dedicated Driver LWR Site & Progressive Web App (PWA)

- Decoupled the driver experience from the Motorpool employee car-sharing portal into a dedicated LWR site: **FleetForce Driver** (`/driver`).
- Added PWA capabilities packaged as a Static Resource (`force-app/main/default/staticresources/fleetforce_driver_pwa/`):
  - `manifest.webmanifest` configuring full-screen standalone mobile app mode, theme colors (`#0f1e33`), and responsive app icons (`192x192`, `512x512`).
  - `sw.js` Service Worker implementing stale-while-revalidate offline caching for the Digital Glovebox, cached driver dashboard, and static assets.
  - In-app install banner with auto-detection for Chromium "Add to Home Screen" prompt and iOS Safari instructions.

### B. Viewport & Scroll Anchoring (Mobile & Responsive Fix)

- Resolved the mobile inspect dragging bug where swiping on Chrome inspect mode (iPhone 16 / Pixel 10) dragged the entire viewport up/down.
- Pinned `.app` with fixed edge-to-edge layout (`position: fixed !important; inset: 0 !important; width: 100vw; height: 100dvh; overflow: hidden; overscroll-behavior: none`).
- Assigned `touch-action: none; user-select: none;` to top header, admin bar, offline banner, and bottom navigation bar.
- Configured `.body` as the sole scrolling container with `flex: 1 1 auto; overflow-y: auto; overscroll-behavior-y: contain; touch-action: pan-y; -webkit-overflow-scrolling: touch`.

### C. Enterprise Admin Mode & Driver Resolution

- Replaced the hardcoded demo driver switcher with an enterprise-grade Admin Mode:
  - Governed by `Fleet_Display_Setting__c.Allow_Admin_Mode_In_Driver_App__c` (toggleable in `FleetForce_Admin.app` General Settings).
  - Gated by custom Permission Set: `FleetforceDriverAppAdmin`.
- Robust multi-path driver resolution in `DriverAppController.resolveCurrentDriver()`:
  1. `User.ContactId` (Community driver login).
  2. `Contact.Related_User__c == currentUserId` (Internal employee mapped to driver Contact).
  3. `Contact.Email == User.Email AND Contact_Type__c = 'Driver'` (Email identity matching).
  - Unlinked users without admin rights see a secure, branded "No Connected Driver Profile" card with zero data leakage.

### D. Navigation Drawer & Customizable Bottom Bar

- Replaced crowded 2-line bottom navigation with an industry-standard hamburger drawer and clean 4-slot bottom bar.
- Slide-out drawer provides one-tap navigation to Home, Vehicle, Trips & Mileage, Route, Service Issues, and Profile.
- Added bottom bar customizer allowing drivers to select which 4 shortcuts stay pinned on their bottom bar.

### E. Trip Logging & IRS-Compliant Mileage Tracking

- Created `Trip__c` custom object with master-detail/lookup to `Contact` (Driver) and `Fleet_Asset__c` (Vehicle).
- Added modal Trip Logger supporting Business vs. Private mileage categorization, business purpose, start/end odometers, route addresses, and notes.
- Added monthly mileage KPI card with business/private ratio bars.

### F. Multi-Vehicle Driver Experience & Digital Glovebox Enhancements

- Highlighted multi-vehicle drivers (e.g., Chloe Bennett, Carlos Gomez, Hannah Lindqvist, each assigned 4 active vehicles).
- Added multi-vehicle badge count in Admin Mode selector (e.g. `Chloe Bennett (4 vehicles)`).
- Added direct vehicle switcher dropdown on both Home and Vehicle screens displaying vehicle authorization roles (`[Primary]`, `[Occasional]`, `[Secondary]`).
- Moved Digital Glovebox and compliance documents to the top of the Vehicle tab above the map.
- Added direct "Glovebox" Quick Action tile on Home.
- Added in-app "View Certificate" modal to `fleetDigitalGlovebox` displaying official electronic vehicle documents (Registration, DOT Inspection, Issuing Authority, validity dates, verification seal) without broken standard record page navigation in LWR.

---

## 2. Test Verification

- **Apex Tests (`DriverAppControllerTest`, `FleetDisplaySettingsControllerTest`):**
  - 11/11 tests passed in `DriverAppControllerTest` (100% pass rate).
  - 8/8 tests passed in `FleetDisplaySettingsControllerTest` (100% pass rate).
- **Jest Unit Tests (`sfdx-lwc-jest`):**
  - 21/21 suites passed, 81/81 unit tests passed org-wide.
- **Org Deployment & Verification:**
  - Deployed cleanly to scratch org `fleetforce-dev-13`.
  - Published `FleetForce Driver` LWR site live.

---

## 3. Next Steps (Queued for Next Session)

- Contact Record Page (`Contact_Record_Page`):
  - Add Fleet related lists to Contact layout: Trips (`Trips__r`), Authorized Vehicles (`Authorized_Drivers__r`), Vehicle Allocations, Fuel Logs, Citations, and Service Tickets.
  - Design and build a dedicated "Driver 360" LWC for the Contact record page summarizing driver stats (safety score, total trips, lifetime/monthly mileage, compliance status, current assigned vehicle, and telematics behavior insights).
