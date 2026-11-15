// Routing demo (docs/Datasets/routing-demo-dataset.md): one data model, two stories.
//   Morning   - Beer Sheva Depot, 6 vans (2 EVs, BSV-03 with an open in-shop ticket), drivers incl. Dana and
//               Yossi, 60 delivery jobs with time windows and loads, a Draft plan for today.
//   Morning, openrouteservice size - Beer Sheva South Depot, 4 vans (BSS-03 in the shop, so 3 are sent),
//               35 drops, a Draft plan set to Openrouteservice (its free key allows 3 vans and 50 stops).
//   Overnight - Beer Sheva Car Share Hub, 3 relocation drivers on a 22:00-06:00 shift, 12 cars to rebalance
//               to three lots as pickup -> drop jobs, a Draft plan for tonight.
// Coordinates only, inside Beer Sheva's bounding box; no street addresses. All dates are relative to today.
// Idempotent: every record it creates is marked (branch names below, asset names BSV-/BSR-/BSC-, contact
// BSS-, contact e-mails @routing-demo.invalid, job External Id RTDEMO-) and deleted and re-created on every run.
// Route events are an append-only audit trail and are left in place.
//
// Usage:  sf apex run --file scripts/apex/seed_routing_demo.apex --target-org <alias>
// Then:   open the "Beer Sheva · morning" Route Plan and press Optimize (or run RoutePlanService.startOptimization).

final String TZ = 'Asia/Jerusalem';
final String DEPOT_NAME = 'Beer Sheva Depot';
final String HUB_NAME = 'Beer Sheva Car Share Hub';
final String SOUTH_NAME = 'Beer Sheva South Depot';
final String MAIL = '@routing-demo.invalid';
final Decimal LAT_MIN = 31.215,
  LAT_MAX = 31.290,
  LON_MIN = 34.745,
  LON_MAX = 34.835;

// Wall-clock time in the depot's time zone.
Datetime localTime(Date d, Integer h, Integer m) {
  Datetime wall = Datetime.newInstanceGmt(d, Time.newInstance(h, m, 0, 0));
  TimeZone z = TimeZone.getTimeZone('Asia/Jerusalem');
  Datetime guess = wall.addSeconds(-z.getOffset(wall) / 1000);
  return wall.addSeconds(-z.getOffset(guess) / 1000);
}

// Deterministic pseudo-random numbers, so every run builds the same city. The state is a one-element list
// because an inner class with a field fails anonymous Apex with an internal server error.
Decimal between(List<Long> state, Decimal lo, Decimal hi) {
  state[0] = Math.mod(state[0] * 1103515245L + 12345L, 2147483648L);
  return (lo + (hi - lo) * (Decimal.valueOf(state[0]) / 2147483648L))
    .setScale(6);
}
List<Long> rng = new List<Long>{ 4471L };

// ── Clean up the previous run ─────────────────────────────────────────────────────────────────
List<fleetforce__Fleet_Branch__c> oldBranches = [
  SELECT Id
  FROM fleetforce__Fleet_Branch__c
  WHERE Name IN (:DEPOT_NAME, :HUB_NAME, :SOUTH_NAME)
];
delete [
  SELECT Id
  FROM fleetforce__Route_Plan__c
  WHERE fleetforce__Depot_Branch__c IN :oldBranches
];
delete [
  SELECT Id
  FROM fleetforce__Route_Job__c
  WHERE fleetforce__External_Id__c LIKE 'RTDEMO-%'
];
List<fleetforce__Fleet_Asset__c> oldAssets = [
  SELECT Id
  FROM fleetforce__Fleet_Asset__c
  WHERE
    fleetforce__Asset_ID__c LIKE 'BS%'
    OR Name LIKE 'BSV-%'
    OR Name LIKE 'BSR-%'
    OR Name LIKE 'BSC-%'
    OR Name LIKE 'BSS-%'
];
delete [
  SELECT Id
  FROM fleetforce__Fuel_Log__c
  WHERE fleetforce__Fleet_Asset__c IN :oldAssets
];
delete [
  SELECT Id
  FROM fleetforce__Carbon_Log__c
  WHERE fleetforce__Fleet_Asset__c IN :oldAssets
];
delete [
  SELECT Id
  FROM fleetforce__Citation__c
  WHERE fleetforce__Fleet_Asset__c IN :oldAssets
];
delete [
  SELECT Id
  FROM fleetforce__Asset_Document__c
  WHERE fleetforce__Fleet_Asset__c IN :oldAssets
];
delete [
  SELECT Id
  FROM fleetforce__Service_Ticket__c
  WHERE fleetforce__Fleet_Asset__c IN :oldAssets
];
delete [
  SELECT Id
  FROM fleetforce__Schedule_Assignment__c
  WHERE fleetforce__Fleet_Asset__c IN :oldAssets
];
delete [
  SELECT Id
  FROM fleetforce__Fleet_Schedule__c
  WHERE Name = 'RTDEMO night relocation'
];
delete oldAssets;
delete [SELECT Id FROM Contact WHERE Email LIKE :('%' + MAIL)];
delete oldBranches;

// ── Branches ──────────────────────────────────────────────────────────────────────────────────
fleetforce__Fleet_Branch__c depot = new fleetforce__Fleet_Branch__c(
  Name = DEPOT_NAME,
  fleetforce__Country__c = 'IL',
  fleetforce__Time_Zone__c = TZ,
  fleetforce__Location__Latitude__s = 31.2518,
  fleetforce__Location__Longitude__s = 34.7913
);
fleetforce__Fleet_Branch__c hub = new fleetforce__Fleet_Branch__c(
  Name = HUB_NAME,
  fleetforce__Country__c = 'IL',
  fleetforce__Time_Zone__c = TZ,
  fleetforce__Location__Latitude__s = 31.2430,
  fleetforce__Location__Longitude__s = 34.7983
);
insert new List<fleetforce__Fleet_Branch__c>{ depot, hub };

// ── Drivers ───────────────────────────────────────────────────────────────────────────────────
List<List<String>> people = new List<List<String>>{
  new List<String>{ 'Dana', 'Levi', 'depot' },
  new List<String>{ 'Yossi', 'Cohen', 'depot' },
  new List<String>{ 'Noa', 'Peretz', 'depot' },
  new List<String>{ 'Amir', 'Haddad', 'depot' },
  new List<String>{ 'Shira', 'Ben-David', 'depot' },
  new List<String>{ 'Omer', 'Katz', 'depot' },
  new List<String>{ 'Lior', 'Azulay', 'hub' },
  new List<String>{ 'Maya', 'Friedman', 'hub' },
  new List<String>{ 'Ido', 'Shapiro', 'hub' }
};
List<Contact> drivers = new List<Contact>();
for (List<String> p : people) {
  drivers.add(
    new Contact(
      FirstName = p[0],
      LastName = p[1],
      Email = p[0].toLowerCase() + '.' + p[1].toLowerCase() + MAIL,
      fleetforce__Contact_Type__c = 'Driver',
      fleetforce__Driver_Status__c = 'Active',
      fleetforce__Driver_Branch__c = p[2] == 'depot' ? depot.Id : hub.Id,
      fleetforce__License_Expiry__c = Date.today().addYears(2)
    )
  );
}
insert drivers;
insert new fleetforce__Driver_Qualification__c(
  fleetforce__Driver__c = drivers[1].Id,
  Name = 'Hazmat',
  fleetforce__Status__c = 'Valid',
  fleetforce__Valid_Until__c = Date.today().addYears(1)
);

// ── Vans at the depot ─────────────────────────────────────────────────────────────────────────
List<fleetforce__Fleet_Asset__c> vans = new List<fleetforce__Fleet_Asset__c>();
for (Integer i = 1; i <= 6; i++) {
  Boolean ev = i >= 5;
  vans.add(
    new fleetforce__Fleet_Asset__c(
      Name = 'BSV-0' + i + (ev ? ' (EV)' : ''),
      fleetforce__Asset_ID__c = 'BSV-0' + i,
      fleetforce__Branch__c = depot.Id,
      fleetforce__Driver__c = drivers[i - 1].Id,
      fleetforce__Status__c = 'Available',
      fleetforce__Is_Active__c = true,
      fleetforce__Fuel_Type__c = ev ? 'Electric' : 'Diesel',
      fleetforce__Engine_Type__c = ev ? 'Electric' : 'Diesel',
      fleetforce__Vehicle_Class__c = 'Commercial',
      fleetforce__Make__c = 'Ford',
      fleetforce__Model__c = ev ? 'E-Transit' : 'Transit-250',
      fleetforce__Model_Year__c = ev ? '2024' : '2023',
      fleetforce__License_Plate__c = '38-' + (100 + i * 13) + '-72',
      fleetforce__Purchase_Price__c = ev ? 54000 : 42000,
      fleetforce__Residual_Value__c = ev ? 36000 : 27000,
      fleetforce__Odometer__c = 15000 + i * 4500,
      fleetforce__Ownership__c = 'Owned',
      fleetforce__Payload_Kg__c = ev ? 700 : 900,
      fleetforce__Cargo_Volume_M3__c = ev ? 8 : 10,
      fleetforce__Pallet_Capacity__c = 4,
      fleetforce__Vehicle_Features__c = Math.mod(i, 2) == 0 ? 'Lift Gate' : null
    )
  );
}
insert vans;
// BSV-03 is in the workshop: the optimizer must leave it out.
insert new fleetforce__Service_Ticket__c(
  fleetforce__Fleet_Asset__c = vans[2].Id,
  fleetforce__Status__c = 'In-Shop',
  fleetforce__Priority__c = 'High',
  fleetforce__Summary__c = 'Brake pads and rotors',
  fleetforce__Actual_Start__c = Date.today().addDays(-1)
);

// ── 60 drops for this morning ─────────────────────────────────────────────────────────────────
List<List<Integer>> slots = new List<List<Integer>>{
  new List<Integer>{ 8, 11 },
  new List<Integer>{ 10, 13 },
  new List<Integer>{ 13, 16 },
  null
};
List<fleetforce__Route_Job__c> jobs = new List<fleetforce__Route_Job__c>();
for (Integer k = 1; k <= 60; k++) {
  jobs.add(
    new fleetforce__Route_Job__c(
      fleetforce__Type__c = 'Delivery',
      fleetforce__Status__c = 'Ready',
      fleetforce__Service_Date__c = Date.today(),
      fleetforce__Branch__c = depot.Id,
      fleetforce__External_Id__c = 'RTDEMO-DROP-' +
        String.valueOf(k).leftPad(2, '0'),
      fleetforce__Priority__c = Math.mod(k, 7) == 0
        ? 50
        : (Math.mod(k, 3) == 0 ? 10 : 0),
      fleetforce__Required_Skills__c = Math.mod(k, 15) == 0
        ? 'Lift Gate'
        : null,
      fleetforce__Notes__c = Math.mod(k, 10) == 0
        ? 'Call on arrival; back gate.'
        : null
    )
  );
}
insert jobs;
List<fleetforce__Job_Visit__c> visits = new List<fleetforce__Job_Visit__c>();
for (Integer k = 1; k <= 60; k++) {
  List<Integer> slot = slots[Math.mod(k, 4)];
  visits.add(
    new fleetforce__Job_Visit__c(
      fleetforce__Route_Job__c = jobs[k - 1].Id,
      fleetforce__Role__c = 'Delivery',
      fleetforce__Location__Latitude__s = between(rng, LAT_MIN, LAT_MAX),
      fleetforce__Location__Longitude__s = between(rng, LON_MIN, LON_MAX),
      fleetforce__Window_Start__c = slot == null
        ? null
        : localTime(Date.today(), slot[0], 0),
      fleetforce__Window_End__c = slot == null
        ? null
        : localTime(Date.today(), slot[1], 0),
      fleetforce__Hard_Window__c = slot != null && Math.mod(k, 5) != 0,
      fleetforce__Service_Minutes__c = 5 + Math.mod(k, 4),
      fleetforce__Load_1__c = 10 + Math.mod(k * 7, 31),
      fleetforce__Load_2__c = (0.05 + Math.mod(k * 3, 8) * 0.05).setScale(2),
      fleetforce__Load_3__c = 0,
      fleetforce__Status__c = 'Pending',
      fleetforce__Access_Notes__c = Math.mod(k, 10) == 0
        ? 'Back gate, code on file'
        : null
    )
  );
}
insert visits;

insert new fleetforce__Route_Plan__c(
  Name = 'Beer Sheva · morning',
  fleetforce__Plan_Date__c = Date.today(),
  fleetforce__Depot_Branch__c = depot.Id,
  fleetforce__Status__c = 'Draft',
  fleetforce__Provider__c = 'FleetForce Routing',
  fleetforce__Objective__c = 'Min Duration',
  fleetforce__Revision__c = 0
);

// ── Morning, openrouteservice size, at the south depot ───────────────────────────────────────
// The same story as above within the openrouteservice free key (3 vans, 50 stops per request): 4 vans,
// BSS-03 in the shop so 3 are sent, the even ones with a Lift Gate, BSS-04 an EV that gets a Charge stop.
// Balanced, so all three vans get work (under Min Duration the solver leaves one idle).
fleetforce__Fleet_Branch__c south = new fleetforce__Fleet_Branch__c(
  Name = SOUTH_NAME,
  fleetforce__Country__c = 'IL',
  fleetforce__Time_Zone__c = TZ,
  fleetforce__Location__Latitude__s = 31.2330,
  fleetforce__Location__Longitude__s = 34.7890
);
insert south;
List<List<String>> southPeople = new List<List<String>>{
  new List<String>{ 'Tal', 'Mizrahi' },
  new List<String>{ 'Eden', 'Biton' },
  new List<String>{ 'Roni', 'Golan' },
  new List<String>{ 'Adi', 'Sasson' }
};
List<Contact> southDrivers = new List<Contact>();
for (List<String> p : southPeople) {
  southDrivers.add(
    new Contact(
      FirstName = p[0],
      LastName = p[1],
      Email = p[0].toLowerCase() + '.' + p[1].toLowerCase() + MAIL,
      fleetforce__Contact_Type__c = 'Driver',
      fleetforce__Driver_Status__c = 'Active',
      fleetforce__Driver_Branch__c = south.Id,
      fleetforce__License_Expiry__c = Date.today().addYears(2)
    )
  );
}
insert southDrivers;
List<fleetforce__Fleet_Asset__c> southVans = new List<fleetforce__Fleet_Asset__c>();
for (Integer i = 1; i <= 4; i++) {
  Boolean ev = i == 4;
  southVans.add(
    new fleetforce__Fleet_Asset__c(
      Name = 'BSS-0' + i + (ev ? ' (EV)' : ''),
      fleetforce__Asset_ID__c = 'BSS-0' + i,
      fleetforce__Branch__c = south.Id,
      fleetforce__Driver__c = southDrivers[i - 1].Id,
      fleetforce__Status__c = 'Available',
      fleetforce__Is_Active__c = true,
      fleetforce__Fuel_Type__c = ev ? 'Electric' : 'Diesel',
      fleetforce__Engine_Type__c = ev ? 'Electric' : 'Diesel',
      fleetforce__Vehicle_Class__c = 'Commercial',
      fleetforce__Make__c = 'Mercedes-Benz',
      fleetforce__Model__c = ev ? 'eSprinter' : 'Sprinter 2500',
      fleetforce__Model_Year__c = ev ? '2024' : '2023',
      fleetforce__License_Plate__c = '49-' + (200 + i * 17) + '-81',
      fleetforce__Purchase_Price__c = ev ? 62000 : 49000,
      fleetforce__Residual_Value__c = ev ? 42000 : 32000,
      fleetforce__Odometer__c = 12000 + i * 3800,
      fleetforce__Ownership__c = 'Owned',
      fleetforce__Payload_Kg__c = ev ? 700 : 900,
      fleetforce__Cargo_Volume_M3__c = ev ? 8 : 10,
      fleetforce__Pallet_Capacity__c = 4,
      fleetforce__Vehicle_Features__c = Math.mod(i, 2) == 0 ? 'Lift Gate' : null
    )
  );
}
insert southVans;
insert new fleetforce__Service_Ticket__c(
  fleetforce__Fleet_Asset__c = southVans[2].Id,
  fleetforce__Status__c = 'In-Shop',
  fleetforce__Priority__c = 'High',
  fleetforce__Summary__c = 'Clutch replacement',
  fleetforce__Actual_Start__c = Date.today().addDays(-1)
);
List<fleetforce__Route_Job__c> southJobs = new List<fleetforce__Route_Job__c>();
for (Integer k = 1; k <= 35; k++) {
  southJobs.add(
    new fleetforce__Route_Job__c(
      fleetforce__Type__c = 'Delivery',
      fleetforce__Status__c = 'Ready',
      fleetforce__Service_Date__c = Date.today(),
      fleetforce__Branch__c = south.Id,
      fleetforce__External_Id__c = 'RTDEMO-SDROP-' +
        String.valueOf(k).leftPad(2, '0'),
      fleetforce__Priority__c = Math.mod(k, 7) == 0
        ? 50
        : (Math.mod(k, 3) == 0 ? 10 : 0),
      fleetforce__Required_Skills__c = Math.mod(k, 8) == 0 ? 'Lift Gate' : null,
      fleetforce__Notes__c = Math.mod(k, 10) == 0
        ? 'Call on arrival; back gate.'
        : null
    )
  );
}
insert southJobs;
List<fleetforce__Job_Visit__c> southVisits = new List<fleetforce__Job_Visit__c>();
for (Integer k = 1; k <= 35; k++) {
  List<Integer> slot = slots[Math.mod(k, 4)];
  southVisits.add(
    new fleetforce__Job_Visit__c(
      fleetforce__Route_Job__c = southJobs[k - 1].Id,
      fleetforce__Role__c = 'Delivery',
      fleetforce__Location__Latitude__s = between(rng, LAT_MIN, LAT_MAX),
      fleetforce__Location__Longitude__s = between(rng, LON_MIN, LON_MAX),
      fleetforce__Window_Start__c = slot == null
        ? null
        : localTime(Date.today(), slot[0], 0),
      fleetforce__Window_End__c = slot == null
        ? null
        : localTime(Date.today(), slot[1], 0),
      fleetforce__Hard_Window__c = slot != null && Math.mod(k, 5) != 0,
      fleetforce__Service_Minutes__c = 5 + Math.mod(k, 4),
      fleetforce__Load_1__c = 10 + Math.mod(k * 7, 31),
      fleetforce__Load_2__c = (0.05 + Math.mod(k * 3, 8) * 0.05).setScale(2),
      fleetforce__Load_3__c = 0,
      fleetforce__Status__c = 'Pending',
      fleetforce__Access_Notes__c = Math.mod(k, 10) == 0
        ? 'Back gate, code on file'
        : null
    )
  );
}
insert southVisits;

insert new fleetforce__Route_Plan__c(
  Name = 'Beer Sheva South · morning',
  fleetforce__Plan_Date__c = Date.today(),
  fleetforce__Depot_Branch__c = south.Id,
  fleetforce__Status__c = 'Draft',
  fleetforce__Provider__c = 'Openrouteservice',
  fleetforce__Objective__c = 'Balanced',
  fleetforce__Revision__c = 0
);

// ── Overnight relocation at the car-share hub ─────────────────────────────────────────────────
// Relocation drivers drive one car at a time: their "vehicle" has capacity 1 in slot 3 and each car
// is a load of 1 there (slot 3 is Pallets in Capacity_Dimension__mdt; see the dataset doc).
fleetforce__Fleet_Schedule__c night = new fleetforce__Fleet_Schedule__c(
  Name = 'RTDEMO night relocation'
);
insert night;
List<String> days = new List<String>{
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday'
};
String weekday = days[
  Math.mod(Date.newInstance(1900, 1, 7).daysBetween(Date.today()), 7)
];
insert new fleetforce__Schedule_Window__c(
  fleetforce__Fleet_Schedule__c = night.Id,
  fleetforce__Day_OfWeek__c = weekday,
  fleetforce__Type__c = 'Available',
  fleetforce__Start_Time__c = Time.newInstance(22, 0, 0, 0),
  fleetforce__End_Time__c = Time.newInstance(6, 0, 0, 0)
);
List<fleetforce__Fleet_Asset__c> shuttles = new List<fleetforce__Fleet_Asset__c>();
for (Integer i = 1; i <= 3; i++) {
  shuttles.add(
    new fleetforce__Fleet_Asset__c(
      Name = 'BSR-0' + i + ' relocation',
      fleetforce__Asset_ID__c = 'BSR-0' + i,
      fleetforce__Branch__c = hub.Id,
      fleetforce__Driver__c = drivers[5 + i].Id,
      fleetforce__Status__c = 'Available',
      fleetforce__Is_Active__c = true,
      fleetforce__Fuel_Type__c = 'Hybrid',
      fleetforce__Engine_Type__c = 'Hybrid',
      fleetforce__Vehicle_Class__c = 'Standard',
      fleetforce__Make__c = 'Toyota',
      fleetforce__Model__c = 'RAV4 Hybrid',
      fleetforce__Model_Year__c = '2024',
      fleetforce__License_Plate__c = '71-' + (300 + i * 19) + '-55',
      fleetforce__Purchase_Price__c = 34000,
      fleetforce__Residual_Value__c = 24000,
      fleetforce__Odometer__c = 8000 + i * 2200,
      fleetforce__Ownership__c = 'Leased',
      fleetforce__Pallet_Capacity__c = 1
    )
  );
}
insert shuttles;
List<fleetforce__Schedule_Assignment__c> assignments = new List<fleetforce__Schedule_Assignment__c>();
for (fleetforce__Fleet_Asset__c s : shuttles) {
  assignments.add(
    new fleetforce__Schedule_Assignment__c(
      fleetforce__Fleet_Schedule__c = night.Id,
      fleetforce__Fleet_Asset__c = s.Id
    )
  );
}
insert assignments;

// The 12 car-share cars are parked around town (no branch, so they are not routing vehicles).
List<fleetforce__Fleet_Asset__c> cars = new List<fleetforce__Fleet_Asset__c>();
for (Integer i = 1; i <= 12; i++) {
  Boolean isTesla = i <= 6;
  cars.add(
    new fleetforce__Fleet_Asset__c(
      Name = 'BSC-' + String.valueOf(i).leftPad(2, '0'),
      fleetforce__Asset_ID__c = 'BSC-' + String.valueOf(i).leftPad(2, '0'),
      fleetforce__Status__c = 'Available',
      fleetforce__Is_Active__c = true,
      fleetforce__Fuel_Type__c = 'Electric',
      fleetforce__Engine_Type__c = 'Electric',
      fleetforce__Vehicle_Class__c = 'Standard',
      fleetforce__Make__c = isTesla ? 'Tesla' : 'Hyundai',
      fleetforce__Model__c = isTesla ? 'Model 3' : 'Ioniq 5',
      fleetforce__Model_Year__c = '2024',
      fleetforce__License_Plate__c = '62-' + (400 + i * 23) + '-14',
      fleetforce__Purchase_Price__c = isTesla ? 42000 : 44000,
      fleetforce__Residual_Value__c = isTesla ? 29000 : 30000,
      fleetforce__Odometer__c = 5000 + i * 1500,
      fleetforce__Ownership__c = 'Owned',
      fleetforce__Last_Location__Latitude__s = between(rng, LAT_MIN, LAT_MAX),
      fleetforce__Last_Location__Longitude__s = between(rng, LON_MIN, LON_MAX)
    )
  );
}
insert cars;
List<List<Decimal>> lots = new List<List<Decimal>>{
  new List<Decimal>{ 31.2430, 34.7983 }, // central station lot
  new List<Decimal>{ 31.2622, 34.8017 }, // university lot
  new List<Decimal>{ 31.2580, 34.8010 } // hospital lot
};
List<fleetforce__Route_Job__c> moves = new List<fleetforce__Route_Job__c>();
for (Integer i = 1; i <= 12; i++) {
  moves.add(
    new fleetforce__Route_Job__c(
      fleetforce__Type__c = 'Relocation',
      fleetforce__Status__c = 'Ready',
      fleetforce__Service_Date__c = Date.today(),
      fleetforce__Branch__c = hub.Id,
      fleetforce__Subject_Asset__c = cars[i - 1].Id,
      fleetforce__External_Id__c = 'RTDEMO-RELOC-' +
        String.valueOf(i).leftPad(2, '0'),
      fleetforce__Priority__c = 0
    )
  );
}
insert moves;
List<fleetforce__Job_Visit__c> legs = new List<fleetforce__Job_Visit__c>();
for (Integer i = 1; i <= 12; i++) {
  List<Decimal> lot = lots[Math.mod(i, 3)];
  legs.add(
    new fleetforce__Job_Visit__c(
      fleetforce__Route_Job__c = moves[i - 1].Id,
      fleetforce__Role__c = 'Pickup',
      fleetforce__Location__Latitude__s = cars[i - 1]
        .fleetforce__Last_Location__Latitude__s,
      fleetforce__Location__Longitude__s = cars[i - 1]
        .fleetforce__Last_Location__Longitude__s,
      fleetforce__Service_Minutes__c = 5,
      fleetforce__Load_3__c = 1,
      fleetforce__Status__c = 'Pending'
    )
  );
  legs.add(
    new fleetforce__Job_Visit__c(
      fleetforce__Route_Job__c = moves[i - 1].Id,
      fleetforce__Role__c = 'Delivery',
      fleetforce__Location__Latitude__s = lot[0],
      fleetforce__Location__Longitude__s = lot[1],
      fleetforce__Service_Minutes__c = 3,
      fleetforce__Load_3__c = 1,
      fleetforce__Status__c = 'Pending'
    )
  );
}
insert legs;

insert new fleetforce__Route_Plan__c(
  Name = 'Car share · overnight relocation',
  fleetforce__Plan_Date__c = Date.today(),
  fleetforce__Depot_Branch__c = hub.Id,
  fleetforce__Status__c = 'Draft',
  fleetforce__Provider__c = 'FleetForce Routing',
  fleetforce__Objective__c = 'Balanced',
  fleetforce__Revision__c = 0
);

// ── Operational Child Records (Fuel, Carbon, Citations, Documents) ───────────
List<fleetforce__Fleet_Asset__c> demoVehicles = new List<fleetforce__Fleet_Asset__c>();
demoVehicles.addAll(vans);
demoVehicles.addAll(southVans);
demoVehicles.addAll(shuttles);

List<fleetforce__Fuel_Log__c> demoFuelLogs = new List<fleetforce__Fuel_Log__c>();
for (Integer v = 0; v < demoVehicles.size(); v++) {
  fleetforce__Fleet_Asset__c a = demoVehicles[v];
  for (Integer k = 1; k <= 3; k++) {
    Boolean isEv = a.fleetforce__Fuel_Type__c == 'Electric';
    Boolean isDiesel = a.fleetforce__Fuel_Type__c == 'Diesel';
    Decimal vol = isEv
      ? (45.0 + Math.mod(v * 7 + k * 3, 20))
      : (isDiesel
          ? (55.0 + Math.mod(v * 5 + k * 4, 25))
          : (35.0 + Math.mod(v * 4 + k * 2, 15)));
    Decimal unitCost = isEv ? 0.35 : (isDiesel ? 1.92 : 1.84);
    Decimal totalCost = (vol * unitCost).setScale(2);
    Decimal eco = isEv ? 3.8 : (isDiesel ? 11.4 : 14.2);
    demoFuelLogs.add(
      new fleetforce__Fuel_Log__c(
        Name = 'FL-' + a.fleetforce__Asset_ID__c + '-' + k,
        fleetforce__Fleet_Asset__c = a.Id,
        fleetforce__Driver__c = a.fleetforce__Driver__c,
        fleetforce__Product_Type__c = isEv
          ? 'Electric Charge.'
          : (isDiesel ? 'Diesel' : 'Petrol'),
        fleetforce__Volume__c = vol,
        fleetforce__Unit_Cost__c = unitCost,
        fleetforce__Total_Cost__c = totalCost,
        fleetforce__Fuel_Economy__c = eco,
        fleetforce__Vendor_Name__c = isEv
          ? 'Afcon EV Charging'
          : (isDiesel ? 'Paz Beer Sheva' : 'Sonol Depot'),
        fleetforce__Transaction_Date__c = Date.today().addDays(-(k * 7 + v)),
        fleetforce__Odometer__c = a.fleetforce__Odometer__c - (k * 280)
      )
    );
  }
}
insert demoFuelLogs;

List<fleetforce__Carbon_Log__c> demoCarbonLogs = new List<fleetforce__Carbon_Log__c>();
for (fleetforce__Fuel_Log__c fl : demoFuelLogs) {
  Boolean isEv = fl.fleetforce__Product_Type__c == 'Electric Charge.';
  Boolean isDiesel = fl.fleetforce__Product_Type__c == 'Diesel';
  Decimal factor = isEv ? 0.3800 : (isDiesel ? 2.6800 : 2.3100);
  demoCarbonLogs.add(
    new fleetforce__Carbon_Log__c(
      Name = 'CL-' + fl.Name,
      fleetforce__Fleet_Asset__c = fl.fleetforce__Fleet_Asset__c,
      fleetforce__Source_Fuel_Log__c = fl.Id,
      fleetforce__Date__c = fl.fleetforce__Transaction_Date__c.date(),
      fleetforce__Scope__c = isEv
        ? 'Scope 2 (Purchased Energy/EV).'
        : 'Scope 1 (Combustion)',
      fleetforce__Calc_Method__c = isEv
        ? 'Regional Grid (EV).'
        : 'Standard EPA',
      fleetforce__Emission_Factor__c = factor,
      fleetforce__CO2_KG__c = (fl.fleetforce__Volume__c * factor).setScale(2),
      fleetforce__Offset_Status__c = isEv ? 'Partially Offset' : 'Unmitigated'
    )
  );
}
insert demoCarbonLogs;

List<fleetforce__Citation__c> demoCitations = new List<fleetforce__Citation__c>();
List<List<Object>> citationConfigs = new List<List<Object>>{
  new List<Object>{
    vans[0],
    drivers[0],
    'Speeding',
    250.00,
    25.00,
    'New',
    'IL-SPD-1001',
    Date.today().addDays(-12)
  },
  new List<Object>{
    vans[1],
    drivers[1],
    'Parking',
    100.00,
    15.00,
    'Paid',
    'BS-PRK-2001',
    Date.today().addDays(-20)
  },
  new List<Object>{
    southVans[0],
    southDrivers[0],
    'Speeding',
    500.00,
    30.00,
    'Contested',
    'IL-SPD-1002',
    Date.today().addDays(-8)
  },
  new List<Object>{
    southVans[1],
    southDrivers[1],
    'Red Light Camera',
    750.00,
    35.00,
    'New',
    'IL-RLC-3001',
    Date.today().addDays(-15)
  },
  new List<Object>{
    vans[3],
    drivers[3],
    'Parking',
    150.00,
    15.00,
    'Paid',
    'BS-PRK-2002',
    Date.today().addDays(-28)
  },
  new List<Object>{
    shuttles[0],
    drivers[6],
    'Toll Evasion',
    180.00,
    20.00,
    'New',
    'IL-TOL-4001',
    Date.today().addDays(-5)
  }
};
for (List<Object> cc : citationConfigs) {
  fleetforce__Fleet_Asset__c a = (fleetforce__Fleet_Asset__c) cc[0];
  Contact d = (Contact) cc[1];
  Decimal fine = (Decimal) cc[3];
  Decimal fee = (Decimal) cc[4];
  demoCitations.add(
    new fleetforce__Citation__c(
      Name = 'DEMO-CIT-' + cc[6],
      fleetforce__Fleet_Asset__c = a.Id,
      fleetforce__Driver__c = d.Id,
      fleetforce__Violation_Type__c = (String) cc[2],
      fleetforce__Fine_Amount__c = fine,
      fleetforce__Admin_Fee__c = fee,
      fleetforce__Total_Amount__c = fine + fee,
      fleetforce__Status__c = (String) cc[5],
      fleetforce__Ticket_Number__c = (String) cc[6],
      fleetforce__Citation_Date__c = (Date) cc[7],
      fleetforce__Issuing_Authority__c = 'Traffic Enforcement'
    )
  );
}
insert demoCitations;

List<fleetforce__Asset_Document__c> demoDocs = new List<fleetforce__Asset_Document__c>();
for (Integer v = 0; v < demoVehicles.size(); v++) {
  fleetforce__Fleet_Asset__c a = demoVehicles[v];
  // 1. Registration
  demoDocs.add(
    new fleetforce__Asset_Document__c(
      Name = 'Registration - ' + a.fleetforce__Asset_ID__c,
      fleetforce__Fleet_Asset__c = a.Id,
      fleetforce__Doc_Type__c = 'Registration',
      fleetforce__Doc_Number__c = 'REG-' + a.fleetforce__Asset_ID__c,
      fleetforce__Issuing_Authority__c = 'Ministry of Transport',
      fleetforce__Compliance_State__c = 'IL',
      fleetforce__Valid_From__c = Date.today().addYears(-1),
      fleetforce__Valid_Until__c = Date.today().addMonths(6),
      fleetforce__Status__c = 'Current'
    )
  );
  // 2. Insurance Card (with a couple expiring soon and one expired)
  Date insExpiry = v == 1
    ? Date.today().addDays(14)
    : (v == 2 ? Date.today().addDays(-5) : Date.today().addMonths(8));
  String insStatus = v == 1
    ? 'Expiring Soon'
    : (v == 2 ? 'Expired' : 'Current');
  demoDocs.add(
    new fleetforce__Asset_Document__c(
      Name = 'Insurance - ' + a.fleetforce__Asset_ID__c,
      fleetforce__Fleet_Asset__c = a.Id,
      fleetforce__Doc_Type__c = 'Insurance Card',
      fleetforce__Doc_Number__c = 'POL-' + a.fleetforce__Asset_ID__c,
      fleetforce__Issuing_Authority__c = 'Harel Fleet Insurance',
      fleetforce__Compliance_State__c = 'IL',
      fleetforce__Valid_From__c = Date.today().addYears(-1),
      fleetforce__Valid_Until__c = insExpiry,
      fleetforce__Status__c = insStatus
    )
  );
  // 3. Inspection Report
  demoDocs.add(
    new fleetforce__Asset_Document__c(
      Name = 'Inspection - ' + a.fleetforce__Asset_ID__c,
      fleetforce__Fleet_Asset__c = a.Id,
      fleetforce__Doc_Type__c = 'Inspection Report',
      fleetforce__Doc_Number__c = 'INSP-' + a.fleetforce__Asset_ID__c,
      fleetforce__Issuing_Authority__c = 'Fleet Safety Bureau',
      fleetforce__Compliance_State__c = 'IL',
      fleetforce__Valid_From__c = Date.today().addMonths(-3),
      fleetforce__Valid_Until__c = Date.today().addMonths(9),
      fleetforce__Status__c = 'Current'
    )
  );
}
insert demoDocs;

System.debug(
  'ROUTING DEMO: 3 branches, ' +
    (drivers.size() + southDrivers.size()) +
    ' drivers, ' +
    vans.size() +
    ' + ' +
    southVans.size() +
    ' vans, ' +
    shuttles.size() +
    ' relocation drivers, ' +
    cars.size() +
    ' cars, ' +
    jobs.size() +
    ' + ' +
    southJobs.size() +
    ' drops, ' +
    moves.size() +
    ' relocations, 3 Draft plans for ' +
    Date.today().format()
);
