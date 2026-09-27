# FleetForce — Package Release & Upgrade Checklist

> Repeatable procedure for cutting a new package version and getting it onto
> a real demo/subscriber org (e.g. `fleetforce-master-tso`). Written
> 2026-09-27, when this question first came up in practice: home screen
> components need polish, and the natural next step is "cut another
> version" — this doc is the checklist so that doesn't need re-deriving
> each time.

## Core facts this checklist depends on

- **Unlocked package**, namespace `fleetforce`, package name "FleetForce
  Platform" (see `sfdx-project.json`).
- An unlocked package version **upgrades in place** when installed over an
  existing install on the same org — it does not wipe org data. Seeded demo
  data, config, and records on a demo org survive an upgrade.
- A **Beta** version (`IsReleased: false`) can only be installed into
  **scratch orgs and sandboxes**. It can *never* be installed into a
  persistent, non-sandbox org (e.g. a real Developer Edition org or
  `fleetforce-master-tso`).
- Promoting a version to **Released is permanent** — it can never be
  un-released or deleted. Released versions are also immutable (no further
  changes to that exact version).
- The packaging promotion gate is **75% org-wide Apex coverage** (as of
  2026-09-27, actual coverage is 93%, comfortably clear).

## The practical consequence: batch, don't release-per-tweak

Because Release is one-way and Beta can't touch a persistent demo org,
the efficient loop is:

1. Do rough iteration (dashboard polish, new components, bug fixes) as
   normal commits against the working scratch/dev org (e.g. the current
   `fleetforce-dev-*` lineage), using Beta package versions for fast
   validation.
2. Let a few fixes accumulate rather than releasing after every single
   change.
3. Only when a batch is genuinely demo-ready, run the release steps below
   once, covering everything accumulated since the last release.

## Checklist: cutting and shipping a new version

1. **Bump the version number** in `sfdx-project.json`
   (`packageDirectories[0].versionNumber`, e.g. `1.0.0.NEXT` auto-increments
   the build number; bump `versionName` too if it's a meaningful milestone).
2. **Deploy and manually verify on a scratch/dev org first.** Don't skip
   this even for "small" changes — this project's history has repeated
   examples of changes that looked safe in source but broke on real
   package install (namespace prefixing, guest profile access, FLS grants
   not captured from UI edits). Use the existing "Subscriber org setup
   procedure" in `manual-setup-steps.md` for a true install-based test, not
   just a source deploy.
3. **Run the full Apex test suite** (`sf apex run test --target-org
   <alias> --code-coverage --result-format human` or equivalent) and
   confirm org-wide coverage stays at or above 75%. Note the actual number
   in the history log entry for this release.
4. **Create the package version:**
   ```bash
   sf package version create \
     --package "FleetForce Platform" \
     --installation-key-bypass \
     --wait 20
   ```
   This creates a new Beta version. Confirm it validates cleanly (no
   packaging-only errors like the locale-field / feature-gated-layout
   issues hit in the Sept 7 session).
5. **Decide: promote to Released, or stay Beta for now?** Only promote if
   this batch is meant to reach `master-tso` (or any other persistent org)
   now. If it's just for continued scratch-org iteration, leave it Beta and
   keep working — promotion is a deliberate, separate decision, not an
   automatic last step.
   ```bash
   sf package version promote --package "FleetForce Platform@<version>"
   ```
6. **Install (upgrade) into the target org:**
   ```bash
   sf package install \
     --package "FleetForce Platform@<version>" \
     --target-org fleetforce-master-tso \
     --wait 20 \
     --publish-wait 10
   ```
   Only a Released version will install into `master-tso` or any other
   persistent org.
7. **Verify live on the target org** — same spirit as the Motorpool
   guest-flow dry run: actually click through whatever changed, don't just
   trust the install succeeding.
8. **Log it.** Add a dated entry to `docs/history/fleetforce-project-history.md`
   with: what changed, the new version number, whether it was released,
   which org(s) it was installed/upgraded on, and current coverage %.

## When this checklist stops being enough (i.e., when CI/CD earns its keep)

This manual loop is the right amount of process for one maintainer and one
demo org. Revisit building actual CI/CD automation around this checklist
when any of the following becomes true — not before:

- More than one persistent org needs to stay in sync (e.g. a real design
  partner org in addition to the demo org).
- Someone other than the current solo maintainer is committing code.
- The release cadence becomes frequent enough that running these steps by
  hand is the actual bottleneck, not decision-making about what to ship.
