// Places every Fleet Asset around its own branch (Lisbon, London, Tel Aviv, Chicago in the demo), so each vehicle's
// last location matches where it operates and the Fleet Map Explorer and live tracker show the right city.
// Vehicles are spread around the branch location on a deterministic sunflower pattern (no randomness, so re-running
// gives the same map). A vehicle with no branch, or a branch with no location, goes to central Lisbon.
// Idempotent. Only touches Last_Location__c.
//
// Usage:  sf apex run --file scripts/apex/seed_branch_locations.apex --target-org <alias>

Decimal defaultLat = 38.7350;   // Saldanha, Lisbon
Decimal defaultLon = -9.1450;

Map<Id, List<Decimal>> hubOf = new Map<Id, List<Decimal>>();
for (fleetforce__Fleet_Branch__c b : [
    SELECT Id, fleetforce__Location__Latitude__s, fleetforce__Location__Longitude__s FROM fleetforce__Fleet_Branch__c
]) {
    if (b.fleetforce__Location__Latitude__s != null && b.fleetforce__Location__Longitude__s != null) {
        hubOf.put(b.Id, new List<Decimal>{ b.fleetforce__Location__Latitude__s, b.fleetforce__Location__Longitude__s });
    }
}

Map<String, Integer> seen = new Map<String, Integer>();
List<fleetforce__Fleet_Asset__c> assets = [
    SELECT Id, fleetforce__Branch__c FROM fleetforce__Fleet_Asset__c ORDER BY Name
];
for (fleetforce__Fleet_Asset__c a : assets) {
    List<Decimal> hub = hubOf.containsKey(a.fleetforce__Branch__c)
        ? hubOf.get(a.fleetforce__Branch__c) : new List<Decimal>{ defaultLat, defaultLon };
    String key = String.valueOf(a.fleetforce__Branch__c);
    Integer i = seen.containsKey(key) ? seen.get(key) : 0;
    seen.put(key, i + 1);
    Double angle = i * 2.399963;                                        // golden angle, radians
    Double radius = Math.min(0.0035 + 0.0022 * Math.sqrt(i), 0.0085);   // degrees, capped at about 0.9 km
    Double lat = hub[0] + radius * Math.sin(angle);
    Double lon = hub[1] + radius * Math.cos(angle) / Math.cos(hub[0].doubleValue() * Math.PI / 180);
    a.fleetforce__Last_Location__Latitude__s = Decimal.valueOf(lat).setScale(6);
    a.fleetforce__Last_Location__Longitude__s = Decimal.valueOf(lon).setScale(6);
}
update assets;
System.debug('Placed ' + assets.size() + ' assets around ' + hubOf.size() + ' branches');
