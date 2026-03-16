public with sharing class FleetKpiController {
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getFleetKpis() {
        Map<String, Integer> kpis = new Map<String, Integer>();
        
        // 1. Total Active Assets
        kpis.put('totalActive', [SELECT count() FROM fleetforce__Fleet_Asset__c WHERE fleetforce__Status__c = 'Active']);
        
        // 2. Vehicles in Maintenance
        kpis.put('inMaintenance', [SELECT count() FROM fleetforce__Fleet_Asset__c WHERE fleetforce__Status__c = 'Maintenance']);
        
        // 3. Critical Violations (Last 30 Days)
        kpis.put('criticalViolations', [SELECT count() FROM fleetforce__Telemetry_Violation__c WHERE fleetforce__Severity__c = 'Critical' AND fleetforce__Timestamp__c = LAST_N_DAYS:30]);
        
        // 4. Open Service Tickets
        kpis.put('openTickets', [SELECT count() FROM fleetforce__Service_Ticket__c WHERE fleetforce__Status__c IN ('New', 'In Progress', 'Parts Ordered')]);
        
        return kpis;
    }

    @AuraEnabled(cacheable=true)
    public static List<fleetforce__Telemetry_Raw__c> getAssetLocations() {
        return [SELECT Id, fleetforce__Asset_ID__c, fleetforce__Latitude__c, fleetforce__Longitude__c, fleetforce__Timestamp__c 
                FROM fleetforce__Telemetry_Raw__c 
                WHERE fleetforce__Latitude__c != null AND fleetforce__Longitude__c != null
                ORDER BY fleetforce__Timestamp__c DESC LIMIT 50];
    }

    @AuraEnabled(cacheable=true)
    public static List<fleetforce__Service_Ticket__c> getMaintenanceAlerts() {
        // High priority or Critical open tickets
        return [SELECT Id, Name, fleetforce__Fleet_Asset__r.Name, fleetforce__Priority__c, fleetforce__Description__c, fleetforce__Status__c
                FROM fleetforce__Service_Ticket__c
                WHERE fleetforce__Status__c IN ('New', 'In Progress', 'Parts Ordered')
                AND fleetforce__Priority__c IN ('High', 'Critical')
                ORDER BY CreatedDate DESC
                LIMIT 10];
    }
}