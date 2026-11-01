# FleetForce Platform release notes

What each released version of the "FleetForce Platform" package (`0Hohd00000000HlCAI`) contains and what changed,
newest first. One section per **released** version; Beta builds that were never released are only listed under the
version they led to.

How to keep it:

- While working, add each change that will ship to **Next version** below, in plain language (what a fleet manager
  or admin notices, not class names).
- When a version is built, set `versionDescription` in `sfdx-project.json` to a one-line summary of that version.
- When it is promoted to Released, turn **Next version** into a dated section with its install ID, and start a new
  empty **Next version**. Part of `package-release-checklist.md`.

Each section has: **What's new**, **Changes and fixes**, **Upgrade notes** (anything an org that already has an
earlier version must do before or after installing), and **After installing** (the per-org steps).

---

## Next version (not built yet)

Will be 1.2.0, or 1.1.1 if it only holds small fixes. 1.1.0 is released, so no further 1.1.0 builds are possible.

### What's new

- **Driver card** on the vehicle page, under the vehicle card: the assigned driver's photo (from their Related User)
  or initials in a circle, status, branch, phone and email (click to call or write), license number, class and
  expiry (amber within 60 days, red once expired), safety score, and a warning for expired or expiring
  qualifications. It only appears when the vehicle has a driver, and follows a change of driver without a reload.

### Changes and fixes

- Vehicle page: the Data Health component moved from the main column to its own tab, "Data Exposure", so the page
  is shorter. The Assistant stays in the side column.
- Vehicle page layout: Make, Model and Model Year moved from the Data Health section to Identity, under VIN.
- The FleetForce Assistant tells a user without the FleetForce Assistant User permission set to ask an administrator
  for it, instead of showing the error "No such column 'Title__c'".

### Upgrade notes

- An org on **1.0.x** still needs the 1.1.0 upgrade note below (the three fields) before this version installs.

---

## 1.1.0.4 — regional settings and data trust

Released 2026-11-01. Install ID `04thd000000135VAAQ`. Built from `main` at `9cda9b4`. 153 Apex tests, 94% coverage.
Builds 1.1.0.1 to 1.1.0.3 were test builds that failed a clean install and were never released.

### What's new

- **Regional settings.** Branches have a country, time zone, currency and units (distance, volume, weight). Picking a
  branch's country fills the rest from a **Country Profile** (Portugal, United Kingdom, Israel, United States and
  others). An org-wide default country, time zone, currency and units, set on the **Regional settings** screen in
  FleetForce Settings, which also lists the Country Profiles and shows whether multi-currency is on.
- **Vehicles inherit from their branch.** A vehicle shows its branch's country, time zone, currency and units unless
  it has its own value. Vehicles can be registered in one country and operate from a branch in another.
- **When a vehicle moves to a branch with other units**, it keeps its old distance unit so its odometer history stays
  correct (design partner question D-001 in `design-partner-decisions.csv`).
- **Units everywhere.** Vehicle summary, map, driver app and fuel logs show km or miles, litres or gallons (US or UK),
  and fuel economy in the country's format (MPG, MPG (UK), L/100 km, km/L; for EVs MPGe, mi/kWh, kWh/100 km).
- **Times in the branch's time zone.** The booking portal has a pick-up location and shows and books times in that
  branch's time zone; the driver app and map show local times.
- **Data trust layer.** Data sources and streams, a health score per vehicle (freshness, completeness, consistency),
  matching of recalls and regulations to vehicles, and alerts. Screens: **Fleet Exposure** and the vehicle's **Data
  Health** card. Permission set `FleetforceDataTrust`.
- **Regulatory Category** on vehicles and on regulatory notices: a notice for a category only matches vehicles of
  that category in that country.
- **`FleetForceSetup`**, a global class the setup scripts call to seed and reset the Data Trust sample data and to
  schedule the nightly data health job (`fleetforce.FleetForceSetup.seedDataTrustSample()` and so on).
- New core vehicle fields: Make, Model, Model Year, Country.

### Changes and fixes

- Branch Country and Time Zone, Schedule Time Zone, and Insurance Policy and Driver Qualification Status now use
  shared value lists (global value sets).
- Fuel logs accept "Gallons (UK)"; electric charging from the driver app now saves.
- The guest Motorpool portal stores pick-up and return times as the guest meant them (they were stored as if the
  guest were on UTC).
- The Account page layout is no longer in the package: a package must not overwrite a customer's Account layout. Our
  version (with the vendor Login URL) is in `unpackaged/`. The Login URL field itself is still in the package.
- Tests no longer depend on the permission sets of the user who runs them.

### Upgrade notes

- **From 1.0.0.8 the install is refused** because three fields changed to a shared value list, which Salesforce does
  not allow on an existing field: Branch Country, Branch Time Zone, Schedule Time Zone. Before installing:
  - if those fields are empty in the org (no branches or schedules), delete the three fields there, then install;
  - if they hold data, use `scripts/migration/migrate_regional.sh`, which backs up, drops, and restores the values.
- Existing branches get no country or units until one is set; set the org default on the Regional settings screen
  first.

### After installing

- Assign the permission sets `FleetAdmin`, `FleetforceAdmin`, `FleetforceDataTrust`, `FleetforceAssistantUser`.
- Optional demo data: `scripts/load_demo_data.sh <alias>` (four branches in Lisbon, London, Tel Aviv and Chicago, plus
  the Data Trust sample).
- The manual steps in `manual-setup-steps.md`: theme and Home page activation, the guest site.

---

## 1.0.0.8 — first release

Released 2026-09-27. Install ID `04thd0000000rsLAAQ`. 74 Apex tests, 93% coverage. Builds 1.0.0.1 to 1.0.0.7 were
Beta builds; 1.0.0.7 was built without the coverage check by mistake.

### What's new

- The **FleetOps** app: vehicles (Fleet Asset) and their components and documents, branches, schedules, reservations
  and availability, fuel logs and fuel cards, service tickets and maintenance plans, insurance, authorised drivers
  and their qualifications, citations, telematics (Geotab) and carbon logs, vendor agreements and rate cards, with
  layouts and the FleetForce theme.
- **Home dashboard**, vehicle map and vehicle summary components.
- **Motorpool guest portal**: a public page where a guest requests a vehicle; the request arrives as a Pending
  reservation.
- **FleetForce Assistant** on the Home page (shows a connection setup card until an API key is configured).
- Permission sets `FleetAdmin`, `FleetforceAdmin`, `FleetforceAssistantUser`.

### After installing

- Theme and Home page activation (UI only), and the guest site with access to `MotorpoolPortalController`: see
  `manual-setup-steps.md`.
