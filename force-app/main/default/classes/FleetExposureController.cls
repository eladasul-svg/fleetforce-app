/**
 * Data behind the fleetExposure LWC, the central view: KPI tiles, the notice table, the affected vehicles of one
 * notice (read through AssetAlertService.query, the same query as the record page) and data health by source.
 */
public with sharing class FleetExposureController {

    public class Summary {
        @AuraEnabled public List<TypeCount> openByType = new List<TypeCount>();
        @AuraEnabled public Integer openAlerts = 0;
        @AuraEnabled public Integer vehiclesAtRisk = 0;
        @AuraEnabled public Integer newNotices7d = 0;
        @AuraEnabled public Decimal averageHealth;
        @AuraEnabled public Integer scoredVehicles = 0;
        @AuraEnabled public Boolean isSample = false;
    }

    public class TypeCount {
        @AuraEnabled public String alertType;
        @AuraEnabled public Integer count;
    }

    public class NoticeRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String externalId;
        @AuraEnabled public String title;
        @AuraEnabled public String noticeType;
        @AuraEnabled public String source;
        @AuraEnabled public String sourceUrl;
        @AuraEnabled public String jurisdiction;
        @AuraEnabled public Date publishedOn;
        @AuraEnabled public Date effectiveOn;
        @AuraEnabled public Integer affectedCount;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean reviewed;
        @AuraEnabled public String severity;
        @AuraEnabled public Boolean isSample;
    }

    public class VehicleRow {
        @AuraEnabled public Id alertId;
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String licensePlate;
        @AuraEnabled public String country;
        @AuraEnabled public Integer healthScore;
        @AuraEnabled public String healthStatus;
        @AuraEnabled public String alertStatus;
        @AuraEnabled public Date dueDate;
    }

    public class SourceRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String referenceUrl;
        @AuraEnabled public Integer streams = 0;
        @AuraEnabled public Integer stale = 0;
        @AuraEnabled public Integer staleShare = 0;
        @AuraEnabled public Boolean isSample;
    }

    @AuraEnabled
    public static Summary getSummary() {
        try {
            Summary s = new Summary();
            Map<String, Integer> byType = new Map<String, Integer>{ 'Data gap' => 0, 'Recall' => 0, 'Regulation' => 0 };
            for (AggregateResult ar : [
                SELECT Alert_Type__c t, COUNT(Id) n
                FROM Asset_Alert__c
                WHERE Status__c IN :AssetAlertService.OPEN_STATUSES
                WITH USER_MODE
                GROUP BY Alert_Type__c
            ]) {
                byType.put((String) ar.get('t'), (Integer) ar.get('n'));
            }
            for (String t : byType.keySet()) {
                TypeCount tc = new TypeCount();
                tc.alertType = t;
                tc.count = byType.get(t);
                s.openByType.add(tc);
                s.openAlerts += tc.count;
            }
            AggregateResult health = [
                SELECT AVG(Data_Health_Score__c) avgScore, COUNT(Id) n
                FROM Fleet_Asset__c
                WHERE Data_Health_Score__c != null AND Is_Active__c = true
                WITH USER_MODE
            ];
            Decimal avgScore = (Decimal) health.get('avgScore');
            s.averageHealth = avgScore == null ? null : avgScore.setScale(0, RoundingMode.HALF_UP);
            s.scoredVehicles = (Integer) health.get('n');
            s.vehiclesAtRisk = [
                SELECT COUNT() FROM Fleet_Asset__c
                WHERE Data_Health_Status__c = 'At risk' AND Is_Active__c = true
                WITH USER_MODE
            ];
            Date since = System.today().addDays(-7);
            s.newNotices7d = [
                SELECT COUNT() FROM External_Notice__c
                WHERE Status__c != 'Withdrawn' AND (Published_On__c >= :since OR (Published_On__c = null AND CreatedDate = LAST_N_DAYS:7))
                WITH USER_MODE
            ];
            s.isSample = [SELECT COUNT() FROM External_Notice__c WHERE Is_Sample__c = true WITH USER_MODE] > 0 ||
                         [SELECT COUNT() FROM Data_Source__c WHERE Is_Sample__c = true WITH USER_MODE] > 0;
            return s;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<NoticeRow> getNotices() {
        try {
            List<NoticeRow> out = new List<NoticeRow>();
            for (External_Notice__c n : [
                SELECT Id, Name, External_Id__c, Title__c, Notice_Type__c, Source__c, Source_URL__c, Jurisdiction__c,
                       Published_On__c, Effective_On__c, Affected_Count__c, Status__c, Reviewed__c, Severity__c, Is_Sample__c
                FROM External_Notice__c
                WITH USER_MODE
                ORDER BY Published_On__c DESC NULLS LAST, Name
                LIMIT 500
            ]) {
                NoticeRow r = new NoticeRow();
                r.id = n.Id;
                r.externalId = n.External_Id__c;
                r.title = n.Title__c ?? n.Name;
                r.noticeType = n.Notice_Type__c;
                r.source = n.Source__c;
                r.sourceUrl = n.Source_URL__c;
                r.jurisdiction = n.Jurisdiction__c;
                r.publishedOn = n.Published_On__c;
                r.effectiveOn = n.Effective_On__c;
                r.affectedCount = n.Affected_Count__c == null ? 0 : n.Affected_Count__c.intValue();
                r.status = n.Status__c;
                r.reviewed = n.Reviewed__c;
                r.severity = n.Severity__c;
                r.isSample = n.Is_Sample__c;
                out.add(r);
            }
            return out;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<VehicleRow> getAffectedVehicles(Id noticeId) {
        if (noticeId == null) {
            return new List<VehicleRow>();
        }
        try {
            AssetAlertService.AlertFilter f = new AssetAlertService.AlertFilter();
            f.noticeIds = new Set<Id>{ noticeId };
            List<VehicleRow> out = new List<VehicleRow>();
            for (Asset_Alert__c a : AssetAlertService.query(f)) {
                VehicleRow r = new VehicleRow();
                r.alertId = a.Id;
                r.assetId = a.Fleet_Asset__c;
                r.assetName = a.Fleet_Asset__r.Name;
                r.licensePlate = a.Fleet_Asset__r.License_Plate__c;
                r.country = a.Fleet_Asset__r.Country__c;
                r.healthScore = a.Fleet_Asset__r.Data_Health_Score__c?.intValue();
                r.healthStatus = a.Fleet_Asset__r.Data_Health_Status__c;
                r.alertStatus = a.Status__c;
                r.dueDate = a.Due_Date__c;
                out.add(r);
            }
            return out;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Streams per source and the share that are stale or missing. */
    @AuraEnabled
    public static List<SourceRow> getSourceHealth() {
        try {
            Map<Id, SourceRow> rows = new Map<Id, SourceRow>();
            for (Data_Source__c src : [
                SELECT Id, Name, Source_Type__c, Reference_URL__c, Is_Sample__c
                FROM Data_Source__c
                WITH USER_MODE
                ORDER BY Name
                LIMIT 200
            ]) {
                SourceRow r = new SourceRow();
                r.id = src.Id;
                r.name = src.Name;
                r.sourceType = src.Source_Type__c;
                r.referenceUrl = src.Reference_URL__c;
                r.isSample = src.Is_Sample__c;
                rows.put(src.Id, r);
            }
            for (AggregateResult ar : [
                SELECT Data_Source__c src, Status__c st, COUNT(Id) n
                FROM Data_Stream__c
                WHERE Data_Source__c IN :rows.keySet()
                WITH USER_MODE
                GROUP BY Data_Source__c, Status__c
            ]) {
                SourceRow r = rows.get((Id) ar.get('src'));
                Integer n = (Integer) ar.get('n');
                r.streams += n;
                String st = (String) ar.get('st');
                if (st == 'Stale' || st == 'Missing') {
                    r.stale += n;
                }
            }
            for (SourceRow r : rows.values()) {
                r.staleShare = r.streams == 0 ? 0 : Math.round(100.0 * r.stale / r.streams);
            }
            return rows.values();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
