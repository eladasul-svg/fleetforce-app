/**
 * Data health evaluation for fleet assets. For each vehicle it:
 *   1. resolves the stream profile (override, else the highest-priority active matching profile, else the default);
 *   2. sets each stream's Status__c (Healthy within the max age, Stale beyond it, Missing if never received);
 *   3. creates or auto-resolves Data gap alerts, keyed by Unique_Key__c so reruns never duplicate;
 *   4. writes the score fields on the asset.
 *
 * Score (0-100) = 0.4 x Freshness + 0.4 x Completeness + 0.2 x Consistency, each part rounded to a whole number first.
 *   Freshness    average over the required profile lines: 100 if the freshest stream of that type is within
 *                Max_Age_Hours__c, falling linearly to 0 at three times that age; a missing stream scores 0.
 *                A profile with no required lines scores 100 if the vehicle has any stream, else 0.
 *   Completeness signals present across all the vehicle's streams / Expected_Signal_Count__c, capped at 100.
 *   Consistency  100 minus open Data gap alert penalties (Critical 40, High 25, Medium 10, Low 5), floor 0.
 *   Bands        85+ Healthy, 60-84 Watch, below 60 At risk.
 * Recall and regulation alerts never change the score.
 *
 * Bulk-safe: a fixed number of queries and DML statements per call, whatever the number of assets.
 */
public with sharing class DataHealthService {

    public static final Map<String, Integer> PENALTY = new Map<String, Integer>{
        'Critical' => 40, 'High' => 25, 'Medium' => 10, 'Low' => 5
    };

    /** True while the service writes, so the triggers it fires do not re-enqueue it. */
    public static Boolean running = false;

    @TestVisible
    private static Datetime nowOverride;

    private static Datetime now() {
        return nowOverride != null ? nowOverride : System.now();
    }

    /** The result for one vehicle; also what the record page shows. */
    public class Result {
        public Id assetId;
        public Id profileId;
        public Integer freshness;
        public Integer completeness;
        public Integer consistency;
        public Integer score;
        public String status;
    }

    public static Map<Id, Result> evaluate(Set<Id> assetIds) {
        assetIds = AssetAlertService.withoutNulls(assetIds);
        Map<Id, Result> results = new Map<Id, Result>();
        if (assetIds.isEmpty()) {
            return results;
        }
        Boolean wasRunning = running;
        running = true;
        try {
            results = doEvaluate(assetIds);
        } finally {
            running = wasRunning;
        }
        return results;
    }

    private static Map<Id, Result> doEvaluate(Set<Id> assetIds) {
        Datetime nowTs = now();
        List<Fleet_Asset__c> assets = [
            SELECT Id, Name, Make__c, Model__c, Fuel_Type__c, Vehicle_Class__c, Stream_Profile_Override__c
            FROM Fleet_Asset__c
            WHERE Id IN :assetIds
        ];
        List<Stream_Profile__c> profiles = [
            SELECT Id, Name, Expected_Signal_Count__c, Make__c, Model__c, Fuel_Type__c, Vehicle_Category__c,
                   Is_Default__c, Priority__c, Active__c,
                   (SELECT Id, Data_Type__c, Required__c, Max_Age_Hours__c, Min_Signals__c FROM Lines__r)
            FROM Stream_Profile__c
            ORDER BY Priority__c ASC NULLS LAST, Name ASC
        ];
        Map<Id, Stream_Profile__c> profileById = new Map<Id, Stream_Profile__c>(profiles);

        Map<Id, List<Data_Stream__c>> streamsByAsset = new Map<Id, List<Data_Stream__c>>();
        for (Data_Stream__c s : [
            SELECT Id, Fleet_Asset__c, Data_Type__c, Last_Update__c, Signals_Present__c, Status__c, Is_Sample__c,
                   Data_Source__r.Name, Data_Source__r.Expected_Frequency_Hours__c
            FROM Data_Stream__c
            WHERE Fleet_Asset__c IN :assetIds
        ]) {
            if (!streamsByAsset.containsKey(s.Fleet_Asset__c)) {
                streamsByAsset.put(s.Fleet_Asset__c, new List<Data_Stream__c>());
            }
            streamsByAsset.get(s.Fleet_Asset__c).add(s);
        }

        // existing data gap alerts this service owns, plus every open data gap alert (for the consistency penalty)
        Map<String, Asset_Alert__c> ownedByKey = new Map<String, Asset_Alert__c>();
        Map<Id, List<Asset_Alert__c>> ownedByAsset = new Map<Id, List<Asset_Alert__c>>();
        Map<Id, List<Asset_Alert__c>> otherOpenGaps = new Map<Id, List<Asset_Alert__c>>();
        for (Asset_Alert__c a : [
            SELECT Id, Fleet_Asset__c, Unique_Key__c, Status__c, Severity__c, Title__c, Detail__c, Data_Stream__c, Is_Sample__c
            FROM Asset_Alert__c
            WHERE Fleet_Asset__c IN :assetIds AND Alert_Type__c = 'Data gap'
        ]) {
            if (isOwnedKey(a.Unique_Key__c)) {
                ownedByKey.put(a.Unique_Key__c, a);
                if (!ownedByAsset.containsKey(a.Fleet_Asset__c)) {
                    ownedByAsset.put(a.Fleet_Asset__c, new List<Asset_Alert__c>());
                }
                ownedByAsset.get(a.Fleet_Asset__c).add(a);
            } else if (AssetAlertService.OPEN_STATUSES.contains(a.Status__c)) {
                if (!otherOpenGaps.containsKey(a.Fleet_Asset__c)) {
                    otherOpenGaps.put(a.Fleet_Asset__c, new List<Asset_Alert__c>());
                }
                otherOpenGaps.get(a.Fleet_Asset__c).add(a);
            }
        }

        List<Data_Stream__c> streamUpdates = new List<Data_Stream__c>();
        Map<String, Asset_Alert__c> alertUpserts = new Map<String, Asset_Alert__c>();
        List<Fleet_Asset__c> assetUpdates = new List<Fleet_Asset__c>();
        Map<Id, Result> results = new Map<Id, Result>();

        for (Fleet_Asset__c asset : assets) {
            Stream_Profile__c profile = resolveProfile(asset, profiles, profileById);
            List<Data_Stream__c> streams = streamsByAsset.containsKey(asset.Id)
                ? streamsByAsset.get(asset.Id)
                : new List<Data_Stream__c>();
            List<Stream_Profile_Line__c> lines = profile == null ? new List<Stream_Profile_Line__c>() : profile.Lines__r;
            Boolean sample = false;

            // max age per data type from the profile, and the freshest stream per type
            Map<String, Stream_Profile_Line__c> lineByType = new Map<String, Stream_Profile_Line__c>();
            for (Stream_Profile_Line__c l : lines) {
                lineByType.put(l.Data_Type__c, l);
            }
            Map<String, Data_Stream__c> freshestByType = new Map<String, Data_Stream__c>();
            Decimal signals = 0;
            for (Data_Stream__c s : streams) {
                sample = sample || s.Is_Sample__c;
                signals += s.Signals_Present__c == null ? 0 : s.Signals_Present__c;
                Decimal maxAge = lineByType.containsKey(s.Data_Type__c)
                    ? lineByType.get(s.Data_Type__c).Max_Age_Hours__c
                    : s.Data_Source__r?.Expected_Frequency_Hours__c;
                String st = streamStatus(s.Last_Update__c, maxAge, nowTs);
                if (s.Status__c != st) {
                    streamUpdates.add(new Data_Stream__c(Id = s.Id, Status__c = st));
                }
                Data_Stream__c best = freshestByType.get(s.Data_Type__c);
                if (best == null || (s.Last_Update__c != null && (best.Last_Update__c == null || s.Last_Update__c > best.Last_Update__c))) {
                    freshestByType.put(s.Data_Type__c, s);
                }
            }

            // freshness and the data gaps the profile implies
            Map<String, Asset_Alert__c> wanted = new Map<String, Asset_Alert__c>();
            Decimal freshnessSum = 0;
            Integer requiredCount = 0;
            for (Stream_Profile_Line__c l : lines) {
                if (l.Required__c != true) {
                    continue;
                }
                requiredCount++;
                Data_Stream__c s = freshestByType.get(l.Data_Type__c);
                Decimal ageH = (s == null || s.Last_Update__c == null) ? null : hoursBetween(s.Last_Update__c, nowTs);
                freshnessSum += lineFreshness(ageH, l.Max_Age_Hours__c);

                String key = 'DG:' + asset.Id + ':' + l.Data_Type__c;
                if (ageH == null) {
                    wanted.put(key, gap(asset.Id, key, 'High', s,
                        'No ' + l.Data_Type__c.toLowerCase() + ' data received',
                        'The vehicle\'s stream profile (' + profile.Name + ') requires ' + l.Data_Type__c.toLowerCase() +
                        ' data, but no source has delivered any for this vehicle.'));
                } else if (l.Max_Age_Hours__c != null && ageH > l.Max_Age_Hours__c) {
                    String sev = ageH >= 3 * l.Max_Age_Hours__c ? 'High' : 'Medium';
                    wanted.put(key, gap(asset.Id, key, sev, s,
                        l.Data_Type__c + ' data is stale',
                        'Last update ' + describeAge(ageH) + ' ago from ' + (s.Data_Source__r?.Name ?? 'the source') +
                        '; the profile allows ' + describeAge(l.Max_Age_Hours__c) + '.'));
                }
                if (s != null && l.Min_Signals__c != null && (s.Signals_Present__c ?? 0) < l.Min_Signals__c) {
                    String sKey = 'DGS:' + asset.Id + ':' + l.Data_Type__c;
                    wanted.put(sKey, gap(asset.Id, sKey, 'Low', s,
                        'Fewer ' + l.Data_Type__c.toLowerCase() + ' signals than expected',
                        (s.Signals_Present__c ?? 0) + ' of ' + l.Min_Signals__c + ' expected signals present.'));
                }
            }

            Integer freshness = requiredCount == 0
                ? (streams.isEmpty() ? 0 : 100)
                : round(freshnessSum / requiredCount);
            Decimal expected = profile?.Expected_Signal_Count__c;
            Integer completeness = (expected == null || expected <= 0) ? 0 : round(Math.min((Decimal) 100, signals * 100 / expected));

            // reconcile owned alerts: create or refresh the wanted ones, auto-resolve the rest
            Integer gapPenalty = 0;
            for (Asset_Alert__c w : wanted.values()) {
                w.Is_Sample__c = sample;
                Asset_Alert__c existing = ownedByKey.get(w.Unique_Key__c);
                if (existing == null || existing.Status__c == 'Resolved') {
                    w.Status__c = 'New';
                    w.Resolved_On__c = null;
                    alertUpserts.put(w.Unique_Key__c, w);
                    gapPenalty += PENALTY.get(w.Severity__c);
                } else {
                    if (existing.Severity__c != w.Severity__c || existing.Title__c != w.Title__c ||
                        existing.Detail__c != w.Detail__c || existing.Data_Stream__c != w.Data_Stream__c) {
                        alertUpserts.put(w.Unique_Key__c, w);
                    }
                    if (AssetAlertService.OPEN_STATUSES.contains(existing.Status__c)) {
                        gapPenalty += PENALTY.get(w.Severity__c);
                    }
                }
            }
            List<Asset_Alert__c> owned = ownedByAsset.containsKey(asset.Id) ? ownedByAsset.get(asset.Id) : new List<Asset_Alert__c>();
            for (Asset_Alert__c existing : owned) {
                if (!wanted.containsKey(existing.Unique_Key__c) &&
                    AssetAlertService.OPEN_STATUSES.contains(existing.Status__c)) {
                    alertUpserts.put(existing.Unique_Key__c, new Asset_Alert__c(
                        Unique_Key__c = existing.Unique_Key__c, Status__c = 'Resolved', Resolved_On__c = nowTs));
                }
            }
            if (otherOpenGaps.containsKey(asset.Id)) {
                for (Asset_Alert__c a : otherOpenGaps.get(asset.Id)) {
                    gapPenalty += PENALTY.containsKey(a.Severity__c) ? PENALTY.get(a.Severity__c) : 0;
                }
            }
            Integer consistency = Math.max(0, 100 - gapPenalty);

            Result r = new Result();
            r.assetId = asset.Id;
            r.profileId = profile?.Id;
            r.freshness = freshness;
            r.completeness = completeness;
            r.consistency = consistency;
            r.score = total(freshness, completeness, consistency);
            r.status = band(r.score);
            results.put(asset.Id, r);

            assetUpdates.add(new Fleet_Asset__c(
                Id = asset.Id,
                Resolved_Stream_Profile__c = r.profileId,
                Freshness_Score__c = r.freshness,
                Completeness_Score__c = r.completeness,
                Consistency_Score__c = r.consistency,
                Data_Health_Score__c = r.score,
                Data_Health_Status__c = r.status,
                Data_Health_Calculated__c = nowTs
            ));
        }

        update streamUpdates;
        if (!alertUpserts.isEmpty()) {
            upsert alertUpserts.values() Asset_Alert__c.Fields.Unique_Key__c;
        }
        update assetUpdates;
        AssetAlertService.recountOpenAlerts(assetIds);
        return results;
    }

    // ---------------------------------------------------------------- profile resolution

    /** Override if set, else the highest-priority (lowest number) active profile whose criteria match, else the default. */
    public static Stream_Profile__c resolveProfile(Fleet_Asset__c asset, List<Stream_Profile__c> profilesByPriority,
                                                   Map<Id, Stream_Profile__c> profileById) {
        if (asset.Stream_Profile_Override__c != null && profileById.containsKey(asset.Stream_Profile_Override__c)) {
            return profileById.get(asset.Stream_Profile_Override__c);
        }
        Stream_Profile__c fallback;
        for (Stream_Profile__c p : profilesByPriority) {
            if (p.Active__c != true) {
                continue;
            }
            if (p.Is_Default__c == true) {
                if (fallback == null) {
                    fallback = p;
                }
                continue;
            }
            if (hasCriteria(p) && matches(p, asset)) {
                return p;
            }
        }
        return fallback;
    }

    private static Boolean hasCriteria(Stream_Profile__c p) {
        return String.isNotBlank(p.Make__c) || String.isNotBlank(p.Model__c) ||
               String.isNotBlank(p.Fuel_Type__c) || String.isNotBlank(p.Vehicle_Category__c);
    }

    private static Boolean matches(Stream_Profile__c p, Fleet_Asset__c a) {
        return same(p.Make__c, a.Make__c) && same(p.Model__c, a.Model__c) &&
               same(p.Fuel_Type__c, a.Fuel_Type__c) && same(p.Vehicle_Category__c, a.Vehicle_Class__c);
    }

    /** A blank criterion matches anything; otherwise a case-insensitive comparison. */
    public static Boolean same(String criterion, String value) {
        return String.isBlank(criterion) || (value != null && criterion.trim().equalsIgnoreCase(value.trim()));
    }

    // ---------------------------------------------------------------- scoring helpers

    public static String streamStatus(Datetime lastUpdate, Decimal maxAgeHours, Datetime nowTs) {
        if (lastUpdate == null) {
            return 'Missing';
        }
        if (maxAgeHours != null && hoursBetween(lastUpdate, nowTs) > maxAgeHours) {
            return 'Stale';
        }
        return 'Healthy';
    }

    /** 100 within max age, linear to 0 at three times max age, 0 if missing. */
    public static Decimal lineFreshness(Decimal ageHours, Decimal maxAgeHours) {
        if (ageHours == null) {
            return 0;
        }
        if (maxAgeHours == null || maxAgeHours <= 0 || ageHours <= maxAgeHours) {
            return 100;
        }
        if (ageHours >= 3 * maxAgeHours) {
            return 0;
        }
        return 100 * (3 * maxAgeHours - ageHours) / (2 * maxAgeHours);
    }

    public static Integer total(Integer freshness, Integer completeness, Integer consistency) {
        return round(0.4 * freshness + 0.4 * completeness + 0.2 * consistency);
    }

    public static String band(Integer score) {
        if (score == null) {
            return null;
        }
        return score >= 85 ? 'Healthy' : (score >= 60 ? 'Watch' : 'At risk');
    }

    public static Decimal hoursBetween(Datetime fromTs, Datetime toTs) {
        return Decimal.valueOf(toTs.getTime() - fromTs.getTime()) / 3600000;
    }

    private static Integer round(Decimal d) {
        return d.setScale(0, RoundingMode.HALF_UP).intValue();
    }

    @TestVisible
    private static String describeAge(Decimal hours) {
        if (hours < 48) {
            Integer h = round(hours);
            return h + (h == 1 ? ' hour' : ' hours');
        }
        Integer d = round(hours / 24);
        return d + ' days';
    }

    public static Boolean isOwnedKey(String key) {
        return key != null && (key.startsWith('DG:') || key.startsWith('DGS:'));
    }

    private static Asset_Alert__c gap(Id assetId, String key, String severity, Data_Stream__c s, String title, String detail) {
        return new Asset_Alert__c(
            Fleet_Asset__c = assetId,
            Unique_Key__c = key,
            Alert_Type__c = 'Data gap',
            Severity__c = severity,
            Title__c = title.left(255),
            Detail__c = detail,
            Data_Stream__c = s?.Id
        );
    }
}
