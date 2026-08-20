# FleetForce Demo Data — Population Plan for Antigravity Agent

**Target org:** `fleetforce-dev-9` (or current active scratch org — confirm alias before running)
**Mode:** Direct org write via connected Salesforce access (API or UI automation)
**Scope:** 9 objects only — motorpool-MVP spine. Do not touch any other FleetForce object.
**Today's date for relative fields:** 2026-08-18 — use real calendar dates anchored to this, not placeholder offsets (see "Dates" section below).

---

## 0. Prerequisite (must be true before starting)

`fleetforce__Authorized_Driver__c` must have these 3 fields already deployed:
`Start_Date__c`, `End_Date__c`, `Restriction_Notes__c`. If they're missing, stop and flag it — do not skip populating them by working around the gap.

---

## 1. Goal

Populate realistic, internally-consistent demo data across the 9-object motorpool spine so a live demo can run start-to-finish: browsing available vehicles, submitting a reservation (including as a guest), seeing an approval, checking out (Allocation happens implicitly through Reservation status, not a separate object in this scope), a maintenance history per vehicle, and a couple of telemetry violations that escalate into service tickets.

**Realism bar:** every record should look like it came from an actual mid-market fleet (50–400 vehicles) — real-sounding company/vendor names, plausible vehicle makes/models/trims/mileage for a commercial fleet (not luxury/exotic), real US city names and coordinates, believable driver names. This is being built for a Salesforce security review and investor/customer demos — it needs to hold up to someone clicking around and reading records closely.

**Explicitly prohibited:**
- Do not use real VINs copied from actual vehicle listings. Generate synthetic VINs that are correctly formatted (17 characters, valid check-digit position) but not traceable to a real vehicle.
- Do not use real people's names, photos, or contact details for guest/driver records — invented names are fine, real ones are not.
- Do not copy descriptive text verbatim from any website — paraphrase / originate wording for ticket summaries, notes, etc.

---

## 2. Load order (respect this — later objects depend on earlier ones existing)

1. `Account`
2. `Contact`
3. `fleetforce__Fleet_Schedule__c`
4. `fleetforce__Fleet_Branch__c`
5. `fleetforce__Fleet_Asset__c`
6. `fleetforce__Authorized_Driver__c`
7. `fleetforce__Telemetry_Violation__c`
8. `fleetforce__Service_Ticket__c`
9. `fleetforce__Reservation__c`

---

## 3. Dates — how to handle them

Write **real, absolute dates/datetimes** anchored to today (2026-08-18) — e.g. a vehicle purchased "2 years ago" gets an actual 2024 date, a violation "12 days ago" gets an actual early-August 2026 timestamp. Do not use placeholder text like `today-30`.

Why: this initial pass is meant to be exported afterward and converted into a reusable relative-offset template by a separate process — that conversion is not your job. Just make the dates realistic and internally consistent (e.g. a Service Ticket's `Actual_Start__c` should not be after its `Actual_End__c`; a Reservation's `End_Time__c` should be after `Start_Time__c`; an Authorized_Driver `End_Date__c`, if set, should be after `Start_Date__c`).

---

## 4. Object-by-object spec

### 4.1 Account — 6–8 records
*Vendors, insurers, and one FMC/leasing company — not sales prospects.*

| Field | Guidance |
|---|---|
| Name | Realistic business names — repair shops, an insurance carrier, a leasing/FMC company |
| Industry | `Insurance` for insurers; `Transportation` or `Other` for vendors/FMC |
| Phone | Realistic US format |
| BillingCity / BillingState | Match the branch cities used in §4.4 where relevant |
| Website | Optional, invented but plausible domain |
| Description | One line, e.g. "Preferred transmission and drivetrain specialist" |

**Do not populate** `Type` (leave blank — live picklist values don't fit a vendor/insurer categorization, see plan discussion).

### 4.2 Contact — 20–25 records
*Mostly drivers, a handful of branch managers.*

| Field | Guidance |
|---|---|
| FirstName / LastName | Invented, realistic, diverse |
| Title | "Delivery Driver", "Route Driver", "Branch Manager", "Fleet Coordinator" |
| MobilePhone | Realistic US format |
| Email | firstname.lastname@[invented company domain] |
| fleetforce__Contact_Type__c | Mostly `Driver`; 3–4 `Manager` (you'll need these for Branch and Ticket references) |
| fleetforce__Driver_Branch__c | Lookup — assign after Branches exist (§4.4) |
| fleetforce__Driver_Status__c | Mostly `Active`; 1–2 `On Leave` or `Suspended` for texture |
| fleetforce__License_Class__c | Match to what they'd plausibly drive (Class A/B CDL for truck drivers, Class D for sedan/van drivers) |
| fleetforce__License_State__c | Match branch state |
| fleetforce__License_Number__c | Invented alphanumeric |
| fleetforce__License_Expiry__c | Mostly 1–3 years out; **include 2–3 that are within 30 days or already expired** — compliance-story texture |
| fleetforce__Safety_Score__c | 0–100, mostly 75–98, a couple lower (60s) for realism |

### 4.3 Fleet_Schedule__c — 3–4 records
| Field | Guidance |
|---|---|
| Name | "Standard Business Hours", "24/7 Operations", "Extended Weekday Hours" |
| fleetforce__Type__c | Mostly `Recurring` |
| fleetforce__Is_24_7__c | True for the 24/7 one, false otherwise |
| fleetforce__Time_Zone__c | Match to branches that will use it |
| fleetforce__Total_Hours__c | e.g. 40, 60, 168 (24/7) |
| fleetforce__Grace_Period_Mins__c | Optional, e.g. 15 |

### 4.4 Fleet_Branch__c — 4–5 records
| Field | Guidance |
|---|---|
| Name | e.g. "Atlanta Hub", "Denver Satellite" |
| fleetforce__Branch_ID__c | e.g. "BR-ATL" |
| fleetforce__Type__c | Mix of Hub/Satellite/HQ/Service Center |
| fleetforce__Status__c | All `Active` |
| fleetforce__Street__c / City__c / US_State__c / Zip_Code__c | Real US city/state combos, spread across 2–3 regions/time zones |
| fleetforce__Location__c (lat/long) | Real coordinates for the chosen city |
| fleetforce__Phone__c | Realistic |
| fleetforce__Capacity__c | 15–60 |
| fleetforce__Time_Zone__c | Match the city |
| fleetforce__Schedule__c | Lookup to §4.3 |
| fleetforce__Primary_Contact__c / fleetforce__Approving_Manager__c | Lookup to a Manager-type Contact from §4.2 |

### 4.5 Fleet_Asset__c — 30–40 records
*The vehicles. Mid-market commercial fleet — pickups, vans, sedans, some light trucks. No luxury/exotic vehicles.*

| Field | Guidance |
|---|---|
| Name | e.g. "2023 Ford F-150 XLT" |
| fleetforce__Asset_ID__c | e.g. "FA-0142" |
| fleetforce__VIN__c | **Synthetic, correctly formatted, not from a real listing** |
| fleetforce__License_Plate__c | Invented, state-appropriate format |
| fleetforce__Branch__c | Lookup to §4.4 — spread across branches |
| fleetforce__Driver__c | Lookup to §4.2, ~60% assigned, rest blank (pool vehicles) |
| fleetforce__Status__c | Mostly `Available`/`Assigned`; 2–3 `Decommissioned`/`Retired`/`Ordered` for texture |
| fleetforce__Body_Type__c / fleetforce__Vehicle_Class__c / fleetforce__Color__c / fleetforce__Drive_Type__c / fleetforce__Transmission__c | Realistic combos for the make/model |
| fleetforce__Engine_Type__c / fleetforce__Fuel_Type__c | Mostly ICE/Gasoline or Diesel; include 3–5 Hybrid/Electric for variety |
| fleetforce__Seat_Count__c | Match body type |
| fleetforce__Odometer__c | Realistic for vehicle age (5k–15k/year) |
| fleetforce__Fuel_Capacity__c / fleetforce__Fuel_Energy_Level__c | Skip capacity for EVs; energy level 20–100% |
| fleetforce__Battery_Capacity_kWh__c / fleetforce__Max_Range__c | **Only for EV/Hybrid rows** |
| fleetforce__Ownership__c | Mix of Owned/Leased/Financed |
| fleetforce__Purchase_Date__c | 1–4 years ago |
| fleetforce__Purchase_Price__c | Realistic for vehicle class ($22k–$65k) |
| fleetforce__Residual_Value__c | **Only for Leased rows** |
| fleetforce__Registered_State__c | Match branch state |
| fleetforce__Vendor__c | Lookup to an Account from §4.1 |
| fleetforce__Last_Location__c (lat/long) | Small random jitter around the assigned branch's coordinates |
| fleetforce__Key_Tag_ID__c | Optional |
| fleetforce__Total_Maintenance_Cost__c | Leave blank or rough-estimate — flagged as possibly-should-be-a-rollup, don't over-invest here |

**Do not populate**: `Height__c`, `Paint_Name__c`, `Serial__c`, `Agreement__c`, `Agreement_Line__c` — out of scope.

### 4.6 Authorized_Driver__c — 40–50 records
*Links drivers to vehicles they're authorized to operate. Roughly 1–2 per vehicle.*

| Field | Guidance |
|---|---|
| fleetforce__Fleet_Asset__c | Required lookup to §4.5 |
| fleetforce__Driver__c | Lookup to §4.2 |
| fleetforce__Type__c | Mostly `Primary`, some `Secondary`/`Occasional` |
| fleetforce__Has_Key__c | Mostly true |
| fleetforce__Is_Active__c | Mostly true |
| Start_Date__c | 6 months – 2 years ago |
| End_Date__c | Blank for most (ongoing); **2–3 records with a past End_Date** for compliance texture |
| Restriction_Notes__c | Sparse — most blank, a few like "Automatic transmission only" or "Local routes only" |

### 4.7 Telemetry_Violation__c — 15–25 records
| Field | Guidance |
|---|---|
| fleetforce__Fleet_Asset__c | Required-ish lookup to §4.5 |
| fleetforce__Driver__c | Lookup to §4.2, optional |
| fleetforce__Type__c | Spread across the full picklist |
| fleetforce__Severity__c | Weight toward Low/Medium; **include at least 3–4 Critical** — a dashboard KPI tile filters on Critical only and needs non-zero data |
| fleetforce__Timestamp__c | **All within the last 30 days** — matches the KPI tile's time window |
| fleetforce__Location__c (lat/long) | Jitter around the vehicle's branch |
| fleetforce__Limit__c / fleetforce__Value__c | e.g. "65 mph" / "82 mph" for speeding; appropriate pairs for other types |
| fleetforce__Is_Ack__c | Mostly false (open); some true (reviewed) |

**Do not populate** `fleetforce__Equipment__c` — out of scope.

### 4.8 Service_Ticket__c — 30–40 records
*Roughly 1 per vehicle, some vehicles with 2.*

| Field | Guidance |
|---|---|
| fleetforce__Fleet_Asset__c | Required lookup to §4.5 |
| fleetforce__Category__c | Spread across the picklist, weighted toward Preventive Maintenance |
| fleetforce__Priority__c | Spread |
| fleetforce__Status__c | Spread across Draft/In-Shop/Completed |
| fleetforce__Summary__c | Short, realistic — "Oil Change - 5,000 mi service", "Brake Pad Replacement - Front" |
| fleetforce__Description__c | Optional, 1–2 sentences, originated wording |
| fleetforce__Date_Reported__c | Realistic recent-ish datetime |
| fleetforce__Due_Date__c / fleetforce__Scheduled_Start__c / fleetforce__Scheduled_End__c | Consistent sequence after Date_Reported |
| fleetforce__Actual_Start__c / fleetforce__Actual_End__c | **Only populate for `Completed` status rows**, and End must be after Start |
| fleetforce__Odometer__c | Match roughly to the vehicle's current odometer |
| fleetforce__Reported_By__c | Lookup to a Contact (driver or manager) |
| fleetforce__Vendor__c | Lookup to an Account from §4.1 |
| fleetforce__Violation_Source__c | **Only for Category = "Telemetry Alert" rows** — lookup to §4.7 |
| fleetforce__Total_Parts_Cost__c / fleetforce__Total_Labor_Cost__c | Realistic dollar amounts for the job type |

**Do not populate**: `Fixed_Cost__c`, `Misc_Fees__c`, `Tax_Rate__c`, `Is_Labor_Taxable__c`, `Grand_Total__c` (formula), `In_Shop__c` (formula).

### 4.9 Reservation__c — 25–35 records
*The flagship object — needs the fullest status spread and some deliberate conflicts.*

| Field | Guidance |
|---|---|
| fleetforce__Status__c | Full spread — Draft, Pending, Approved, Active, Completed, Cancelled, Rejected |
| fleetforce__Start_Time__c / fleetforce__End_Time__c | Mix of past (Completed), present/near-future (Active/Approved), and future (Draft/Pending) |
| fleetforce__Origin_Branch__c / fleetforce__Destination_Branch__c | Same branch for most (local use); a few different (one-way trips) |
| fleetforce__Assigned_Asset__c | **Blank for Draft/Pending; populated for Approved and later statuses** |
| fleetforce__Requestor_Contact__c | Lookup to §4.2 |
| Guest fields (First/Last Name, Email, Phone) | **Populate on 4–5 records only** — these specifically demo the guest-reservation flow. Leave blank on the rest (internal requestor via Requestor_Contact instead) |
| fleetforce__Preferred_Body__c / fleetforce__Preferred_Engine__c / fleetforce__Min_Seats__c | Mainly meaningful on rows without an Assigned_Asset yet |
| fleetforce__Priority__c | Spread |
| fleetforce__Cost_Center__c | Optional |
| fleetforce__Approval_Date__c | Only for Approved+ statuses, after Start_Time is set but before it occurs |
| fleetforce__Cancel_Reason__c | Only on Cancelled rows |
| fleetforce__Rejection_Reason__c | Only on Rejected rows |

**Do not populate** `fleetforce__Requestor_User__c` — would require real Salesforce User records, out of scope.

**Critical requirement — deliberate conflicts:** create **2–3 pairs** of Reservation records that share the same `Assigned_Asset__c` with overlapping `Start_Time__c`/`End_Time__c` windows. These exist specifically to demonstrate the motorpool rules engine catching a double-booking — do not accidentally avoid overlaps.

---

## 5. When you're done

Stop and report:
- Final record count per object
- Confirmation that load order was respected (no orphaned lookups)
- Confirmation that the 2–3 deliberate Reservation conflicts were created, and which record pairs they are
- Any field you were unable to populate as specified, and why
- Any picklist value you needed that wasn't in the live org's value set

Do not export or modify anything outside these 9 objects. Do not delete or modify any existing records unless they're leftover test data you created earlier in this same session.
