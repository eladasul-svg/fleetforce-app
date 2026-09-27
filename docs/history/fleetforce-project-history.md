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

Status as of 2026-09-27, third pass (guest reservation transport fixed; `fleetforce-master-tso` identified — see entries below):

- [x] FleetAdmin permset FLS completed (48 previously-missing fields), Fleetforce Admin profile `ViewSetup` fix, obsolete `unpackaged/` portal duplicates removed — portal now ships only in the package, no more dev-org-vs-package overwrite race. (commit `ac9aa2e`, 2026-09-18)
- [x] **FleetForce Assistant shipped** — new `fleetforceAssistant` LWC (utility bar, Home sidebar, Fleet Asset record page) backed by the Claude Messages API, with org-key and personal-key auth paths, a 6-tool tool-loop (list/describe/query/get + create/update proposals gated on user approval before any DML), and session/message persistence. 32 new tests, full suite 71/71 passing, 92% org-wide coverage. (commit `7bdeea7`, 2026-09-18) **Confirmed live 2026-09-27:** renders correctly on the Home page in `fleetforce-dev-10` (connection-setup card, since no API key is configured yet — correct default state).
- [x] `fleetforce-dev-9` fully retired — it expired as flagged in the 2026-09-06 entry. `fleetforce-dev-10` is the new dev org (created 2026-09-18, expires **2026-10-18**), already repointed as the Motorpool site admin (`ac9aa2e`). All 4 commits from this stretch (`26a3217`..`7bdeea7`) were pushed to `origin/main` 2026-09-27 after confirming 71/71 tests pass on `fleetforce-dev-10`.
- [x] **Motorpool guest portal submission regression (found earlier 2026-09-27) fixed same day, commit `5199a03`.** Root cause: guest Apex Remoting (`@RemoteAction`, `/apexremote`) 503s on Force.com Sites in this org — a different code path from the page-routing 503s fixed in the 2026-09-07/08 session, so that fix didn't cover it. Replaced the transport with an unauthenticated `@RestResource`/`@HttpPost` endpoint (`/services/apexrest/fleetforce/motorpoolReservation` — namespace prefix required, or it 404s). Updated both `InMaintenance.page` (the one actually served) and `MotorpoolPortal.page` (kept in sync). **Verified end-to-end through the real guest UI on `fleetforce-dev-10`:** submission succeeds, record lands in `fleetforce__Reservation__c` with `Status__c = 'Pending'`. Added `MotorpoolPortalControllerTest` (3 tests; class had zero coverage before). Full suite 74/74, org-wide coverage 93%.
- [x] **`fleetforce-master-tso` identified.** User authenticated it (`sf org login web`) — it's a real, persistent **Enterprise Edition** org (not scratch, not sandbox), `NamespacePrefix: null` (correctly doesn't own the `fleetforce` namespace), trial expiration **2027-04-05**, and — critically — **`CreatedDate: 2026-04-04`, months before this project's own history log starts (2026-05-10).** It was never touched by any logged session because it predates this whole Claude-Code-tracked workstream; almost certainly provisioned once during initial Salesforce Partner Program / Environment Hub onboarding and then forgotten. **It is completely blank** — zero packages installed, zero FleetForce custom objects, zero Sites. Nothing to fix or verify there yet.
- [ ] **⚠️ The Sept 27 REST-endpoint fix cannot reach `fleetforce-master-tso` directly, and this is a hard platform rule, not a gap in the fix.** `sf package version list` confirms `FleetForce Platform` 1.0.0.6 has `IsReleased: false` (still Beta), and Salesforce only allows installing unreleased/Beta unlocked package versions into **scratch orgs and sandboxes** — never into a persistent org like this one. Path to actually get FleetForce (and the fix) onto it: cut a new version incorporating the fix → **promote to Released** (org-wide coverage 93%, well above the 75% gate) → `sf package install` the Released version into `fleetforce-master-tso`. Promoting a version is one-way (can't un-release), so this needs an explicit go-ahead, not a side effect of a bug fix.
- [ ] **Final consolidated sanity check on `true-sub-test`** — branding/logo, app name, dashboard KPI tiles — still not confirmed done (carried over from 2026-09-07, no evidence found this happened).
- [ ] **`MotorpoolGuestFlow` permset cleanup** — still not confirmed done; no reference to it found anywhere in current `force-app`/`unpackaged` metadata, so status is genuinely unknown (carried over from 2026-09-07).
- [ ] **Promote 1.0.0.6 (or a new 1.0.0.7 with the REST fix) to Released, then install into `fleetforce-master-tso`** — this is now the concrete next milestone: `fleetforce-master-tso` is a real ~6-month-runway persistent org, so once a Released version lands on it, it becomes a genuinely viable non-expiring demo backend, no Environment Hub/Trialforce templating strictly required unless multi-tenant cloning is actually needed.
- [ ] Deferred guest portal product decisions: missing `Preferred_Engine__c`/`Preferred_Body__c` collection, no date-range validation, no guest confirmation email/reference number.
- [ ] Strategic note, not urgent: Motorpool portal runs on legacy Force.com Sites Classic, not modern Experience Cloud — worth a deliberate future migration decision given the strategy doc's positioning.
- [ ] `geotabSettingsManager` polish items (spinner overlap, password-in-JS-state, alert styling) — admin-only, low priority.
- [ ] Named Credential migration — required before AppExchange security review, not before demos. Untouched.
- [ ] Draft flow cleanup — three `Fleetforce_*` draft flows with logic discrepancies vs. active counterparts. Untouched.
- [ ] KPI component v2 (Custom-Metadata-Type-driven configurable redesign) — deferred to v2. Untouched.
- [ ] CI/CD design — the explicit next phase after TSO MVP ships. Not yet started.

---

## 2026-09-27, part 3 — `fleetforce-master-tso` identified: real, persistent, and completely blank

User authenticated `fleetforce-master-tso` (`sf org login web`), unblocking the investigation part 2 had to leave open.

`sf org display` plus a direct `Organization` SOQL query gave the full picture: it's a genuine **Enterprise Edition, non-sandbox, non-scratch** org — a real persistent deploy target, not a clone-template-only artifact — with a trial expiration of **2027-04-05** and, tellingly, a `CreatedDate` of **2026-04-04**. That's before this project's own history log even starts (2026-05-10), which resolves the "was this set up in an unlogged session?" question from part 2: it wasn't part of any session this log would have captured at all — it's almost certainly a leftover from initial Salesforce Partner Program / Environment Hub onboarding, created once and never touched again on the FleetForce side. `NamespacePrefix` is correctly `null` (it doesn't own the `fleetforce` namespace, as expected for a genuine subscriber-style org).

It is, however, **entirely empty**: `sf package installed list` returns nothing, and direct queries confirm zero FleetForce custom objects and zero Sites. There's no Motorpool portal to test there — step 4 of the request (reproduce the guest flow) had nothing to reproduce against.

Checked whether today's REST-endpoint fix could go straight onto it. `sf package version list` shows `FleetForce Platform` 1.0.0.6 with `IsReleased: false` — still Beta. Unreleased unlocked package versions can only install into scratch orgs or sandboxes, a real Salesforce platform restriction (already flagged as a risk in the Sept 7 session's own TSO research) — not something fixable from this side. So the fix genuinely cannot reach this org yet, through no fault of the fix itself.

Net position: `fleetforce-master-tso` is a real find — a persistent, non-expiring-soon (~6 months) org that, once a Released package version lands on it, becomes a legitimate demo/staging backend without depending on scratch-org lifecycles at all. Getting there needs a deliberate promote-to-Released decision, which is left for the user rather than taken as a side effect of this session.

## 2026-09-27, part 2 — TSO investigation blocked; Motorpool guest reservation transport fixed

Follow-up same day to the status-check entry above. Two goals: find and assess `fleetforce-master-tso` (a name the user referenced as if it should already exist), and fix the Motorpool guest-submission regression found in part 1.

**`fleetforce-master-tso`: not found, not authenticated, not documented.** Checked `sf org list`, `~/.sfdx/alias.json` (which has every org this project has ever touched, back to `fleetforce-dev-2`), and grepped the whole repo — no trace. This is either an org set up in an unlogged session (the same failure mode that lost the Sept 18 Assistant work until this session's history sweep caught it) or one that was planned but never actually created. Genuinely blocked here: authenticating a new org needs either its login URL or the user completing an OAuth login themselves, and guessing at either would be worse than asking. Parts 2 and 3 of the requested work (installed-package-version check, reproducing the guest flow there) couldn't proceed without it.

**Motorpool guest reservation transport: root cause found and fixed.** The 503 flagged in part 1 turned out to be specific to VF Remoting (`@RemoteAction`, served at `/apexremote`) on this org's Force.com Site — a different failure than the page-routing 503s the Sept 7–8 session chased down, so that fix didn't cover it. Rebuilt `MotorpoolPortalController.submitReservation` as an unauthenticated `@RestResource`/`@HttpPost` endpoint instead. First attempt (`/services/apexrest/motorpoolReservation`, no namespace) 404'd; a raw `fetch()` probe from the live page found the actual working path requires the namespace prefix (`/services/apexrest/fleetforce/motorpoolReservation`) — consistent with the rest of this codebase already assuming the `fleetforce` namespace is present at runtime in this org. Updated the JS in both `InMaintenance.page` (the page Site actually serves, per `indexPage`) and `MotorpoolPortal.page` (kept in sync — this project has been bitten before by two copies of the same page drifting apart). Hit one dead end along the way: the browser pane kept showing stale JS after each deploy even in a brand-new tab, which turned out to be normal `Cache-Control: public, max-age=600` HTTP caching on the Site's edge, confirmed by comparing against a fresh `curl` — not a platform bug, just needed a genuinely cache-busted request to verify.

Verified for real: filled out the reservation form through the live guest portal UI end-to-end, got "Request Submitted!", and confirmed via SOQL that the record actually landed (`fleetforce__Status__c = 'Pending'`). Added `MotorpoolPortalControllerTest` (3 tests — the class had zero dedicated coverage before this). Full suite 74/74 passing, org-wide coverage 93% (up from 92%). Cleaned up the throwaway test records created while probing the endpoint. Committed and pushed (`5199a03`).

Net effect: the guest portal is now genuinely closer to "confirmed working end-to-end" than it was after Sept 7–8 — that session's claim covered page load, not submission, and submission was actually broken until today. Promotion to Released is still gated on resolving the `fleetforce-master-tso` question above.

## 2026-09-18 — FleetAdmin FLS/permission fixes and the FleetForce Assistant

Two commits, same day. First, closed out permission debt left over from the Sept 7–8 packaging push: `FleetAdmin` permset was missing FLS on 48 packaged custom fields (`Guest_Email__c`, `Battery_Capacity_kWh__c`, `Violation_Source__c`, most `Service_Ticket__c` fields, and others) — seed data and real admins couldn't write them. Also fixed the `Fleetforce Admin` profile deploy by adding `ViewSetup` (a prerequisite for `ViewFlowUsageAndFlowEventData`), and removed the obsolete `unpackaged/` copies of the portal page/controller (`InMaintenance.page`, `FleetforceMotorpool.page`, `FleetforceMotorpoolController`) now that the portal ships in the package — those duplicates had been silently overwriting the packaged page on every dev-org deploy. Repointed the Motorpool site admin at the new dev org, `fleetforce-dev-10` (the previous `fleetforce-dev-9` had expired).

Second, and larger: built the **FleetForce Assistant**, a Claude-backed chat LWC surfaced in the utility bar, the Home sidebar, and the Fleet Asset record page. Two auth paths — an org-wide key via a Named/External Credential, or a personal key per user via a protected hierarchy custom setting (Custom protocol credentials can't have per-user principals, so the personal path calls Anthropic directly through a Remote Site). The assistant runs a 6-tool loop (list/describe/query/get objects, plus create/update) with writes staged as proposals the user must explicitly approve before any DML runs in `USER_MODE`. History persists in two new objects (`Assistant_Session__c`/`Assistant_Message__c`), trimmed at user-text boundaries to keep tool call/result pairs intact. 32 new tests; full suite 71/71, org-wide coverage 92%.

Both commits sat unpushed until the 2026-09-27 status check below.

## 2026-09-27 — Post-gap status check, push, and a real portal regression found

Picked up cold after the Sept 18 session with no open thread — treated as a standard status-check sweep. `fleetforce-dev-9` was confirmed gone from `sf org list` (expired, as anticipated); `fleetforce-dev-10` (created 2026-09-18, the Sept 18 commits already pointed at it) is the live dev org, expiring 2026-10-18. Ran the 3 new Assistant test classes (32/32 pass) and then the full local suite (71/71 pass, 92% coverage) before pushing — nothing regressed. Pushed the 4 commits that had been sitting local since Sept 18 (`26a3217`..`7bdeea7`).

Then did the live verification the previous session's commit messages had claimed but this session hadn't independently checked: opened `fleetforce-dev-10` and confirmed the FleetForce Assistant renders correctly on the Home page (connection-setup card, since no key is configured — correct default). Opening the Motorpool portal surfaced a real problem: the page itself still loads fine (HTTP 200, as before), but actually submitting a reservation now fails at Step 2 with "Unable to connect to the server." — the guest Apex Remoting call (`POST /motorpool/apexremote`) returns HTTP 503. This is the same failure family as the Sept 7–8 session's page-routing 503s, but on the remoting endpoint rather than page routing, so the `indexPage=fleetforce__InMaintenance` fix didn't cover it. The guest profile already grants class access to `MotorpoolPortalController` in source (checked both namespaced and non-namespaced variants), so it isn't a simple FLS miss — needs a live Setup-UI investigation (guest user debug logs) rather than further metadata guessing. This directly contradicts the "confirmed working end-to-end" claim from Sept 7–8 and blocks promoting the package to Released until resolved.

## 2026-09-07 — Component polish, Apex coverage 30%→94%, and the full TSO packaging journey

Long, dense session covering two stated goals: polish live components against real seed data, and push toward an actual TSO MVP. Full narrative, all findings, and lessons learned are in the dedicated session file — this entry is deliberately brief.

**Component work:** deleted an unrelated-project component (`caseTaskStatusPanel`), fixed map zoom/sort/click-through bugs on the two other dashboard widgets, and fully rewrote `fleetListMap` after discovering it was likely completely non-functional (illegal `cacheable=true` + callout combination). Also resolved a CustomApplication naming mystery — the "Fleetforce" app had been renamed to "FleetOps" directly in the org UI weeks earlier and never retrieved into source.

**Apex coverage:** went from an unmeasured baseline (turned out to be 30%) to 94%, closing the real packaging gate. Caught a genuine production bug in `GeotabService` along the way.

**Packaging:** created the first-ever package for this project, iterating through 6 versions as real validation and installation bugs surfaced — a namespace/name collision (resolved cleanly, no deletion needed), a proper `unpackaged/` vs. `force-app` architectural split (profiles and standard layouts don't belong in packages), a global-Quick-Action packaging bug, and a real production bug in Geotab credential handling that only packaging exposed.

**The big one:** the Motorpool guest reservation portal — the flagship demo differentiator — had never been tested all session. Found it completely broken (3 blockers), fixed two cleanly, and spent most of the session's back half chasing the third: an HTTP 503 that took a full architecture investigation, an abandoned Screen Flow approach, a false-positive "subscriber test" (same Dev Hub, source deploy — correctly caught and rejected), and finally a genuinely separate Dev Hub test to reach a conclusive, evidence-based answer: the 503 is a real, universal Force.com Sites platform limitation with an exact, permanent, confirmed fix.

Session ends with the portal and dashboard both verified working in a true subscriber context — a genuinely solid checkpoint before promoting to Released and creating the actual TSO.
→ [full session notes](sessions/2026-09-07-component-polish-and-tso-packaging.md)

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
