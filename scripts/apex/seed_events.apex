// Seeds fleet-manager Events (inspections, contract reviews, motorpool returns, service, transport)
// for the next 8 days (today .. today+7), each related to a Fleet Asset, so the Home page
// "Today's Events" card is never empty. Dates are relative to the day the script runs.
// Idempotent: deletes events it created earlier (Description starts with [seed]) before re-creating.
// Owner = the running user. Agreement / Reservation don't have Activities enabled, so every event
// is linked to a Fleet Asset and the agreement/reservation context is in the Subject.
//
// Usage:  sf apex run --file scripts/apex/seed_events.apex --target-org <alias>

// Description is long text (not filterable in SOQL), so filter on the marker in Apex.
List<Event> previous = new List<Event>();
for (Event e : [SELECT Id, Description FROM Event WHERE WhatId IN (SELECT Id FROM fleetforce__Fleet_Asset__c)]) {
    if (e.Description != null && e.Description.startsWith('[seed]')) previous.add(e);
}
delete previous;

Id me = UserInfo.getUserId();
Date today = Date.today();

List<fleetforce__Fleet_Asset__c> assets = [
    SELECT Id, Name, fleetforce__License_Plate__c, fleetforce__Branch__r.Name, fleetforce__Agreement__c
    FROM fleetforce__Fleet_Asset__c WHERE fleetforce__Is_Active__c = true ORDER BY Name LIMIT 60
];
Map<Id, fleetforce__Fleet_Asset__c> byId = new Map<Id, fleetforce__Fleet_Asset__c>(assets);

Map<Id, String> plate = new Map<Id, String>();
for (fleetforce__Fleet_Asset__c a : assets) {
    plate.put(a.Id, String.isBlank(a.fleetforce__License_Plate__c) ? a.Name : a.fleetforce__License_Plate__c);
}

// Event pools: each entry is [subject, location-hint]. Assets are chosen to match where possible.
List<String> templates = new List<String>();   // 'TYPE|subject|assetId|location'

// Contract renewals - active agreements ending soonest, linked to a vehicle under that agreement
for (fleetforce__Agreement__c ag : [
    SELECT Id, Name, fleetforce__Type__c FROM fleetforce__Agreement__c
    WHERE fleetforce__Status__c = 'Active' ORDER BY fleetforce__End_Date__c LIMIT 4
]) {
    for (fleetforce__Fleet_Asset__c a : assets) {
        if (a.fleetforce__Agreement__c == ag.Id) {
            templates.add('RENEW|Contract renewal review - ' + ag.Name + '|' + a.Id + '|Fleet Office (video call)');
            break;
        }
    }
}
// Vehicle returns to the motorpool - assets from reservations
Set<Id> seen = new Set<Id>();
for (fleetforce__Reservation__c r : [
    SELECT fleetforce__Assigned_Asset__c FROM fleetforce__Reservation__c
    WHERE fleetforce__Assigned_Asset__c != null AND fleetforce__Status__c IN ('Active', 'Approved', 'Completed')
    ORDER BY fleetforce__End_Time__c DESC LIMIT 30
]) {
    if (byId.containsKey(r.fleetforce__Assigned_Asset__c) && seen.add(r.fleetforce__Assigned_Asset__c)) {
        fleetforce__Fleet_Asset__c a = byId.get(r.fleetforce__Assigned_Asset__c);
        templates.add('RETURN|Vehicle return to motorpool - ' + plate.get(a.Id) + '|' + a.Id + '|' +
            (a.fleetforce__Branch__r != null ? a.fleetforce__Branch__r.Name : 'Motorpool'));
    }
}
// Inspections, service appointments, transport - rotating through the remaining assets
List<String> kinds = new List<String>{ 'Annual inspection', 'Service appointment', 'Vehicle transport pickup', 'Registration renewal appointment', 'Tire and brake check' };
for (Integer i = 0; i < assets.size() && templates.size() < 40; i++) {
    fleetforce__Fleet_Asset__c a = assets[Math.mod(i * 7 + 2, assets.size())];
    String k = kinds[Math.mod(i, kinds.size())];
    templates.add('MISC|' + k + ' - ' + plate.get(a.Id) + '|' + a.Id + '|' +
        (a.fleetforce__Branch__r != null ? a.fleetforce__Branch__r.Name : 'Motorpool'));
}

// Interleave types so every day mixes contract / return / inspection items.
List<String> ordered = new List<String>();
List<String> renew = new List<String>(), ret = new List<String>(), misc = new List<String>();
for (String t : templates) {
    if (t.startsWith('RENEW')) renew.add(t); else if (t.startsWith('RETURN')) ret.add(t); else misc.add(t);
}
Integer n = Math.max(renew.size(), Math.max(ret.size(), misc.size()));
for (Integer i = 0; i < n; i++) {
    if (i < misc.size()) ordered.add(misc[i]);
    if (i < ret.size()) ordered.add(ret[i]);
    if (i < renew.size()) ordered.add(renew[i]);
}

// 2-3 events per day, today .. today+7
List<Integer> hours = new List<Integer>{ 9, 11, 14 };
List<Event> out = new List<Event>();
Integer idx = 0;
for (Integer day = 0; day <= 7; day++) {
    Date d = today.addDays(day);
    Integer perDay = (day == 0 || Math.mod(day, 2) == 1) ? 3 : 2;
    for (Integer s = 0; s < perDay && ordered.size() > 0; s++) {
        List<String> p = ordered[Math.mod(idx++, ordered.size())].split('\\|');
        Datetime start = Datetime.newInstance(d.year(), d.month(), d.day(), hours[s], 0, 0);
        out.add(new Event(
            OwnerId = me, WhatId = (Id) p[2], Subject = p[1], Location = p[3],
            StartDateTime = start, EndDateTime = start.addMinutes(60),
            Description = '[seed] Fleet manager calendar item'
        ));
    }
}
insert out;
System.debug('Seeded ' + out.size() + ' events');
