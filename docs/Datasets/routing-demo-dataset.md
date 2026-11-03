# Routing demo dataset

The data behind the routing demo script in `docs/decisions/routing-module.md` ("Market and demo choice").
One data model, two stories, both around Beer Sheva. Loaded by `scripts/apex/seed_routing_demo.apex`,
which `scripts/load_demo_data.sh` runs after the other seeds.

**Rules this dataset follows** (same as the main dataset): coordinates only, inside Beer Sheva's
bounding box (lat 31.215–31.290, lon 34.745–34.835), no street addresses (`Job_Visit__c.Address__c` is
left blank); every date is relative to the day the seed runs; re-running deletes and re-creates
everything the seed made. Points come from a fixed-seed generator, so every org gets the same city.

## Story 1: the morning (own-fleet last mile)

| Record                                    | What                                                                              | Why it is there                                                                                                                                                   |
| ----------------------------------------- | --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Fleet_Branch__c` **Beer Sheva Depot**    | 31.2518, 34.7913, Asia/Jerusalem                                                  | Start and end of every van                                                                                                                                        |
| Drivers                                   | Dana Levi, Yossi Cohen, Noa Peretz, Amir Haddad, Shira Ben-David, Omer Katz       | Dana and Yossi are the 11:40 story; Yossi holds a valid **Hazmat** qualification (a skill)                                                                        |
| `Fleet_Asset__c` **BSV-01 … BSV-06**      | 900 kg / 10 m³ / 4 pallets (EVs 700 kg / 8 m³); even numbers have a **Lift Gate** | Capacity in all three `Capacity_Dimension__mdt` slots                                                                                                             |
| **BSV-05 (EV), BSV-06 (EV)**              | `Fuel_Type__c = Electric`                                                         | The optimizer adds a 30-minute **Charge** stop between 11:30 and 13:30                                                                                            |
| **BSV-03**                                | Open service ticket, Status _In-Shop_, started yesterday                          | The optimizer leaves it out ("open in-shop service ticket" in the plan summary)                                                                                   |
| 60 `Route_Job__c` **RTDEMO-DROP-01 … 60** | Delivery, today, 1 visit each                                                     | Windows 08–11, 10–13, 13–16 or none; every 5th windowed visit is a soft window; 10–40 kg and 0.05–0.40 m³ each; every 15th needs a Lift Gate; some priority 10/50 |
| `Route_Plan__c` **Beer Sheva · morning**  | Draft, today, FleetForce Routing, Min Duration                                    | Press Optimize                                                                                                                                                    |

What the demo shows: 5 routes (BSV-03 excluded), Lift Gate drops only on BSV-02/04/06, a Charge
waypoint on both EVs, every window kept.

**11:40, something goes wrong.** Open Dana's route (BSV-01) and the assistant: _"Loading is 40 minutes
late, and Cohen can only take it after 3."_ Claude calls `report_delay(40)`, `update_window(...)` for the
customer, then `reoptimize_remaining` with the next stop locked; the before/after shows one late stop.
As a dispatcher, `propose_handoff` moves that stop to Yossi's route (BSV-02) and needs approval.

## Story 2: overnight relocation (car sharing)

| Record                                                                        | What                                                                                                                                             |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Fleet_Branch__c` **Beer Sheva Car Share Hub**                                | 31.2430, 34.7983 (central station lot)                                                                                                           |
| Drivers Lior Azulay, Maya Friedman, Ido Shapiro on **BSR-01 … 03 relocation** | Shift 22:00–06:00 from the `RTDEMO night relocation` schedule (today's weekday)                                                                  |
| 12 cars **BSC-01 … 12**                                                       | Parked around town (`Last_Location__c`), no branch, so they are not routing vehicles                                                             |
| 12 `Route_Job__c` **RTDEMO-RELOC-01 … 12**                                    | Type Relocation, `Subject_Asset__c` = the car; a Pickup visit at the car and a Delivery visit at the central station, university or hospital lot |
| `Route_Plan__c` **Car share · overnight relocation**                          | Draft, today                                                                                                                                     |

A relocation driver drives one car at a time. That is modelled with capacity slot 3: each car is a load
of 1 there and each relocation driver's "vehicle" has `Pallet_Capacity__c = 1`, so the solver always
drops a car before picking up the next. (Slot 3 is labelled Pallets in `Capacity_Dimension__mdt`; an org
that runs car sharing for real would relabel it Seats.)

## Where the same scenarios are tested

- `services/routing/tests/fixtures.py`: the same depot and bounding box for pytest (morning vans, the
  12-car relocation, the 40-minute delay with a locked stop, skills left unassigned).
- `RoutingTestData.cls`: a smaller version (4 vans, one in the shop, one with an expired licence) for
  the Apex tests.

`seeder.py` and `data/seed.recipe.yml` (Snowfakery) are the older motorpool generators and are not
extended; the routing objects are seeded only by the Apex script.
