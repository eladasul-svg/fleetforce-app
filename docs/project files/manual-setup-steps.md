# FleetForce — Manual Setup Steps (Non-Metadata-Deployable)

> These steps cannot be captured in source or automated via `sf project 
> deploy`. They must be done via Setup UI. Keep this list current as more 
> are discovered — check it before any TSO configuration or fresh scratch 
> org spin-up.

---

## One-time steps for the actual TSO (needed once, persists after)

These apply to configuring the real Trialforce Source Org. Since a TSO is 
a persistent org (not re-spun like a scratch org), these are done once.

1. **Activate the "Fleetforce" theme** — Setup → Themes and Branding → 
   select "Fleetforce" → Activate. `LightningExperienceTheme` metadata 
   captures the theme definition but not which theme is active.
   (Discovered 2026-08-20.)

~~2. **Enable "Let site guest users run flows"**~~ — **No longer applicable.**
   The Motorpool guest portal was rebuilt as a native Visualforce form with
   a `@RemoteAction` Apex controller (`MotorpoolPortalController`), bypassing
   Screen Flow entirely. Guest users never invoke `FlowRuntimeConnect.startFlow`,
   so no flow-access org preference is needed. The "Process Automation Settings"
   page was removed from Setup in a recent release and the underlying
   `enableFlowsLightningApp` field cannot be set via Metadata API or Tooling API —
   the VF+RemoteAction approach is the correct architecture for Force.com Sites
   Classic guest portals.
   (Resolved 2026-09-07.)

---

## Per-scratch-org steps (needed every fresh scratch org spin, dev-cycle only)

These do NOT apply to the TSO itself — they're artifacts of scratch org 
metadata portability, not relevant to a persistent org with real users.

1. **Update Motorpool site's `siteAdmin` / `siteGuestRecordDefaultOwner`** 
   — `Motorpool.site-meta.xml` hardcodes a scratch-org admin username. 
   Every new scratch org has a different auto-generated admin username 
   (e.g. `test-8krhiycuuqa1@example.com`), so this must be updated to the 
   new org's actual admin after each fresh spin, or the site falls back 
   to the "InMaintenance" page.
   (Discovered 2026-09-07.)

---

## Subscriber org setup procedure (validated 2026-09-07 on `fleetforce-sub-test`)

Full end-to-end steps to stand up a subscriber-style scratch org from scratch.

### 1. Create the scratch org

```bash
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias fleetforce-sub-test \
  --duration-days 7 \
  --target-dev-hub <your-devhub-alias>
```

### 2. Deploy the full unpackaged metadata

```bash
sf project deploy start \
  --source-dir unpackaged/main/default \
  --target-org fleetforce-sub-test \
  --wait 20
```

This deploys ~29 custom objects, the Motorpool Force.com Site, VF pages,
Apex classes, profiles, permission sets, and all supporting metadata.

### 3. Update the site admin username

`Motorpool.site-meta.xml` hardcodes a username that won't match the new org.
After deploy, open the site in Classic Setup and correct `siteAdmin` /
`siteGuestRecordDefaultOwner` to the new org's admin user — **or** update
the file before deploying:

```bash
# Get new org's admin username
sf org display --target-org fleetforce-sub-test --json | python3 -c \
  "import json,sys; print(json.load(sys.stdin)['result']['username'])"
```

Then edit `unpackaged/main/default/sites/Motorpool.site-meta.xml` and
replace both `<siteAdmin>` and `<siteGuestRecordDefaultOwner>` values,
then redeploy the sites directory.

### 4. Seed data via Snowfakery / CumulusCI

```bash
# Import the org into CumulusCI (one-time per org)
python3 -m cumulusci org import fleetforce-sub-test sub_test

# Run the seed recipe (220 records, ~8 seconds)
python3 -m cumulusci task run snowfakery \
  --org sub_test \
  --recipe data/seed.recipe.yml
```

Expected results: 7 Accounts, 4 Fleet Schedules, 24 Contacts, 20 Fleet
Branches, 35 Fleet Assets, 45 Authorized Drivers, 20 Telemetry Violations,
30 Reservations, 35 Service Tickets — 0 errors.

### 5. Verify the guest portal

```bash
curl -s -o /dev/null -w "HTTP %{http_code}" \
  "https://<your-site-domain>.scratch.my.salesforce-sites.com/motorpool"
```

Should return `HTTP 200`. The page title should be "FleetForce Motorpool
Portal". VF remoting is wired when `Visualforce.remoting` appears in the
response body.

### 6. Activate the FleetForce theme (manual UI step)

Setup → Themes and Branding → select "Fleetforce" → Activate.

### 7. Verify admin dashboard

Open the org in Lightning, navigate to the home page. KPI tiles and the
map should show data from the seed. The real-time asset tracker shows "no
active location telemetry" by design — it requires live GPS pings from
vehicles, not seeded static data.

---

## Known architecture notes

- **Force.com Site page routing quirk (namespace-owning orgs):** In an org
  that owns the `fleetforce` namespace, the site's `indexPage` can only
  reliably serve the page configured as `inMaintenancePage`. All other VF
  page references return HTTP 503. Workaround: deploy the portal form to
  `InMaintenance.page` and set `indexPage=InMaintenance`. This does not
  affect true subscriber orgs (different namespace/DevHub).
- **Real-time telemetry:** The tracker LWC polls for live telemetry events.
  Seeded data is static — it won't populate the tracker. Future work:
  add simulated telemetry to the seed recipe or a scheduled Apex job.

---

## Known but not yet fully resolved

- ~~Whether `enableGuestUserFlowAccess` becomes Metadata-API-controllable~~
  — moot; portal no longer uses Screen Flows for guest access.
