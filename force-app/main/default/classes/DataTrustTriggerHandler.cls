/**
 * Trigger logic for the data trust objects. The services set their own running flags while they write, so the
 * writes they make (stream statuses, alerts, affected counts) never re-trigger them.
 */
public with sharing class DataTrustTriggerHandler {

    /** Stream inserted, deleted or changed in anything but the status the service sets: re-evaluate its vehicle. */
    public static void onStreams(List<Data_Stream__c> newList, Map<Id, Data_Stream__c> oldMap) {
        if (DataHealthService.running) {
            return;
        }
        Set<Id> assetIds = new Set<Id>();
        for (Data_Stream__c s : (newList != null ? newList : oldMap.values())) {
            Data_Stream__c old = (oldMap != null && newList != null) ? oldMap.get(s.Id) : null;
            if (old == null || s.Last_Update__c != old.Last_Update__c || s.Signals_Present__c != old.Signals_Present__c ||
                s.Data_Type__c != old.Data_Type__c || s.Fleet_Asset__c != old.Fleet_Asset__c) {
                assetIds.add(s.Fleet_Asset__c);
                if (old != null) {
                    assetIds.add(old.Fleet_Asset__c);
                }
            }
        }
        DataTrustJobs.evaluateSoon(assetIds);
    }

    /** Notice activated, reviewed, withdrawn or its criteria edited: re-match it. */
    public static void onNotices(List<External_Notice__c> newList, Map<Id, External_Notice__c> oldMap) {
        if (NoticeMatchingService.running) {
            return;
        }
        List<String> watched = new List<String>{
            'Status__c', 'Reviewed__c', 'Notice_Type__c', 'Make__c', 'Model__c', 'Year_From__c', 'Year_To__c',
            'Fuel_Type__c', 'Vehicle_Category__c', 'Jurisdiction__c', 'Severity__c', 'Effective_On__c', 'Title__c', 'Summary__c'
        };
        Set<Id> changed = new Set<Id>();
        for (External_Notice__c n : newList) {
            External_Notice__c old = oldMap?.get(n.Id);
            if (old == null) {
                if (NoticeMatchingService.isEligible(n)) {
                    changed.add(n.Id);
                }
                continue;
            }
            for (String f : watched) {
                if (n.get(f) != old.get(f)) {
                    changed.add(n.Id);
                    break;
                }
            }
        }
        DataTrustJobs.matchSoon(changed);
    }

    /**
     * Alert inserted, deleted or its status changed outside the services: recount the vehicle's open alerts, and
     * re-score it when a data gap opened or closed (the consistency score depends on open data gaps).
     */
    public static void onAlerts(List<Asset_Alert__c> newList, Map<Id, Asset_Alert__c> oldMap) {
        if (DataHealthService.running || NoticeMatchingService.running) {
            return;
        }
        Set<Id> recount = new Set<Id>();
        Set<Id> rescore = new Set<Id>();
        for (Asset_Alert__c a : (newList != null ? newList : oldMap.values())) {
            Asset_Alert__c old = (oldMap != null && newList != null) ? oldMap.get(a.Id) : null;
            if (old != null && a.Status__c == old.Status__c && a.Severity__c == old.Severity__c) {
                continue;
            }
            recount.add(a.Fleet_Asset__c);
            if (a.Alert_Type__c == 'Data gap') {
                rescore.add(a.Fleet_Asset__c);
            }
        }
        rescore.remove(null);
        recount.removeAll(rescore);
        if (!rescore.isEmpty()) {
            DataHealthService.evaluate(rescore); // also recounts
        }
        AssetAlertService.recountOpenAlerts(recount);
    }
}
