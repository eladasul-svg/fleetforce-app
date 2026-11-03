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
