// Seeds fleet-manager Tasks (overdue / due today / upcoming) related to Fleet Assets.
// Dates are relative to today so the Home page "Today's Tasks" always has something to show.
// Idempotent: deletes tasks it created earlier (Description starts with [seed]) before re-creating.
// Owner = the running user.
//
// Usage:  sf apex run --file scripts/apex/seed_tasks.apex --target-org <alias>

// Description is long text (not filterable in SOQL), so filter on the marker in Apex.
List<Task> previous = new List<Task>();
for (Task t : [SELECT Id, Description FROM Task WHERE WhatId IN (SELECT Id FROM fleetforce__Fleet_Asset__c)]) {
    if (t.Description != null && t.Description.startsWith('[seed]')) previous.add(t);
}
delete previous;

Id me = UserInfo.getUserId();
Date today = Date.today();
List<Task> out = new List<Task>();

// 1) Registration renewals driven by real Asset Documents (expired -> overdue, expiring soon -> upcoming)
for (fleetforce__Asset_Document__c d : [
    SELECT fleetforce__Fleet_Asset__c, fleetforce__Fleet_Asset__r.fleetforce__License_Plate__c,
           fleetforce__Fleet_Asset__r.Name, fleetforce__Valid_Until__c, fleetforce__Status__c
    FROM fleetforce__Asset_Document__c
    WHERE fleetforce__Doc_Type__c = 'Registration'
      AND fleetforce__Status__c IN ('Expired', 'Expiring Soon', 'Pending Renewal')
    ORDER BY fleetforce__Valid_Until__c
    LIMIT 10
]) {
    String plate = d.fleetforce__Fleet_Asset__r.fleetforce__License_Plate__c;
    Boolean expired = d.fleetforce__Status__c == 'Expired';
    out.add(new Task(
        OwnerId = me, WhatId = d.fleetforce__Fleet_Asset__c,
        Subject = 'Renew registration - ' + (String.isBlank(plate) ? d.fleetforce__Fleet_Asset__r.Name : plate),
        ActivityDate = expired ? today.addDays(-3) : (d.fleetforce__Valid_Until__c < today ? today : d.fleetforce__Valid_Until__c),
        Priority = expired ? 'High' : 'Normal', Status = 'Not Started',
        Description = '[seed] Registration valid until ' + d.fleetforce__Valid_Until__c
    ));
}

// 2) A spread of routine fleet tasks across other assets: [subject, day offset, priority]
List<List<Object>> routine = new List<List<Object>>{
    new List<Object>{ 'Annual safety inspection',            -9, 'High'   },
    new List<Object>{ 'Confirm insurance coverage',          -5, 'High'   },
    new List<Object>{ 'Follow up with vendor on repair ETA', -2, 'Normal' },
    new List<Object>{ 'Tire rotation',                        0, 'Normal' },
    new List<Object>{ 'Review telematics violation',          0, 'High'   },
    new List<Object>{ 'Schedule oil change',                  1, 'Normal' },
    new List<Object>{ 'Driver license check',                 3, 'Normal' },
    new List<Object>{ 'Prepare vehicle for transport',        7, 'Normal' },
    new List<Object>{ 'Title transfer paperwork',            12, 'Normal' },
    new List<Object>{ 'Pre-lease return inspection',         20, 'Low'    }
};
List<fleetforce__Fleet_Asset__c> assets = [
    SELECT Id, fleetforce__License_Plate__c, Name FROM fleetforce__Fleet_Asset__c
    WHERE fleetforce__Is_Active__c = true ORDER BY Name LIMIT 40
];
for (Integer i = 0; i < routine.size() && i < assets.size(); i++) {
    fleetforce__Fleet_Asset__c a = assets[Math.mod(i * 3, assets.size())];
    String label = String.isBlank(a.fleetforce__License_Plate__c) ? a.Name : a.fleetforce__License_Plate__c;
    out.add(new Task(
        OwnerId = me, WhatId = a.Id,
        Subject = (String) routine[i][0] + ' - ' + label,
        ActivityDate = today.addDays((Integer) routine[i][1]),
        Priority = (String) routine[i][2], Status = 'Not Started',
        Description = '[seed] Routine fleet task'
    ));
}

insert out;
System.debug('Seeded ' + out.size() + ' tasks');
