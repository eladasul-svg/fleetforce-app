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
    public Option(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public class GeneralSettings {
    @AuraEnabled
    public Boolean enableAiInsights;
    @AuraEnabled
    public String aiProvider;
    @AuraEnabled
    public Boolean enableExtendedPrivacy;
    @AuraEnabled
    public Boolean autoCreateDtcTickets;
    @AuraEnabled
    public Decimal maintenanceGraceDays;
    @AuraEnabled
    public Decimal odometerDriftThreshold;
    @AuraEnabled
    public Decimal telemetryRetentionDays;
    @AuraEnabled
    public Boolean hasGoogleKey;
    @AuraEnabled
    public Boolean hasAnthropicKey;
    @AuraEnabled
    public Boolean hasOpenAiKey;
    @AuraEnabled
    public String maskedGoogleKey;
    @AuraEnabled
    public String maskedAnthropicKey;
    @AuraEnabled
    public String maskedOpenAiKey;
    @AuraEnabled
    public Boolean canEdit;
    @AuraEnabled
    public List<Option> aiProviders;
  }

  public class BrandSettings {
    @AuraEnabled
    public String iconStyle;
    @AuraEnabled
    public Boolean useCustomTheme;
    @AuraEnabled
    public String customThemeName;
    @AuraEnabled
    public String customBrandColor;
    @AuraEnabled
    public String customLogoUrl;
    @AuraEnabled
    public Boolean canEdit;
  }

  @AuraEnabled(cacheable=true)
  public static GeneralSettings getGeneralSettings() {
    fleetforce__Fleet_Display_Setting__c org = fleetforce__Fleet_Display_Setting__c.getOrgDefaults();
    GeneralSettings g = new GeneralSettings();
    g.enableAiInsights = org.fleetforce__Enable_AI_Insights__c != null
      ? org.fleetforce__Enable_AI_Insights__c
      : true;
    g.enableExtendedPrivacy = org.fleetforce__Enable_Extended_Privacy__c != null
      ? org.fleetforce__Enable_Extended_Privacy__c
      : false;
    g.autoCreateDtcTickets = org.fleetforce__Auto_Create_DTC_Tickets__c != null
      ? org.fleetforce__Auto_Create_DTC_Tickets__c
      : true;
    g.maintenanceGraceDays = org.fleetforce__Maintenance_Grace_Days__c != null
      ? org.fleetforce__Maintenance_Grace_Days__c
      : 14;
    g.odometerDriftThreshold = org.fleetforce__Odometer_Drift_Threshold__c !=
      null
      ? org.fleetforce__Odometer_Drift_Threshold__c
      : 5;
    g.telemetryRetentionDays = org.fleetforce__Telemetry_Retention_Days__c !=
      null
      ? org.fleetforce__Telemetry_Retention_Days__c
      : 90;
    g.hasGoogleKey = String.isNotBlank(org.fleetforce__Google_Api_Key__c);
    g.hasAnthropicKey = String.isNotBlank(org.fleetforce__Anthropic_Api_Key__c);
    g.hasOpenAiKey = String.isNotBlank(org.fleetforce__OpenAI_Api_Key__c);
    g.maskedGoogleKey = maskKey(org.fleetforce__Google_Api_Key__c);
    g.maskedAnthropicKey = maskKey(org.fleetforce__Anthropic_Api_Key__c);
    g.maskedOpenAiKey = maskKey(org.fleetforce__OpenAI_Api_Key__c);
    g.canEdit = canEditGeneral();
    g.aiProviders = buildAvailableAiProviders(
      g.hasGoogleKey,
      g.hasAnthropicKey,
      g.hasOpenAiKey
    );
    // Determine active provider from configured models
    if (String.isNotBlank(org.fleetforce__AI_Provider__c)) {
      g.aiProvider = org.fleetforce__AI_Provider__c;
    } else if (!g.aiProviders.isEmpty()) {
      g.aiProvider = g.aiProviders[0].value;
    } else {
      g.aiProvider = null;
    }
    return g;
  }

  @AuraEnabled
  public static GeneralSettings saveGeneralSettings(
    Boolean enableAiInsights,
    String aiProvider,
    Boolean enableExtendedPrivacy,
    String googleApiKey,
    String anthropicApiKey,
    String openAiApiKey,
    Boolean autoCreateDtcTickets,
    Decimal maintenanceGraceDays,
    Decimal odometerDriftThreshold,
    Decimal telemetryRetentionDays
  ) {
    if (!canEditGeneral()) {
      throw new AuraHandledException(
        'You do not have permission to change FleetForce general settings.'
      );
    }
    fleetforce__Fleet_Display_Setting__c org = fleetforce__Fleet_Display_Setting__c.getOrgDefaults();
    if (enableAiInsights != null) {
      org.fleetforce__Enable_AI_Insights__c = enableAiInsights == true;
    }
    if (enableExtendedPrivacy != null) {
      org.fleetforce__Enable_Extended_Privacy__c =
        enableExtendedPrivacy == true;
    }
    if (autoCreateDtcTickets != null) {
      org.fleetforce__Auto_Create_DTC_Tickets__c = autoCreateDtcTickets == true;
    }
    if (maintenanceGraceDays != null) {
      org.fleetforce__Maintenance_Grace_Days__c = maintenanceGraceDays;
    }
    if (odometerDriftThreshold != null) {
      org.fleetforce__Odometer_Drift_Threshold__c = odometerDriftThreshold;
    }
    if (telemetryRetentionDays != null) {
      org.fleetforce__Telemetry_Retention_Days__c = telemetryRetentionDays;
    }

    if (String.isNotBlank(googleApiKey) && !googleApiKey.contains('••')) {
      org.fleetforce__Google_Api_Key__c = googleApiKey.trim() == 'CLEAR'
        ? null
        : googleApiKey.trim();
    }
    if (String.isNotBlank(anthropicApiKey) && !anthropicApiKey.contains('••')) {
      org.fleetforce__Anthropic_Api_Key__c = anthropicApiKey.trim() == 'CLEAR'
        ? null
        : anthropicApiKey.trim();
    }
    if (String.isNotBlank(openAiApiKey) && !openAiApiKey.contains('••')) {
      org.fleetforce__OpenAI_Api_Key__c = openAiApiKey.trim() == 'CLEAR'
        ? null
        : openAiApiKey.trim();
    }

    if (String.isNotBlank(aiProvider)) {
      org.fleetforce__AI_Provider__c = aiProvider.trim();
    }
    upsert org;
    return getGeneralSettings();
  }

  @AuraEnabled(cacheable=true)
  public static BrandSettings getBrandSettings() {
    fleetforce__Fleet_Display_Setting__c org = fleetforce__Fleet_Display_Setting__c.getOrgDefaults();
    BrandSettings b = new BrandSettings();
    String style = org.fleetforce__Vehicle_Icon_Style__c;
    b.iconStyle = style != null && STYLES.contains(style.toLowerCase())
      ? style.toLowerCase()
      : DEFAULT_STYLE;
    b.useCustomTheme = org.fleetforce__Use_Custom_Theme__c == true;
    b.customThemeName = String.isNotBlank(org.fleetforce__Custom_Theme_Name__c)
      ? org.fleetforce__Custom_Theme_Name__c
      : 'FleetForce Packaged Theme';
    b.customBrandColor = String.isNotBlank(
        org.fleetforce__Custom_Brand_Color__c
      )
      ? org.fleetforce__Custom_Brand_Color__c
      : '#0F1E33';
    b.customLogoUrl = org.fleetforce__Custom_Logo_Url__c;
    b.canEdit = canEditBrand();
    return b;
  }

  @AuraEnabled
  public static BrandSettings saveBrandSettings(
    String iconStyle,
    Boolean useCustomTheme,
    String customThemeName,
    String customBrandColor,
    String customLogoUrl
  ) {
    if (!canEditBrand()) {
      throw new AuraHandledException(
        'You do not have permission to change FleetForce brand settings.'
      );
    }
    fleetforce__Fleet_Display_Setting__c org = fleetforce__Fleet_Display_Setting__c.getOrgDefaults();
    if (String.isNotBlank(iconStyle)) {
      String s = iconStyle.trim().toLowerCase();
      if (STYLES.contains(s)) {
        org.fleetforce__Vehicle_Icon_Style__c = s;
      }
    }
    org.fleetforce__Use_Custom_Theme__c = useCustomTheme == true;
    org.fleetforce__Custom_Theme_Name__c = customThemeName;
    org.fleetforce__Custom_Brand_Color__c = String.isNotBlank(customBrandColor)
      ? customBrandColor.trim()
      : '#0F1E33';
    org.fleetforce__Custom_Logo_Url__c = customLogoUrl;
    upsert org;
    return getBrandSettings();
  }

  private static String maskKey(String key) {
    if (String.isBlank(key)) {
      return '';
    }
    String trimmed = key.trim();
    if (trimmed.length() <= 8) {
      return '••••••••';
    }
    return trimmed.substring(0, 4) +
      '••••' +
      trimmed.substring(trimmed.length() - 4);
  }

  private static List<Option> buildAvailableAiProviders(
    Boolean hasGoogle,
    Boolean hasAnthropic,
    Boolean hasOpenAi
  ) {
    List<Option> optionsList = new List<Option>();
    if (hasGoogle) {
      optionsList.add(
        new Option('Google Gemini 2.5 Flash (Fast)', 'Gemini 2.5 Flash')
      );
      optionsList.add(
        new Option('Google Gemini 2.5 Pro (Deep Analytics)', 'Gemini 2.5 Pro')
      );
    }
    if (hasAnthropic) {
      optionsList.add(
        new Option('Anthropic Claude 3.5 Sonnet', 'Claude 3.5 Sonnet')
      );
      optionsList.add(
        new Option('Anthropic Claude 3.5 Haiku', 'Claude 3.5 Haiku')
      );
    }
    if (hasOpenAi) {
      optionsList.add(new Option('OpenAI GPT-4o', 'GPT-4o'));
      optionsList.add(new Option('OpenAI GPT-4o mini', 'GPT-4o mini'));
    }
    return optionsList;
  }

  private static Boolean canEditGeneral() {
    Schema.DescribeSObjectResult d = Schema.sObjectType.fleetforce__Fleet_Display_Setting__c;
    if (!d.isUpdateable() || !d.isCreateable()) {
      return false;
    }
    for (
      Schema.SObjectField f : new List<Schema.SObjectField>{
        fleetforce__Fleet_Display_Setting__c.fleetforce__Enable_AI_Insights__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__AI_Provider__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__Enable_Extended_Privacy__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__Google_Api_Key__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__Anthropic_Api_Key__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__OpenAI_Api_Key__c
      }
    ) {
      if (!f.getDescribe().isUpdateable()) {
        return false;
      }
    }
    return true;
  }

  private static Boolean canEditBrand() {
    Schema.DescribeSObjectResult d = Schema.sObjectType.fleetforce__Fleet_Display_Setting__c;
    if (!d.isUpdateable() || !d.isCreateable()) {
      return false;
    }
    for (
      Schema.SObjectField f : new List<Schema.SObjectField>{
        fleetforce__Fleet_Display_Setting__c.fleetforce__Vehicle_Icon_Style__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__Use_Custom_Theme__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__Custom_Theme_Name__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__Custom_Brand_Color__c,
        fleetforce__Fleet_Display_Setting__c.fleetforce__Custom_Logo_Url__c
      }
    ) {
      if (!f.getDescribe().isUpdateable()) {
        return false;
      }
    }
    return true;
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
