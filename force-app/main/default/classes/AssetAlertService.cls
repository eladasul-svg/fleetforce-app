/**
 * The one place Asset_Alert__c is read and counted. The record page component (assetDataHealth) and the fleet
 * exposure view (fleetExposure) both read alerts through query(), so the two screens can never disagree.
 *
 * Alert keys (Unique_Key__c) keep every rerun idempotent:
 *   DG:<assetId>:<data type>    stream missing or stale       (owned by DataHealthService)
 *   DGS:<assetId>:<data type>   fewer signals than expected   (owned by DataHealthService)
 *   NT:<noticeId>:<assetId>     recall / regulation match     (owned by NoticeMatchingService)
 * Any other key (for example DGC: consistency gaps from a file import) is left alone by both services.
 */
public with sharing class AssetAlertService {

    public static final Set<String> OPEN_STATUSES = new Set<String>{ 'New', 'Acknowledged', 'In progress' };
    public static final Set<String> CLOSED_STATUSES = new Set<String>{ 'Resolved', 'Dismissed' };
    public static final Map<String, Integer> SEVERITY_RANK = new Map<String, Integer>{
        'Critical' => 0, 'High' => 1, 'Medium' => 2, 'Low' => 3
    };

    /** Which alerts to read. Null members are not applied. */
    public class AlertFilter {
        public Set<Id> assetIds;
        public Set<Id> noticeIds;
        public Boolean openOnly = false;
        public Integer maxRows = 2000;
    }

    public static List<Asset_Alert__c> query(AlertFilter f) {
        List<String> conditions = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
        if (f.assetIds != null) {
            conditions.add('Fleet_Asset__c IN :assetIds');
            binds.put('assetIds', f.assetIds);
        }
        if (f.noticeIds != null) {
            conditions.add('External_Notice__c IN :noticeIds');
            binds.put('noticeIds', f.noticeIds);
        }
        if (f.openOnly == true) {
            conditions.add('Status__c IN :openStatuses');
            binds.put('openStatuses', OPEN_STATUSES);
        }
        binds.put('maxRows', f.maxRows);
        String soql =
            'SELECT Id, Name, Fleet_Asset__c, Fleet_Asset__r.Name, Fleet_Asset__r.License_Plate__c, ' +
            'Fleet_Asset__r.Make__c, Fleet_Asset__r.Model__c, Fleet_Asset__r.Model_Year__c, Fleet_Asset__r.Country__c, ' +
            'Fleet_Asset__r.Data_Health_Score__c, Fleet_Asset__r.Data_Health_Status__c, ' +
            'Alert_Type__c, Severity__c, Status__c, Title__c, Detail__c, Due_Date__c, Unique_Key__c, Resolved_On__c, ' +
            'Data_Stream__c, External_Notice__c, Is_Sample__c, CreatedDate ' +
            'FROM Asset_Alert__c' +
            (conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND ')) +
            ' ORDER BY Due_Date__c ASC NULLS LAST, CreatedDate DESC LIMIT :maxRows';
        return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    /** Most severe first, then earliest due date. */
    public static List<Asset_Alert__c> sortBySeverity(List<Asset_Alert__c> alerts) {
        List<SeverityOrder> wrapped = new List<SeverityOrder>();
        for (Asset_Alert__c a : alerts) {
            wrapped.add(new SeverityOrder(a));
        }
        wrapped.sort();
        List<Asset_Alert__c> out = new List<Asset_Alert__c>();
        for (SeverityOrder w : wrapped) {
            out.add(w.alert);
        }
        return out;
    }

    public static Integer rank(String severity) {
        return SEVERITY_RANK.containsKey(severity) ? SEVERITY_RANK.get(severity) : 4;
    }

    private class SeverityOrder implements Comparable {
        Asset_Alert__c alert;
        SeverityOrder(Asset_Alert__c a) {
            alert = a;
        }
        public Integer compareTo(Object other) {
            Asset_Alert__c b = ((SeverityOrder) other).alert;
            Integer diff = rank(alert.Severity__c) - rank(b.Severity__c);
            if (diff != 0) {
                return diff;
            }
            if (alert.Due_Date__c == b.Due_Date__c) {
                return 0;
            }
            if (alert.Due_Date__c == null) {
                return 1;
            }
            if (b.Due_Date__c == null) {
                return -1;
            }
            return alert.Due_Date__c < b.Due_Date__c ? -1 : 1;
        }
    }

    /** Writes Open_Alert_Count__c on each asset (data gaps, recalls and regulations). */
    public static void recountOpenAlerts(Set<Id> assetIds) {
        assetIds = withoutNulls(assetIds);
        if (assetIds.isEmpty()) {
            return;
        }
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Fleet_Asset__c assetId, COUNT(Id) n
            FROM Asset_Alert__c
            WHERE Fleet_Asset__c IN :assetIds AND Status__c IN :OPEN_STATUSES
            GROUP BY Fleet_Asset__c
        ]) {
            counts.put((Id) ar.get('assetId'), (Integer) ar.get('n'));
        }
        List<Fleet_Asset__c> changed = new List<Fleet_Asset__c>();
        for (Fleet_Asset__c a : [SELECT Id, Open_Alert_Count__c FROM Fleet_Asset__c WHERE Id IN :assetIds]) {
            Integer n = counts.containsKey(a.Id) ? counts.get(a.Id) : 0;
            if (a.Open_Alert_Count__c != n) {
                changed.add(new Fleet_Asset__c(Id = a.Id, Open_Alert_Count__c = n));
            }
        }
        update changed;
    }

    /** Sets an alert's status from the screens; stamps Resolved_On__c when it closes. */
    public static Asset_Alert__c setStatus(Id alertId, String status) {
        if (!OPEN_STATUSES.contains(status) && !CLOSED_STATUSES.contains(status)) {
            throw new IllegalArgumentException('Unknown alert status: ' + status);
        }
        Asset_Alert__c a = [SELECT Id, Status__c, Resolved_On__c FROM Asset_Alert__c WHERE Id = :alertId WITH USER_MODE];
        a.Status__c = status;
        a.Resolved_On__c = CLOSED_STATUSES.contains(status) ? System.now() : null;
        update as user a;
        return a;
    }

    public static Set<Id> withoutNulls(Set<Id> ids) {
        Set<Id> out = new Set<Id>();
        if (ids != null) {
            out.addAll(ids);
            out.remove(null);
        }
        return out;
    }
}
