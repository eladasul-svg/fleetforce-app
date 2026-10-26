// Makes the Driver app demo-ready for three drivers, each showing different features (all dates relative to today):
//   Chloe Bennett    - on a trip right now, license expiring soon, a new citation, a scheduled service, two upcoming bookings
//   Hannah Lindqvist - vehicle ready for a pre-trip check, medical certificate expiring, one booking
//   Carlos Gomez     - vehicle in the workshop, a recent high-severity telemetry violation, registration expiring
// Idempotent: records it creates are marked in fields the app never shows (Cost_Center__c, Name, Limit__c,
// Approval_Notes__c = 'DEMO-DRIVER') and are deleted and re-created on every run. Run after the main seed and seed_motorpool_bookings.apex.
//
// Usage:  sf apex run --file scripts/apex/seed_driver_app.apex --target-org <alias>

Map<String, Contact> drivers = new Map<String, Contact>();
for (Contact c : [SELECT Id, Name FROM Contact WHERE fleetforce__Contact_Type__c = 'Driver'
                  AND Name IN ('Chloe Bennett', 'Hannah Lindqvist', 'Carlos Gomez')]) {
    drivers.put(c.Name, c);
}
Set<Id> driverIds = new Map<Id, Contact>(drivers.values()).keySet();

// clean up earlier demo records
delete [SELECT Id FROM fleetforce__Reservation__c WHERE fleetforce__Cost_Center__c = 'DEMO-DRIVER'];
delete [SELECT Id FROM fleetforce__Allocation__c WHERE Name LIKE 'TRIP-DEMO%'];
delete [SELECT Id FROM fleetforce__Citation__c WHERE Name = 'DEMO citation' OR fleetforce__Ticket_Number__c LIKE 'DEMO-%'];
delete [SELECT Id FROM fleetforce__Telemetry_Violation__c WHERE fleetforce__Limit__c = 'DEMO-DRIVER'];
delete [SELECT Id FROM fleetforce__Service_Ticket__c WHERE fleetforce__Approval_Notes__c = 'DEMO-DRIVER' OR fleetforce__Summary__c LIKE 'DEMO:%'];

// every demo driver needs a current vehicle: keep the one already assigned, else take their first authorized one
Map<Id, fleetforce__Fleet_Asset__c> carOf = new Map<Id, fleetforce__Fleet_Asset__c>();
for (fleetforce__Fleet_Asset__c a : [
    SELECT Id, Name, fleetforce__Driver__c, fleetforce__Odometer__c FROM fleetforce__Fleet_Asset__c
    WHERE fleetforce__Driver__c IN :driverIds AND fleetforce__Is_Active__c = true ORDER BY Name
]) {
    if (!carOf.containsKey(a.fleetforce__Driver__c)) {
        carOf.put(a.fleetforce__Driver__c, a);
    }
}
List<fleetforce__Fleet_Asset__c> toAssign = new List<fleetforce__Fleet_Asset__c>();
for (Contact c : drivers.values()) {
    if (!carOf.containsKey(c.Id)) {
        for (fleetforce__Authorized_Driver__c ad : [
            SELECT fleetforce__Fleet_Asset__c FROM fleetforce__Authorized_Driver__c
            WHERE fleetforce__Driver__c = :c.Id AND fleetforce__Is_Active__c = true
              AND fleetforce__Fleet_Asset__r.fleetforce__Is_Active__c = true
              AND fleetforce__Fleet_Asset__r.fleetforce__Driver__c = null LIMIT 1
        ]) {
            fleetforce__Fleet_Asset__c a = new fleetforce__Fleet_Asset__c(Id = ad.fleetforce__Fleet_Asset__c, fleetforce__Driver__c = c.Id);
            toAssign.add(a);
        }
    }
}
update toAssign;
for (fleetforce__Fleet_Asset__c a : [
    SELECT Id, Name, fleetforce__Driver__c, fleetforce__Odometer__c FROM fleetforce__Fleet_Asset__c
    WHERE fleetforce__Driver__c IN :driverIds AND fleetforce__Is_Active__c = true ORDER BY Name
]) {
    if (!carOf.containsKey(a.fleetforce__Driver__c)) {
        carOf.put(a.fleetforce__Driver__c, a);
    }
}

// pool vehicles for the bookings
List<fleetforce__Fleet_Asset__c> pool = [
    SELECT Id, fleetforce__Branch__c FROM fleetforce__Fleet_Asset__c
    WHERE fleetforce__Is_Active__c = true AND fleetforce__Status__c = 'Available' AND fleetforce__Driver__c = null ORDER BY Name DESC LIMIT 6
];

List<Contact> contactUpdates = new List<Contact>();
List<fleetforce__Reservation__c> reservations = new List<fleetforce__Reservation__c>();
List<fleetforce__Allocation__c> trips = new List<fleetforce__Allocation__c>();
List<fleetforce__Citation__c> citations = new List<fleetforce__Citation__c>();
List<fleetforce__Telemetry_Violation__c> violations = new List<fleetforce__Telemetry_Violation__c>();
List<fleetforce__Service_Ticket__c> tickets = new List<fleetforce__Service_Ticket__c>();
List<fleetforce__Asset_Document__c> docUpdates = new List<fleetforce__Asset_Document__c>();
Date today = Date.today();

Contact chloe = drivers.get('Chloe Bennett');
if (chloe != null && carOf.containsKey(chloe.Id)) {
    fleetforce__Fleet_Asset__c car = carOf.get(chloe.Id);
    contactUpdates.add(new Contact(Id = chloe.Id, fleetforce__License_Expiry__c = today.addDays(25), fleetforce__Driver_Status__c = 'Active',
        fleetforce__Medical_Cert__c = today.addDays(220)));
    for (fleetforce__Asset_Document__c doc : [
        SELECT Id FROM fleetforce__Asset_Document__c WHERE fleetforce__Fleet_Asset__c = :car.Id AND fleetforce__Doc_Type__c = 'Registration' LIMIT 1
    ]) {
        docUpdates.add(new fleetforce__Asset_Document__c(Id = doc.Id, fleetforce__Valid_Until__c = today.addDays(160), fleetforce__Status__c = 'Current'));
    }
    tickets.add(new fleetforce__Service_Ticket__c(fleetforce__Fleet_Asset__c = car.Id, fleetforce__Reported_By__c = chloe.Id,
        fleetforce__Status__c = 'Draft', fleetforce__Scheduled_Start__c = today.addDays(6), fleetforce__Scheduled_End__c = today.addDays(6),
        fleetforce__Category__c = 'Preventive Maintenance', fleetforce__Priority__c = 'Low', fleetforce__Date_Reported__c = Datetime.now().addDays(-3),
        fleetforce__Summary__c = 'Scheduled service: oil change and tire rotation', fleetforce__Approval_Notes__c = 'DEMO-DRIVER',
        fleetforce__Description__c = 'Routine 15,000 mile service booked at the branch workshop.'));
    trips.add(new fleetforce__Allocation__c(Name = 'TRIP-DEMO-1', fleetforce__Driver__c = chloe.Id, fleetforce__Fleet_Asset__c = car.Id,
        fleetforce__Status__c = 'Active', fleetforce__Actual_Check_Out__c = Datetime.now().addHours(-3),
        fleetforce__Odometer_Start__c = car.fleetforce__Odometer__c, fleetforce__Fuel_Level_Out__c = 82,
        fleetforce__Condition_Out__c = 'All good at pick-up.'));
    citations.add(new fleetforce__Citation__c(Name = 'DEMO citation', fleetforce__Ticket_Number__c = 'CIT-2026-4471', fleetforce__Fleet_Asset__c = car.Id,
        fleetforce__Driver__c = chloe.Id, fleetforce__Violation_Type__c = 'Parking', fleetforce__Status__c = 'New',
        fleetforce__Fine_Amount__c = 65, fleetforce__Total_Amount__c = 65, fleetforce__Citation_Date__c = Datetime.now().addDays(-2),
        fleetforce__Court_Date__c = today.addDays(21)));
    if (pool.size() > 1) {
        reservations.add(new fleetforce__Reservation__c(Name = 'DEMO-D1', fleetforce__Requestor_Contact__c = chloe.Id, fleetforce__Assigned_Asset__c = pool[0].Id,
            fleetforce__Origin_Branch__c = pool[0].fleetforce__Branch__c, fleetforce__Cost_Center__c = 'DEMO-DRIVER', fleetforce__Status__c = 'Approved',
            fleetforce__Start_Time__c = Datetime.newInstanceGmt(today.addDays(1), Time.newInstance(8, 30, 0, 0)),
            fleetforce__End_Time__c = Datetime.newInstanceGmt(today.addDays(1), Time.newInstance(18, 0, 0, 0))));
        reservations.add(new fleetforce__Reservation__c(Name = 'DEMO-D2', fleetforce__Requestor_Contact__c = chloe.Id, fleetforce__Assigned_Asset__c = pool[1].Id,
            fleetforce__Origin_Branch__c = pool[1].fleetforce__Branch__c, fleetforce__Cost_Center__c = 'DEMO-DRIVER', fleetforce__Status__c = 'Pending',
            fleetforce__Start_Time__c = Datetime.newInstanceGmt(today.addDays(5), Time.newInstance(9, 0, 0, 0)),
            fleetforce__End_Time__c = Datetime.newInstanceGmt(today.addDays(6), Time.newInstance(17, 0, 0, 0))));
    }
}

Contact hannah = drivers.get('Hannah Lindqvist');
if (hannah != null && carOf.containsKey(hannah.Id)) {
    contactUpdates.add(new Contact(Id = hannah.Id, fleetforce__Medical_Cert__c = today.addDays(18), fleetforce__Driver_Status__c = 'Active',
        fleetforce__License_Expiry__c = today.addDays(400)));
    if (pool.size() > 2) {
        reservations.add(new fleetforce__Reservation__c(Name = 'DEMO-D3', fleetforce__Requestor_Contact__c = hannah.Id, fleetforce__Assigned_Asset__c = pool[2].Id,
            fleetforce__Origin_Branch__c = pool[2].fleetforce__Branch__c, fleetforce__Cost_Center__c = 'DEMO-DRIVER', fleetforce__Status__c = 'Approved',
            fleetforce__Start_Time__c = Datetime.newInstanceGmt(today.addDays(2), Time.newInstance(10, 0, 0, 0)),
            fleetforce__End_Time__c = Datetime.newInstanceGmt(today.addDays(2), Time.newInstance(16, 0, 0, 0))));
    }
}

Contact carlos = drivers.get('Carlos Gomez');
if (carlos != null && carOf.containsKey(carlos.Id)) {
    fleetforce__Fleet_Asset__c car = carOf.get(carlos.Id);
    contactUpdates.add(new Contact(Id = carlos.Id, fleetforce__Driver_Status__c = 'Active', fleetforce__License_Expiry__c = today.addDays(500)));
    tickets.add(new fleetforce__Service_Ticket__c(fleetforce__Fleet_Asset__c = car.Id, fleetforce__Reported_By__c = carlos.Id,
        fleetforce__Status__c = 'In-Shop', fleetforce__Actual_Start__c = today, fleetforce__Scheduled_Start__c = today,
        fleetforce__Scheduled_End__c = today.addDays(2), fleetforce__Category__c = 'Corrective Repair', fleetforce__Priority__c = 'High',
        fleetforce__Date_Reported__c = Datetime.now().addDays(-1), fleetforce__Summary__c = 'Brake pads and rotor replacement', fleetforce__Approval_Notes__c = 'DEMO-DRIVER',
        fleetforce__Description__c = 'Driver reported grinding when braking. Pads and rotors being replaced.'));
    violations.add(new fleetforce__Telemetry_Violation__c(fleetforce__Fleet_Asset__c = car.Id, fleetforce__Driver__c = carlos.Id,
        fleetforce__Type__c = 'Speeding', fleetforce__Severity__c = 'High', fleetforce__Timestamp__c = Datetime.now().addDays(-1),
        fleetforce__Value__c = '92 mph', fleetforce__Limit__c = 'DEMO-DRIVER'));
    for (fleetforce__Asset_Document__c doc : [
        SELECT Id FROM fleetforce__Asset_Document__c WHERE fleetforce__Fleet_Asset__c = :car.Id AND fleetforce__Doc_Type__c = 'Registration' LIMIT 1
    ]) {
        docUpdates.add(new fleetforce__Asset_Document__c(Id = doc.Id, fleetforce__Valid_Until__c = today.addDays(12), fleetforce__Status__c = 'Expiring Soon'));
    }
}

update contactUpdates;
insert reservations;
insert trips;
insert citations;
insert violations;
insert tickets;
update docUpdates;
System.debug('Driver demo: ' + drivers.size() + ' drivers, ' + reservations.size() + ' reservations, ' + trips.size() + ' open trip, '
    + citations.size() + ' citation, ' + violations.size() + ' violation, ' + tickets.size() + ' ticket');
