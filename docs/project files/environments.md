# FleetForce environments

Agreed 2026-11-01. Every org has one role. Nothing important lives only in an org: everything is in git and an org
can be rebuilt with one command (`scripts/new_org.sh`). Check this page before creating, deploying to or deleting
an org, and keep the table of current orgs up to date.

## Roles and rules

| Role                 | Org                                                                                  | Lifetime   | Gets code by                                                    | Rule                                                                                                           |
| -------------------- | ------------------------------------------------------------------------------------ | ---------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| **Packaging**        | `fleetforcePBO` (Dev Hub, the business org)                                          | Persistent | —                                                               | Owns the packages and the `fleetforce` namespace, creates scratch orgs. Never develop or demo here.            |
| **Develop**          | One scratch org per piece of work, alias `fleetforce-dev-<n>`                        | 30 days    | Source deploy                                                   | The only place source is deployed to. Rebuild rather than nurse an expiring org.                               |
| **Test the package** | Fresh scratch org per release, alias `fleetforce-pkgtest-<n>`, no namespace          | Hours      | Package install                                                 | Install the new version, run the checks in the release checklist, delete.                                      |
| **Demo**             | Scratch org with the package installed and demo data, alias `fleetforce-demo-<name>` | 30 days    | Package install (source only when a demo needs unreleased work) | No development. Rebuild for each event.                                                                        |
| **Released version** | `fleetforce-master-tso` (Trialforce source org, persistent until 2027-04-05)         | Persistent | Package install of **released** versions only                   | Holds the latest valid package and its setup. Trials are copied from it, so no source deploys, no experiments. |

Why development is not in a sandbox: the Apex names fields with the `fleetforce__` prefix, which only compiles in
an org that has the namespace. Scratch orgs from `fleetforcePBO` have it; sandboxes never do. The real quality gate
is the package version build (it runs every test in its own clean org) and a test install, not the dev org.

## Flow of a change

1. Develop in `fleetforce-dev-<n>` (source), commit to a branch.
2. Build a package version (`--code-coverage`), install it into a fresh `fleetforce-pkgtest-<n>` and check it
   (`docs/project files/package-release-checklist.md`).
3. Promote the version to Released and update `release-notes.md` (what is in each version, upgrade notes).
4. Install it into `fleetforce-master-tso`, do the manual steps in `manual-setup-steps.md`.
5. Demo orgs are rebuilt from the released version.

## Changing pages and layouts in the UI

Record pages, page layouts and similar screens are easier to design in Lightning App Builder or the layout editor
than in XML. Agreed 2026-11-01:

1. **Before:** Claude retrieves the page and layout from the dev org, so it has a baseline (and checks it matches
   git).
2. **Edit:** the user changes them in the UI of `fleetforce-dev-<n>` and saves. Pages that are already active need
   no re-activation. Say if a new page was created or an assignment changed: those are stored elsewhere.
3. **After:** Claude retrieves them again, compares with the baseline, explains each change and anything worth
   reconsidering, and copies the result into `force-app/` (renaming generated ids such as
   `Facet-fb7a20f1-...` to readable names). Further changes requested in words are made in source on top.
4. Deploy back to the dev org with `--ignore-conflicts` (the org copy is now older than source), check it, add the
   change to `release-notes.md` and commit.

Nothing stays only in the org: the next package version is built from source.

## One-command rebuild

```bash
./scripts/new_org.sh fleetforce-dev-13                       # develop: namespaced scratch org, source, demo data
./scripts/new_org.sh fleetforce-pkgtest-1 --package 04t...    # test: no namespace, installs that version, demo data
./scripts/new_org.sh fleetforce-demo-lisbon --package 04t... --multicurrency
./scripts/new_org.sh fleetforce-dev-13 --no-data              # empty org
```

It creates the org (30 days), deploys or installs, assigns the permission sets, trims the App Launcher and loads the
demo data (`scripts/load_demo_data.sh`). What it cannot do is listed in `manual-setup-steps.md` (theme and Home page
activation, the LWR site).

## Current orgs (update when one is created or deleted)

| Alias                   | Role                           | Expires    | Notes                                                                                                                                     |
| ----------------------- | ------------------------------ | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `fleetforcePBO`         | Packaging (Dev Hub)            | —          |                                                                                                                                           |
| `fleetforce-master-tso` | Released version               | 2027-04-05 | FleetForce Platform 1.0.0.8, no demo data. Next: 1.2.0 (see the 1.1.0 upgrade notes in `release-notes.md`).                               |
| `fleetforce-pkgtest-1`  | Test the package               | 2026-11-08 | 1.1.0.4 installed, four-country demo data. Delete once 1.2.0 is tested.                                                                   |
| `fleetforce-dev-12`     | Develop                        | 2026-11-30 | Regional work (phases A to C), four-country demo data. Default org (`sf config`).                                                         |
| `fleetforce-dev-13`     | Develop                        | 2026-12-03 | Routing module (`feature/routing-module`), source deploy, no demo data yet. Not the default org.                                          |
| `fleetforce-demo-mc`    | Demo                           | 2026-11-30 | Multi-currency (EUR corporate, GBP, USD, ILS). Source deploy for now: the regional work is not released yet.                              |
| `fleetforce-dev-11`     | Old demo                       | 2026-11-20 | Conference demo state (US data, before the regional work). Let it expire unless it is migrated (`scripts/migration/migrate_regional.sh`). |
| `true-subscriber-hub`   | Second Dev Hub (other account) | —          | For install tests from a different account. No active scratch org.                                                                        |

Other orgs connected to this machine (`aharai-prod`, `myProductionOrg`, `br7gdev`, `pss_dev_org`) belong to other
projects; FleetForce commands must never target them.
