# Routing module — deviations from the work order

Companion to `routing-module.md`. Each entry: what was planned, what was done, why.
The design's shape is kept throughout: demand (`Route_Job__c` → `Job_Visit__c`) separate from the
plan (`Route_Plan__c` → `Route__c` → `Waypoint__c`), visits pointing to waypoints, an append-only
`Route_Event__c`, and the solver behind `RoutingProvider`.

## R0 Orient

**D-R0-1 · Branch not created.** Planned: create `feature/routing-module`. Done: the branch already
existed on origin (it carries the design doc commit `e2c8de4`), so it was checked out and tracked
instead. Why: the kickoff instruction said so.

**Orientation notes (inputs for later tasks, not deviations):**

- `AssistantToolsTest.definitionsDescribeSixTools` and `AssistantServiceTest` assert that exactly 6
  tools are sent to Claude. Routing tools therefore cannot be added to `AssistantTools.definitions()`;
  they are added only for sessions opened on a `Route__c` record (see R4).
- `Service_Ticket__c.In_Shop__c` is a formula checkbox (started and not ended), so "open in-shop
  ticket" is read directly from it.
- Fuel type `Electric` (global value set `Fuel_Type`) identifies EVs; `Fleet_Asset__c.Max_Range__c`
  and `Battery_Capacity_kWh__c` already exist.
- Permission sets: `FleetforceAdmin`/`FleetAdmin` are large admin sets, `FleetforceAssistantUser`
  grants only the assistant objects. Routing FLS goes in a new `FleetforceRouting` set (see R2).

## R1 Routing service

**D-R1-1 · Locked stops are played forward by the service, not pinned through VROOM.** Planned:
check whether VROOM's `vehicles[].steps` can pin stops. Done: it cannot as a hard constraint (it is an
initial-solution hint), so `options.fixed[] = {vehicle_id, task_ids[]}` is simulated in the service
from the vehicle's start and clock, and the solver starts from the last locked stop at its departure
time, exactly as the design's fallback describes. A locked stop that is already past its window is
kept and reported with `late_seconds`.

**D-R1-2 · Skill names are mapped to integers in the service, not in Apex.** Planned:
`RoutePlanService.buildRequest` maps skill names to integers. Done: the contract takes skill strings
and the service maps them. Why: one mapping in one place, readable requests in logs, and the Apex
stays provider-neutral (ORS/Google adapters would need their own mapping anyway).

**D-R1-3 · Unassigned reasons are diagnosed by the service.** VROOM reports which tasks it could not
place but not why. The service checks skills, then capacity, then reachability inside the time window
and shift, and otherwise reports `no_room`.

**D-R1-4 · OSRM image.** The design names `osrm/osrm-backend`; the maintained image is now published as
`ghcr.io/project-osrm/osrm-backend` (same project), pinned to `v5.27.1`. The VROOM docker image is not
needed because VROOM runs in-process through `pyvroom` 1.15.2, as designed.

**D-R1-5 · `balanced` objective.** VROOM has no workload-balancing objective, so `balanced` caps tasks
per vehicle at ⌈tasks / vehicles⌉ + 1 and adds a distance cost. `min_vehicles` adds a large fixed cost
per vehicle used.

**D-R1-6 · Docker not exercised here.** The cloud session has Docker on the path but no daemon access was
tried and there are no GCP credentials; the Dockerfiles, compose file, `cloudbuild.yaml` and
`service.yaml` are written but unbuilt. All 35 pytest tests run on `HaversineMatrix`, with OSRM
responses mocked through `httpx.MockTransport`.
