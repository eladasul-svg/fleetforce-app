# Routing module — local session next steps

For the local Claude Code session (or Elad) after the cloud session on `feature/routing-module`.
Design: `docs/decisions/routing-module.md`. What changed from the plan and why:
`docs/decisions/routing-deviations.md`. Read `docs/project files/environments.md` before creating or
deleting any org.

The cloud session could not reach an org or GCP. Nothing in `force-app` has been compiled. The routing
service passes its 35 pytest tests on `HaversineMatrix`; Jest passes (55 tests). Expect a short round of
Apex compile fixes on the first deploy.

Run everything from the repo root.

## 1. Get the branch

```bash
git fetch origin feature/routing-module
```

```bash
git checkout feature/routing-module
```

```bash
git pull origin feature/routing-module
```

```bash
npm install
```

## 2. Routing service tests (local, no Docker)

Needs Python 3.10+ (the image uses 3.12). This Mac has a standalone 3.12 in `~/.local/python3.12`; if
`python3 --version` says 3.9, replace `python3` below with `~/.local/python3.12/bin/python3`.

```bash
cd services/routing && python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt && python -m pytest -q; deactivate; cd ../..
```

Expected: `35 passed`.

## 3. Deploy to a new namespaced scratch org and run the Apex tests

Pick the next free alias from the "Current orgs" table (here `fleetforce-dev-13`). `--no-data` keeps the
first deploy fast; the demo data comes in step 5.

```bash
./scripts/new_org.sh fleetforce-dev-13 --no-data
```

If the deploy inside `new_org.sh` fails, rerun the deploy on its own to see every error:

```bash
sf project deploy start --source-dir force-app --target-org fleetforce-dev-13 --wait 30
```

Likely first-deploy fixes (the code only passed the Apex parser in the cloud):

- a type mismatch the parser cannot see (Long vs Integer, Double vs Decimal, String vs Id map keys);
- the order of elements in a generated metadata file. The routing objects, fields, layouts and the
  `FleetforceRouting` permission set come from `scripts/routing/gen_routing_metadata.py`: fix the generator,
  rerun it, and let the pre-commit hook re-format.

```bash
python3 scripts/routing/gen_routing_metadata.py .
```

Then run the routing and assistant tests (the assistant ones must still pass unchanged):

```bash
sf apex run test --target-org fleetforce-dev-13 --code-coverage --result-format human --wait 30 --class-names RoutingDtosTest,RoutingProvidersTest,OrsRoutingProviderTest,MockRoutingProviderTest,RoutePlanServiceTest,RoutePlanOptimizeJobTest,RouteEventsTest,RoutingPolicyTest,RouteReplanServiceTest,RoutingAssistantToolsTest,RoutingAssistantIntegrationTest,RoutingActionsTest,ModelProvidersTest,RoutePlanControllerTest,DriverRouteControllerTest,AssistantServiceTest,AssistantToolsTest,AssistantControllerTest
```

Then the whole org, to be sure nothing else broke (the package needs 75%, the target is 90%+):

```bash
sf apex run test --target-org fleetforce-dev-13 --code-coverage --result-format human --wait 60 --test-level RunLocalTests
```

Deploy the guest profile change (class access to `DriverRouteController` for the driver app's Route tab):

```bash
sf project deploy start --source-dir "unpackaged/main/default/profiles/FleetForce Motorpool Profile.profile-meta.xml" --target-org fleetforce-dev-13 --wait 10
```

## 4. Routing service on Google Cloud Run

Set these once per shell (pick the project; `me-west1` is Tel Aviv):

```bash
export PROJECT_ID=<gcp-project-id> REGION=me-west1 REPO=fleetforce SERVICE=fleetforce-routing
```

```bash
gcloud config set project "$PROJECT_ID"
```

```bash
gcloud services enable run.googleapis.com artifactregistry.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com
```

```bash
gcloud artifacts repositories create "$REPO" --repository-format=docker --location="$REGION"
```

```bash
gcloud iam service-accounts create fleetforce-routing --display-name="FleetForce Routing (Cloud Run)"
```

One key per subscriber org. Generate a key and map it to the scratch org's Id:

```bash
export ORG_ID=$(sf org display --target-org fleetforce-dev-13 --json | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['id'])") KEY=$(openssl rand -hex 24)
```

```bash
printf '{"%s": "%s"}' "$KEY" "$ORG_ID" | gcloud secrets create fleetforce-routing-keys --data-file=-
```

```bash
gcloud secrets add-iam-policy-binding fleetforce-routing-keys --member="serviceAccount:fleetforce-routing@$PROJECT_ID.iam.gserviceaccount.com" --role=roles/secretmanager.secretAccessor
```

Build the OSRM graph and both images, push, and deploy (about 10–15 minutes; pre-processing runs in
Cloud Build, never at request time):

```bash
gcloud builds submit services/routing --config services/routing/cloudbuild.yaml --substitutions=_REGION=$REGION,_REPO=$REPO,_SERVICE=$SERVICE
```

The Cloud Build service account needs to deploy Cloud Run and act as the runtime account. If the
`deploy` step fails on permissions:

```bash
export CB_SA=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')@cloudbuild.gserviceaccount.com
```

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$CB_SA" --role=roles/run.admin
```

```bash
gcloud iam service-accounts add-iam-policy-binding "fleetforce-routing@$PROJECT_ID.iam.gserviceaccount.com" --member="serviceAccount:$CB_SA" --role=roles/iam.serviceAccountUser
```

The service authenticates with `X-FleetForce-Key`, so Cloud Run itself must allow unauthenticated calls:

```bash
gcloud run services add-iam-policy-binding "$SERVICE" --region="$REGION" --member=allUsers --role=roles/run.invoker
```

```bash
export URL=$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')
```

```bash
curl -s "$URL/healthz"
```

Expected: `{"status":"ok","solver":"pyvroom","osrm":"up","matrix_source":"osrm",...}`. For demos keep one
instance warm:

```bash
gcloud run services update "$SERVICE" --region="$REGION" --min-instances=1
```

Smoke test with the key (one van, one drop at the depot):

```bash
curl -s -X POST "$URL/v1/optimize" -H "X-FleetForce-Key: $KEY" -H 'Content-Type: application/json' -d '{"vehicles":[{"id":"v","start":[34.7913,31.2518],"end":[34.7913,31.2518],"shift_start":"2026-11-04T05:00:00Z","shift_end":"2026-11-04T15:00:00Z"}],"jobs":[{"id":"j","location":[34.8017,31.2622],"service_seconds":300}]}'
```

## 5. Point Salesforce at the service, then seed and run the demo

In the org (UI, the same pattern as `Claude_API`): Setup → Named Credentials → **FleetForce Routing** →
set the URL to `$URL`. Then External Credentials → **FleetForce Routing** → Principals → **Org** →
Authentication Parameters → add `ApiKey` = `$KEY`. The `FleetforceRouting` permission set already grants
the `Org` principal.

```bash
echo "$URL"; echo "$KEY"
```

Load the demo data (the routing seed runs last):

```bash
./scripts/load_demo_data.sh fleetforce-dev-13
```

Or only the routing demo:

```bash
sf apex run --file scripts/apex/seed_routing_demo.apex --target-org fleetforce-dev-13
```

Place the board: open any Route Plan → Edit Page → drag **Route Plan Board** onto the page → Save →
Activate as the org default. Also add the FleetForce Assistant to the Route record page (as on the Fleet
Asset page) so route chats get the routing tools.

**Morning scenario.** Open **Beer Sheva · morning** → Optimize. Expect 5 routes (BSV-03 left out for its
in-shop ticket), Lift Gate drops only on BSV-02/04/06, a Charge stop on both EVs. Check from the CLI:

```bash
sf data query --target-org fleetforce-dev-13 --query "SELECT Name, fleetforce__Status__c, fleetforce__Revision__c, fleetforce__Unassigned_Count__c, fleetforce__Total_Distance_Km__c, fleetforce__Error__c FROM fleetforce__Route_Plan__c"
```

**11:40 scenario.** Open Dana's route (BSV-01) → assistant: _"Loading is 40 minutes late, and Cohen can
only take it after 3."_ Expect `report_delay`, `update_window`, then a `reoptimize_remaining` proposal
with the before/after. As a dispatcher, ask to hand the late stop to Yossi (`propose_handoff`). Approve,
then check the audit trail:

```bash
sf data query --target-org fleetforce-dev-13 --query "SELECT Name, fleetforce__Type__c, fleetforce__Actor_Type__c, fleetforce__Route__r.Name, fleetforce__Assistant_Session__c, fleetforce__Occurred_At__c FROM fleetforce__Route_Event__c ORDER BY Name"
```

**Overnight relocation.** Open **Car share · overnight relocation** → Optimize. Expect 3 routes, each
pickup followed by its drop.

**Offline fallback.** If the service is not up yet, set a plan's provider to **Mock** to rehearse the
screens (a greedy planner inside Apex, not an optimizer), then press Optimize:

```bash
sf data update record --target-org fleetforce-dev-13 --sobject fleetforce__Route_Plan__c --where "Name='Beer Sheva · morning'" --values "fleetforce__Provider__c=Mock"
```

**Openrouteservice** (dev only, max 50 stops and 3 vans per request): set the key on the `Openrouteservice`
external credential's Org principal (Authentication Parameter `ApiKey`). The seed's **Beer Sheva South ·
morning** plan is already set to Openrouteservice and sized for it (3 vans sent, 35 drops); the overnight
plan fits too (3 drivers, 24 stops). The 60-drop **Beer Sheva · morning** does not. Not available on
openrouteservice: locked stops in a re-plan, reasons for unplanned jobs (all show `no_room`), and the Min
Distance and Min Vehicles objectives; Balanced works.

## 6. Package version and install test

The fixed rule: a source deploy is not a package install. Add the routing changes to the "Next version"
section of `docs/project files/release-notes.md` first (new objects, the `FleetforceRouting` permission
set, the two named credentials, `AssistantService` now calling through `ModelProvider`). Then:

```bash
sf package version create --package "FleetForce Platform" --installation-key-bypass --code-coverage --wait 60
```

```bash
./scripts/new_org.sh fleetforce-pkgtest-2 --package <04t from the previous command>
```

In the installed org, hand-check: the Route Plan board, Optimize against Cloud Run (named credential URL
and key set again: they are not packaged values), and the assistant on a Route.

## 7. Merge

Review the draft PR, then follow the normal flow into `claude/peaceful-galileo-olirr2`. Update the
"Current orgs" table and the Queued Work Orders in `docs/history/fleetforce-project-history.md`.
