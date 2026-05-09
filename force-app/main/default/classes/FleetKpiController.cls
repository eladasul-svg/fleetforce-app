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
        
        // 2. In Maintenance — count of distinct vehicles with an open Service Ticket
        // currently in the shop. We count Service_Ticket rows grouped by asset,
        // not Fleet_Asset directly, so this reflects actual work-in-progress
        // rather than a derived availability flag.
        AggregateResult[] inShopAgg = [
            SELECT COUNT_DISTINCT(fleetforce__Fleet_Asset__c) assetCount
            FROM fleetforce__Service_Ticket__c
            WHERE fleetforce__Status__c = 'In-Shop'
        ];
        Integer inMaintenanceCount = (inShopAgg.isEmpty() || inShopAgg[0].get('assetCount') == null)
            ? 0
            : (Integer) inShopAgg[0].get('assetCount');
        kpis.put('inMaintenance', inMaintenanceCount);
        
        // 3. Critical Violations in the last 30 days.
        kpis.put('criticalViolations', [
            SELECT count() 
            FROM fleetforce__Telemetry_Violation__c 
            WHERE fleetforce__Severity__c = 'Critical' 
              AND fleetforce__Timestamp__c = LAST_N_DAYS:30
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
                   fleetforce__Availability_Status__c,
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