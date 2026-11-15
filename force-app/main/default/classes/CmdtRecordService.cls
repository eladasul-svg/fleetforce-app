/**
 * @description Dynamic query service for Custom Metadata Type records in FleetForce.
 */
public with sharing class CmdtRecordService {
  @AuraEnabled(cacheable=true)
  public static List<SObject> getRecords(String cmdtApiName) {
    try {
      CmdtTypeRegistry.validate(cmdtApiName);

      Schema.SObjectType sObjType = resolveSObjectType(cmdtApiName);
      if (sObjType == null) {
        throw new AuraHandledException(
          'CMDT type "' + cmdtApiName + '" could not be found.'
        );
      }
      Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe()
        .fields.getMap();

      Set<String> selectFields = new Set<String>{
        'Id',
        'DeveloperName',
        'MasterLabel'
      };
      for (String fieldKey : fieldMap.keySet()) {
        Schema.DescribeFieldResult fd = fieldMap.get(fieldKey).getDescribe();
        selectFields.add(fd.getName());
      }

      String targetObject = sObjType.getDescribe().getName();
      String query =
        'SELECT ' +
        String.join(new List<String>(selectFields), ', ') +
        ' FROM ' +
        String.escapeSingleQuotes(targetObject) +
        ' ORDER BY MasterLabel ASC';

      return Database.query(query);
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
    String className = CmdtRecordService.class.getName();
    return className.contains('.') ? className.substringBefore('.') : '';
  }
}
