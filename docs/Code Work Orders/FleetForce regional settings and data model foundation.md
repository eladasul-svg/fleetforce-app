# FleetForce regional settings and data model foundation

Oct 31, 2026 · @Elad Asulin · DRAFT for review before it goes to Code

Spec for Code. Source: the data model audit of 31 Oct 2026 (findings 1, 2, 3, 5, 8) and the design agreed the same day: **branch holds the regional settings, the vehicle inherits them, and a few fields on the vehicle can override.** Goal: a base-level demo for a multi-country fleet (target prospect: about 10K vehicles across several countries), and a model that is safe to put into the first managed package.

Work in a fresh scratch org (30 days). Source deploy is not package install: finish by installing the result into a clean org as a package, as in the 1.0.0.8 process.

## Governing rule

**Most specific wins; blank means inherit.** Order: vehicle, then branch, then org default (`Fleet_Display_Setting__c`). There are no inherit/override toggles anywhere. An empty field uses the level above. Registration country is a legal fact that drives regulations and defaults to the branch country; units, currency and time zone follow the branch (operating location). Who may edit branch settings is controlled by standard permissions, not by a custom setting. A per-user display preference is P1.

## Design in one paragraph

Each **Fleet Branch** has Country, Time Zone, Currency, Distance Unit, Volume Unit and Weight Unit. When an admin picks a Country on a branch, the other fields are pre-filled from a **Country Profile** (custom metadata) and can be changed. A **Fleet Asset** inherits all of these from its branch through formula fields (the "Effective ..." fields), so moving a vehicle to another branch changes them with no code. On the vehicle, only these can be overridden: Registration Country (the existing `Country__c`, now explicitly "registered in") and Distance Unit. Org-wide defaults and the admin screen live in `Fleet_Display_Setting__c` and the `fleetSettings` component.

## P0 changes (must land before the first managed version)

### 1. Country, time zone, currency on branch

- New global value set `Country_ISO`: ISO 3166-1 alpha-2 API values, English labels, extensible, not restricted.
- `Fleet_Branch__c.Country__c`: replace the 5-value picklist with `Country_ISO`. Migrate existing values (United States to US, Canada to CA, Mexico to MX, United Kingdom to GB, Other to blank).
- `Fleet_Branch__c.Time_Zone__c`: replace the US zones with IANA names (`Europe/Lisbon`, `Asia/Jerusalem`, `Europe/London`, `America/New_York`, and so on). Map old values (Eastern to America/New_York, Central to America/Chicago, Mountain to America/Denver, Pacific to America/Los_Angeles, Alaska to America/Anchorage, Hawaii to Pacific/Honolulu). Check every use, including `Fleet_Schedule__c.Time_Zone__c`, layouts, list views, permission sets and the booking portal.
- New on branch: `Currency_Code__c` (picklist, ISO 4217 value set `Currency_ISO`, extensible), `Distance_Unit__c` (km, mi), `Volume_Unit__c` (L, gal US, gal UK), `Weight_Unit__c` (kg, lb). Weight and volume apply to gross weight, fuel capacity and fuel logs.
- `US_State__c`, `Zip_Code__c`, `County_Province__c`: keep, mark optional, relabel the generic ones (Region / State, Postal code). Do not delete.

### 2. Country Profile (custom metadata)

- `Country_Profile__mdt`: ISO Code (text 2, unique by DeveloperName), Country Name, Default Currency, Default Time Zone, Distance Unit, Volume Unit, Weight Unit, Fuel Economy Format (MPG US, MPG UK, L/100km), Regulatory Regime (EU, US, UK, IL, Other).
- Ship records for PT, IL, GB, US, DE, FR, ES, NL, CA, MX, with correct units (GB: miles for distance, litres for fuel; US: miles and US gallons; the rest metric).
- A before-save flow (or LWC on the branch form) pre-fills the branch fields from the profile when Country changes and the field is blank. Never overwrite a value the user set.

### 3. Inheritance on the vehicle

- `Fleet_Asset__c.Country__c` becomes a picklist on `Country_ISO` (unrestricted, so CSV import of unknown codes still loads and is flagged by Data Trust). Help text: "Country where the vehicle is registered."
- New override: `Distance_Unit_Override__c`.
- New formula fields (all text): `Effective_Registration_Country__c` (vehicle Country if set, else branch Country), `Operating_Country__c` (branch Country), `Effective_Time_Zone__c`, `Effective_Currency__c`, `Effective_Distance_Unit__c` (override, else branch, else org default), `Effective_Volume_Unit__c`, `Effective_Weight_Unit__c`.
- New formula `Odometer_Km__c` (number): Odometer converted to kilometres using `Effective_Distance_Unit__c`. All cross-fleet reports and KPIs that total distance must use it. Stored odometer values stay as entered in the vehicle's unit.
- Add `Odometer Unit` display next to Odometer on the record page and list views using `Effective_Distance_Unit__c`.

### 4. Org defaults and the admin screen

- Extend `Fleet_Display_Setting__c` (org defaults): Default Distance, Volume, Weight units, Default Country, Default Time Zone for new branches.
- Extend the `fleetSettings` LWC with a **Regional settings** section: org default units and country; a read-only status line showing whether multi-currency is enabled (`UserInfo.isMultiCurrencyOrganization()`) with a link to Setup > Company Settings > Manage Currencies and one sentence of guidance; a read-only table of Country Profiles. Respect the FLS and `isUpdateable` checks used by the existing `FleetDisplaySettingsController`.
- Customer overrides of country profile defaults are P1. For P0 the admin changes values on the branch itself.

### 5. Units in the UI and catalog

- Show vehicle distance, fuel economy and weights in the vehicle's effective units. Convert for display only; stored values keep the unit they were entered in, so no data is rewritten.
- `Vehicle_Model__mdt` stores EPA MPG. Add a display conversion to L/100km and km/L when the effective regime asks for it, and label MPGe correctly. Do not add WLTP data in P0.
- Booking portal and driver app: use the branch time zone for pickup and return times, and show it ("Lisbon time"). Test a guest in a different time zone.

### 6. Regulatory Category

- New global value set `Regulatory_Category` on `Fleet_Asset__c.Regulatory_Category__c`: EU M1, M2, M3, N1, N2, N3, L; US weight classes 1 to 8; Other. Extensible.
- Data Trust: `NoticeMatchingService` and `External_Notice__c` match on Regulatory Category instead of Vehicle Class; keep Vehicle Class matching only as a fallback when the category is blank. Update the Data Trust README and tests.

### 7. Vehicle identity

- `VIN__c`: unique, case-insensitive, external ID. Validation rule: blank or exactly 17 characters, letters and digits, no I, O or Q.
- New `Plate_Key__c` text(60, unique, external ID), set by trigger or flow as `Country + "|" + normalised plate` when VIN is blank. Normalise by uppercasing and removing spaces and hyphens.
- Check the seed and demo data for duplicate VINs first and report them.

### 8. Fix wrong field types

- `Insurance_Policy__c.Status__c` and `Driver_Qualification__c.Status__c` are Number fields. Convert to picklists (Insurance: Active, Expired, Cancelled, Pending. Qualification: Valid, Expiring Soon, Expired, Revoked). Check layouts, validation rules, flows and seed data for dependencies first and list what changes.

## Multi-currency (do not make the package depend on it)

- Add `MultiCurrency` to the demo scratch definition only; the standard definition and the packaging build stay single-currency.
- No packaged Apex, SOQL or flow may reference `CurrencyIsoCode` statically. Use `UserInfo.isMultiCurrencyOrganization()` and dynamic access (`SObject.get`, `Schema.describe`). Every test class that touches money must pass in both modes.
- On the demo org: enable multi-currency, set corporate currency EUR, add ILS, GBP and USD with dated or fixed rates, then confirm a report grouped by country shows costs converted to EUR.

## Seeds, migration and demo data

- Update `seeder.py`, the Snowfakery recipes, the SFDMU export CSVs, `DataTrustSampleData` and `scripts/apex/seed_*` for the new values. The Data Trust reference vehicles must still score 100 / 80 / 45.
- Branches: replace the US city branches with Lisbon (PT), Tel Aviv (IL), London (GB) and Chicago (US). Spread the demo vehicles across them and give each branch its currency, time zone and units from its Country Profile. Add at least one vehicle registered in a different country from its branch (for example registered PT, operating from London).
- Write a one-time migration script for existing orgs (dev-11 and `fleetforce-master-tso`).

## Not in scope (P1, after the discovery call)

First registration date, emission standard, CO2 g/km, inspection and registration expiry roll-ups; insurance premium, disposal and replacement fields, cost roll-ups; legal entity and cost center on the vehicle; EU driver licence categories and tachograph card; country profile overrides in the admin screen.

## Acceptance

0. Blank means inherit at every level: clearing a vehicle or branch value makes it fall back to the level above, with no other setting involved.
1. The 4 demo branches exist, each showing its own country, time zone, currency and units, and vehicles show the inherited values; the cross-border vehicle shows registration country and operating country separately.
2. Moving a vehicle to another branch changes its effective values with no code and no refresh.
3. A report totalling distance across a UK (miles) vehicle and a PT (km) vehicle uses `Odometer_Km__c` and gives the correct sum. A UK vehicle shows miles for distance and litres for fuel; a Portugal vehicle shows km and litres; a US vehicle shows miles and gallons.
4. A booking for the Lisbon branch made from a guest browser in another time zone shows and stores Lisbon time.
5. A Data Trust notice for category N1 in PT matches only N1 vehicles registered in PT.
6. All Apex tests pass in a single-currency org and in a multi-currency org. Jest tests pass.
7. The package version installs into a clean org and the demo script in `docs/data-trust/README.md` still works.
8. A history entry and a session file are written before the session closes.
