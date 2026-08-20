# Session: TSO foundation cleanup + demo data architecture
**Date:** 2026-06-06
**Note:** Reconstructed from conversation summary on 2026-08-12 (no primary
notes existed). Verify details against actual org/repo state before relying
on specifics.

## Goal
Fix foundation → package properly → seed with demo data → snapshot to TSO.
Scope locked to motorpool-only MVP.

## Foundation cleanup
- Triaged May data-model docs against live org; org was already ahead of
  docs. Reservation object's lookups were already correct — item 1.2 reduced
  to deleting one duplicate field, `Dest_Branch__c`.
- Fixed `FleetKpiController` SOQL (minimal fix chosen over full CMT-driven
  redesign, which was deferred to v2).
- Locked KPI tile definitions:
  - Active Fleet: `Status IN (Available, Assigned)`
  - In Shop: Service Tickets `Status = In-Shop`
  - Critical Violations: `Severity = Critical` only
  - Open Tickets: `Status IN (Draft, In-Shop)`
- Identified dashboard tiles were navigating to "Recently Viewed" instead of
  filtered list views → work order written for 4 named list views + LWC
  navigation update.
- Layout cleanup, Bucket 1 (complete): Fleet Asset (reference template),
  Fleet Branch (already clean), Service Ticket (patched 2 missing fields),
  Telemetry Violation (rebuilt, 4 sections), Reservation (rebuilt, 6 sections,
  unblocked by the 1.2 cleanup).
- Layout cleanup, Bucket 2 (work order written, execution unconfirmed):
  Allocation, Authorized Driver, Contact-Driver layout, Fleet Schedule.
- List view standardization work order written: all 28 FleetForce objects
  get a uniform "All" list view (dev name `All`, label `All [Object
  Plural]`, all-users visibility, no filter). Execution unconfirmed.
- Two orphan fields deleted: `Service_Vendor__c` (duplicate text field,
  proper lookup is `Vendor__c`), and `Dest_Branch__c` (duplicate lookup on
  Reservation). `Total_Cost__c` flagged for Code to verify before placing —
  not yet resolved.

## Demo data architecture
- One master `.xlsx` (`FleetForce_Demo_Dataset.xlsx`), one sheet per object,
  as human-editable source of truth.
- Tree-import plan with `ref` columns and `*__ref` lookup columns so
  relationships resolve without hardcoded IDs across org spins.
- Offset integers in date cells (e.g. `-3`, `7`) resolve to real dates
  relative to spin-day — keeps time-windowed tiles (Critical Violations)
  perpetually current.
- Spine: 9 objects in topological load order — Account, Contact,
  Fleet_Schedule, Fleet_Branch, Fleet_Asset, Authorized_Driver,
  Telemetry_Violation, Service_Ticket, Reservation.
- All 17 cross-reference relationships validated programmatically.
- Generator script work order written for Code: reconcile columns vs. live
  org, handle geolocation composition, resolve relative dates, produce an
  `sf data import tree` plan. Execution unconfirmed.

## Key correction
Vehicle map should read from `Fleet_Asset.Last_Location__c` (existing
geolocation field), not `Telemetry_Raw__c` records. Simplified the dataset
considerably. **Map controller repoint is an open follow-on code task** —
status unknown as of 2026-08-12.

## Explicitly deferred (not for demo)
- KPI component v2 (CMT-driven configurable redesign)
- Test classes for 75% coverage packaging gate
- Draft-flow cleanup (`Fleetforce_*` Draft flows vs. Active counterparts)
- Named Credential migration (required before AppExchange security review,
  not before demos)
- Bucket 3 layout pass
- Maintenance-path fixes: Availability_Blackout, Service_Line_Item
  relationships
