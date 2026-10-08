# Session: Component polish, Apex coverage, and the TSO packaging journey
**Date:** 2026-09-07

## Goal for the session

Two stated goals at the start: (1) polish existing live components now that
real seed data exists to click through, and (2) move as fast as responsibly
possible toward a real Trialforce Source Org (TSO) MVP, followed by a
CI/CD-style release cadence. Explicit instruction: "make sure we have a
good base" — favor correctness over speed where the two conflicted.

---

## Part 1 — Component audit and fixes

Full audit of all 6 LWCs against real seeded data (see prior session for
Snowfakery recipe validation). Findings, by severity:

**Deleted:** `caseTaskStatusPanel` — hardcoded, Hebrew UI, no live data.
Confirmed contamination from an unrelated project (Aharai/Be'er Sheva),
swept in during the Aug 4 "grab everything" commit. Removed entirely
(component, controller, any page references).

**`fleetMapTracker` (Real-Time Asset Tracker) — fixed:**
- Removed hardcoded `zoom-level="10"`, switched to auto-fit — the fixed
  zoom was breaking on the seed data's multi-city spread (Atlanta, Denver,
  Dallas, Phoenix), showing one city's markers with the other three
  off-screen.
- Removed `list-view="visible"` (redundant built-in Salesforce list
  chrome, inconsistent with `fleetListMap`'s custom sidebar).
- Fixed empty-state icon variant mismatch.

**`maintenanceAlerts` (Critical Maintenance Alerts) — fixed:**
- Sort changed from `CreatedDate DESC` to `Priority ASC, Date_Reported__c
  ASC NULLS LAST` — the widget's whole purpose (surfacing critical items
  first) was undermined by insertion-order sorting.
- Added click-through navigation to the underlying `Service_Ticket__c`
  record via `NavigationMixin` (previously display-only).

**`fleetListMap` (Fleet Map Explorer) — full rewrite, not a patch:**
The audit found this component was very likely completely non-functional:
`@AuraEnabled(cacheable=true)` combined with an HTTP callout is an illegal
combination in Apex (runtime error). Root architecture was fetching
list-view records via a scraped Visualforce session token
(`SessionIdGenerator.page` + `ListViewService.cls`) — fragile and illegal
in combination with the cacheable annotation.

Decision (confirmed with user): drop generic list-view-switching entirely,
replace with a small fixed set of named filters (All / Available / In
Shop / Critical) backed by plain, direct, cacheable SOQL. Rebuilt as:
- New `FleetAssetMapController.cls` — 4 clean static SOQL branches, no
  callouts, legally `cacheable=true`.
- Rewrote `fleetListMap.js`/`.html`/`.css` against the new controller.
- Fixed status-color logic to match real `Fleet_Asset__c.Status__c`
  picklist values (was checking for `'maintenance'`/`'grounded'`, which
  don't exist — every vehicle was rendering green regardless of status).
- Fixed odometer formatting (thousands separator), EV fuel-label mismatch
  (showed "fuel" for Electric vehicles), and marker-click → sidebar-scroll
  bidirectionality.
- Deleted `ListViewService.cls` and `SessionIdGenerator.page` entirely
  (proper destructive change, not just local deletion).

**Deferred (admin-facing only, not customer-demo-critical):**
`geotabSettingsManager` issues (spinner overlap, password-in-JS-state,
alert styling) — noted but not fixed this session.

### A recurring pattern surfaced here
Every deletion this session left dangling references elsewhere that had
to be separately discovered and fixed — `ListViewService`/
`SessionIdGenerator` deletion left 8 profiles still referencing the dead
VF page; the new `FleetAssetMapController` was initially missing from all
9 profiles/permset's class-access lists (same shape as the FLS pattern
from earlier sessions). **Standing lesson: any deletion or rename needs a
full-repo reference sweep, not just removal of the definition file.**

---

## Part 2 — The CustomApplication naming mystery

While deploying the `fleetListMap` permission changes, profiles failed to
deploy: `no CustomApplication named Fleetforce found`. Investigation
initially suspected a packaged/managed-app conflict, but the actual cause
(recalled by the user, then confirmed by Code): the "Fleetforce" app had
been renamed to "FleetOps" directly in the org UI on Aug 20 (alongside the
branding work) and never retrieved into source — the same
manual-org-change-never-retrieved pattern that has recurred all project
(theme, layouts, FLS grants).

Retrieved `FleetOps.app-meta.xml` cleanly (richer than the stale
`Fleetforce.app-meta.xml` — includes `workspaceConfig`, 32 tab mappings),
updated all 8 profiles' `applicationVisibilities`. Two secondary issues
surfaced during this fix: stale `SessionIdGenerator` references still in
all 8 profiles (the earlier deletion's dangling-reference problem, again),
and a `ViewSetupAuditTrail` permission incompatible with scratch org
licensing on 6 profiles. Both fixed. Deploy: 11/11, 0 failures.

---

## Part 3 — Apex test coverage: 30% → 94%

Baseline check (never done before, only assumed from partial info):
**30% org-wide**, well below the 75% packaging threshold. 5 classes at 0%
coverage with no test classes at all: `FleetAssetMapController` (new this
session, 8 lines), `GeotabService` (94 lines), `GeotabSettingsController`
(43 lines), `GeotabSyncBatch` (60 lines), `GeotabSyncScheduler` (12
lines). 4 classes already >75% with small gaps, deprioritized.

Wrote all 5 test classes in priority order. **Caught a real production
bug along the way:** a fragile `(List<Map<String,Object>>)` cast from
`JSON.deserializeUntyped` in `GeotabService.fetchStatusData` — fixed with
a proper `castToTypedList` helper. This also explained
`GeotabSyncBatch`'s persistently low coverage.

Iterative fixes during the test-writing process: a bad `getMessage()`
assertion on `AuraHandledException` (returns a generic string, not the
set message), a fragile `JSON.deserializeUntyped` cast issue, and 3 tests
that needed to accept `Metadata.Operations.enqueueDeployment()` throwing
in scratch-org test context as a valid outcome rather than a failure.

**Final: 38/38 tests, 100% pass rate, 94% org-wide coverage.** Packaging
gate cleared.

---

## Part 4 — TSO path research

Before proceeding, verified current Salesforce partner-program mechanics
against live docs rather than assume from training data:
- A TSO requires an actual package installed into it via Environment Hub
  — nothing had been packaged this project until this session.
- Public self-serve Trialforce (SignupRequest API, lead/license
  generation) requires a Partner Support approval cycle — but this is a
  **later** milestone, not a blocker, since the GTM strategy is
  design-partner-direct, not public self-serve.
- 75% coverage is technically an unlocked-package *promotion* gate, not a
  *creation* gate — but since unreleased beta versions can only install
  into scratch orgs/sandboxes (not a real TSO), coverage is a practical
  hard blocker regardless.

Decisions: **unlocked package** (not managed) for MVP speed, deferring
the managed/OEM-royalty AppExchange model to a later milestone per the
strategy doc's own phasing. Namespace was already reserved (confirmed by
user).

---

## Part 5 — Creating the package (multiple rounds)

### Namespace conflict
`sf package create` failed: a **Managed** package named "Fleetforce"
already existed under the `fleetforce` namespace with 0 versions (likely
a side effect of the original namespace reservation). Researched whether
namespaces can host multiple packages — confirmed yes, the error was a
*name* collision, not a namespace-exclusivity rule. Created a new package
under a distinct name ("FleetForce Platform"), same namespace — no
deletion needed, nothing destructive.

### Round 1 — 29 validation errors
First `sf package version create` attempt failed with 29 errors across 3
categories: locale-specific standard fields (`Contact.FirstNameLocal`/
`LastNameLocal` in 8 profiles), standard WebLinks not present in the
packaging validation org (`Account.Billing`, `Opportunity.DeliveryStatus`,
etc.), and feature-gated standard layouts (Employee/SOS/Service-Catalog/
WorkPlan — swept in by the Aug 4 bulk layout retrieve, unrelated to
FleetForce).

**Paused before fixing** — flagged that deleting Account/Case/Opportunity
layouts outright risked regressing the original Aug 4 fix (those layouts
exist specifically to unblock scratch-org deploys). Investigated proper
SFDX multi-directory scoping instead.

### The `unpackaged/` architecture
Confirmed `sfdx-project.json` supports multiple `packageDirectories`
entries — only the one tagged `"package"` gets included in a package
version; all directories still deploy to scratch orgs normally. This is
also the correct ISV pattern for profiles (should never ship in a
package; permission sets do the real FLS work) and standard-object
layouts (not portable across orgs/editions).

Moved via `git mv` (history preserved): all 8 profiles, 127 standard
object layouts, and `sites/Motorpool.site-meta.xml` into `unpackaged/`.
Deleted 11 genuinely FleetForce-unrelated feature-gated layouts outright
(Employee/SOS/Service-Catalog/WorkPlan family). Verified no scratch-org
deploy regression: 724/724, 0 errors.

### Round 2 — remaining errors
Package directories are *all* deployed to the validation org regardless
of packaging tag, so profile-sourced errors persisted even after the
move. Stripped the 2 locale-field references from all 8 profiles
directly (invalid regardless of context) and deleted the corresponding
`Contact.FirstNameLocal`/`LastNameLocal` field-stub files from
`force-app` (Hebrew-locale retrieval artifacts, not real custom fields).
Final blocker: `CustomSite` metadata type is unsupported in unlocked
packages entirely — moved `sites/Motorpool.site-meta.xml` to
`unpackaged/`.

**Package version 1.0.0.1 created: `04thd0000000pH3AAI`, Beta, 94%
coverage confirmed by the packaging process itself.**

---

## Part 6 — The Motorpool portal: from "never audited" to fully proven

### The critical gap
Every fix so far in the session touched the internal admin dashboard.
**The Motorpool guest reservation portal — the flagship "90-second demo"
differentiator per the original strategy doc — had never once come up
this session, or been tested at all.** Flagged as the highest-priority
item before any TSO install.

### First audit — 3 blockers found
1. Site served the `InMaintenance` fallback — completely inaccessible.
2. `c:MotorpoolApp` hardcoded namespace reference in
   `MotorpoolPortal.page` — resolves to nothing in any namespace-aware
   org. Code comment had the scratch-org reasoning exactly backwards.
3. `startFlow("Motorpool_Reservation_Request")` missing the
   `fleetforce__` prefix.

**Meta-finding:** both namespace bugs are exactly the class of bug that
"works" only in the namespace-owning dev org — every test so far had
been run in `fleetforce-dev-9` itself, meaning this bug class could exist
elsewhere undetected. A full codebase sweep for the same pattern came
back clean — isolated to this one file.

### Fixing the blockers — more nuanced than expected
`c:MotorpoolApp` fixed to `fleetforce:MotorpoolApp`. The flow name fix
required real nuance: `dev-9`, as the *namespace owner*, does not
self-prefix its own flows (`Motorpool_Reservation_Request`, no prefix),
while subscriber orgs need the prefix. Built `MotorpoolPortalController`
to detect the correct name at render time via
`Organization.NamespacePrefix` — a proper fix, not a hardcoded guess.

### The InMaintenance investigation — a long detour
Root cause A: `Motorpool.site-meta.xml`'s `siteAdmin` referenced a
username from a *different, deleted* prior scratch org — a real
metadata-portability bug, fixed (this is a per-scratch-org issue, not a
TSO issue, since a TSO has real persistent users).

Root cause B became a much deeper investigation than expected. The
originally-assumed fix — an org-wide "Let site guest users run flows"
toggle — turned out not to exist in the current org at all. Research
revealed why: that mechanism was **deprecated in Winter '22**, replaced
by per-flow granular `flowAccesses` grants. Added the correct
`flowAccesses` entry to the Motorpool Profile — grant confirmed registered
in `SetupEntityAccess` — but the flow **still** failed with an
`INSUFFICIENT_ACCESS` error.

Extensive further investigation (Tooling API field enumeration, named
permission sets, `<flow:interview>` native VF embedding, debug log trace
flags) all failed to unblock it. Final conclusion: **Force.com Sites
Classic has a platform-level guest-user restriction on Screen Flow access
via Lightning Out that cannot be resolved via any current metadata,
Tooling API, or permission configuration** — the "Process Automation
Settings" page itself no longer exists in Setup for this API version.

**Resolution:** abandoned the Screen Flow architecture entirely. Rebuilt
the guest form as a native Visualforce page backed by a
`@RemoteAction global` Apex method (`MotorpoolPortalController
.submitReservation`) — same 7 fields, same `Reservation__c` insert.
**Confirmed the new implementation replicates 100% of the original flow's
behavior** — the flow graph was exactly `START → Screen_Guest_Info →
Screen_Trip_Details → Create_Reservation → Screen_Success`, a single
record insert with no other elements (no notifications, no approvals,
nothing else to replicate).

Live-tested successfully in `dev-9`: guest submission created a real
`Reservation__c` record with `Status=Pending`.

### Strategic note surfaced by this investigation
The reason Screen Flow guest access is broken here is that the Motorpool
portal runs on **legacy Force.com Sites Classic**, not modern Experience
Cloud/Digital Experience — where guest Screen Flow embedding works
properly. This is a reasonable near-term choice but worth a deliberate
future decision, since the strategy doc cites Experience Cloud portals as
a core platform differentiator against Fleetio.

---

## Part 7 — First "subscriber" test: a false positive

Tested against `fleetforce-sub-test` — but this org was created under the
*same* Dev Hub (`fleetforcePBO`) that owns the `fleetforce` namespace, and
tested via `sf project deploy start` (source deploy), not a real package
install. **This was flagged as not a valid subscriber test before
trusting any of its conclusions** — source deploy bypasses exactly the
package-install-specific validation that matters most.

During this invalid test, a 503 was hit and "fixed" by repurposing the
`inMaintenancePage` slot as the live form (`indexPage=InMaintenance`) —
Code's own notes explicitly flagged this fix as unconfirmed against a
true subscriber context. Correctly held before accepting it as permanent
architecture.

---

## Part 8 — The true subscriber test

User created a genuinely separate Dev Hub-enabled org. Two real,
independent bugs surfaced — both invisible to every prior test because
none had used real package installation:

### Bug 1 — global Quick Actions break package install
`Fleet_Asset__c-Fleet Asset Layout` referenced `NewTask`/`NewEvent` as
Quick Actions. Salesforce's package installer resolves
`<actionType>QuickAction</actionType>` as an object-specific action
search — fails to find a Fleet_Asset__c-specific `NewTask`, blocks the
entire install. A theory that this was actually an `enableActivities`
misconfiguration was raised and **properly falsified via git-history
timeline** (the field had been `true` in source since March 30, five
months before any package version existed — ruling it out cleanly rather
than arguing about it). Swept the whole codebase for the same pattern —
confirmed isolated to this one layout. Fixed by removing both Quick
Actions from the packaged layout (admins can add them back manually
post-install if wanted).

### Bug 2 — Geotab CMT record: packaging error reveals a real production bug
`Geotab_Setting__mdt.Default` (containing fake test credentials) was
referenced in the package manifest but failed to zip correctly. Correct
fix: customer Geotab credentials don't belong in the package at all
(same pattern as the `siteAdmin` username) — moved to `unpackaged/` as a
post-install configuration template.

This move broke `GeotabServiceTest` and `GeotabSyncBatchTest`, revealing
a **real, independent production bug**: `GeotabService.authenticate()`
does a bare, unguarded SOQL assign-to-SObject query against
`Geotab_Setting__mdt` — meaning **every subscriber would crash on this
method immediately post-install**, before they've had a chance to
configure Geotab credentials at all. This had nothing to do with
packaging; the packaging error just happened to be what surfaced it.
Confirmed `GeotabSyncScheduler` is not auto-scheduled (requires explicit
admin action), so this wouldn't recur automatically — but would still
hit on first manual trigger.

Fixed properly: guarded `authenticate()` with a clean
`AuraHandledException`, added `@TestVisible injectConfig()` /
`testService` injection points across `GeotabService`/`GeotabSyncBatch`,
updated all 3 dependent test classes to be CMT-count-aware (work
correctly whether 0 or 1 records exist). Coverage settled at **91%**
(down from 94% since the packaged CMT record no longer exists to satisfy
one test's happy path — still well above the 75% floor).

### The real answer on the 503
With bugs 1 and 2 fixed (package versions 1.0.0.4, 1.0.0.5), ran the
actual conclusive test: deployed the *original*, unmodified portal
architecture to the true subscriber org and tested directly.
**Confirmed: HTTP 503 is NOT a namespace-owning-org artifact — it is a
genuine, universal Force.com Sites platform behavior.** Root cause: Sites
returns 503 for any `indexPage` using a namespace-prefixed page
(`fleetforce__X`), with exactly one exception — the page referenced by
`inMaintenancePage` receives special global routing and always returns
200, in any org.

**Permanent, correct fix (shipped in 1.0.0.6):** moved the full portal
form into `force-app/pages/InMaintenance.page` (now properly packaged,
using the packaged `MotorpoolPortalController`), set the site's
`indexPage=fleetforce__InMaintenance`. **Confirmed end-to-end in the true
subscriber org:** HTTP 200, VF remoting active
(`fleetforce.MotorpoolPortalController.submitReservation` wired), real
`Reservation__c` record created via a live guest submission. 39/39 tests
pass. 220 Snowfakery seed records loaded cleanly via CumulusCI.

---

## Lessons learned (session-level, not just findings)

1. **Source deploy and package install are genuinely different validation
   paths.** Every test before this session's true-subscriber pass used
   `sf project deploy start`, which had been silently masking at least 2
   real, independent bugs (global Quick Actions, Geotab CMT crash) that
   only `sf package install` surfaces. Trust package-install tests over
   source-deploy tests for anything packaging-related.

2. **A scratch org under the same Dev Hub as the package namespace is not
   a valid subscriber-org proxy**, even when using real package
   installation. Namespace-owner-org behavior (self-unprefixed flow
   names, different Site routing) is genuinely different from subscriber
   behavior. A second, unrelated Dev Hub is necessary for trustworthy
   validation.

3. **Manual org UI changes never retrieved into source is the single most
   recurring failure pattern this entire project** — it caused the
   CustomApplication/FleetOps mystery this session, and the theme/branding
   mystery, the FLS drift (3 separate times), and the layout drift
   before that. Worth treating as a standing risk category, not isolated
   incidents.

4. **Falsify theories with evidence, not argument.** The `enableActivities`
   theory was cleanly ruled out by checking git commit history against
   package-version-creation timestamps — a much stronger method than
   reasoning about it in the abstract.

5. **Deletions and renames need a full-repo reference sweep.** Recurred
   at least 3 times this session alone (`SessionIdGenerator` in profiles,
   `FleetAssetMapController` missing from permsets, stale field
   references).

---

## Artifacts created/updated this session
- `docs/history/manual-setup-steps.md` (later relocated by user to
  `docs/project files/manual-setup-steps.md`) — tracks non-metadata-
  deployable manual steps (theme activation, per-scratch-org site admin
  username, and the now-resolved guest-flow investigation).
- Package versions: 1.0.0.1 → 1.0.0.6, with 1.0.0.6 as the current
  validated state.
- New classes: `FleetAssetMapController`, `MotorpoolPortalController`
  (evolved significantly across the session).
- Deleted: `caseTaskStatusPanel` (all files), `ListViewService.cls`,
  `SessionIdGenerator.page`, `Contact.FirstNameLocal`/`LastNameLocal`
  field stubs.

## Open items for next session
- Final consolidated sanity check on `true-sub-test`: branding/logo,
  app name, dashboard KPI tiles — requested, result not yet confirmed.
- `MotorpoolGuestFlow` permset cleanup — requested, result not yet
  confirmed.
- Once both confirmed clean: **decision point — promote 1.0.0.6 to
  Released**, then Environment Hub → actual TSO creation.
- Still-deferred product decisions on the guest portal: missing
  `Preferred_Engine__c`/`Preferred_Body__c` collection, no date-range
  validation, no guest confirmation email/reference number.
- `geotabSettingsManager` polish items, deferred as admin-only/low-priority.
- Strategic note: consider migrating the Motorpool portal from legacy
  Force.com Sites Classic to modern Experience Cloud at some point —
  not urgent, but worth a deliberate decision given the strategy doc's
  positioning.
- CI/CD design — explicitly the next phase after TSO MVP, not yet started.
