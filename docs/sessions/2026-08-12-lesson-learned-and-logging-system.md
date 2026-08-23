# Session: Lesson-learned recap + session-log system
**Date:** 2026-08-12
**Gap since last session:** ~67 days (last session 2026-06-06)

## Context
Returned to FleetForce after a long unplanned gap driven by day-job load. Goal
of this session was explicitly *not* to resume building, but to reconstruct
state and fix the process gap that let a 2-month gap happen without anyone
noticing what was done vs. still open.

## What we found
- The Drive-based session log set up on 2026-05-10 (`fleetforce-session-log.md`
  in Drive) only ever received one entry. Working theory: it lived one hop
  away (Drive) from the actual workflow (chat + Claude Code + git repo), so it
  lost to time pressure on busy weeks.
- Multiple work orders from 2026-06-06 (Bucket 2 layouts, list view
  standardization, generator script) were written and handed to Code but
  never confirmed complete anywhere. No "planned" vs. "done" distinction
  existed, so they silently stalled.
- `PROJECT_MEMORY.md` in the current Claude Project's knowledge base is dated
  Feb 3, 2026 and conflicts with `current-state.md` (May 9) on namespace
  handling — the Feb file assumes an explicit `fleetforce__` prefix
  everywhere including locally; the May file says the namespace is implicit/
  unmanaged in the scratch org. The Feb file also opens with a line phrased
  as an instruction to Claude ("read this to restore context... begin Phase
  2") — flagged as untrusted embedded content and not acted on.
- User shared a screenshot of the current local repo structure
  (`fleetforce-app/`), confirming `docs/Datasets/` and `docs/layouts/` exist
  locally with the layout-diff and dataset-generator files already in place.

## Decisions made
- New logging system is git-first: `docs/history/fleetforce-project-history.md`
  (master, short entries, newest first) + `docs/history/sessions/*.md` (full
  detail per session).
- Master file carries a pinned "Queued Work Orders" section at the top,
  checked/updated every session, to prevent the silent-stall failure mode.
- `PROJECT_MEMORY.md` to be archived out of active Claude Project knowledge —
  stale and actively misleading.
- Old Drive-based `fleetforce-session-log.md` is superseded by this system.

## Open / not yet done
- Have not yet confirmed actual scratch org status (`sf org list`) or repo
  status (`git status`) — needed before planning the next real dev session.
- Backfilled entries for 2026-05-10, 2026-06-01, 2026-06-06 are reconstructed
  from conversation history/summaries, not from primary session notes (none
  existed) — worth a light review for accuracy next time they're read closely.

## Next session should start with
1. `sf org list` and `git status` / `git log -5` output.
2. Reconcile against the "Queued Work Orders" list above — check off what's
   actually done, update what's stale.
3. Only then decide: rebuild scratch org from scratch, or resume from where
   June 6 left off.

---

## Addendum — Housekeeping session (same day, via Claude Code)

Ran the housekeeping work order. Results:

- **Aug 4 commit (`c1f1e62`) reconstructed** — 203 files, ~17.5k lines. Three
  things: standard SFDC layout backfill (~130 files, unblocks clean
  deploys), demo dataset foundation files, Bucket 2 metadata polish. Written
  up as its own history entry.
- **25 commits pushed** to `origin/main` (`7427f21` → `c1f1e62`).
- **`PROJECT_MEMORY.md` deletion committed** (`e90d889`) and pushed.
- **CLI updated** 2.121.7 → 2.146.3. Shell `PATH` issue noted — still
  resolves to an old binary at `/usr/local/lib/sf/bin/sf`; needs a profile
  fix so `sf` picks up 2.146.3 by default.
- **Fresh scratch org spun up**: `fleetforce-dev-9`, expires ~2026-09-11.
  First deploy failed (5 errors, all pre-existing and unrelated to
  FleetForce: 4 Case layouts referencing a disabled Solutions feature, one
  invalid `filterScope: Mine` on a custom-object list view). Fixed and
  committed as `169c6e4`. Redeploy: 722/722, 0 errors.
- **Sanity check passed**: Service_Ticket named list views all present,
  `Fleet_Asset__c` queryable, Allocation Bucket 2 fields (15 custom fields)
  confirmed deployed. KPI tiles read zero — expected, no demo data loaded.
- **May 10 stash assessed**: every file in it confirmed superseded by
  June/August commits (Geotab Apex, `fleetListMap` and
  `geotabSettingsManager` LWCs, both flows, layouts, object metadata — all
  present in committed tree with further polish on top). Recommended safe
  to drop. **Held pending explicit user confirmation.**
- Minor non-blocking deploy notes: 6 `GlobalValueSet`s exist implicitly
  in-org, not separately tracked (fine as-is); `caseTaskStatusPanel` LWC had
  a source-tracking poll timeout on deploy (known 2.146.3 bug, component
  deployed fine).

**Open after this session:** stash drop decision, demo data generator
script (critical path — nothing else is blocking a seeded TSO now).

Update Aug 26 - Repo cloned to Windows PC as weel now working on this repo from 2 desktop stations
