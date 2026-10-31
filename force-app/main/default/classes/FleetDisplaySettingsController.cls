/**
 * Reads and writes the org-wide FleetForce settings (Fleet_Display_Setting__c): the vehicle icon style and the
 * regional defaults (units, country, time zone, currency) used when a branch or vehicle leaves them blank.
 * The getters are safe for every user; the savers need edit access to the setting, which FleetforceAdmin grants.
 */
public with sharing class FleetDisplaySettingsController {
  public static final String DEFAULT_STYLE = 'silhouette';
  @TestVisible
  private static final Set<String> STYLES = new Set<String>{
    'silhouette',
    'flat',
    'classic',
    'modern',
    'futuristic'
  };

  @AuraEnabled(cacheable=true)
  public static String getIconStyle() {
    String style = fleetforce__Fleet_Display_Setting__c.getInstance()
      .fleetforce__Vehicle_Icon_Style__c;
    return style != null && STYLES.contains(style.toLowerCase())
      ? style.toLowerCase()
      : DEFAULT_STYLE;
  }

  @AuraEnabled
  public static String saveIconStyle(String style) {
    String value = style == null ? '' : style.trim().toLowerCase();
    if (!STYLES.contains(value)) {
      throw new AuraHandledException('Unknown icon style: ' + style);
    }
    if (
      !Schema.sObjectType.fleetforce__Fleet_Display_Setting__c.isUpdateable() ||
      !Schema.sObjectType.fleetforce__Fleet_Display_Setting__c.fields.fleetforce__Vehicle_Icon_Style__c.isUpdateable()
    ) {
      throw new AuraHandledException(
        'You do not have permission to change FleetForce display settings.'
      );
    }
    fleetforce__Fleet_Display_Setting__c org = fleetforce__Fleet_Display_Setting__c.getOrgDefaults();
    org.fleetforce__Vehicle_Icon_Style__c = value;
    upsert org;
    return value;
  }

  public class Option {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    Option(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class ProfileRow {
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public String timeZone;
    @AuraEnabled
    public String distanceUnit;
    @AuraEnabled
    public String volumeUnit;
    @AuraEnabled
    public String weightUnit;
    @AuraEnabled
    public String fuelEconomy;
    @AuraEnabled
    public String regime;
  }

  public class RegionalSettings {
    @AuraEnabled
    public String distanceUnit;
    @AuraEnabled
    public String volumeUnit;
    @AuraEnabled
    public String weightUnit;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public String timeZone;
    @AuraEnabled
    public String currencyCode;
    @AuraEnabled
    public Boolean multiCurrency;
    @AuraEnabled
    public String orgCurrency;
    @AuraEnabled
    public Boolean canEdit;
    @AuraEnabled
    public List<Option> distanceUnits;
    @AuraEnabled
    public List<Option> volumeUnits;
    @AuraEnabled
    public List<Option> weightUnits;
    @AuraEnabled
    public List<Option> countries;
    @AuraEnabled
    public List<Option> timeZones;
    @AuraEnabled
    public List<Option> currencies;
    @AuraEnabled
    public List<ProfileRow> profiles = new List<ProfileRow>();
  }

  private static final Map<String, String> FUEL_ECONOMY_LABELS = new Map<String, String>{
    'MPG_US' => 'MPG (US)',
    'MPG_UK' => 'MPG (UK)',
    'L_100km' => 'L/100 km',
    'km_L' => 'km/L'
  };

  @AuraEnabled(cacheable=true)
  public static RegionalSettings getRegionalSettings() {
    fleetforce__Fleet_Display_Setting__c org = fleetforce__Fleet_Display_Setting__c.getOrgDefaults();
    RegionalSettings r = new RegionalSettings();
    r.distanceUnit = org.fleetforce__Default_Distance_Unit__c;
    r.volumeUnit = org.fleetforce__Default_Volume_Unit__c;
    r.weightUnit = org.fleetforce__Default_Weight_Unit__c;
    r.country = org.fleetforce__Default_Country__c;
    r.timeZone = org.fleetforce__Default_Time_Zone__c;
    r.currencyCode = org.fleetforce__Default_Currency__c;
    r.multiCurrency = UserInfo.isMultiCurrencyOrganization();
    r.orgCurrency = corporateCurrency();
    r.canEdit = canEditRegional();

    Map<String, Schema.SObjectField> branch = Schema.sObjectType.fleetforce__Fleet_Branch__c.fields.getMap();
    r.distanceUnits = options(branch.get('fleetforce__Distance_Unit__c'));
    r.volumeUnits = options(branch.get('fleetforce__Volume_Unit__c'));
    r.weightUnits = options(branch.get('fleetforce__Weight_Unit__c'));
    r.countries = options(branch.get('fleetforce__Country__c'));
    r.timeZones = options(branch.get('fleetforce__Time_Zone__c'));
    r.currencies = options(branch.get('fleetforce__Currency_Code__c'));

    List<fleetforce__Country_Profile__mdt> profiles = fleetforce__Country_Profile__mdt.getAll()
      .values();
    for (fleetforce__Country_Profile__mdt p : profiles) {
      ProfileRow row = new ProfileRow();
      row.code = p.fleetforce__ISO_Code__c;
      row.name = p.fleetforce__Country_Name__c;
      row.currencyCode = p.fleetforce__Default_Currency__c;
      row.timeZone = p.fleetforce__Default_Time_Zone__c;
      row.distanceUnit = p.fleetforce__Distance_Unit__c;
      row.volumeUnit = p.fleetforce__Volume_Unit__c;
      row.weightUnit = p.fleetforce__Weight_Unit__c;
      row.fuelEconomy = FUEL_ECONOMY_LABELS.get(
        p.fleetforce__Fuel_Economy_Format__c
      ) ?? p.fleetforce__Fuel_Economy_Format__c;
      row.regime = p.fleetforce__Regulatory_Regime__c;
      r.profiles.add(row);
    }
    return r;
  }

  /** Blank values are allowed: they fall back to km / L / kg, or leave new branches without a default. */
  @AuraEnabled
  public static RegionalSettings saveRegionalSettings(
    String distanceUnit,
    String volumeUnit,
    String weightUnit,
    String country,
    String timeZone,
    String currencyCode
  ) {
    if (!canEditRegional()) {
      throw new AuraHandledException(
        'You do not have permission to change FleetForce regional settings.'
      );
    }
    Map<String, Schema.SObjectField> branch = Schema.sObjectType.fleetforce__Fleet_Branch__c.fields.getMap();
    fleetforce__Fleet_Display_Setting__c org = fleetforce__Fleet_Display_Setting__c.getOrgDefaults();
    org.fleetforce__Default_Distance_Unit__c = checked(
      distanceUnit,
      branch.get('fleetforce__Distance_Unit__c'),
      'distance unit'
    );
    org.fleetforce__Default_Volume_Unit__c = checked(
      volumeUnit,
      branch.get('fleetforce__Volume_Unit__c'),
      'volume unit'
    );
    org.fleetforce__Default_Weight_Unit__c = checked(
      weightUnit,
      branch.get('fleetforce__Weight_Unit__c'),
      'weight unit'
    );
    org.fleetforce__Default_Country__c = checked(
      country,
      branch.get('fleetforce__Country__c'),
      'country'
    );
    org.fleetforce__Default_Time_Zone__c = checked(
      timeZone,
      branch.get('fleetforce__Time_Zone__c'),
      'time zone'
    );
    org.fleetforce__Default_Currency__c = checked(
      currencyCode,
      branch.get('fleetforce__Currency_Code__c'),
      'currency'
    );
    upsert org;
    return getRegionalSettings();
  }

  private static Boolean canEditRegional() {
    Schema.DescribeSObjectResult d = Schema.sObjectType.fleetforce__Fleet_Display_Setting__c;
    if (!d.isUpdateable() || !d.isCreateable()) {
      return false;
    }
    for (
      Schema.SObjectField f : new List<Schema.SObjectField>{
        fleetforce__Fleet_Display_Setting__c.fleetforce__Default_Distance_Unit__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__Default_Volume_Unit__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__Default_Weight_Unit__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__Default_Country__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__Default_Time_Zone__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__Default_Currency__c
      }
    ) {
      if (!f.getDescribe().isUpdateable()) {
        return false;
      }
    }
    return true;
  }

  private static List<Option> options(Schema.SObjectField field) {
    List<Option> out = new List<Option>();
    for (Schema.PicklistEntry e : field.getDescribe().getPicklistValues()) {
      if (e.isActive()) {
        out.add(new Option(e.getLabel(), e.getValue()));
      }
    }
    return out;
  }

  private static String checked(
    String value,
    Schema.SObjectField field,
    String what
  ) {
    if (String.isBlank(value)) {
      return null;
    }
    for (Option o : options(field)) {
      if (o.value == value) {
        return value;
      }
    }
    throw new AuraHandledException('Unknown ' + what + ': ' + value);
  }

  /** The corporate currency in a multi-currency org (read dynamically, so the package never depends on it), else the org currency. */
  private static String corporateCurrency() {
    if (UserInfo.isMultiCurrencyOrganization()) {
      try {
        List<SObject> rows = Database.query(
          'SELECT IsoCode FROM CurrencyType WHERE IsCorporate = true LIMIT 1'
        );
        if (!rows.isEmpty()) {
          return (String) rows[0].get('IsoCode');
        }
      } catch (Exception e) {
        // fall through to the user's currency
      }
    }
    return UserInfo.getDefaultCurrency();
  }
}
