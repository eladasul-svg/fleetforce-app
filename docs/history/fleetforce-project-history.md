# FleetForce — Project History

> Append-only log. Newest entry at the top. Each entry is a short paragraph;
> full detail lives in `sessions/YYYY-MM-DD-subject.md`.
>
> **At the start of every session:** read the "Queued Work Orders" section
> below first — it's the source of truth for what's actually done vs. just
> planned. Update it before wrapping any session.
>
> **Editing discipline (added 2026-09-06):** log entries below the Queued
> Work Orders section are append-only — once written, don't edit them again,
> only add new entries above. Only the Queued Work Orders section itself
> should be edited in place. This file previously suffered header corruption
> from repeated in-place edits to old entries (fixed in this revision) —
> don't repeat that pattern.

---

## 🔧 Queued Work Orders (check/update this every session)

Status as of 2026-09-06:

- [x] **Phase 2 (Snowfakery recipe) — validated, working, committed.** Corrections applied: `random_reference` scoped to drivers-only via a `Contact_Type__c = 'Driver'` macro for driver-specific fields; `Service_Ticket__c.Violation_Source__c` gated on `Category__c == 'Telemetry Alert'`. **Fresh-org validation succeeded: 204 records, 0 errors** (commit `27648bc`, ~Aug 21). The 9-object motorpool spine now has a working "click of a button" seed mechanism: `sf snowfakery run data/seed.recipe.yml --target-org <any-fresh-org>`.
- [x] **Full-system relationship audit closed out** — all 8 originally-flagged (May 9) broken `referenceTo` lookups confirmed fixed, not just the spine's share: `Reservation__c` (fixed June 6) plus `Availability_Blackout__c.Fleet_Asset__c`, `Service_Line_Item__c.Service_Ticket__c`, `Service_Line_Item__c.Asset_Component__c`, `Fuel_Log__c.Fuel_Card__c`, `Asset_Insurance_Link__c.Insurance_Policy__c`, `Schedule_Exception__c.Fleet_Schedule__c`, `Schedule_Assignment__c.Fleet_Schedule__c` (user-confirmed visually, ~Aug 20). `Reservation__c.Priority__c` "Urget"→"Urgent" typo also fixed.
- [x] **17-object layout batch + 5 Name→AutoNumber conversions retrieved and committed** — commits `7eb711f`, `e15cc11`, `03f925f`. Auto-number formats: `ABO-{0000}`, `BAN-{0000}`, `ASN-{0000}`, `EXN-{0000}`, `SWN-{0000}`. Along the way, caught and fixed stale/missing FLS entries on 3 previously-undiscovered `Carbon_Log__c` fields plus a proper `destructiveChangesPost.xml` for the deleted duplicate `Carbon_Log__c.Fuel_Log__c` field.
- [x] **Branding fixed, activated, and retrieved into source** — root cause was editing the base Cosmos theme instead of a clone. Cloned to "Fleetforce Theme" (`0S1Wm00000003VlKAI`), activated, retrieved as 7 files (theme definition + 3 real ContentAsset images), commit `5d1e01e`.
- [ ] **⚠️ Theme activation is NOT capturable in metadata — permanent manual step on every fresh org spin.** After every future scratch org deploy: Setup → Themes and Branding → select "Fleetforce" → Activate. Needs folding into a formal spin-up runbook once one exists.
- [ ] **Open aesthetic question, undecided:** the Lightning App nav name "Fleetforce" now reads as redundant next to the new logo/wordmark. Discussed renaming to something functional (e.g. "Fleetforce Ops") to leave room for a future second app. No decision made.
- [x] **Full-scope SFDMU export complete** — decided to capture all 28 custom objects (not just the 9-object spine) since Antigravity had already populated everything and the data was reviewed-good. Pre-flight verified 3 previously-untracked objects (`Allocation__c`, `Asset_Component__c`, `Asset_Document__c`) plus discovered a 4th, `Maintenance_Plan__c`. Export: 32 CSVs, 867 records across 31 objects, cross-references resolved to human-readable columns. Commit `cebf987`.
- [x] **CumulusCI entered the toolchain** — `cumulusci.yml` committed (~Aug 23), pairs naturally with Snowfakery. Not yet discussed in depth — worth understanding its specific role next time it comes up.
- [x] **Org drift check clean after a 2-week gap** (checked 2026-09-06) — Apex (19/19) and object counts matched exactly between `fleetforce-dev-9` and source. First gap in this project's history that needed no rescue.
- [ ] **⚠️ 3 commits were unpushed as of 2026-09-06:** `7f5c6ea`, `1d6bf70`, `27648bc`. **Confirm these are now pushed.**
- [ ] **`fleetforce-dev-9` expiry** — had ~5 days left as of 2026-09-06 (~2026-09-11). Confirm status; decide whether a replacement org is needed.
- [ ] **Next real decision point, undecided:** extend the Snowfakery recipe to cover the remaining ~19 non-spine objects, or shift focus to packaging/TSO now that the 9-object spine has a proven seed mechanism.
- [ ] Two low-priority notes from an earlier deploy, still true: 6 `GlobalValueSet`s exist implicitly in-org but aren't separately tracked in source (fine to leave); a `caseTaskStatusPanel` LWC source-tracking poll timeout is a known 2.146.3 platform bug, component itself deploys fine.
- [ ] Test classes: 6 Apex classes originally lacked coverage; 75% threshold is the packaging gate. `FleetKpiControllerTest` was added ~Aug 21 — worth checking current coverage %.
- [ ] Named Credential migration — required before AppExchange security review, not before demos. Untouched.
- [ ] Draft flow cleanup — three `Fleetforce_*` draft flows with logic discrepancies vs. active counterparts. Untouched.
- [ ] KPI component v2 (Custom-Metadata-Type-driven configurable redesign) — deferred to v2. Untouched.

---

## 2026-09-06 — Post-vacation status check + history file repair

Picked back up after a ~2-week gap, using `fleetforce-dev-9`'s 5-remaining-days as the forcing function for a status check. Good news: both previously-requested Snowfakery recipe corrections were confirmed already applied, and the fresh-org validation run had actually happened and succeeded (204 records, 0 errors, ~Aug 21). Org/source drift check came back completely clean for the first time in this project's history. Found 3 commits still unpushed.

Separately: the working copy of this master history file had been lost when the sandbox holding it reset over the gap, and got reconstructed from chat scrollback — which turned out to be lossy compared to the user's actual current repo file. Comparing versions surfaced real header corruption from earlier in-place edits (two entries had lost their own `##` headers). **Decision: this file's log entries are now strictly append-only — only the Queued Work Orders checklist gets edited going forward.** Also decided: at the start of any future session, especially after a gap, ask for the current repo file directly rather than trust chat-memory reconstruction.

While reviewing the user's actual local session files against this reconstruction, found the same corruption pattern one layer down: the `2026-08-12-lesson-learned-and-logging-system.md` session file (meant to be write-once) had picked up a stray one-line append dated Aug 26 ("Repo cloned to Windows PC..."), tacked onto an already-closed session file instead of getting its own entry. Fixed by stripping it back to its original content. On investigation, the underlying Aug 26 event turned out to be a non-issue: a Windows machine was cloned in anticipation of working remotely during a 2-week trip, but no actual work happened on it — the user returned to working on the Mac exclusively. No multi-machine drift occurred; no action needed beyond the file cleanup itself.

## 2026-08-19/21/23 — Full-system relationship fixes, layouts, branding, SFDMU export, and Snowfakery build+validation

*(Dates approximate — reconstructed from commit metadata and screenshot timestamps.)*

Following the Aug 18 table design and Antigravity handoff (below): Antigravity completed the full data population and was reviewed as good. User discovered the org's actual custom object count (29, not 9) and proposed broadening scope; held the 9-object spine as the *recipe* validation target while agreeing to capture the already-populated full org via export.

User visually confirmed all 7 remaining broken `referenceTo` relationships from the May audit were fixed, plus the `Reservation__c.Priority__c` typo — closing an 8-item bug list open since May 9. Retrieved this plus a 17-object layout batch and 5 Name→AutoNumber conversions, catching incidental FLS drift on 3 `Carbon_Log__c` fields along the way.

Found and fixed a branding bug: the logo update had been made on the base Cosmos theme instead of a clone. Cloned to "Fleetforce Theme," activated, confirmed rendering, retrieved into source. Confirmed activation state isn't capturable in metadata. Briefly discussed (undecided) renaming the redundant-looking app nav label.

Decided to capture the full org as data rather than just the spine, since Antigravity's population was done and reviewed-good. Verified 3 previously-untracked objects plus discovered a 4th (`Maintenance_Plan__c`). Ran a full SFDMU export: 32 CSVs, 867 records, 31 objects.

Corrected a flawed first-draft Snowfakery plan from Code (wrong object list missing `Reservation__c`; load order violating 2 real FK dependencies). Locked the corrected 9-object scope, confirmed `Requestor_User__c`/`Approved_By__c` were scratch-org-admin artifacts (nulled in recipe). Recipe built (`fc64184`), tightened (driver-only reference scoping, violation-source category-gating), and validated end-to-end: 204 records, 0 errors.

## 2026-08-18 — Schema manifest, table design, and Antigravity handoff

Pulled a fresh, authoritative schema manifest for the 9-object spine (246 fields). Caught and fixed a source-tracking corruption plus a missing FLS permission-set assignment along the way. Cross-checked the old 21-issue schema-reconcile doc: 5 resolved, 12 were picklist drift, 4 fields genuinely missing — created 3 (`Authorized_Driver__c.Start_Date__c`/`End_Date__c`/`Restriction_Notes__c`), dropped 1 (`Account.Vendor_ID__c`). Resolved a modeling gap on `Account.Type` (no longer has vendor/insurer values — decided to leave blank, lean on `Industry`).

Discovered the org has 29 custom objects, not 9 — discussed broadening scope, decided against it at the time (motorpool-MVP lock, 2 objects known-broken, broader scope works against the security-review goal). Revisited later once relationship bugs were fixed (see entry above).

Designed the full 9-sheet table structure. Landed on the workflow: Antigravity writes directly into the org (letting Salesforce validation catch errors live), export to CSV becomes canonical afterward. Deployed 3 new `Authorized_Driver__c` fields, granted FLS in-org only (fixed properly later same day — see below). Wrote and handed off `antigravity-demo-data-plan.md`.

**FLS consolidation (same date):** found and fixed all 7 fields with in-org-only FLS grants never captured in source. Diff confirmed clean otherwise. Redeployed 0 errors, commit `6abebc1` — closed a failure mode that had recurred 3 times.
→ [full session notes](sessions/2026-08-18-schema-manifest-and-table-design.md)

## 2026-08-12 — Lesson-learned recap, status check, and full housekeeping

*(Consolidated from several same-day log fragments during the 2026-09-06 cleanup.)*

Reconnected after a ~2-month gap. Diagnosed why the Drive-based session log (set up 2026-05-10) had stalled after one entry, and why several June 6 work orders went unconfirmed. Found `PROJECT_MEMORY.md` stale and conflicting, flagged a leftover embedded instruction in it (not acted on). Agreed on this git-synced `docs/history/` system.

Ran a status check: 3 of 4 open June 6 items turned out done already (map controller repoint, Bucket 2 layouts, list view standardization) — just never checked off. Real gap: the demo data generator, never built. Also surfaced 25 unpushed commits, an obsolete stash, and an unlogged Aug 4 commit (reconstructed separately below).

Ran housekeeping end to end: pushed 25 commits, committed `PROJECT_MEMORY.md` deletion, updated CLI, spun up `fleetforce-dev-9` (clean 722/722 after patching 5 unrelated pre-existing issues), dropped the confirmed-obsolete stash, fixed shell PATH via a self-maintaining symlink. Housekeeping backlog fully closed by end of session.
→ [full session notes](sessions/2026-08-12-lesson-learned-and-logging-system.md)

## 2026-08-04 — Pre-break sweep (reconstructed 2026-08-12)

Reconstructed from commit `c1f1e62` — no log entry existed at the time. One large "flush before the break" commit (203 files): standard SFDC layout backfill (~130 files, unblocks clean deploys), demo dataset foundation files, and final Bucket 2 metadata polish. Reads as a checkpoint, not exploratory work.

## 2026-06-06 — TSO foundation cleanup + demo data architecture

Triaged May docs against the live org (already ahead of docs). Locked demo scope to motorpool-only MVP. Fixed `FleetKpiController` SOQL, locked KPI tile definitions. Full Bucket 1 layout pass, Bucket 2 work order written. List view standardization work order written. Designed the original demo data architecture (master `.xlsx`, `ref`/offset conventions, 9-object load order — precursor to the eventual SFDMU+Snowfakery approach). Corrected vehicle map source to `Fleet_Asset.Last_Location__c`.
→ [full session notes](sessions/2026-06-06-tso-foundation-and-demo-data.md)

## 2026-06-01 — Re-orientation after 23-day gap

Status check after a gap. Confirmed `fleetforce-dev-2` likely expired. Catalogued assets, identified 8 broken `referenceTo` lookups and dead dashboard KPIs as blocking. Agreed next actions: fix lookups, fix dashboard SOQL, spec the motorpool LWC.
→ [full session notes](sessions/2026-06-01-reorientation-23-day-gap.md)

## 2026-05-10 — Claude workflow setup + foundation cleanup

First working session. Set up claude.ai projects, established Drive as canonical (later superseded by this file). Locked product strategy ($15–30/vehicle/month, direct-sales-first). Full metadata audit surfaced 8 broken lookups, dead dashboard SOQL, invalid flow picklists, plaintext Geotab credentials, 6 untested Apex classes. Manual + Claude Code fixes applied. Git stash incident at session end — diagnosed and recovered.
→ [full session notes](sessions/2026-05-10-setup-and-foundation-cleanup.md)
