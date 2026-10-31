// Multi-currency demo org only (config/demo-multicurrency-scratch-def.json, corporate currency EUR).
// Run by scripts/demo_multicurrency_setup.sh, which first adds GBP, USD and ILS (Apex cannot create currencies).
// Gives every record with money on it the currency of its branch: branches use Currency_Code__c, vehicles and
//    their tickets, line items, citations and fuel logs use the vehicle's Effective_Currency__c. Amounts loaded in the
//    US demo data are scaled from USD into that currency; fuel logs already carry local prices and are not scaled.
// Dynamic on purpose (CurrencyIsoCode exists only in multi-currency orgs). Idempotent: records already in their
// target currency are skipped, so nothing is scaled twice.
//
// Usage:  sf apex run --file scripts/apex/demo_currencies.apex --target-org fleetforce-demo-mc

if (!UserInfo.isMultiCurrencyOrganization()) {
    System.debug('Not a multi-currency org: nothing to do.');
    return;
}
Map<String, Decimal> perEur = new Map<String, Decimal>{ 'EUR' => 1, 'GBP' => 0.84, 'USD' => 1.08, 'ILS' => 4.05 };

Set<String> existing = new Set<String>();
for (SObject c : Database.query('SELECT IsoCode FROM CurrencyType WHERE IsActive = true')) {
    existing.add((String) c.get('IsoCode'));
}
if (!existing.containsAll(perEur.keySet())) {
    // Apex cannot create currencies; scripts/demo_multicurrency_setup.sh adds them through the API first
    System.debug('Missing currencies: run scripts/demo_multicurrency_setup.sh first. Active: ' + existing);
    return;
}

// object -> [path to the currency, scale amounts?]
List<List<Object>> plan = new List<List<Object>>{
    new List<Object>{ 'fleetforce__Fleet_Branch__c', 'fleetforce__Currency_Code__c', false },
    new List<Object>{ 'fleetforce__Fleet_Asset__c', 'fleetforce__Effective_Currency__c', true },
    new List<Object>{ 'fleetforce__Service_Ticket__c', 'fleetforce__Fleet_Asset__r.fleetforce__Effective_Currency__c', true },
    new List<Object>{ 'fleetforce__Service_Line_Item__c', 'fleetforce__Service_Ticket__r.fleetforce__Fleet_Asset__r.fleetforce__Effective_Currency__c', true },
    new List<Object>{ 'fleetforce__Citation__c', 'fleetforce__Fleet_Asset__r.fleetforce__Effective_Currency__c', true },
    new List<Object>{ 'fleetforce__Fuel_Log__c', 'fleetforce__Fleet_Asset__r.fleetforce__Effective_Currency__c', false }
};
for (List<Object> p : plan) {
    String obj = (String) p[0];
    String path = (String) p[1];
    Boolean scale = (Boolean) p[2];
    List<String> money = new List<String>();
    for (Schema.SObjectField f : Schema.getGlobalDescribe().get(obj).getDescribe().fields.getMap().values()) {
        Schema.DescribeFieldResult d = f.getDescribe();
        if (d.getType() == Schema.DisplayType.CURRENCY && d.isUpdateable() && !d.isCalculated()) {
            money.add(d.getName());
        }
    }
    String soql = 'SELECT Id, CurrencyIsoCode, ' + path + (money.isEmpty() ? '' : ', ' + String.join(money, ', ')) + ' FROM ' + obj;
    List<SObject> changed = new List<SObject>();
    for (SObject r : Database.query(soql)) {
        SObject at = r;
        List<String> parts = path.split('\\.');
        for (Integer i = 0; i < parts.size() - 1 && at != null; i++) {
            at = at.getSObject(parts[i]);
        }
        String target = at == null ? null : (String) at.get(parts[parts.size() - 1]);
        if (String.isBlank(target) || !perEur.containsKey(target) || target == r.get('CurrencyIsoCode')) {
            continue;
        }
        SObject u = r.getSObjectType().newSObject(r.Id);
        u.put('CurrencyIsoCode', target);
        if (scale) {
            Decimal factor = perEur.get(target) / perEur.get('USD');
            for (String m : money) {
                Decimal v = (Decimal) r.get(m);
                if (v != null) {
                    u.put(m, (v * factor).setScale(2));
                }
            }
        }
        changed.add(u);
    }
    update changed;
    System.debug(obj + ': ' + changed.size() + ' records set to their branch currency');
}
