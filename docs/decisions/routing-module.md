# FleetForce Routing Module — Design & Cloud Work Order

Nov 3, 2026 · @Elad Asulin

## Summary and decisions

FleetForce Routing is a vehicle-first planning and in-day dispatch module. It sits beside the existing motorpool, allocation and telematics objects. The optimizing is done by an external solver, and Claude acts as the dispatcher that turns what happens on the road into solver inputs.

- **Demo vertical: own-fleet last mile.** Distributors, wholesalers, municipal services and utilities that already manage their vans in FleetForce. Car-sharing relocation is a second scenario on the same data model (Section 3).
- **Data model: separate the need from the stop.** `Route_Job__c` and `Job_Visit__c` hold the demand. `Route_Plan__c`, `Route__c` and `Waypoint__c` hold the plan. `Route_Event__c` is the audit trail (Section 5).
- **Engine: open-source VROOM, behind a provider interface.** Phase 1 runs the FleetForce Routing Service on Google Cloud Run (VROOM + OSRM on an OpenStreetMap extract). The openrouteservice free key takes the same VROOM JSON, but it's for dev and tests only: it caps at 50 jobs and 3 vehicles per request. Google Route Optimization is a premium adapter, because per-stop pricing would cost more than our licence price (Section 4).
- **Traffic: plan on typical speeds, refresh ETAs on events.** Traffic-aware calls go only to the next leg, triggered by an event, as a paid add-on.
- **AI: Claude is the dispatcher, the solver does the maths.** It works through the existing `AssistantTools` propose → approve pattern, the same tools are exposed as invocable Apex for Agentforce, and a `ModelProvider` interface supports bring-your-own-model (Section 7).
- **Build: a cloud Claude Code session writes the first slice on a branch of the GitHub repo.** That means the routing service, metadata, Apex and tests. A local session then deploys to scratch orgs and to GCP (Section 8).

&#91;embedded content: routing module architecture · Salesforce, Cloud Run, external services\]

Jobs flow down into a plan through the Cloud Run solver. The driver's words reach the plan only through the assistant and its policy, which send them back through the same solver.

## Research findings

The findings below are why the design looks the way it does. Code should read this section before making changes to it.

**Salesforce Field Service (SFS) is built around labour, not vehicles.**

- The core objects are WorkOrder, ServiceAppointment, ServiceResource, ServiceTerritory(Member), AssignedResource, Shift, ResourceAbsence and the Skill objects ([core data model](https://developer.salesforce.com/docs/platform/data-models/guide/field-service-core-data-model.html)).
- As far as we know, it has no route record, no pickup→delivery pairing, and no load capacity (weight or volume). Capacity is time only, and travel is calculated between consecutive appointments.
- These are the gaps FleetForce fills. We take jobs from SFS rather than compete with it.

**Salesforce's native options are external engines or extra licences.**

- Enhanced Scheduling and Optimization (ESO) runs outside Apex. Its limits include 50,000 optimized appointments per 24 hours, a 10 s trigger CPU limit and a 30-day horizon ([ESO limits](https://help.salesforce.com/s/articleView?id=sf.pfs_enhanced_available_limits.htm&language=en_US&type=5)).
- Salesforce Maps has Apex methods: `getRoute()` (follows the order you give it, no optimizing), `GetDistanceMatrix()`, and visit-plan optimization. All of them need a Salesforce Maps (Advanced) licence on the customer's side ([Maps Apex](https://developer.salesforce.com/docs/sales/maps-dev-guide/guide/maps-apex-overview.html)). That's a bad dependency for an ISV.
- Apex can't be the solver: it has no road graph, and sync/async CPU limits are 10 s and 60 s. The pattern is an async callout through a Named Credential, with results written back.

**Agentforce for Field Service calls the optimization engine. It doesn't replace it.** Filling schedule gaps "leverages the Salesforce Field Service optimization engine" ([announcement](https://www.salesforce.com/news/stories/agentforce-for-field-service-announcement/)).

**LLMs as direct route solvers do badly; LLMs working with solvers do well.** A July 2026 survey compared LLM-generated capacitated routes with the PyVRP solver ([arXiv 2607.00604](https://arxiv.org/html/2607.00604v1)):

| Approach                              | 20 stops    | 100 stops   | 200 stops   | 500 stops       |
| ------------------------------------- | ----------- | ----------- | ----------- | --------------- |
| LLM generates routes directly         | 21.9% worse | 45.0% worse | 55.6% worse | no valid result |
| LLM designs the heuristic (HeuriGym)  | 3.5%        | —           | 5.1%        | 3.7%            |
| LLM steers a neural solver (NCO-LLMs) | —           | 0.9%        | 1.0%        | 1.2%            |

The survey has no measurements yet for human-in-the-loop dispatching, which is our use. It marks this as a promising direction.

**The engines come in two layers.**

- **Road network** (travel-time and distance matrix): OSRM, Valhalla, GraphHopper, openrouteservice (all OpenStreetMap), or Google, HERE, TomTom and Mapbox.
- **Optimizer:** [VROOM](https://github.com/VROOM-Project/vroom) (BSD-2). It covers TSP, CVRP, VRPTW, multi-depot and mixed fleets, and pickup→delivery with time windows, plus skills, breaks, priorities, multiple capacity dimensions and open trips. It works with OSRM, ORS and Valhalla, or a custom matrix. Other options: OR-Tools, PyVRP, Timefold (Apache 2.0; its hosted Field Service Routing is priced on request — [pricing](https://timefold.ai/pricing)), and Google Route Optimization.

**Traffic.** Open-source engines use typical speeds. Valhalla can load historical speed profiles if you supply them ([docs](https://valhalla.github.io/valhalla/concepts/historical-traffic/)). Live traffic means a commercial provider.

**Bring your own model.**

- Agentforce runs Salesforce-managed Claude models on Bedrock, inside the trust boundary.
- Its Bring Your Own LLM option accepts Bedrock, Azure OpenAI, OpenAI and Vertex, all through the Models API with Trust Layer support ([supported models](https://developer.salesforce.com/docs/ai/agentforce/guide/supported-models.html)).

**What the repo already has.**

- `AssistantTools` / `AssistantService` / `AssistantClaudeClient`: Claude tool use, with writes that are proposed and approved, then run in USER\_MODE.
- `Assistant_Session__c`, which keeps a record context and `Pending_Proposal__c`.
- `DriverAppController`, for the guest driver app.
- Geotab sync into `Fleet_Asset__c.Last_Location__c`.
- The Fleet\_Schedule, Schedule\_Window and Schedule\_Assignment objects.
- `Allocation__c` and `Driver_Qualification__c`.

## Market and demo choice

Last mile is the bigger need, so the demo leads with it. But we position it as **own-fleet** last mile, not courier software.

Pure last-mile routing is crowded and priced per driver or per visit. Examples: Onfleet, Circuit, OptimoRoute, Bringg, and Routific at about $0.10–0.15 a visit ([2026 pricing comparison](https://kardinal.ai/route-optimization-api-pricing-2026-comparison/)). FleetForce wins where the route has to know the vehicle and the driver. That's the 50–400 vehicle owned fleets in our target market.

| Vertical                                                            | Routing shape                                                        | Competition                                             | Fit with FleetForce                                                                  |
| ------------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Own-fleet last mile (distributors, wholesalers, municipal services) | Depot → many drops, time windows, capacity, returns                  | Crowded at the courier end, thin inside fleet platforms | Strong: vehicles, drivers, EV range and maintenance status are already in FleetForce |
| Field service fleets (utilities, municipal maintenance, installers) | Skills + appointments + parts pickup                                 | SFS, ServiceTitan, others                               | Medium: we feed SFS jobs or serve teams without SFS                                  |
| Car sharing / rental ops                                            | Relocation, cleaning, charging, refuel: pickup→drop with no customer | Few specialists                                         | Strong for Autofleet-style ops and FMC partners, but a smaller market                |

**Demo script (one data model, two stories):**

1. **Morning.** 6 vans at the Beer Sheva depot, 60 drops with time windows, 2 EVs, and one van flagged with an open service ticket. Optimize: the flagged van is left out, and the EVs get a charge waypoint added.
2. **11:40, something goes wrong.** Dana tells the assistant: "Loading is 40 minutes late, and Cohen can only take it after 3." Claude re-optimizes her remaining stops. It shows one late stop, and offers handing it to Yossi as option B, which needs dispatcher approval.
3. **Second story, same screens.** A car-sharing relocation plan: 12 cars to rebalance overnight. These are pickup→drop jobs with no customer.

## Engine and cost

Hosting VROOM + OSRM ourselves on Cloud Run costs tens of dollars a month. Google's per-stop optimization would cost more than the customer pays us. So for routing, a paid key is the expensive option, not the cheap one.

**Worked example: one customer, 30 vans, 40 stops a day, 22 working days.** That's 26,400 planned stops a month, plus in-day re-optimizations. Assume 3 per driver a day over about 20 remaining stops, which is about 39,600 more.

| Option                                    | What you need                                                   | Monthly cost for that customer                                                                            | Notes                                                                                                 |
| ----------------------------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Google Route Optimization, Fleet Routing  | GCP project, OAuth service account, a key in a Named Credential | \~$1,950 (66k stops at $30 per 1,000 after 1,000 free)                                                    | Best quality and live traffic, but costs 2.6× the \~$750 licence (30 × $25)                           |
| openrouteservice free key                 | Sign-up, an API key                                             | $0                                                                                                        | Optimization capped at 50 jobs and 3 vehicles per request: dev and tests only, too small for the demo |
| **Self-hosted VROOM + OSRM on Cloud Run** | Docker image, Artifact Registry, Cloud Run, Secret Manager      | \~$0–75 (approximate: inside the free tier when it scales to zero, \~$40–75 if one instance is kept warm) | Typical speeds only, and we run it. Israel's map fits in a 2 GiB container                            |
| Google Route Matrix Pro, traffic add-on   | Same GCP key                                                    | \~$150 (approximate: \~20k elements at $10 per 1,000 after 5,000 free; event-triggered ETA refresh only)  | Charge as a premium feature                                                                           |

Prices: [Google Maps Platform pricing list](https://developers.google.com/maps/billing-and-pricing/pricing) (lowest volume tier), [ORS restrictions](https://openrouteservice.org/restrictions/), [OSRM memory guide](https://github.com/Project-OSRM/osrm-backend/wiki/Disk-and-Memory-Requirements).

**How big the map data is (approximate).** OSRM needs about 2× the .pbf size in RAM to serve, and about 7× at peak while it pre-processes.

- **Israel** (about a 0.1–0.2 GB extract): fits in one small container.
- **The whole US** (about an 11 GB extract): around 22 GB of RAM to serve. Use a per-state or per-region extract per customer, or a Compute Engine VM with a lot of memory.
- Pre-process on Cloud Build or a temporary VM, never at request time.

**Recommendation.** GCP is the right call: Cloud Run, Artifact Registry, Secret Manager and Cloud Build cover all of it. The service is a thin wrapper around official images that already exist (`ghcr.io/vroom-project/vroom-docker` and `osrm/osrm-backend`), so "start from open source and go from there" holds. Keep `RoutingProvider` in Apex so a customer's own Google key can be plugged in for traffic or a premium tier.

## Data model

There are five new objects, a log object and one metadata type. Demand (`Route_Job__c` → `Job_Visit__c`) is kept apart from the plan (`Route_Plan__c` → `Route__c` → `Waypoint__c`). The two meet through `Job_Visit__c.Waypoint__c`, so several visits can share one stop and a pickup→drop job spans two stops.

Field names below are a starting point. Code may rename them or add fields as long as the shape holds: demand separate from plan, visits pointing to waypoints, and an append-only event log.

### Demand side

**Route\_Job\_\_c** — one business need, e.g. "deliver order 4471" or "relocate car 55 to the airport lot".

| Field                                         | Type                      | Notes                                                                                                        |
| --------------------------------------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Type\_\_c                                     | Picklist                  | Delivery, Pickup, Pickup and Delivery, Service, Relocation, Inspection, Cleaning, Charging                   |
| Status\_\_c                                   | Picklist                  | New, Ready, Planned, In Progress, Completed, Failed, Cancelled                                               |
| Service\_Date\_\_c                            | Date                      | Planning day                                                                                                 |
| Branch\_\_c                                   | Lookup Fleet\_Branch\_\_c | Planning depot                                                                                               |
| Priority\_\_c                                 | Number 0–100              | Maps to VROOM `priority`                                                                                     |
| Account\_\_c / Contact\_\_c                   | Lookup                    | Customer, optional                                                                                           |
| Subject\_Asset\_\_c                           | Lookup Fleet\_Asset\_\_c  | The car being moved (car sharing), optional                                                                  |
| Source\_Object\_\_c / Source\_Record\_Id\_\_c | Text                      | Where the job came from: Reservation\_\_c, Service\_Ticket\_\_c, an SFS ServiceAppointment, an Order, a Case |
| Required\_Skills\_\_c                         | Multi-select picklist     | Matched against driver qualifications and vehicle features                                                   |
| Planned\_Route\_\_c                           | Lookup Route\_\_c         | Set by the optimizer                                                                                         |
| External\_Id\_\_c                             | Text, external ID, unique | For upserts from integrations                                                                                |
| Notes\_\_c                                    | Long text                 | Free text. The assistant extracts access notes and service time from it                                      |

**Job\_Visit\_\_c** (master-detail to Route\_Job\_\_c) — one place the job needs: 1 for a service or delivery, 2 for a pickup→drop.

| Field                                      | Type                 | Notes                                             |
| ------------------------------------------ | -------------------- | ------------------------------------------------- |
| Role\_\_c                                  | Picklist             | Pickup, Delivery, Service                         |
| Location\_\_c                              | Geolocation          | Required for routing                              |
| Address\_\_c                               | Text                 | Display and geocoding                             |
| Window\_Start\_\_c / Window\_End\_\_c      | DateTime             | Optional; VROOM `time_windows`                    |
| Hard\_Window\_\_c                          | Checkbox             | Soft windows become a cost in the solver          |
| Service\_Minutes\_\_c                      | Number               | Time on site                                      |
| Load\_1\_\_c / Load\_2\_\_c / Load\_3\_\_c | Number               | Load change per capacity dimension (+ for pickup) |
| Waypoint\_\_c                              | Lookup Waypoint\_\_c | The stop that serves this visit                   |
| Status\_\_c                                | Picklist             | Pending, Done, Failed                             |
| Access\_Notes\_\_c                         | Text area            | "Back gate, code 1234"                            |

### Plan side

**Route\_Plan\_\_c** — one planning run, for one depot and one day.

| Field                                                | Type                      | Notes                                                                      |
| ---------------------------------------------------- | ------------------------- | -------------------------------------------------------------------------- |
| Plan\_Date\_\_c                                      | Date                      |                                                                            |
| Depot\_Branch\_\_c                                   | Lookup Fleet\_Branch\_\_c |                                                                            |
| Status\_\_c                                          | Picklist                  | Draft, Optimizing, Optimized, Published, In Progress, Completed, Cancelled |
| Provider\_\_c                                        | Picklist                  | FleetForce Routing, Openrouteservice, Google                               |
| Objective\_\_c                                       | Picklist                  | Min Duration, Min Distance, Min Vehicles, Balanced                         |
| Revision\_\_c                                        | Number                    | Goes up on every re-optimization                                           |
| Last\_Optimized\_At\_\_c                             | DateTime                  |                                                                            |
| Unassigned\_Count\_\_c                               | Number                    | Jobs the solver couldn't fit                                               |
| Total\_Distance\_Km\_\_c / Total\_Duration\_Min\_\_c | Number                    | KPIs                                                                       |
| Solver\_Summary\_\_c                                 | Long text (JSON)          | Raw summary, for debugging                                                 |
| Error\_\_c                                           | Text area                 | Last callout error                                                         |

**Route\_\_c** (master-detail to Route\_Plan\_\_c) — one vehicle and one driver for one shift.

| Field                                                    | Type                     | Notes                                                          |
| -------------------------------------------------------- | ------------------------ | -------------------------------------------------------------- |
| Fleet\_Asset\_\_c                                        | Lookup Fleet\_Asset\_\_c |                                                                |
| Driver\_\_c                                              | Lookup Contact           |                                                                |
| Allocation\_\_c                                          | Lookup Allocation\_\_c   | Created on publish, so the motorpool sees the van as in use    |
| Status\_\_c                                              | Picklist                 | Planned, Published, In Progress, Completed, Cancelled          |
| Start\_Location\_\_c / End\_Location\_\_c                | Geolocation              | Default to the depot; can be the driver's home or an open trip |
| Shift\_Start\_\_c / Shift\_End\_\_c                      | DateTime                 | From Schedule\_Assignment\_\_c                                 |
| Planned\_Start\_\_c / Planned\_End\_\_c                  | DateTime                 | From the solver                                                |
| Planned\_Distance\_Km\_\_c / Planned\_Duration\_Min\_\_c | Number                   |                                                                |
| Actual\_Start\_\_c / Actual\_End\_\_c                    | DateTime                 |                                                                |
| Revision\_\_c                                            | Number                   |                                                                |
| Geometry\_\_c                                            | Long text                | Encoded polyline for the map                                   |

**Waypoint\_\_c** (master-detail to Route\_\_c) — every stop the vehicle makes, whatever the reason.

| Field                                            | Type                      | Notes                                                                   |
| ------------------------------------------------ | ------------------------- | ----------------------------------------------------------------------- |
| Sequence\_\_c                                    | Number                    | Current order                                                           |
| Type\_\_c                                        | Picklist                  | Start, End, Job Stop, Break, Refuel, Charge, Depot Reload, Driver Added |
| Location\_\_c                                    | Geolocation               |                                                                         |
| Branch\_\_c                                      | Lookup Fleet\_Branch\_\_c | When the stop is a depot                                                |
| Planned\_Arrival\_\_c / Planned\_Departure\_\_c  | DateTime                  | From the solver                                                         |
| ETA\_\_c / ETA\_Updated\_At\_\_c                 | DateTime                  | Refreshed in-day                                                        |
| Actual\_Arrival\_\_c / Actual\_Departure\_\_c    | DateTime                  | Driver app or geofence from Geotab `Last_Location__c`                   |
| Status\_\_c                                      | Picklist                  | Planned, En Route, Arrived, Completed, Skipped, Failed                  |
| Locked\_\_c                                      | Checkbox                  | Stays pinned during re-optimization (started or promised stops)         |
| Service\_Minutes\_\_c / Wait\_Minutes\_\_c       | Number                    |                                                                         |
| Leg\_Distance\_Km\_\_c / Leg\_Duration\_Min\_\_c | Number                    | Leg from the previous waypoint                                          |
| Reason\_\_c                                      | Text                      | Why it was added or skipped                                             |

### Audit trail and configuration

**Route\_Event\_\_c** — append-only, never updated or deleted.

| Field                                         | Type             | Notes                                                                                                                                           |
| --------------------------------------------- | ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Route\_Plan\_\_c / Route\_\_c / Waypoint\_\_c | Lookups          | Whatever the event touches                                                                                                                      |
| Type\_\_c                                     | Picklist         | Delay Reported, Window Changed, Stop Skipped, Stop Added, Reoptimized, Handoff Proposed, Handoff Approved, Proposal Rejected, Arrived, Departed |
| Actor\_Type\_\_c                              | Picklist         | Driver, Dispatcher, Assistant, System                                                                                                           |
| Actor\_User\_\_c                              | Lookup User      |                                                                                                                                                 |
| Assistant\_Session\_\_c                       | Lookup           | When the change came through the assistant                                                                                                      |
| Payload\_\_c                                  | Long text (JSON) | Before→after difference                                                                                                                         |
| Occurred\_At\_\_c                             | DateTime         |                                                                                                                                                 |

**Capacity\_Dimension\_\_mdt** — records for slots 1–3: Label (Weight, Volume, Pallets, Seats, Totes), Unit\_\_c, Asset\_Field\_\_c (which Fleet\_Asset\_\_c field holds that capacity), Is\_Active\_\_c.

### Changes to existing objects

| Object                                                  | Change                                                                                                                                                          | Why                                                                    |
| ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Fleet\_Asset\_\_c                                       | Add Payload\_Kg\_\_c, Cargo\_Volume\_M3\_\_c, Pallet\_Capacity\_\_c, Vehicle\_Features\_\_c (multi-select: Refrigerated, Lift Gate, Wheelchair Ramp, Tow Hitch) | Gross weight isn't payload, and the solver needs capacity and features |
| Fleet\_Branch\_\_c                                      | Used as the depot. No change                                                                                                                                    | Already has Location\_\_c and Schedule\_\_c                            |
| Schedule\_Assignment\_\_c + Schedule\_Window\_\_c       | Used for driver shifts. No change                                                                                                                               | No Shift object needed                                                 |
| Allocation\_\_c                                         | Created when a route is published                                                                                                                               | Same conflict rules as the motorpool                                   |
| Service\_Ticket\_\_c                                    | An open ticket with In\_Shop\_\_c set makes the asset ineligible                                                                                                | Keeps broken vans out of plans                                         |
| Driver\_Qualification\_\_c, Contact.License\_Class\_\_c | Mapped to skills                                                                                                                                                | Matched against Required\_Skills\_\_c                                  |

**Deliberately left out of v1:**

- Place\_\_c (saved sites with geofence and opening hours)
- Proof of delivery (photo or signature)
- Multi-day routes
- Crews

They can each be added later without breaking the model.

## Routing service architecture

The FleetForce Routing Service is one Cloud Run service, `fleetforce-routing`, with two containers. Our Python API runs the VROOM solver in-process through `pyvroom`. An OSRM sidecar runs on localhost with map data built ahead of time. Salesforce calls the API asynchronously through a Named Credential and writes the result back as records.

### Service components

- **API container** (Python 3.12, FastAPI). It translates FleetForce's neutral JSON into VROOM input, gets a matrix, solves, and returns a neutral result.
  - Matrix sources sit behind an interface: `OsrmMatrix` (sidecar `/table`) and `HaversineMatrix` (straight-line distance at an assumed speed, for tests and when OSRM is down). Later: `GoogleMatrix` for traffic.
  - Solver: `pyvroom` with a custom matrix. If `pyvroom` turns out to be a blocker, call the `vroom` binary or `vroom-express` instead.
- **OSRM sidecar** (`osrm/osrm-backend`, car profile, MLD). The Israel extract comes from Geofabrik, is pre-processed in Cloud Build, and is baked into the image.
- **Auth.** Header `X-FleetForce-Key`, checked against keys in Secret Manager, one per subscriber org (key → org Id). Each request logs org Id, job count, vehicle count and solve time to Cloud Logging, so it can be metered later.
- **Deploy.** Artifact Registry + Cloud Run (`min-instances 0` for dev, 1 for demos), with `cloudbuild.yaml` in the repo.

### API contract (v1)

| Endpoint            | Input                                                                                                                                                                                                                                                                                  | Output                                                                                                                                                 |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /v1/optimize` | `vehicles[]`: id, start/end \[lon, lat\], shift window, capacity\[3\], skills, breaks. `jobs[]`: id, location, service seconds, time windows, delivery/pickup amounts, skills, priority. `shipments[]`: pickup + delivery pairs. `options`: objective, geometry, `fixed[]` (see below) | `routes[]`: vehicle, steps (type, id, arrival, departure, leg distance and duration, load), geometry, totals. `unassigned[]`: id and reason. `summary` |
| `POST /v1/matrix`   | locations\[\]                                                                                                                                                                                                                                                                          | durations\[\]\[\], distances\[\]\[\]                                                                                                                   |
| `POST /v1/route`    | an ordered list of waypoints (for manual reordering)                                                                                                                                                                                                                                   | legs, geometry, totals                                                                                                                                 |
| `GET /healthz`      | —                                                                                                                                                                                                                                                                                      | solver and OSRM status                                                                                                                                 |

**Re-optimizing during the day.** Model it as: vehicle start = its current position and time, plus the remaining unlocked visits only. A locked next stop becomes the start (at its planned departure time). Code should check whether VROOM's `vehicles[].steps` can pin stops more directly, and use it if so.

### On the Salesforce side

- **Callout setup.** Named Credential `FleetForce_Routing` plus an External Credential with a custom header for the key, packaged and namespace-safe like `Claude_API`.
- **Provider interface.** `RoutingProvider` with `optimize`, `matrix` and `route`. Implementations:
  - `FleetForceRoutingProvider` (default)
  - `OrsRoutingProvider` (same VROOM shape, for dev)
  - `MockRoutingProvider` (tests)
  - Later: `GoogleRouteOptimizationProvider`
- **`RoutePlanService`.**
  - `buildRequest(planId)` reads jobs, visits, eligible assets, drivers and shifts, and maps skill names to integers.
  - `applyResult(planId, result)` upserts Route\_\_c and Waypoint\_\_c records, sets `Job_Visit__c.Waypoint__c`, records what couldn't be assigned, and writes a Route\_Event\_\_c.
- **`RoutePlanOptimizeJob`** (Queueable, `Database.AllowsCallouts`). Sets status to Optimizing, makes the callout (timeout up to 120 s), applies the result, then publishes `Route_Plan_Update__e` so the UI refreshes.
- **Rule from the `fleetListMap` bug: no `@AuraEnabled(cacheable=true)` method may make a callout.**

## AI dispatcher

Claude never invents a sequence. Every route change goes through the solver and then a policy check before anything is written. This builds on the existing `AssistantTools` propose → approve → USER\_MODE pattern, with an `Assistant_Session__c` per route (`Record_Object__c = Route__c`).

### Routing tools

| Tool                               | Who can use it     | What it does                                                                    | Writes?             |
| ---------------------------------- | ------------------ | ------------------------------------------------------------------------------- | ------------------- |
| `get_route`                        | Driver, dispatcher | Remaining waypoints, ETAs, windows, load                                        | No                  |
| `report_delay(minutes, reason)`    | Driver             | Moves the route clock forward; logs Delay Reported                              | Event only          |
| `update_window(visit, start, end)` | Driver, dispatcher | Changes a customer's time window                                                | Proposal            |
| `skip_stop(waypoint, reason)`      | Driver             | Marks it Skipped and puts its job back to Ready                                 | Proposal            |
| `add_waypoint(type, near)`         | Driver             | Adds a Break, Refuel, Charge or Driver Added stop                               | Proposal            |
| `reoptimize_remaining(locked[])`   | Driver, dispatcher | Calls `/v1/optimize` for this route and returns the before/after difference     | Proposal            |
| `what_if(change)`                  | Dispatcher         | Runs the solver across the whole plan and returns the difference without saving | No                  |
| `propose_handoff(visit, toRoute)`  | Dispatcher         | Moves a job between routes and re-optimizes both                                | Proposal + approval |

### Policy (`RoutingPolicy` class, settings in custom metadata)

- **Driver can approve alone:** reordering their own route, adding a break or charge stop, reporting a delay.
- **Needs a dispatcher:** anything that breaks a hard window, touches another route, or leaves a job unassigned.
- **Never allowed:** routing a vehicle with an open in-shop ticket, or a driver whose licence or qualification has expired.
- **Every approved change** writes a Route\_Event\_\_c linked to the Assistant\_Session\_\_c.

### Driver app voice mode

- Speech in and out through the browser's Web Speech API.
- Replies are no more than 2 sentences.
- Proposals that need a tap wait until the vehicle is stationary ("confirm when stopped").
- Design for distracted-driving rules in Israel and the US from day one.

### Bring your own model and Agentforce

- **`ModelProvider` interface.** `AssistantClaudeClient` becomes one implementation, alongside:
  - `OpenAICompatibleProvider` (any endpoint with `/chat/completions` tool calling)
  - `SalesforceModelsApiProvider` (Agentforce Models API: Salesforce-managed Claude on Bedrock, or the customer's own Bedrock, Azure OpenAI, OpenAI or Vertex model)

  The tool definitions stay plain JSON Schema. Each adapter only maps message and tool-call formats.

- **Agentforce actions.** Each routing tool is also an `@InvocableMethod` (`RoutingActions`). A customer with Agentforce can then build a "FleetForce Dispatcher" agent on the same logic and policy.
- Agentforce is the enterprise path, not a requirement. Mid-market fleets use the built-in assistant.

## Cloud session work order

The cloud session builds everything that doesn't need an org or GCP credentials. It works on branch `feature/routing-module` of `eladasul-svg/fleetforce-app` and pushes there. A local session then pulls that branch to deploy and test. Nothing needs downloading by hand: git carries it.

These tasks are guidance, not a contract. When Code hits a roadblock, it picks the simplest fix that keeps the shape in Sections 5–7, and records it in `docs/decisions/routing-deviations.md` (what was planned, what was done, why).

### Before you start (local, about 5 minutes)

- [ ] Commit or stash the 10 uncommitted changes on `claude/peaceful-galileo-olirr2`, and push, so the cloud session starts from current code.
- [ ] Save this doc as `docs/decisions/routing-module.md` (export to Markdown), then commit and push.
- [ ] Start the cloud session on the repo, and paste the kickoff prompt below.

### What the cloud session can't do

- It can't authenticate to the Dev Hub or any scratch org, so no deploys and no Apex test runs. Apex is written with tests, but compiled and run locally.
- It has no GCP credentials, so no Cloud Build or Cloud Run deploy. Docker may not be available either.
- **What it can run:** Python (pytest), Node (Jest for LWC), and `sf` commands that don't need an org.

### Tasks, highest value first (if credit runs out, what's done is still useful)

- [ ] **R0 Orient.**
  - Read `docs/decisions/routing-module.md`, `AssistantTools.cls`, `AssistantService.cls`, `AssistantClaudeClient.cls`, `DriverAppController.cls`, and the object folders for Fleet\_Asset\_\_c, Fleet\_Branch\_\_c, Allocation\_\_c, Schedule\_Assignment\_\_c and Driver\_Qualification\_\_c.
  - Check the permission sets in the repo.
  - Create `feature/routing-module`.
- [ ] **R1 Routing service** (`services/routing/`).
  - FastAPI app with `/v1/optimize`, `/v1/matrix`, `/v1/route` and `/healthz`, using pyvroom, `OsrmMatrix` and `HaversineMatrix`.
  - API-key auth, Pydantic schemas (OpenAPI generated from them), Dockerfile, an OSRM pre-processing script (Geofabrik `israel-and-palestine`, car, MLD), `cloudbuild.yaml`, and a Cloud Run multi-container `service.yaml`.
  - pytest fixtures for:
    - (a) 6 vans and 60 drops around the Beer Sheva depot, with time windows and capacity
    - (b) 12-car overnight relocation as pickup→drop shipments
    - (c) re-optimizing the remaining stops after a 40-minute delay, with one stop locked
    - (d) skills that leave a job unassigned with a reason
  - **Done when:** all tests pass with HaversineMatrix, and the README covers running locally with docker compose (OSRM + API).
- [ ] **R2 Metadata.** Objects, fields, picklists and relationships from Section 5. Also: the Capacity\_Dimension\_\_mdt type plus Weight, Volume and Pallets records; the `Route_Plan_Update__e` platform event; tabs; minimal layouts; and permission set field access (captured in source, following the FLS lesson).
  - **Done when:** source files follow the repo's existing conventions, and nothing references something that doesn't exist.
- [ ] **R3 Apex integration.**
  - DTOs, `RoutingProvider`, `FleetForceRoutingProvider` (Named Credential `FleetForce_Routing` + External Credential metadata), `OrsRoutingProvider`, `MockRoutingProvider`, `RoutePlanService` and `RoutePlanOptimizeJob`.
  - Tests use `HttpCalloutMock`, aiming for 90%+ coverage.
  - Keep namespace-safe naming, like `AssistantClaudeClient.namedCredentialName()`.
- [ ] **R4 Assistant tools and policy.**
  - The routing tools from Section 7, added to `AssistantTools` (or a `RoutingAssistantTools` it registers), plus `RoutingPolicy` and the `RoutingActions` invocables.
  - Refactor to a `ModelProvider` interface with Claude as the default, and stubs for the OpenAI-compatible and Models API providers.
  - The existing assistant tests must still pass unchanged.
- [ ] **R5 Demo data.**
  - Extend the dataset plan (`docs/Datasets`, the seeder) with the Beer Sheva depot, 6 vans (2 EVs, one with an open in-shop ticket), drivers including Dana and Yossi, 60 delivery jobs, and the relocation scenario.
  - Use coordinates only, inside the city's bounding box, and relative dates as the current dataset does. No invented street addresses.
- [ ] **R6 UI (stretch).**
  - LWC `routePlanBoard`: map, a list per route, an Optimize button, unassigned jobs.
  - A route tab in the driver app with the assistant panel.
  - Jest tests.
- [ ] **R7 Hand-off.**
  - A `docs/history/` entry, the deviations file, and `docs/Code Work Orders/routing-local-next-steps.md` with exact commands for the local session.
  - Push the branch and open a draft PR.

### Kickoff prompt for the cloud session

```markdown
Read docs/decisions/routing-module.md fully, especially "Research findings" and "Cloud session work order".
Work on branch feature/routing-module. Do tasks R0→R7 in order, committing after each task.
The work order is guidance, not a contract: if something blocks you, choose the simplest
solution that keeps the design's shape and log it in docs/decisions/routing-deviations.md.
You cannot reach a Salesforce org or GCP: write Apex with tests but don't try to deploy;
verify the routing service with pytest using HaversineMatrix.
Follow the repo's existing conventions (namespace fleetforce, USER_MODE, no cacheable callouts,
FLS captured in permission sets). Push and open a draft PR at the end.
```

### Local session afterwards (scope only; R7 writes the commands)

1. Pull the branch and deploy to a scratch org. Run the Apex tests and fix compile errors.
2. Build OSRM data and the image with Cloud Build, deploy to Cloud Run, store the key in Secret Manager, and set the External Credential.
3. Seed the demo data and run the morning and 11:40 scenarios from start to finish.
4. Create a package version and install it into a separate org (the fixed methodology rule: a source deploy is not a package install).

## Open questions

- [ ] US demo region: which state's extract should we pre-build second, for US design partners?
- [ ] Pricing: is routing part of the base licence, or an add-on per vehicle? Traffic-aware ETAs are priced separately either way.
- [ ] Does the driver app stay on the guest Sites setup, or move to Experience Cloud logins once drivers have a route and an assistant session?
- [ ] Will Philips or other leads want SFS integration (SFS ServiceAppointment as a job source) in the first release?

## Sources

- [Vehicle Routing Problem Meets Large Language Models: An Overview and Perspectives (arXiv, Jul 2026)](https://arxiv.org/html/2607.00604v1)
- [Field Service core data model](https://developer.salesforce.com/docs/platform/data-models/guide/field-service-core-data-model.html)
- [ESO limits and limitations](https://help.salesforce.com/s/articleView?id=sf.pfs_enhanced_available_limits.htm&language=en_US&type=5)
- [Salesforce Maps Apex methods](https://developer.salesforce.com/docs/sales/maps-dev-guide/guide/maps-apex-overview.html)
- [Agentforce for Field Service announcement](https://www.salesforce.com/news/stories/agentforce-for-field-service-announcement/)
- [Agentforce supported models and BYOLLM](https://developer.salesforce.com/docs/ai/agentforce/guide/supported-models.html)
- [VROOM](https://github.com/VROOM-Project/vroom)
- [OSRM disk and memory requirements](https://github.com/Project-OSRM/osrm-backend/wiki/Disk-and-Memory-Requirements)
- [Valhalla historical traffic](https://valhalla.github.io/valhalla/concepts/historical-traffic/)
- [openrouteservice restrictions](https://openrouteservice.org/restrictions/)
- [Google Maps Platform pricing list](https://developers.google.com/maps/billing-and-pricing/pricing)
- [Google Route Optimization usage and billing](https://developers.google.com/maps/documentation/route-optimization/usage-and-billing)
- [Route optimization API pricing: 2026 comparison (Kardinal)](https://kardinal.ai/route-optimization-api-pricing-2026-comparison/)
- [Timefold pricing](https://timefold.ai/pricing)
