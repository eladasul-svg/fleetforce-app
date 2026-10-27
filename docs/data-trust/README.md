# Data trust layer (P0, preview on sample data)

Every vehicle shows where its data comes from, whether that data is complete and current, and which recalls or regulations affect it. One central view covers the whole fleet. The P0 build is a **preview on seeded sample data**, labelled as such in the UI. Nothing in it claims a live connection.

Spec: *FleetForce data trust layer: object model and Claude-assisted integration* (28 Oct 2026). Sample data and the reference vehicles: [seed-README.md](seed-README.md).

## Setup

```bash
# new scratch org (30 days so it outlives the event)
sf org create scratch -f config/project-scratch-def.json -a fleetforce-dev-12 --duration-days 30
# ...existing fleet seed as usual (seeder.py / scripts/apex/*), then:
./scripts/data_trust_setup.sh fleetforce-dev-12   # deploy, assign FleetforceDataTrust, seed, schedule nightly
```

To add it to an existing org such as `fleetforce-dev-11`, run only `./scripts/data_trust_setup.sh fleetforce-dev-11`.

Run the Apex tests with `sf apex run test --class-names DataHealthServiceTest,NoticeMatchingServiceTest,DataTrustSampleDataTest,DataTrustControllersTest,DataTrustJobsTest --code-coverage --result-format human --target-org <alias>`.
Run the Jest tests with `npm run test:unit -- --testPathPattern 'assetDataHealth|fleetExposure'`.

## What is built

| Area | Pieces |
| --- | --- |
| Objects | `Data_Source__c`, `Data_Stream__c` (master-detail to Fleet Asset), `Stream_Profile__c`, `Stream_Profile_Line__c`, `External_Notice__c`, `Asset_Alert__c` (master-detail to Fleet Asset). Every object has an `Is_Sample__c` flag. `Sync_Log__c` is P1 and not built |
| Fleet Asset fields | Data Health Score / Status, Freshness / Completeness / Consistency Score, Data Health Calculated, Open Alerts, Stream Profile Override, Stream Profile Used (set by the service). **Added because they did not exist:** Make, Model, Model Year, Country (ISO 2). Existing fields are reused: Fuel Type, and **Vehicle Class** for "vehicle category" |
| Apex (all `with sharing`) | `DataHealthService` (evaluation and score), `NoticeMatchingService`, `AssetAlertService` (the single alert query both screens use, open-alert counts), `DataTrustJobs` (queueables, nightly schedulable batch), `DataTrustTriggerHandler` plus three triggers, `AssetDataHealthController`, `FleetExposureController`, `DataTrustSampleData` (seed and reset) |
| LWC | `assetDataHealth` (on both Fleet Asset record pages, under the vehicle image), `fleetExposure` (app page **Fleet Exposure**, a tab in Fleet Ops), `dataTrustFormat` (shared icons and labels) |
| Access | Permission set `FleetforceDataTrust` (objects, field-level security, classes, tabs). The Fleet Asset layout has a Data Health section and related lists for streams and alerts |

### Rules as implemented

- **Profile resolution.** The override is used if set. Otherwise the active profile with the **lowest Priority number** among those whose criteria all match (make, model, fuel type, category; a blank criterion matches anything). Otherwise the active default profile.
- **Stream status.** Healthy if the stream is within the profile line's Max Age (or the source's Expected Frequency when the profile has no line for that data type). Stale if older. Missing if it has never been received.
- **Data gap alerts.** The service owns the `DG:` keys (missing: High; stale: Medium, or High at three times the max age) and the `DGS:` keys (fewer signals than the line minimum: Low). It reopens alerts it resolved itself, but leaves Acknowledged, In progress and Dismissed alerts as the user set them. Other data gaps, such as the `DGC:` consistency gaps from a file import, count toward Consistency but are never auto-resolved.
- **Notice matching** runs only for notices that are **Active and Reviewed**. Jurisdiction is a list of ISO country codes separated by `;` or `,`; a blank jurisdiction matches every country. Only active vehicles are matched. A withdrawn, draft or unreviewed notice resolves its alerts. Recall alerts start with "Possible recall:" and carry "Possible match, confirm by VIN with the manufacturer."
- **Triggers.** A stream change re-scores its vehicle (queueable). A notice change re-matches the notice (queueable). An alert status change recounts the vehicle's open alerts, and re-scores it when a data gap opens or closes. The services set a running flag so their own writes never re-trigger them.
- **Nightly.** `DataTrustJobs.scheduleNightly()` runs at 02:00: data health for every active vehicle in batches of 200, then all notice matching.

## Demo script (about 3 minutes)

1. **Fleet Ops → Fleet Exposure.** KPI tiles show open data gaps, recall alerts and regulation alerts, vehicles at risk, new notices in the last 7 days, and average fleet health. Below them is the notice table, which filters by type, jurisdiction and status.
2. Click a recall title. The drill-down lists the affected vehicles with their health and alert status. The amber note says these are **possible matches to confirm by VIN**.
3. Open REF-3, the At risk vehicle (its id is in the seed summary, and it is in the `SAMPLE-RCL-001` drill-down). The record page shows the gauge (45) with Freshness 25, Completeness 75 and Consistency 25, stale telematics streams, a missing maintenance plan gap and the recall alert.
4. Click the ↗ icon on a stream. The source's system of reference opens in a new tab (an `example.com` placeholder in the preview).
5. Click **Acknowledge** on the recall alert. A toast appears and the status changes. Then click **Refresh** (↻) to recalculate. The score stays 45, because acknowledged alerts are still open and recalls never change the score.
6. Close by saying plainly: this is a preview on sample data, and live recall feeds and Claude-assisted import come next.

## Not done here / needs the org

- **Not yet deployed or run in an org.** The build environment had no Salesforce CLI or org. All Apex was syntax-checked with the Apex parser only. The Apex tests (including the 200-vehicle bulk test), coverage, both screens at 1024×768 and the demo screenshots all have to be checked in the scratch org.
- No hardcoded namespace in the new code. The existing classes still use the `fleetforce__` prefix; that is unchanged.
- P1 and P2 are not started: live US recall pull, the CSV mapping assistant, bulk actions, Sync Log, regulation intake, OEM notices and connectors.
