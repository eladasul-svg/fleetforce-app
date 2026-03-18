/**
 * GeotabSyncBatch
 * Iterates through all active Telematics_Equipment__c records that have a Geotab_Id__c,
 * fetches live telematics data from Geotab, and updates the parent Fleet_Asset__c record.
 *
 * Run manually:
 *   Database.executeBatch(new GeotabSyncBatch(), 50);
 */
global class GeotabSyncBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, Geotab_Id__c, fleetforce__Fleet_Asset__c
            FROM fleetforce__Telematics_Equipment__c
            WHERE Geotab_Id__c != null
              AND fleetforce__Fleet_Asset__c != null
        ]);
    }

    global void execute(Database.BatchableContext bc, List<fleetforce__Telematics_Equipment__c> scope) {
        // Collect all Geotab Device IDs in this batch
        List<String> geotabIds = new List<String>();
        Map<String, Id> geotabIdToAssetId = new Map<String, Id>();

        for (fleetforce__Telematics_Equipment__c te : scope) {
            geotabIds.add(te.Geotab_Id__c);
            geotabIdToAssetId.put(te.Geotab_Id__c, te.fleetforce__Fleet_Asset__c);
        }

        if (geotabIds.isEmpty()) return;

        try {
            GeotabService svc = new GeotabService();
            svc.authenticate();

            // ── GPS Position ──────────────────────────────────────────────────────
            List<Map<String, Object>> statusInfoList = svc.fetchDeviceStatusInfo(geotabIds);

            // Build: geotabDeviceId → statusInfo map for quick lookup
            Map<String, Map<String, Object>> statusByDeviceId = new Map<String, Map<String, Object>>();
            for (Map<String, Object> info : statusInfoList) {
                Map<String, Object> device = (Map<String, Object>) info.get('device');
                if (device != null && device.containsKey('id')) {
                    statusByDeviceId.put((String) device.get('id'), info);
                }
            }

            // ── Odometer ─────────────────────────────────────────────────────────
            List<Map<String, Object>> odometerData = svc.fetchStatusData(geotabIds, 'DiagnosticOdometerId');
            Map<String, Decimal> odometerByDeviceId = buildLatestValueMap(odometerData);

            // ── Fuel Level ───────────────────────────────────────────────────────
            List<Map<String, Object>> fuelData = svc.fetchStatusData(geotabIds, 'DiagnosticFuelLevelPercentageId');
            Map<String, Decimal> fuelByDeviceId = buildLatestValueMap(fuelData);

            // ── Update Fleet Assets ───────────────────────────────────────────────
            List<fleetforce__Fleet_Asset__c> assetsToUpdate = new List<fleetforce__Fleet_Asset__c>();

            for (String geoId : geotabIds) {
                Id assetId = geotabIdToAssetId.get(geoId);
                if (assetId == null) continue;

                fleetforce__Fleet_Asset__c asset = new fleetforce__Fleet_Asset__c(Id = assetId);

                // Location
                if (statusByDeviceId.containsKey(geoId)) {
                    Map<String, Object> info = statusByDeviceId.get(geoId);
                    asset.fleetforce__Last_Location__Latitude__s  = toDecimal(info.get('latitude'));
                    asset.fleetforce__Last_Location__Longitude__s = toDecimal(info.get('longitude'));
                }

                // Odometer (Geotab returns metres; convert to miles)
                if (odometerByDeviceId.containsKey(geoId)) {
                    Decimal metres = odometerByDeviceId.get(geoId);
                    asset.fleetforce__Odometer__c = metres != null ? (metres / 1609.344).setScale(0) : null;
                }

                // Fuel level (0-1 ratio; convert to percentage)
                if (fuelByDeviceId.containsKey(geoId)) {
                    Decimal fuelRatio = fuelByDeviceId.get(geoId);
                    asset.fleetforce__Fuel_Energy_Level__c = fuelRatio != null ? (fuelRatio * 100).setScale(0) : null;
                }

                assetsToUpdate.add(asset);
            }

            if (!assetsToUpdate.isEmpty()) {
                update assetsToUpdate;
            }

        } catch (Exception e) {
            System.debug('GeotabSyncBatch Error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('GeotabSyncBatch completed.');
    }

    // --------------------------------------------------------------------------
    // Helpers
    // --------------------------------------------------------------------------

    /**
     * Given a list of StatusData maps, returns the most recent value per device.
     */
    private Map<String, Decimal> buildLatestValueMap(List<Map<String, Object>> statusDataList) {
        Map<String, Decimal> result = new Map<String, Decimal>();
        Map<String, DateTime> latestDt = new Map<String, DateTime>();

        for (Map<String, Object> sd : statusDataList) {
            Map<String, Object> device = (Map<String, Object>) sd.get('device');
            if (device == null) continue;

            String devId  = (String) device.get('id');
            Decimal value = toDecimal(sd.get('data'));
            String dtStr  = (String) sd.get('dateTime');
            DateTime dt   = dtStr != null ? (DateTime) JSON.deserialize('"' + dtStr + '"', DateTime.class) : null;

            if (dt != null && (!latestDt.containsKey(devId) || dt > latestDt.get(devId))) {
                latestDt.put(devId, dt);
                result.put(devId, value);
            }
        }
        return result;
    }

    private Decimal toDecimal(Object val) {
        if (val == null) return null;
        try { return Decimal.valueOf(String.valueOf(val)); }
        catch (Exception e) { return null; }
    }
}
