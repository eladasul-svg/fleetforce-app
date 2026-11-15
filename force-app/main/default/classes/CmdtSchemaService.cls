/**
 * @description Dynamic Schema Inspection service for Custom Metadata Types in FleetForce.
 * Provides field definitions, data types, and picklist entries for generic LWC rendering.
 */
public with sharing class CmdtSchemaService {
  public class CmdtFieldInfo {
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String dataType;
    @AuraEnabled
    public Boolean isLookup;
    @AuraEnabled
    public List<CmdtPicklistEntry> picklistValues;
  }

  public class CmdtPicklistEntry {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
  }

  public class CmdtTypeInfo {
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String pluralLabel;
  }

  private static final Set<String> EXCLUDED_FIELDS = new Set<String>{
    'id',
    'developername',
    'masterlabel',
    'label',
    'namespaceprefix',
    'language',
    'qualifiedapiname',
    'systemmodstamp'
  };

  @AuraEnabled(cacheable=true)
  public static CmdtTypeInfo getTypeInfo(String cmdtApiName) {
    CmdtTypeRegistry.validate(cmdtApiName);
    Schema.SObjectType sType = resolveSObjectType(cmdtApiName);
    if (sType == null) {
      throw new AuraHandledException(
        'CMDT type "' + cmdtApiName + '" could not be found.'
      );
    }
    Schema.DescribeSObjectResult d = sType.getDescribe();
    CmdtTypeInfo info = new CmdtTypeInfo();
    info.apiName = d.getName();
    info.label = d.getLabel();
    info.pluralLabel = d.getLabelPlural();
    return info;
  }

  @AuraEnabled(cacheable=true)
  public static List<CmdtFieldInfo> getFieldDescribes(String cmdtApiName) {
    try {
      CmdtTypeRegistry.validate(cmdtApiName);

      Schema.SObjectType sObjType = resolveSObjectType(cmdtApiName);
      if (sObjType == null) {
        throw new CmdtTypeRegistry.UnsupportedCmdtTypeException(
          'CMDT type "' + cmdtApiName + '" could not be described.'
        );
      }

      Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe()
        .fields.getMap();
      List<CmdtFieldInfo> results = new List<CmdtFieldInfo>();

      for (String fieldKey : fieldMap.keySet()) {
        if (EXCLUDED_FIELDS.contains(fieldKey.toLowerCase())) {
          continue;
        }
        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldKey)
          .getDescribe();

        CmdtFieldInfo info = new CmdtFieldInfo();
        info.apiName = fieldDescribe.getName();
        info.label = fieldDescribe.getLabel();
        info.isLookup = (fieldDescribe.getType() ==
        Schema.DisplayType.REFERENCE);
        info.dataType = mapDisplayType(fieldDescribe.getType());

        if (fieldDescribe.getType() == Schema.DisplayType.PICKLIST) {
          info.picklistValues = new List<CmdtPicklistEntry>();
          for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
              CmdtPicklistEntry pe = new CmdtPicklistEntry();
              pe.label = entry.getLabel();
              pe.value = entry.getValue();
              info.picklistValues.add(pe);
            }
          }
        }

        results.add(info);
      }

      results.sort(new FieldLabelComparator());
      return results;
    } catch (Exception ex) {
      AuraHandledException ahe = new AuraHandledException(ex.getMessage());
      ahe.setMessage(ex.getMessage());
      throw ahe;
    }
  }

  private static Schema.SObjectType resolveSObjectType(String apiName) {
    Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
    if (gd.containsKey(apiName)) {
      return gd.get(apiName);
    }
    String namespace = getNamespacePrefix();
    if (
      String.isNotBlank(namespace) && gd.containsKey(namespace + '__' + apiName)
    ) {
      return gd.get(namespace + '__' + apiName);
    }
    return null;
  }

  private static String getNamespacePrefix() {
    String className = CmdtSchemaService.class.getName();
    return className.contains('.') ? className.substringBefore('.') : '';
  }

  private static String mapDisplayType(Schema.DisplayType dt) {
    if (dt == Schema.DisplayType.BOOLEAN) {
      return 'checkbox';
    }
    if (
      dt == Schema.DisplayType.INTEGER ||
      dt == Schema.DisplayType.DOUBLE ||
      dt == Schema.DisplayType.PERCENT ||
      dt == Schema.DisplayType.CURRENCY
    ) {
      return 'number';
    }
    if (dt == Schema.DisplayType.PICKLIST) {
      return 'picklist';
    }
    if (dt == Schema.DisplayType.TEXTAREA) {
      return 'textarea';
    }
    if (dt == Schema.DisplayType.DATE) {
      return 'date';
    }
    if (dt == Schema.DisplayType.DATETIME) {
      return 'datetime';
    }
    return 'text';
  }

  public class FieldLabelComparator implements Comparator<CmdtFieldInfo> {
    public Integer compare(CmdtFieldInfo a, CmdtFieldInfo b) {
      if (a == null || a.label == null) {
        return (b == null || b.label == null) ? 0 : -1;
      }
      if (b == null || b.label == null) {
        return 1;
      }
      return a.label.compareTo(b.label);
    }
  }
}
