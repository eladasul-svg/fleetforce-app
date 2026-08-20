# Session: Claude workflow setup + foundation cleanup
**Date:** 2026-05-10 (covers work from 2026-05-09 continuing into 05-10)
**Note:** Reconstructed from conversation summary and partial chat log on
2026-08-12 (this is the session that created the now-superseded Drive-based
log).

## Claude workflow setup
- Three claude.ai projects created: Product & Engineering, Go-to-Market,
  Legal & Partnership.
- Drive established as canonical home for living docs, linked into project
  knowledge, mirrored to `docs/decisions/` in the sfdx repo.
- Original `fleetforce-session-log.md` created in Drive — received one entry
  (this session) then stalled. **Superseded by the git-based
  `docs/history/` system as of 2026-08-12.**
- Working preferences established: plan in chat, build in Claude Code; Code
  used conservatively (manual org-UI fixes preferred for simple metadata
  changes); bite-sized work orders given weekend-only availability.

## Product strategy decisions
- v1 architecture: platform + curated flagship LWCs + add-on marketplace
  (nCino/Veeva/Novidea pattern, not a monolithic app like Fleetio).
- Pricing target: $15–30/vehicle/month.
- Distribution: direct sales first to owned-fleet mid-market (50–400
  vehicles); FMC white-label conversations only after 3–5 direct reference
  customers.
- Open questions deferred to discovery: which 1–2 wedge use cases, which
  vertical to lead with, specific design partner names.

## Technical audit
Claude Code retrieved and summarized full org metadata (30 custom objects,
20 Apex classes, 6 LWCs, 8 flows), surfacing:
- 8 broken Account-pointing lookups
- Non-functional dashboard SOQL
- Invalid flow picklist values
- Plain-text Geotab credentials
- 6 Apex classes with no test coverage

## Cleanup performed
- User manually fixed 7 of 8 broken lookups, picklist issues, and validation
  rules in the org UI.
- Claude provided corrected `FleetKpiController` Apex (fixed SOQL status
  filters; switched `getAssetLocations` to query
  `Fleet_Asset__c.Last_Location__c` directly instead of `Telemetry_Raw__c`)
  and updated `fleetMapTracker.js` to match. Deployed and verified via
  Claude Code.

## Incident
Git stash incident at session end: untracked files (`docs/`, `CLAUDE.md`,
other untracked metadata) were swept into a stash by the `-u` flag, making
the docs folder appear empty. Diagnosed and recovered via
`git checkout stash@{0} -- docs/ CLAUDE.md`.

## Output files from this session
`fleetforce-claude-setup.md`, `fleetforce-strategy.md`,
`fleetforce-session-log.md` (now superseded).
