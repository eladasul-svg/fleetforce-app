public with sharing class FleetKpiController {
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getFleetKpis() {
        Map<String, Integer> kpis = new Map<String, Integer>();
        
        // 1. Active Fleet — vehicles in operational lifecycle states.
        // Excludes Ordered (not yet arrived), Decommissioned, and Retired.
        kpis.put('totalActive', [
            SELECT count() 
            FROM fleetforce__Fleet_Asset__c 
            WHERE fleetforce__Status__c IN ('Available', 'Assigned')
        ]);
        
        // 2. In Maintenance — count of Service Tickets currently in the shop.
        // Counts ticket rows (not distinct vehicles) so the tile matches the
        // list view record count. Motorpool-only demo: Availability_Blackout
        // grounding is out of scope so we avoid depending on it.
        kpis.put('inMaintenance', [
            SELECT count()
            FROM fleetforce__Service_Ticket__c
            WHERE fleetforce__Status__c = 'In-Shop'
        ]);

        // 3. High + Critical Violations in the last 30 days.
        // Uses CreatedDate (indexed) rather than Timestamp__c to stay under
        // query limits and match the list-view filter the tile navigates to.
        kpis.put('criticalViolations', [
            SELECT count()
            FROM fleetforce__Telemetry_Violation__c
            WHERE fleetforce__Severity__c IN ('High', 'Critical')
              AND CreatedDate = LAST_N_DAYS:30
        ]);
        
        // 4. Open Service Tickets — anything not yet Completed.
        // Picklist values are: Draft, In-Shop, Completed.
        kpis.put('openTickets', [
            SELECT count() 
            FROM fleetforce__Service_Ticket__c 
            WHERE fleetforce__Status__c IN ('Draft', 'In-Shop')
        ]);
        
        return kpis;
    }
    
    /**
     * Returns the current location of every active vehicle for the live map.
     * 
     * Reads directly from Fleet_Asset__c.Last_Location__c, which is maintained
     * by GeotabSyncBatch on every sync. This decouples the live-map view from
     * the underlying telemetry storage decision (Custom Object vs. Big Object,
     * single-tier vs. two-tier).
     * 
     * TODO: when telemetry volume grows, evolve Telemetry_Raw__c into a
     * two-tier model — a "latest snapshot" Custom Object for fast reads and
     * a Big Object for historical archive. This method does not need to change.
     */
    @AuraEnabled(cacheable=true)
    public static List<fleetforce__Fleet_Asset__c> getAssetLocations() {
        return [
            SELECT Id, Name,
                   fleetforce__Status__c,
                   fleetforce__Last_Location__Latitude__s,
                   fleetforce__Last_Location__Longitude__s,
                   fleetforce__Driver__c,
                   fleetforce__Driver__r.Name,
                   fleetforce__Branch__c,
                   fleetforce__Branch__r.Name
            FROM fleetforce__Fleet_Asset__c
            WHERE fleetforce__Last_Location__Latitude__s != null
              AND fleetforce__Is_Active__c = true
            LIMIT 200
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static List<fleetforce__Service_Ticket__c> getMaintenanceAlerts() {
        // High-priority or Critical Service Tickets that are not yet Completed.
        // Status picklist: Draft, In-Shop, Completed.
        return [
            SELECT Id, Name, 
                   fleetforce__Fleet_Asset__r.Name, 
                   fleetforce__Priority__c, 
                   fleetforce__Description__c, 
                   fleetforce__Status__c
            FROM fleetforce__Service_Ticket__c
            WHERE fleetforce__Status__c IN ('Draft', 'In-Shop')
              AND fleetforce__Priority__c IN ('High', 'Critical')
            ORDER BY CreatedDate DESC
            LIMIT 10
        ];
    }
}