/**
 * @description Controller for the FleetForce Admin Auto-Naming configuration LWC.
 * Enables administrators to configure, preview, test, and bulk-recalculate record
 * naming patterns across all supported FleetForce objects.
 */
public with sharing class AutoNamingAdminController {
  public class ObjectConfigDTO {
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String currentPattern;
    @AuraEnabled
    public Boolean isActive;
    @AuraEnabled
    public Boolean allowManualOverride;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Integer recordCount;
  }

  public class FieldDTO {
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String dataType;
    @AuraEnabled
    public String token;
  }

  public class BatchStatusDTO {
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer totalJobItems;
    @AuraEnabled
    public Integer jobItemsProcessed;
    @AuraEnabled
    public Integer numberOfErrors;
    @AuraEnabled
    public Boolean isCompleted;
  }

  private static final List<String> SUPPORTED_OBJECTS = new List<String>{
    'Fleet_Asset__c',
    'Service_Ticket__c',
    'Reservation__c',
    'Citation__c',
    'Driver_Qualification__c'
  };

  /**
   * @description Returns all supported objects and their active naming configurations.
   */
  @AuraEnabled(cacheable=true)
  public static List<ObjectConfigDTO> getSupportedObjects() {
    List<ObjectConfigDTO> result = new List<ObjectConfigDTO>();
    Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

    for (String cleanName : SUPPORTED_OBJECTS) {
      Schema.SObjectType sType = resolveSObjectType(cleanName, globalDescribe);
      if (sType == null) {
        continue;
      }

      Map<String, SObjectField> fieldMap = sType.getDescribe().fields.getMap();
      SObjectField nameField = fieldMap.get('name');
      if (
        nameField == null ||
        !nameField.getDescribe().isCreateable() ||
        !nameField.getDescribe().isUpdateable()
      ) {
        continue; // Skip objects whose Name is AutoNumber
      }

      ObjectConfigDTO dto = new ObjectConfigDTO();
      dto.apiName = cleanName;
      dto.label = sType.getDescribe().getLabel();

      Auto_Naming_Rule__mdt rule = AutoNamingService.getRule(cleanName);
      if (rule != null) {
        dto.currentPattern = rule.Pattern__c;
        dto.isActive = rule.Is_Active__c;
        dto.allowManualOverride = rule.Allow_Manual_Override__c;
        dto.description = rule.Description__c;
      } else {
        dto.currentPattern = AutoNamingService.resolvePattern(null, cleanName);
        dto.isActive = true;
        dto.allowManualOverride = false;
        dto.description = 'Default built-in rule';
      }

      // Quick record count query
      try {
        String countQuery =
          'SELECT count() FROM ' + sType.getDescribe().getName();
        dto.recordCount = Database.countQuery(
          countQuery,
          AccessLevel.USER_MODE
        );
      } catch (Exception ex) {
        dto.recordCount = 0;
      }

      result.add(dto);
    }

    return result;
  }

  /**
   * @description Returns eligible fields for tokenization on the target object.
   */
  @AuraEnabled(cacheable=true)
  public static List<FieldDTO> getObjectFields(String objectApiName) {
    List<FieldDTO> result = new List<FieldDTO>();
    Schema.SObjectType sType = resolveSObjectType(
      objectApiName,
      Schema.getGlobalDescribe()
    );
    if (sType == null) {
      return result;
    }

    Set<String> excludedFieldNames = new Set<String>{
      'id',
      'isdeleted',
      'createddate',
      'createdbyid',
      'lastmodifieddate',
      'lastmodifiedbyid',
      'systemmodstamp',
      'lastvieweddate',
      'lastreferenceddate',
      'name',
      'connectionreceivedid',
      'connectionsentid'
    };

    Map<String, SObjectField> fieldMap = sType.getDescribe().fields.getMap();
    for (String fieldKey : fieldMap.keySet()) {
      if (excludedFieldNames.contains(fieldKey.toLowerCase())) {
        continue;
      }

      DescribeFieldResult dfr = fieldMap.get(fieldKey).getDescribe();
      // Filter out internal system and complex relation fields
      DisplayType dt = dfr.getType();
      if (
        dt == DisplayType.BASE64 ||
        dt == DisplayType.ADDRESS ||
        dt == DisplayType.LOCATION
      ) {
        continue;
      }

      FieldDTO f = new FieldDTO();
      f.apiName = AutoNamingService.stripNamespace(dfr.getName());
      f.label = dfr.getLabel();
      f.dataType = String.valueOf(dt);
      f.token = '{' + f.apiName + '}';
      result.add(f);
    }

    return result;
  }

  /**
   * @description Saves/updates an Auto_Naming_Rule__mdt record using Salesforce Apex Metadata API.
   */
  @AuraEnabled
  public static void saveRule(
    String objectApiName,
    String pattern,
    Boolean isActive,
    Boolean allowManualOverride,
    String description
  ) {
    String cleanName = AutoNamingService.stripNamespace(objectApiName);
    String devName = cleanName.replace('__c', '');

    String namespace = getNamespacePrefix();
    String prefix = String.isNotBlank(namespace) ? namespace + '__' : '';
    String mdFullName = prefix + 'Auto_Naming_Rule.' + devName;

    Metadata.CustomMetadata customMetadata = new Metadata.CustomMetadata();
    customMetadata.fullName = mdFullName;
    customMetadata.label = cleanName.replace('__c', '').replace('_', ' ');

    Metadata.CustomMetadataValue objField = new Metadata.CustomMetadataValue();
    objField.field = prefix + 'Object_API_Name__c';
    objField.value = objectApiName;
    customMetadata.values.add(objField);

    Metadata.CustomMetadataValue patField = new Metadata.CustomMetadataValue();
    patField.field = prefix + 'Pattern__c';
    patField.value = pattern;
    customMetadata.values.add(patField);

    Metadata.CustomMetadataValue actField = new Metadata.CustomMetadataValue();
    actField.field = prefix + 'Is_Active__c';
    actField.value = isActive;
    customMetadata.values.add(actField);

    Metadata.CustomMetadataValue ovrField = new Metadata.CustomMetadataValue();
    ovrField.field = prefix + 'Allow_Manual_Override__c';
    ovrField.value = allowManualOverride;
    customMetadata.values.add(ovrField);

    Metadata.CustomMetadataValue descField = new Metadata.CustomMetadataValue();
    descField.field = prefix + 'Description__c';
    descField.value = description != null ? description : '';
    customMetadata.values.add(descField);

    Metadata.DeployContainer mdContainer = new Metadata.DeployContainer();
    mdContainer.addMetadata(customMetadata);

    if (!Test.isRunningTest()) {
      Metadata.Operations.enqueueDeployment(mdContainer, null);
    }
  }

  private static String getNamespacePrefix() {
    String className = AutoNamingAdminController.class.getName();
    if (className.contains('.')) {
      return className.substringBefore('.');
    }
    return '';
  }

  /**
   * @description Generates a live preview using an actual sample record or representative mock.
   */
  @AuraEnabled
  public static String previewPattern(String objectApiName, String pattern) {
    String cleanName = AutoNamingService.stripNamespace(objectApiName);
    Schema.SObjectType sType = resolveSObjectType(
      cleanName,
      Schema.getGlobalDescribe()
    );
    if (sType == null) {
      return 'Invalid Object';
    }

    Map<String, SObjectField> fieldMap = sType.getDescribe().fields.getMap();

    // Query one real record to test
    try {
      String query =
        'SELECT ' +
        String.join(new List<String>(fieldMap.keySet()), ', ') +
        ' FROM ' +
        sType.getDescribe().getName() +
        ' WITH USER_MODE LIMIT 1';
      List<SObject> sampleRecords = Database.query(query);
      if (!sampleRecords.isEmpty()) {
        return AutoNamingService.formatName(
          sampleRecords[0],
          pattern,
          fieldMap,
          cleanName
        );
      }
    } catch (Exception ex) {
      // Fall through to mock
    }

    // Mock record preview if no records exist yet in org
    SObject mock = sType.newSObject();
    if (cleanName == 'Fleet_Asset__c') {
      safePut(mock, 'Make__c', 'Ford', fieldMap);
      safePut(mock, 'Model__c', 'Transit-250', fieldMap);
      safePut(mock, 'Model_Year__c', '2024', fieldMap);
      safePut(mock, 'License_Plate__c', '84-219-50', fieldMap);
      safePut(mock, 'Status__c', 'Available', fieldMap);
    } else if (cleanName == 'Service_Ticket__c') {
      safePut(mock, 'Summary__c', 'Brake Pad & Rotor Replacement', fieldMap);
      safePut(mock, 'Status__c', 'In-Shop', fieldMap);
    } else if (cleanName == 'Citation__c') {
      safePut(mock, 'Ticket_Number__c', 'CIT-9842', fieldMap);
      safePut(mock, 'Violation_Type__c', 'Speeding', fieldMap);
    } else if (cleanName == 'Reservation__c') {
      safePut(mock, 'Preferred_Body__c', 'Transit Van', fieldMap);
      safePut(mock, 'Status__c', 'Pending', fieldMap);
    }

    return AutoNamingService.formatName(mock, pattern, fieldMap, cleanName);
  }

  /**
   * @description Initiates a batch recalculation job across all records of the target object.
   */
  @AuraEnabled
  public static Id runRecalculateBatch(String objectApiName, String pattern) {
    AutoNamingBatch batch = new AutoNamingBatch(objectApiName, pattern);
    return Database.executeBatch(batch, 200);
  }

  /**
   * @description Checks the progress of an active recalculation batch.
   */
  @AuraEnabled
  public static BatchStatusDTO getBatchJobStatus(Id jobId) {
    AsyncApexJob job = [
      SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors
      FROM AsyncApexJob
      WHERE Id = :jobId
      WITH USER_MODE
    ];

    BatchStatusDTO dto = new BatchStatusDTO();
    dto.status = job.Status;
    dto.jobItemsProcessed = job.JobItemsProcessed;
    dto.totalJobItems = job.TotalJobItems;
    dto.numberOfErrors = job.NumberOfErrors;
    dto.isCompleted = (job.Status == 'Completed' ||
    job.Status == 'Failed' ||
    job.Status == 'Aborted');
    return dto;
  }

  private static Schema.SObjectType resolveSObjectType(
    String cleanName,
    Map<String, Schema.SObjectType> globalDescribe
  ) {
    if (globalDescribe.containsKey(cleanName.toLowerCase())) {
      return globalDescribe.get(cleanName.toLowerCase());
    }
    for (String key : globalDescribe.keySet()) {
      if (AutoNamingService.stripNamespace(key).equalsIgnoreCase(cleanName)) {
        return globalDescribe.get(key);
      }
    }
    return null;
  }

  private static void safePut(
    SObject record,
    String fieldName,
    Object val,
    Map<String, SObjectField> fieldMap
  ) {
    String actualField = AutoNamingService.resolveFieldApiName(
      fieldName,
      fieldMap
    );
    if (actualField != null) {
      record.put(actualField, val);
    }
  }
}
