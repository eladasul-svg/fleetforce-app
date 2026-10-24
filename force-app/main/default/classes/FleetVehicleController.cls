/**
 * Supplies the data behind the fleetVehicleImage LWC: the vehicle's own attributes plus EPA fuel economy
 * from the Vehicle_Model__mdt reference table. A vehicle is matched to its model record by Name with the
 * leading model year and any trailing parenthetical removed ("2023 Ford F-150 Lariat 4WD (On Order)" ->
 * "Ford F-150 Lariat 4WD"). A vehicle with no matching record, or a record without figures, simply has no
 * fuel economy to show.
 */
public with sharing class FleetVehicleController {

    public class VehicleCard {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String bodyType;
        @AuraEnabled public String fuelType;
        @AuraEnabled public String color;
        @AuraEnabled public String licensePlate;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal seatCount;
        @AuraEnabled public Decimal odometer;
        @AuraEnabled public Decimal mpgCity;
        @AuraEnabled public Decimal mpgHighway;
        @AuraEnabled public Decimal mpgCombined;
        @AuraEnabled public Decimal evRangeMiles;
        @AuraEnabled public Boolean epaRated = false;
    }

    @AuraEnabled(cacheable=true)
    public static VehicleCard getCard(Id assetId) {
        try {
            List<fleetforce__Fleet_Asset__c> rows = [
                SELECT Id, Name, fleetforce__Body_Type__c, fleetforce__Fuel_Type__c, fleetforce__Color__c,
                       fleetforce__License_Plate__c, fleetforce__Status__c, fleetforce__Seat_Count__c,
                       fleetforce__Odometer__c
                FROM fleetforce__Fleet_Asset__c
                WHERE Id = :assetId
                WITH USER_MODE
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                return null;
            }
            fleetforce__Fleet_Asset__c a = rows[0];
            VehicleCard c = new VehicleCard();
            c.id = a.Id;
            c.name = a.Name;
            c.bodyType = a.fleetforce__Body_Type__c;
            c.fuelType = a.fleetforce__Fuel_Type__c;
            c.color = a.fleetforce__Color__c;
            c.licensePlate = a.fleetforce__License_Plate__c;
            c.status = a.fleetforce__Status__c;
            c.seatCount = a.fleetforce__Seat_Count__c;
            c.odometer = a.fleetforce__Odometer__c;

            fleetforce__Vehicle_Model__mdt model = modelsByKey().get(modelKey(a.Name));
            if (model != null && model.fleetforce__MPG_Combined__c != null) {
                c.epaRated = true;
                c.mpgCity = model.fleetforce__MPG_City__c;
                c.mpgHighway = model.fleetforce__MPG_Highway__c;
                c.mpgCombined = model.fleetforce__MPG_Combined__c;
                c.evRangeMiles = model.fleetforce__EV_Range_Miles__c;
            }
            return c;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** The reference-data record for a vehicle (matched by name, ignoring model year and any trailing parenthetical). */
    public static fleetforce__Vehicle_Model__mdt modelFor(String assetName) {
        return modelsByKey().get(modelKey(assetName));
    }

    @TestVisible
    private static String modelKey(String assetName) {
        if (String.isBlank(assetName)) {
            return '';
        }
        return assetName.replaceFirst('\\s*\\([^)]*\\)\\s*$', '').replaceFirst('^\\d{4}\\s+', '').trim().toLowerCase();
    }

    private static Map<String, fleetforce__Vehicle_Model__mdt> modelsByKey() {
        Map<String, fleetforce__Vehicle_Model__mdt> out = new Map<String, fleetforce__Vehicle_Model__mdt>();
        for (fleetforce__Vehicle_Model__mdt m : fleetforce__Vehicle_Model__mdt.getAll().values()) {
            if (m.fleetforce__Model_Key__c != null) {
                out.put(m.fleetforce__Model_Key__c.trim().toLowerCase(), m);
            }
        }
        return out;
    }
}
