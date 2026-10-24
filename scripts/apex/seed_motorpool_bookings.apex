// Makes the Motorpool booking portal demo-ready:
//  1) widens the bookable pool (status Available) with a mix of sedans, SUVs, hybrids, an EV and pickups;
//  2) creates upcoming reservations and maintenance windows, relative to today, so availability differs by vehicle
//     and by day. With the portal's default search (pick-up in 3 days, return the next day) roughly half the pool
//     is booked or in maintenance.
// Idempotent: its own reservations (Cost_Center__c = 'DEMO-SEED') and blackouts (Source_ID__c = 'DEMO-SEED') are
// deleted and re-created, so run it again whenever the dates need refreshing.
//
// Usage:  sf apex run --file scripts/apex/seed_motorpool_bookings.apex --target-org <alias>

// 1) pool
Set<String> poolNames = new Set<String>{
    '2024 Toyota RAV4 Hybrid XLE', '2024 Hyundai Tucson Hybrid', '2023 Toyota Highlander Hybrid',
    '2024 Honda Accord EX', '2024 Toyota Camry LE', '2023 Subaru Outback Premium',
    '2024 Ford F-150 Lightning Pro EV', '2024 Ford Ranger XLT 4WD', '2022 Ford Transit-250 Cargo Van'
};
List<fleetforce__Fleet_Asset__c> promote = new List<fleetforce__Fleet_Asset__c>();
for (fleetforce__Fleet_Asset__c a : [
    SELECT Id, fleetforce__Status__c FROM fleetforce__Fleet_Asset__c
    WHERE Name IN :poolNames AND fleetforce__Is_Active__c = true AND fleetforce__Status__c != 'Available'
]) {
    a.fleetforce__Status__c = 'Available';
    promote.add(a);
}
update promote;

// 2) bookings
delete [SELECT Id FROM fleetforce__Reservation__c WHERE fleetforce__Cost_Center__c = 'DEMO-SEED'];
delete [SELECT Id FROM fleetforce__Availability_Blackout__c WHERE fleetforce__Source_ID__c = 'DEMO-SEED'];

List<fleetforce__Fleet_Asset__c> pool = [
    SELECT Id, fleetforce__Branch__c FROM fleetforce__Fleet_Asset__c
    WHERE fleetforce__Is_Active__c = true AND fleetforce__Status__c = 'Available' ORDER BY Name
];

// pattern per vehicle (cycled): [kind (R = reservation, M = maintenance, F = free), start day, start hour, end day, end hour]
List<List<Object>> patterns = new List<List<Object>>{
    new List<Object>{ 'R', 2, 8, 4, 17 },    // booked across the default window
    new List<Object>{ 'R', 4, 8, 6, 18 },    // overlaps the end of the default window
    new List<Object>{ 'R', 0, 8, 1, 17 },    // earlier in the week: window is free
    new List<Object>{ 'M', 3, 0, 5, 23 },    // maintenance across the window
    new List<Object>{ 'R', 5, 9, 7, 17 },    // later in the week: window is free
    new List<Object>{ 'R', 3, 9, 3, 18 },    // a single day inside the window
    new List<Object>{ 'M', 1, 8, 2, 18 },    // maintenance earlier: window is free
    new List<Object>{ 'F', 0, 0, 0, 0 }      // nothing booked
};
List<String> firstNames = new List<String>{ 'Ana', 'Miguel', 'Sofia', 'João', 'Marta', 'Rui' };
List<String> lastNames = new List<String>{ 'Costa', 'Ferreira', 'Santos', 'Oliveira', 'Pereira', 'Lopes' };

List<fleetforce__Reservation__c> reservations = new List<fleetforce__Reservation__c>();
List<fleetforce__Availability_Blackout__c> blackouts = new List<fleetforce__Availability_Blackout__c>();
Date today = Date.today();
for (Integer i = 0; i < pool.size(); i++) {
    List<Object> p = patterns[Math.mod(i, patterns.size())];
    String kind = (String) p[0];
    if (kind == 'F') {
        continue;
    }
    Datetime s = Datetime.newInstanceGmt(today.addDays((Integer) p[1]), Time.newInstance((Integer) p[2], 0, 0, 0));
    Datetime e = Datetime.newInstanceGmt(today.addDays((Integer) p[3]), Time.newInstance((Integer) p[4], 0, 0, 0));
    if (kind == 'R') {
        reservations.add(new fleetforce__Reservation__c(
            Name = 'SEED-' + (1000 + i),
            fleetforce__Assigned_Asset__c = pool[i].Id,
            fleetforce__Origin_Branch__c = pool[i].fleetforce__Branch__c,
            fleetforce__Start_Time__c = s, fleetforce__End_Time__c = e,
            fleetforce__Guest_First_Name__c = firstNames[Math.mod(i, firstNames.size())],
            fleetforce__Guest_Last_Name__c = lastNames[Math.mod(i * 5, lastNames.size())],
            fleetforce__Guest_Email__c = 'guest' + i + '@example.com',
            fleetforce__Status__c = 'Approved',
            fleetforce__Cost_Center__c = 'DEMO-SEED'
        ));
    } else {
        blackouts.add(new fleetforce__Availability_Blackout__c(
            fleetforce__Fleet_Asset__c = pool[i].Id,
            fleetforce__Start_Time__c = s, fleetforce__End_Time__c = e,
            fleetforce__Reason__c = 'Maintenance',
            fleetforce__Source_ID__c = 'DEMO-SEED'
        ));
    }
}
insert reservations;
insert blackouts;
System.debug('Pool ' + pool.size() + ' vehicles, promoted ' + promote.size() + ', reservations ' + reservations.size() + ', blackouts ' + blackouts.size());
