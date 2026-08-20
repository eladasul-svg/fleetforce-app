# FleetForce — Project History

> Append-only log. Newest entry at the top. Each entry is a short paragraph;
> full detail lives in `sessions/YYYY-MM-DD-subject.md`.
>
> **At the start of every session:** read the "Queued Work Orders" section
> below first — it's the source of truth for what's actually done vs. just
> planned. Update it before wrapping any session.

---

## 🔧 Queued Work Orders (check/update this every session)

Status as of 2026-08-18:

- [x] Housekeeping backlog (push, stash, CLI, PATH) — fully closed 2026-08-12.
- [x] **Fresh schema manifest pulled** — 246 fields across the 9-object spine, confirmed against live `fleetforce-dev-9`. Surfaced and fixed a source-tracking corruption + missing FLS assignment along the way (see 2026-08-18 session).
- [x] **Table design locked** — all 9 sheets designed field-by-field, picklist drift resolved, scope decisions made (Account.Type skipped, Vendor_ID__c dropped, 3 new Authorized_Driver__c fields added).
- [x] **3 new `Authorized_Driver__c` fields deployed** — `Start_Date__c`, `End_Date__c`, `Restriction_Notes__c`. Live and FLS-granted in `fleetforce-dev-9`.
- [x] **FLS consolidation complete** — all 7 previously in-org-only grants (3 Authorized_Driver__c + 4 Service_Ticket__c approval fields) added to `permissionsets/FleetAdmin.permissionset-meta.xml`. Diff confirmed clean: no orphan grants from earlier sessions either. Redeployed 0 errors. Commit `6abebc1`. **Permission set is now fully reproducible from source — this failure mode is closed.**
- [x] **4 new Service_Ticket__c approval fields populated** — done via Antigravity during the original data population run, no separate top-up needed.
- [ ] **Antigravity data population** — plan doc handed off (`antigravity-demo-data-plan.md`), not yet run. 9-object spine, direct org write, 20–50 records per object depending on object, deliberate reservation conflicts required.
- [x] Page layouts pulled + committed — Authorized Driver, Service Ticket, Reservation. Commit `f0114ed`.
- [x] Name field → Auto Number, 3 objects — `Authorized_Driver__c` (`AUTH-{0000}`, "Authorization Number"), `Service_Ticket__c` (`ST-{0000}`, "Service Ticket Number"), `Telemetry_Violation__c` (`VIO-{0000}`, "Violation Number"). **Import template implication: `Name` is system-generated/read-only on these 3 objects — omit from master CSV.**
- [ ] **Export + reusable-template runner — now the only real open item.** Master CSVs (9 files + `_field-types.csv` companion) not yet exported. Once exported, still need: schema-sync instructions doc, and the load-order/ref-resolution/date-offset import runner script.
- [ ] **Full 20-object expansion — deliberately deferred, not forgotten.** Org actually has 29 custom objects total; scope is intentionally locked to the 9-object motorpool spine for now (2 of the remaining objects, `Availability_Blackout__c` and `Service_Line_Item__c`, are known-broken from the June 6 audit and shouldn't be touched without a dedicated fix session).
- [ ] Two low-priority notes from the deploy: 6 `GlobalValueSet`s exist implicitly in-org but aren't separately tracked in source (fine to leave); `caseTaskStatusPanel` LWC had a source-tracking poll timeout on deploy (known 2.146.3 platform bug, component itself deployed fine).

---

## 2026-08-18 — Schema manifest, table design, and Antigravity handoff

Shifted from housekeeping to actual demo-data planning. Had Code pull a fresh, authoritative schema manifest for the 9-object motorpool spine directly from `fleetforce-dev-9` — 246 fields. Along the way Code caught and fixed a real bug: a source-tracking corruption from an earlier rolled-back deploy had silently caused most custom fields to appear missing on describe, compounded by the admin user not having the `FleetAdmin` permission set assigned. Both fixed. Cross-checked the old `_schema-reconcile.md`'s 21 flagged issues against the live schema: 5 resolved by earlier work, 12 were just picklist value drift (xlsx authored against stale values), and 4 fields were genuinely missing. Decided to create 3 of those 4 (`Authorized_Driver__c.Start_Date__c`/`End_Date__c`/`Restriction_Notes__c`) and drop the 4th (`Account.Vendor_ID__c`) as out of scope. Also resolved a real modeling gap: live `Account.Type` no longer has vendor/insurer-style values (it's a generic sales-pipeline picklist now) — decided to leave it blank and lean on `Industry` instead, rather than force a schema change onto a standard object.

User discovered the live org actually has 29 custom objects, not 9 — raised whether to broaden scope for the Antigravity data-population pass. Discussed and explicitly decided **against** broadening: motorpool-MVP scope lock stands, 2 of the other objects are already known-broken and undebugged, and broader scope works against the "shortest path to security review" goal rather than helping it.

Designed the full 9-sheet table structure field-by-field (documented in full above/in chat — not duplicated here, see the master table design). Landed on a workflow shift for populating data: instead of hand-filling an Excel workbook, delegate to an Antigravity agent that writes **directly into the org**, letting Salesforce's own validation catch errors live; export to CSV afterward becomes the canonical dataset, which a separate deterministic script re-imports on every future org spin-up.

Deployed the 3 new `Authorized_Driver__c` fields (0 errors) and granted FLS — but the FLS grant was done directly in-org on the `FleetAdmin` permission set, not via metadata, so it won't survive a future org rebuild until it's added to source.

Wrote and handed off `antigravity-demo-data-plan.md` — a complete field-by-field population plan for the Antigravity agent, covering load order, realism constraints (synthetic VINs, no real personal data), and the deliberate double-booking conflicts needed to demo the reservation rules engine. Not yet run.

**Next session:** run the Antigravity agent against the plan, then build the export + reusable-template runner once real data exists to export.
→ [full session notes: pending — write once Antigravity run completes]

Closed out the last two housekeeping items. Dropped the May 10 stash (confirmed superseded, now empty). Fixed the shell PATH issue by pointing `~/.zshrc` at the `~/.local/share/sf/client/current` symlink rather than the version-pinned path — better than originally asked, since it self-updates on future `sf update` calls instead of needing a repo edit each time. Confirmed `sf --version` reports 2.146.3. **Housekeeping backlog is now fully closed.** Only remaining item before real dev work resumes: the demo data generator script.
→ [full session notes](sessions/2026-08-12-lesson-learned-and-logging-system.md)

## 2026-08-04 — Pre-break sweep (reconstructed 2026-08-12)

Reconstructed after the fact from commit `c1f1e62` — this session had no log entry at the time. A large "flush everything before the break" commit (203 files, ~17.5k lines) covering three unrelated things: (1) bulk-added ~130 missing standard Salesforce layout files (Account, Case, Contact, Opportunity, etc.) into source tracking — these unblock clean deploys to fresh scratch orgs, since Salesforce won't deploy custom layouts referencing standard objects that themselves lack tracked layouts; (2) committed the demo dataset foundation — `FleetForce_Demo_Dataset.xlsx`, `data/_schema-reconcile.md` (21 issues flagged across 9 objects vs. `fleetforce-dev-8`), and the generator work order spec; (3) final Bucket 2 polish on Authorized_Driver, Fleet_Schedule, and Contact metadata, plus the `caseTaskStatusPanel` LWC. No decisions or open questions recorded — this reads as a checkpoint commit, not exploratory work.

## 2026-08-12 — Housekeeping via Claude Code

Ran the housekeeping work order end to end. Pushed all 25 backlogged commits to `origin/main` (nothing had been pushed since before June). Committed the `PROJECT_MEMORY.md` deletion. Updated the CLI (2.121.7 → 2.146.3 — note: shell `PATH` still resolves to an old binary, needs a profile fix). Spun up a fresh scratch org, `fleetforce-dev-9` (expires ~2026-09-11); first deploy failed on 5 pre-existing metadata issues unrelated to FleetForce (disabled Solutions feature referenced in 4 standard Case layouts, one invalid list view `filterScope`) — patched and redeployed clean, 722/722 components. Sanity-checked list views, KPI-relevant object queryability, and Bucket 2 fields — all good; KPIs read zero as expected since no demo data is loaded yet. Assessed the May 10 stash: every file in it is superseded by June/August commits, safe to drop — held for explicit confirmation before discarding. Also reconstructed the Aug 4 "mystery commit" (see entry above) by reading its diff, closing the gap in this log.

**Remaining before real dev work resumes:** demo data generator script (still not built — this is now the critical path item), and a decision on the May 10 stash.
→ [full session notes](sessions/2026-08-12-lesson-learned-and-logging-system.md)

Ran a read-only status check through Claude Code to reconcile the queued work orders against reality. Good news: three of four open items from June 6 turned out to be done (map controller repoint, Bucket 2 layouts, list view standardization) — they just were never checked off. The real remaining item is the demo data generator: `seeder.py` and a schema-reconcile pass exist, but the spec'd xlsx → `sf data import tree` generator was never built. Also surfaced: no active scratch org (`fleetforce-dev-2` is gone), 25 commits sitting unpushed to `origin/main`, one likely-obsolete stash from May 10, and — most notably — a commit from **2026-08-04** ("Last commit before summer break") that isn't accounted for in any session record. That's a real gap in the log we just built: a session happened that neither the old Drive log nor conversation history captured. Need to reconstruct what it covered.
→ [full session notes](sessions/2026-08-12-lesson-learned-and-logging-system.md)

## 2026-08-12 — Lesson-learned recap + session-log system

Reconnected after a ~2-month gap since the last working session (June 6). Reviewed conversation history to reconstruct where things stood, since no running log existed to check directly — confirmed the Drive-based session log set up on 2026-05-10 only ever got one entry before stalling, likely because it lived one hop away (Drive) from where work actually happens (git repo + Claude Code). Diagnosed a second failure mode: several work orders from the June 6 session were written and handed off but never confirmed done, with nothing tracking "planned" vs. "executed." Found `PROJECT_MEMORY.md` in project knowledge to be stale (Feb 3) and actively conflicting with `current-state.md` on namespace handling; it also contains a leftover embedded instruction, flagged and not acted on. Agreed on a git-synced `docs/history/` system: this master file (short entries, pinned queued-work-orders section) plus a `sessions/` folder for full detail. Next step is confirming actual scratch org and repo state before planning further work.
→ [full session notes](sessions/2026-08-12-lesson-learned-and-logging-system.md)

## 2026-06-06 — TSO foundation cleanup + demo data architecture

Major session. Triaged the May data-model docs against the live org and found the org already ahead of documentation (Reservation lookups already correct — item reduced to deleting one duplicate field, `Dest_Branch__c`). Locked demo scope to **motorpool-only MVP**, deferring maintenance-path fixes. Fixed `FleetKpiController` SOQL and locked KPI tile definitions (Active Fleet, In Shop, Critical Violations, Open Tickets). Completed a full layout pass on Bucket 1 objects (Fleet Asset, Fleet Branch, Service Ticket, Telemetry Violation, Reservation) and wrote a Bucket 2 work order. Wrote a list view standardization work order (28 objects, uniform "All" view + 4 named views for dashboard navigation). Designed and built the demo data architecture: one master `.xlsx` with per-object sheets, tree-import plan with `ref`/`*__ref` columns for relationship resolution, offset-date logic so time-sensitive tiles stay perpetually current, spine of 9 objects in topological load order, all 17 cross-reference relationships validated. Corrected the vehicle map data source to `Fleet_Asset.Last_Location__c` (flagged map controller repoint as a follow-on task). Wrote a generator script work order for Code.
→ [full session notes](sessions/2026-06-06-tso-foundation-and-demo-data.md)

## 2026-06-01 — Re-orientation after 23-day gap

Status check after a gap. Confirmed scratch org `fleetforce-dev-2` likely expired (last synced 2026-05-08). Catalogued current assets (30 custom objects, 20 Apex classes, 6 LWCs, 8 flows, Geotab sync). Identified two blocking bugs: 8 broken `referenceTo` lookups pointing to `Account` instead of correct targets, and dead dashboard KPIs from `FleetKpiController` querying non-existent picklist values. Secondary issues noted: plain-text Geotab password, 6 Apex classes without test coverage, possible duplicate-flow double-firing. Agreed next three actions: confirm/recreate scratch org + fix lookups, fix dashboard SOQL, spec (not build) the motorpool LWC.
→ [full session notes](sessions/2026-06-01-reorientation-23-day-gap.md)

## 2026-05-10 — Claude workflow setup + foundation cleanup

First working session in the new Claude project structure. Set up three claude.ai projects (Product & Engineering, Go-to-Market, Legal & Partnership), established Drive as canonical for living docs (mirrored to `docs/decisions/` in the sfdx repo), and created the original `fleetforce-session-log.md` (this file supersedes it). Locked product strategy: platform + curated flagship LWCs + add-on marketplace model, pricing target $15–30/vehicle/month, direct-sales-first distribution. Claude Code retrieved and audited full org metadata, surfacing 8 broken Account-pointing lookups, non-functional dashboard SOQL, invalid flow picklist values, plain-text Geotab credentials, and 6 untested Apex classes. Manually fixed 7 of 8 broken lookups, picklist issues, and validation rules in the org UI; Claude fixed `FleetKpiController` SOQL and `fleetMapTracker.js` in chat, deployed via Claude Code. Session ended with a git stash incident (untracked files swept by `-u` flag) — diagnosed and recovered.
→ [full session notes](sessions/2026-05-10-setup-and-foundation-cleanup.md)
