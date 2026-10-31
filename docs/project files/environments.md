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
3. Promote the version to Released.
4. Install it into `fleetforce-master-tso`, do the manual steps in `manual-setup-steps.md`.
5. Demo orgs are rebuilt from the released version.

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
| `fleetforce-master-tso` | Released version               | 2027-04-05 | FleetForce Platform 1.0.0.8, no demo data. Next: clean install of the regional release (phase D).                                         |
| `fleetforce-dev-12`     | Develop                        | 2026-11-30 | Regional work (phases A to C), four-country demo data. Default org (`sf config`).                                                         |
| `fleetforce-demo-mc`    | Demo                           | 2026-11-30 | Multi-currency (EUR corporate, GBP, USD, ILS). Source deploy for now: the regional work is not released yet.                              |
| `fleetforce-dev-11`     | Old demo                       | 2026-11-20 | Conference demo state (US data, before the regional work). Let it expire unless it is migrated (`scripts/migration/migrate_regional.sh`). |
| `true-subscriber-hub`   | Second Dev Hub (other account) | —          | For install tests from a different account. No active scratch org.                                                                        |

Other orgs connected to this machine (`aharai-prod`, `myProductionOrg`, `br7gdev`, `pss_dev_org`) belong to other
projects; FleetForce commands must never target them.
