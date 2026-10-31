# FleetForce data trust layer: object model and Claude-assisted integration

Oct 28, 2026 · @Elad Asulin

Spec for Code: a data trust layer on FleetForce. Every vehicle shows where its data comes from, whether it is complete and current, and what recalls or regulations affect it, with one central view across the fleet. Tomorrow's demo runs on seeded sample data in the scratch org; live feeds and Claude-assisted import come after.

## Scope

Tomorrow's demo is a **preview on seeded sample data**, labelled as such in the UI. Nothing in it claims a live connection. Live feeds and Claude-assisted import follow once the demo has shown the shape.

| Priority | Built for       | What                                                                                            |
| -------- | --------------- | ----------------------------------------------------------------------------------------------- |
| P0       | Tomorrow's demo | Data model, health score, asset record page component, fleet exposure view, seed data and reset |
| P1       | After the demo  | Live US recall pull, CSV mapping assistant, bulk actions on the exposure view, Sync Log         |
| P2       | Later           | Regulation intake with AI-drafted notices, OEM notices, declarative API connectors              |

Create the scratch org with `--duration-days 30` so it does not expire right after the event.

## Data model

The shape is: a **source** (the connection), **streams** (what that source gives each vehicle), a **profile** (what a vehicle should receive), and **alerts** (the output, whether a data gap, a recall or a regulation). Recalls and regulations enter as **notices** that are matched to vehicles. Code confirms API names against the repo and follows its conventions; no hardcoded namespace.

| Object                     | Level                             | Key fields                                                                                                                                                                                                                                                                                                             |
| -------------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Data\_Source\_\_c          | Customer connection               | Vendor, Source\_Type (Telematics, FMC feed, OEM, Regulatory feed, File import, Other), Reference\_URL (link to the system of reference), Status, Last\_Received, Expected\_Frequency\_Hours, owner                                                                                                                     |
| Data\_Stream\_\_c          | Source x vehicle                  | Fleet\_Asset (master-detail), Data\_Source, Data\_Type (Location, Odometer, Fuel or charge, Diagnostics, Maintenance plan, Registration, Insurance, Other), External\_Id, Last\_Update, Record\_Count\_30d, Signals\_Present, Reference\_URL                                                                           |
| Stream\_Profile\_\_c       | Rule set                          | Expected\_Signal\_Count, match criteria (Make, Model, Fuel\_Type, Vehicle\_Category), Is\_Default, Priority, Active                                                                                                                                                                                                    |
| Stream\_Profile\_Line\_\_c | Profile line                      | Stream\_Profile (master-detail), Data\_Type, Required, Max\_Age\_Hours, Min\_Signals                                                                                                                                                                                                                                   |
| External\_Notice\_\_c      | Recall or regulation              | Notice\_Type (Recall, Regulation, Service bulletin), Source, External\_Id (unique), Title, Summary, Source\_URL, Published\_On, Effective\_On, Jurisdiction, Severity, match criteria (Make, Model, Year\_From, Year\_To, Fuel\_Type, Vehicle\_Category), Status (Draft, Active, Withdrawn), Reviewed, Affected\_Count |
| Asset\_Alert\_\_c          | Output, one per vehicle per issue | Fleet\_Asset, Alert\_Type (Data gap, Recall, Regulation, Other), Severity, Status (New, Acknowledged, In progress, Resolved, Dismissed), Title, Detail, Data\_Stream, External\_Notice, Due\_Date, Unique\_Key (unique, external id), Resolved\_On                                                                     |
| Sync\_Log\_\_c (P1)        | Event                             | Data\_Source, Started, Records\_Received, Errors, Message                                                                                                                                                                                                                                                              |

**Additions to the fleet asset object:** Data\_Health\_Score (0-100), Data\_Health\_Status, Freshness\_Score, Completeness\_Score, Consistency\_Score, Data\_Health\_Calculated, Open\_Alert\_Count, Stream\_Profile\_Override (lookup). Matching also needs make, model, year, fuel type, vehicle category and country on the asset; Code adds only the ones that do not exist yet.

**Profile resolution** for a vehicle: its override if set, otherwise the highest-priority active profile whose criteria match, otherwise the default profile. The mixed-fleet case is two profiles: a Standard profile expecting 8 signals (default) and an EV batch profile expecting 14, matched by make or fuel type.

**Design rules:** Asset\_Alert\_\_c is the single list the screens read, so the record page and the exposure view share one query. Keep raw telemetry in the source and store only counters and a link. Do not add a Sync\_Log row per record, only per sync.

## Logic

**Health score (0-100)** = 0.4 x Freshness + 0.4 x Completeness + 0.2 x Consistency. The screens always show the three parts next to the total, never the number alone.

- **Freshness:** for each required profile line, 100 if the stream's age is within Max\_Age\_Hours, falling linearly to 0 at three times that age; a missing stream scores 0. The score is the average across lines.
- **Completeness:** total signals present across the vehicle's streams divided by the profile's Expected\_Signal\_Count, capped at 100.
- **Consistency:** 100 minus the penalties for open Data gap alerts (Critical 40, High 25, Medium 10, Low 5), floor 0.
- **Bands:** 85 and above Healthy, 60 to 84 Watch, below 60 At risk.

Recall and regulation alerts do not change the score. They describe exposure, not data quality, and are shown separately.

**Evaluation service** (Apex, with sharing, bulk-safe): resolves the profile, sets each stream's status (Healthy within max age, Stale beyond it, Missing if absent), creates or auto-resolves Data gap alerts using Unique\_Key so reruns never duplicate, and writes the score fields on the asset. It runs when a stream changes (queueable), nightly (scheduled), and on demand from the record page.

**Notice matching** (Apex): for notices that are Active and Reviewed, find vehicles matching make, model, year range, fuel type, category and a country inside the jurisdiction, and create one alert per vehicle (type Recall or Regulation, severity from the notice, due date from Effective\_On). Idempotent through Unique\_Key. A withdrawn notice resolves its alerts. Affected\_Count is maintained by the service.

**Recall matches are "possible", not confirmed.** The public US recall data is by make, model and year, so the alert text says "Possible match, confirm by VIN with the manufacturer".

## Screens

**1. `assetDataHealth`: an LWC on the fleet asset record page.**

- A score gauge in the band's colour, with the three sub-scores beneath, the calculation time and a Refresh button.
- A stream list: source, data type, last update as relative time, status chip, and an icon that opens the source's reference URL in a new tab.
- An open-alerts list sorted by severity: type icon, title, due date, status; a click opens the alert.
- Empty state ("No data sources linked yet"), error state with a toast, and a "Sample data" banner when the seed flag is on.
- Status is shown with icon and text, not colour alone. It must work at 1024 px wide, in desktop-site mode on a tablet and on a laptop, in one- and two-column regions. Base Lightning components only, no external libraries, Jest tests.

**2. `fleetExposure`: a Lightning app page and tab, the central view.**

- KPI tiles: open alerts by type, vehicles at risk, new notices in the last 7 days, average fleet health.
- A notice table: title, type, source, jurisdiction, effective date, affected vehicles, status, with filters for type, jurisdiction and status.
- A click on a notice lists its affected vehicles and their alert status. This drill-down is P0.
- A second panel, data health by source (streams per source and the share that are stale), is P0 if time allows. Bulk actions (acknowledge, assign owner) are P1.

## Intake

The security-world analogy only goes so far. CVEs work because every entry maps to standard product identifiers. Recalls map to make, model and year, so they are matchable. Regulations carry no such identifiers, so who they apply to has to be derived and then confirmed by a person.

| Source                                                                                                               | What it gives                                                                                                                     | Status                                                                                                              |
| -------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| [NHTSA recalls API](https://www.nhtsa.gov/nhtsa-datasets-and-apis) (US)                                              | Recalls by make, model and year, or by campaign number; bulk flat files. NHTSA's page lists no VIN lookup and mentions no API key | Verified. P1: scheduled pull through a Named Credential, upsert on campaign number                                  |
| [UK DVSA vehicle recalls service](https://documentation.vehicle-recalls.api.gov.uk/recalls/vehicle-recalls-service/) | Manufacturers submit recall data to DVSA, which shows it to the public through MOT services                                       | No public feed for fleets found. Not a source for now                                                               |
| [EUR-Lex](https://eur-lex.europa.eu/content/help/my-eurlex/my-rss-feeds.html?locale=en) (EU law)                     | RSS alerts for new publications                                                                                                   | The feature exists; feed types and setup not confirmed. P2                                                          |
| [legislation.gov.uk](https://www.legislation.gov.uk/developer) (UK law)                                              | A Legislation API under the Open Government Licence                                                                               | A new-legislation feed was not confirmed. P2                                                                        |
| OEM notices                                                                                                          | No common feed found                                                                                                              | Realistic routes: manufacturer portal or email, the FMC, the telematics vendor. Manual entry or file import for now |
| City and local rules                                                                                                 | No feed found                                                                                                                     | Manual                                                                                                              |

**Regulation intake (P2).** A law-publication feed produces a draft notice written by Claude: summary, jurisdiction, vehicle categories, effective date and match criteria. The draft is saved with Reviewed unchecked. Matching only runs after a person reviews and activates it. AI-drafted notices are never activated automatically.

**CSV mapping assistant (P1).** Claude proposes a mapping from the file's columns to the fields, the user sees a preview (new, updated, conflicting), approves, and ordinary Apex loads it with a batch ID so it can be undone. It runs as the user, so sharing and field-level security apply, and only the schema and a few sample rows go to the model.

**API connectors (P2).** Claude generates a declarative connector (endpoint, credential reference, field mapping, schedule) that a generic engine runs after an admin approves it. It does not write Apex into production.

**File content is untrusted.** A CSV cell or API response can contain instructions. The model's output must be only a structured mapping, validated against the schema, with a short allow-list of actions.

## Demo seed data and script

Extend the existing demo fleet of about 60 vehicles rather than creating a second one. Everything is fictional and marked as sample. Dates are offsets from the run date. The existing reset command must also remove these records.

| Seed               | Content                                                                                                                                                                                                                                   |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sources            | "Telematics vendor (sample)", "FMC maintenance file (sample)", "Fuel card feed (sample)"                                                                                                                                                  |
| Profiles           | Standard (8 signals, default) and EV batch (14 signals) matched to the 6 electric vehicles                                                                                                                                                |
| Streams            | Most vehicles healthy; 8 with stale telematics (3 to 9 days old); 5 missing a required stream                                                                                                                                             |
| Data gaps          | 2 vehicles where the FMC file says a maintenance plan is active but the fleet record does not                                                                                                                                             |
| Notices            | 2 recalls with obviously fake IDs (SAMPLE-RCL-001 and 002) matching 9 and 4 vehicles; 2 regulations (a low-emission zone rule change and a driver-documents rule), each with an effective date in the future and a 3-country jurisdiction |
| Reference vehicles | 3 vehicles whose scores are calculated by hand and listed in the seed README, so the score logic can be checked                                                                                                                           |

**Demo script, about 3 minutes:**

1. Open the fleet exposure view: this week's notices, how many vehicles each affects, average fleet health.
2. Open a notice and its affected vehicles. Say that recall matches are possible matches to confirm by VIN.
3. Open an At risk vehicle: the gauge and its three parts, a stale telematics stream, a data gap, a recall alert.
4. Click a stream's source link to show that the system of reference stays where it is.
5. Acknowledge an alert, refresh, and show it update.
6. Say plainly that this is a preview on sample data, and that live recall feeds and Claude-assisted import are next.

## Acceptance criteria and rules for Code

- [ ] All new objects, fields, the Apex classes, both LWCs and a permission set deploy from source into the scratch org.
- [ ] Seed and reset run twice in a row with the same result.
- [ ] The three reference vehicles show the hand-calculated scores.
- [ ] Both screens work at 1024x768 in desktop-site mode and on a laptop, including empty and error states.
- [ ] Apex coverage is at least 90% on new classes, with a bulk test of 200 vehicles. Jest tests cover both LWCs.
- [ ] Screenshots of each demo step are attached to the report.

**Rules**

- Work on a branch such as `feature/data-trust`. No credentials, tokens or org auth files in git.
- Use Named Credentials for any callout, never hardcoded endpoints. All Apex runs with sharing.
- Retrieve any change made by hand in the org into source, including field-level security and the page layout.
- Keep the model package-ready (no hardcoded namespace), even though tomorrow's demo is in the scratch org.
- Show sample records as sample. Do not present real recalls or regulations as live until a real pull has produced them.

**If time runs short, cut in this order:** bulk actions, the data-health-by-source panel, Sync\_Log\_\_c, Stream\_Profile\_Line\_\_c (use the profile header only), then LWC polish. Never cut the five core objects, the score, the record page component, or the exposure view with its drill-down.

## Open decisions for Elad

1. **Asset fields.** Which of make, model, year, fuel type, vehicle category and country already exist on the fleet asset? Code checks the repo and adds only the missing ones.
2. **Real or sample recalls tomorrow.** Recommendation: labelled sample data tomorrow, a real US pull after the event.
3. **Whose Claude key** for the CSV assistant in customer orgs, who pays, and what data leaves their org. This decides what the website can say.
4. **Website wording.** No "recall and regulation tracking" claim until a real feed has run.
5. **Channel fit.** A tool that checks FMC-supplied data may sit awkwardly with a later FMC white-label plan. Worth deciding how it is framed before talking to FMCs.
