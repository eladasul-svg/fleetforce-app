# Work Order — Demo dataset generator + tree-import loader

> **For:** Claude Code, against the live scratch org (`fleetforce-dev-8` / `<scratch-alias>`) + repo.
> **Input:** `FleetForce_Demo_Dataset.xlsx` (Elad's curated source of truth — commit it to `data/` in the repo).
> **Goal:** A generator script that converts the workbook into a `sf data import tree` plan with reference IDs and relative-date resolution, loadable into any fresh scratch/TSO org in correct dependency order. **Re-runnable on every spin.**

---

## What the workbook is

9 object sheets + a `_README` tab. Conventions (also in `_README`):
- **`ref` column** (1st col): unique human key per row.
- **Lookup columns named `*__ref`**: hold the *ref* of the target row, NOT a Salesforce Id. Resolve at load.
- **Offset-date columns** (named `*_Offset`, or lat/long pairs `Last_Location_Lat`/`_Long`): integer = days from spin-day. `-3` = 3 days ago, `7` = next week, blank = empty. Convert to actual ISO datetime at generate time.
- **Static dates** (e.g. `fleetforce__Purchase_Date__c`): literal `YYYY-MM-DD`, pass through.
- Picklist cells already use exact API values.

Load order (parents first): **Account → Contact → Fleet_Schedule → Fleet_Branch → Fleet_Asset → Authorized_Driver → Telemetry_Violation → Service_Ticket → Reservation.**

---

## Step 0 — Schema reconcile (the docs are ~1 month stale)

Before generating, confirm the workbook columns match the live org. For each sheet, describe the object and compare:

```bash
ALIAS=<scratch-alias>
# example for one object — loop over all 9
sf sobject describe -s fleetforce__Fleet_Asset__c -o $ALIAS --json > /tmp/fa.json
```

For every non-`ref`, non-`*__ref`, non-`*_Offset`, non-lat/long column:
- **Field exists + type/picklist matches?** → use it.
- **Field missing in org?** → **mark it** in a reconcile report `data/_schema-reconcile.md` (do NOT silently drop). Elad decides: create the field, or remove the column.
- **Picklist value not valid?** → mark it (e.g. a Color or Status the org doesn't have).

Special columns the generator handles, not direct fields:
- `Account` sheet: `Type`, `Industry`, `BillingCity/State`, `Phone` are STANDARD Account fields (no namespace).
- `Contact` sheet: `FirstName/LastName/Email/Phone` standard; `Account__ref` → Contact.AccountId.
- `Fleet_Branch`: `Latitude`/`Longitude` → compose into the `fleetforce__Location__c` geolocation compound field.
- `Fleet_Asset`: `Last_Location_Lat`/`Last_Location_Long` → compose into `fleetforce__Last_Location__c` geolocation.
- `Authorized_Driver`/`Telemetry_Violation`/`Service_Ticket`/`Reservation`: `*_Offset` columns map to specific datetime fields:
  - Authorized_Driver: `Start_Date_Offset`→`fleetforce__Start_Date__c`, `End_Date_Offset`→`fleetforce__End_Date__c` (these are Date, not DateTime).
  - Telemetry_Violation: `Timestamp_Offset`→`fleetforce__Timestamp__c` (DateTime).
  - Service_Ticket: `Date_Reported_Offset`→`fleetforce__Date_Reported__c` (DateTime); `Scheduled_Start_Offset`→`fleetforce__Scheduled_Start__c` (Date); `Actual_Start_Offset`→`fleetforce__Actual_Start__c` (Date).
  - Reservation: `Start_Time_Offset`→`fleetforce__Start_Time__c`, `End_Time_Offset`→`fleetforce__End_Time__c` (DateTime); `Approval_Date_Offset`→`fleetforce__Approval_Date__c` (DateTime).

> Confirm those target field API names + types in Step 0. If any differ, mark in the reconcile report.

**STOP after Step 0, show Elad `data/_schema-reconcile.md`.** Proceed once confirmed.

---

## Step 1 — Generator script `scripts/gen_dataset.py`

Reads the xlsx, emits tree-import JSON files + a plan. Behavior:

1. **One JSON per object** in `data/tree/` (e.g. `Account.json`), records in sheet order.
2. **Reference IDs:** each record's `attributes.referenceId` = its `ref` value. Each `*__ref` lookup becomes `"<FieldApiName>": "@<targetRef>"` — the tree API resolves `@ref` to the created Id. (Map `*__ref` column → real lookup field, e.g. `Branch__ref` → `fleetforce__Branch__c`, `Driver__ref` → `fleetforce__Driver__c`, `Account__ref` → `AccountId`, `Reported_By__ref` → `fleetforce__Reported_By__c` [User lookup — see caveat], etc.)
3. **Relative dates:** `today + offset days`, formatted ISO (`YYYY-MM-DD` for Date, full ISO8601 for DateTime). Blank offset → omit the field.
4. **Geolocation:** compose lat/long into the compound field's components (`fleetforce__Last_Location__Latitude__s` / `__Longitude__s`).
5. **Plan file** `data/tree/plan.json` lists the 9 JSON files in dependency order with their sobject types.
6. Skip any column flagged "remove" in the reconcile report.

> ⚠️ **`Reported_By__ref` caveat:** Service_Ticket.`Reported_By__c` is a **User** lookup, but the workbook points it at Contact refs (`c_*`). Users can't be tree-imported the same way (they're not created by this dataset). **Two options — flag to Elad:** (a) drop `Reported_By__c` from the load (leave blank), or (b) map all to the running user's Id at generate time. Recommend (a) for simplicity. Do NOT try to create Users.

---

## Step 2 — Load script `scripts/load_dataset.sh`

```bash
#!/usr/bin/env bash
set -e
ALIAS="${1:-<scratch-alias>}"
python3 scripts/gen_dataset.py            # regenerate (resolves dates to TODAY)
sf data import tree --plan data/tree/plan.json -o "$ALIAS"
echo "Loaded demo dataset into $ALIAS"
```

> `sf data import tree` honors `referenceId`/`@ref` resolution within a single plan, loading files in plan order. Note the per-file 200-record limit (we're well under).

---

## Step 3 — Verify load

After loading into dev-8:
- Row counts per object match the workbook.
- Spot-check resolution: open a Fleet_Asset, confirm Branch/Driver/Vendor lookups populated (not blank).
- **Dashboard check (the payoff):** open the home page — `Active Fleet` and `Open Tickets`/`In Shop` tiles non-zero, `Critical Violations` shows the count of Critical-severity violations dated in the last 30 days (the offsets are all within -15, so all current). Confirm the numbers match the data.
- Open a Fleet_Branch + Fleet_Asset, confirm geolocation populated (map-ready).

---

## Step 4 — Commit

```bash
git add data/ scripts/gen_dataset.py scripts/load_dataset.sh
git commit -m "data: curated demo dataset (xlsx source) + tree-import generator/loader

9-object spine, ref-based relationships, relative-date offsets resolved at load.
Re-runnable on any fresh scratch/TSO org."
```

---

## Known follow-on (not this work order)
- **Map controller:** `fleetMapTracker`/`FleetKpiController.getAssetLocations` reads `Telemetry_Raw__c`. The dataset puts positions on `Fleet_Asset__c.Last_Location__c` (correct design). A separate small work order repoints the controller to read Last_Location__c so the map renders from this data.
- **Peripheral objects:** Allocation, Fuel_Log, etc. not in v1 dataset. Add as new sheets later — generator already handles any sheet following the conventions, so growth = add a sheet + add to plan order.

## Not in scope
- ❌ Don't create Users.
- ❌ Don't silently drop columns — reconcile report + Elad decision.
- ❌ Don't hardcode dates — always relative to load-day.
