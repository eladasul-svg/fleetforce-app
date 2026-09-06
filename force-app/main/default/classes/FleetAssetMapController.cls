public with sharing class FleetAssetMapController {

    @AuraEnabled(cacheable=true)
    public static List<fleetforce__Fleet_Asset__c> getAssets(String filter) {
        if (filter == 'Available') {
            return [
                SELECT Id, Name,
                       fleetforce__Status__c,
                       fleetforce__License_Plate__c,
                       fleetforce__Fuel_Energy_Level__c,
                       fleetforce__Fuel_Type__c,
                       fleetforce__Odometer__c,
                       fleetforce__Last_Location__Latitude__s,
                       fleetforce__Last_Location__Longitude__s
                FROM fleetforce__Fleet_Asset__c
                WHERE fleetforce__Status__c = 'Available'
                ORDER BY Name
                LIMIT 200
            ];
        } else if (filter == 'InShop') {
            return [
                SELECT Id, Name,
                       fleetforce__Status__c,
                       fleetforce__License_Plate__c,
                       fleetforce__Fuel_Energy_Level__c,
                       fleetforce__Fuel_Type__c,
                       fleetforce__Odometer__c,
                       fleetforce__Last_Location__Latitude__s,
                       fleetforce__Last_Location__Longitude__s
                FROM fleetforce__Fleet_Asset__c
                WHERE Id IN (
                    SELECT fleetforce__Fleet_Asset__c
                    FROM fleetforce__Service_Ticket__c
                    WHERE fleetforce__Status__c = 'In-Shop'
                )
                ORDER BY Name
                LIMIT 200
            ];
        } else if (filter == 'Critical') {
            return [
                SELECT Id, Name,
                       fleetforce__Status__c,
                       fleetforce__License_Plate__c,
                       fleetforce__Fuel_Energy_Level__c,
                       fleetforce__Fuel_Type__c,
                       fleetforce__Odometer__c,
                       fleetforce__Last_Location__Latitude__s,
                       fleetforce__Last_Location__Longitude__s
                FROM fleetforce__Fleet_Asset__c
                WHERE Id IN (
                    SELECT fleetforce__Fleet_Asset__c
                    FROM fleetforce__Telemetry_Violation__c
                    WHERE fleetforce__Severity__c = 'Critical'
                      AND CreatedDate = LAST_N_DAYS:30
                )
                ORDER BY Name
                LIMIT 200
            ];
        } else {
            return [
                SELECT Id, Name,
                       fleetforce__Status__c,
                       fleetforce__License_Plate__c,
                       fleetforce__Fuel_Energy_Level__c,
                       fleetforce__Fuel_Type__c,
                       fleetforce__Odometer__c,
                       fleetforce__Last_Location__Latitude__s,
                       fleetforce__Last_Location__Longitude__s
                FROM fleetforce__Fleet_Asset__c
                ORDER BY Name
                LIMIT 200
            ];
        }
    }
}
