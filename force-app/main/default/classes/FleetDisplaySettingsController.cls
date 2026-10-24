/**
 * Reads and writes the org-wide vehicle icon style (Fleet_Display_Setting__c). getIconStyle() is safe for
 * every user; saveIconStyle() needs edit access to the setting, which FleetforceAdmin grants.
 */
public with sharing class FleetDisplaySettingsController {

    public static final String DEFAULT_STYLE = 'silhouette';
    @TestVisible
    private static final Set<String> STYLES = new Set<String>{ 'silhouette', 'flat', 'classic', 'modern', 'futuristic' };

    @AuraEnabled(cacheable=true)
    public static String getIconStyle() {
        String style = fleetforce__Fleet_Display_Setting__c.getInstance().fleetforce__Vehicle_Icon_Style__c;
        return style != null && STYLES.contains(style.toLowerCase()) ? style.toLowerCase() : DEFAULT_STYLE;
    }

    @AuraEnabled
    public static String saveIconStyle(String style) {
        String value = style == null ? '' : style.trim().toLowerCase();
        if (!STYLES.contains(value)) {
            throw new AuraHandledException('Unknown icon style: ' + style);
        }
        if (!Schema.sObjectType.fleetforce__Fleet_Display_Setting__c.isUpdateable()
            || !Schema.sObjectType.fleetforce__Fleet_Display_Setting__c.fields.fleetforce__Vehicle_Icon_Style__c.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to change FleetForce display settings.');
        }
        fleetforce__Fleet_Display_Setting__c org = fleetforce__Fleet_Display_Setting__c.getOrgDefaults();
        org.fleetforce__Vehicle_Icon_Style__c = value;
        upsert org;
        return value;
    }
}
