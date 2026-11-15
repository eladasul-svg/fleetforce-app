/**
 * @description Registry and allowlist of supported Custom Metadata Types in FleetForce.
 * Enforces security boundaries and provides friendly labels for UI selectors.
 */
public with sharing class CmdtTypeRegistry {
  public static final Set<String> SUPPORTED_TYPES = new Set<String>{
    'Country_Profile__mdt',
    'Vehicle_Model__mdt',
    'Auto_Naming_Rule__mdt',
    'Routing_Policy_Setting__mdt',
    'Capacity_Dimension__mdt',
    'Geotab_Setting__mdt'
  };

  public class TypeOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String description;

    public TypeOption(String label, String value, String description) {
      this.label = label;
      this.value = value;
      this.description = description;
    }
  }

  public class UnsupportedCmdtTypeException extends Exception {
  }

  public static String stripNamespace(String apiName) {
    if (String.isBlank(apiName)) {
      return '';
    }
    return apiName.contains('__') && apiName.countMatches('__') > 1
      ? apiName.substringAfter('__')
      : apiName;
  }

  public static void validate(String cmdtApiName) {
    String cleanName = stripNamespace(cmdtApiName);
    if (String.isBlank(cleanName) || !SUPPORTED_TYPES.contains(cleanName)) {
      throw new UnsupportedCmdtTypeException(
        'CMDT type "' +
          cmdtApiName +
          '" is not in the supported list for FleetForce Control Panel.'
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<TypeOption> getSupportedTypes() {
    List<TypeOption> options = new List<TypeOption>{
      new TypeOption(
        'Country Profiles',
        'Country_Profile__mdt',
        'Regional baseline defaults per country (time zone, currency, distance, volume, fuel economy).'
      ),
      new TypeOption(
        'Vehicle Models',
        'Vehicle_Model__mdt',
        'Manufacturer models, EV ranges, MPG metrics, and documentation links.'
      ),
      new TypeOption(
        'Record Auto-Naming Rules',
        'Auto_Naming_Rule__mdt',
        'Standardization formula tokens for Fleet Assets, Reservations, and Citations.'
      ),
      new TypeOption(
        'Routing Policy Settings',
        'Routing_Policy_Setting__mdt',
        'Dispatch scheduling, time windows, and route optimization rules.'
      ),
      new TypeOption(
        'Capacity Dimensions',
        'Capacity_Dimension__mdt',
        'Payload, volume, and seating dimension configurations.'
      ),
      new TypeOption(
        'Geotab Settings',
        'Geotab_Setting__mdt',
        'Telematics server endpoints, credentials, and polling sync intervals.'
      )
    };
    return options;
  }
}
