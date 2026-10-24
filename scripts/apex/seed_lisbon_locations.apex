// Places every Fleet Asset inside Lisbon so the Fleet Map Explorer opens zoomed to a city instead of a continent.
// Assets are grouped by branch: each branch gets a Lisbon neighbourhood as its hub, and the branch's vehicles are
// spread around it on a deterministic sunflower pattern (no randomness, so re-running gives the same map).
// Idempotent. Only touches Last_Location__c.
//
// Usage:  sf apex run --file scripts/apex/seed_lisbon_locations.apex --target-org <alias>

// Hubs, assigned to branches in name order: [latitude, longitude]
List<List<Decimal>> hubs = new List<List<Decimal>>{
    new List<Decimal>{ 38.7350, -9.1450 },   // Saldanha / Avenidas Novas
    new List<Decimal>{ 38.7640, -9.1075 },   // Olivais / Parque das Nacoes (inland edge, the Tagus shore is at about -9.094)
    new List<Decimal>{ 38.7170, -9.1700 },   // Campo de Ourique / Alcantara
    new List<Decimal>{ 38.7550, -9.1750 }    // Lumiar / Benfica
};

Map<Id, Integer> branchHub = new Map<Id, Integer>();
Integer h = 0;
for (fleetforce__Fleet_Branch__c b : [SELECT Id FROM fleetforce__Fleet_Branch__c ORDER BY Name]) {
    branchHub.put(b.Id, Math.mod(h++, hubs.size()));
}

Map<Integer, Integer> seen = new Map<Integer, Integer>();
List<fleetforce__Fleet_Asset__c> assets = [
    SELECT Id, fleetforce__Branch__c FROM fleetforce__Fleet_Asset__c ORDER BY Name
];
for (fleetforce__Fleet_Asset__c a : assets) {
    Integer hub = branchHub.containsKey(a.fleetforce__Branch__c) ? branchHub.get(a.fleetforce__Branch__c) : 0;
    Integer i = seen.containsKey(hub) ? seen.get(hub) : 0;
    seen.put(hub, i + 1);
    Double angle = i * 2.399963;                       // golden angle, radians
    Double radius = Math.min(0.0035 + 0.0022 * Math.sqrt(i), 0.0085);   // degrees; capped (~0.9 km) so no pin reaches the river
    Double lat = hubs[hub][0] + radius * Math.sin(angle);
    Double lon = hubs[hub][1] + radius * Math.cos(angle) * 1.28;   // widen longitude to compensate for latitude
    a.fleetforce__Last_Location__Latitude__s = Decimal.valueOf(lat).setScale(6);
    a.fleetforce__Last_Location__Longitude__s = Decimal.valueOf(lon).setScale(6);
}
update assets;
System.debug('Relocated ' + assets.size() + ' assets to Lisbon');
