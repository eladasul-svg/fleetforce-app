/**
 * @description Batch Apex job to recalculate and standardize record names across an entire object.
 * Used by the FleetForce Admin App when saving new naming rules or triggering manual bulk backfills.
 */
public with sharing class AutoNamingBatch implements Database.Batchable<SObject>, Database.Stateful {
  private String objectApiName;
  private String customPattern;
  public Integer recordsProcessed = 0;
  public Integer recordsUpdated = 0;
  public List<String> errorMessages = new List<String>();

  public AutoNamingBatch(String objectApiName) {
    this(objectApiName, null);
  }

  public AutoNamingBatch(String objectApiName, String customPattern) {
    this.objectApiName = AutoNamingService.stripNamespace(objectApiName);
    this.customPattern = customPattern;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    // Find SObjectType
    Schema.SObjectType sType = Schema.getGlobalDescribe()
      .get(this.objectApiName);
    if (sType == null) {
      // Check with namespace if not found
      for (String key : Schema.getGlobalDescribe().keySet()) {
        if (
          AutoNamingService.stripNamespace(key)
            .equalsIgnoreCase(this.objectApiName)
        ) {
          sType = Schema.getGlobalDescribe().get(key);
          break;
        }
      }
    }

    if (sType == null) {
      throw new IllegalArgumentException(
        'Unknown object: ' + this.objectApiName
      );
    }

    Map<String, SObjectField> fieldMap = sType.getDescribe().fields.getMap();
    String patternToUse = this.customPattern;
    if (String.isBlank(patternToUse)) {
      Auto_Naming_Rule__mdt rule = AutoNamingService.getRule(
        this.objectApiName
      );
      patternToUse = AutoNamingService.resolvePattern(rule, this.objectApiName);
    }

    // Extract token fields from pattern
    Set<String> queryFields = new Set<String>{ 'Id', 'Name' };
    Matcher m = Pattern.compile('\\{([a-zA-Z0-9_]+)\\}').matcher(patternToUse);
    while (m.find()) {
      String token = m.group(1);
      String actualField = AutoNamingService.resolveFieldApiName(
        token,
        fieldMap
      );
      if (actualField != null) {
        queryFields.add(actualField);
      }
    }

    // Add fallback fields if present
    for (
      String fb : new List<String>{
        'Asset_ID__c',
        'VIN__c',
        'Summary__c',
        'Ticket_Number__c',
        'Type__c'
      }
    ) {
      String actual = AutoNamingService.resolveFieldApiName(fb, fieldMap);
      if (actual != null) {
        queryFields.add(actual);
      }
    }

    String soql =
      'SELECT ' +
      String.join(new List<String>(queryFields), ', ') +
      ' FROM ' +
      sType.getDescribe().getName();
    return Database.getQueryLocator(soql);
  }

  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    if (scope.isEmpty()) {
      return;
    }

    AutoNamingService.isBypassed = true;
    try {
      Schema.SObjectType sType = scope[0].getSObjectType();
      Map<String, SObjectField> fieldMap = sType.getDescribe().fields.getMap();
      String cleanObjName = AutoNamingService.stripNamespace(
        sType.getDescribe().getName()
      );

      String patternToUse = this.customPattern;
      if (String.isBlank(patternToUse)) {
        Auto_Naming_Rule__mdt rule = AutoNamingService.getRule(cleanObjName);
        patternToUse = AutoNamingService.resolvePattern(rule, cleanObjName);
      }

      List<SObject> toUpdate = new List<SObject>();
      for (SObject rec : scope) {
        recordsProcessed++;
        String newName = AutoNamingService.formatName(
          rec,
          patternToUse,
          fieldMap,
          cleanObjName
        );
        String currentName = (String) rec.get('Name');

        if (String.isNotBlank(newName) && newName != currentName) {
          rec.put('Name', newName);
          toUpdate.add(rec);
        }
      }

      if (!toUpdate.isEmpty()) {
        Database.SaveResult[] results = Database.update(
          toUpdate,
          false,
          AccessLevel.USER_MODE
        );
        for (Database.SaveResult sr : results) {
          if (sr.isSuccess()) {
            recordsUpdated++;
          } else {
            for (Database.Error err : sr.getErrors()) {
              errorMessages.add(err.getMessage());
            }
          }
        }
      }
    } finally {
      AutoNamingService.isBypassed = false;
    }
  }

  public void finish(Database.BatchableContext bc) {
    System.debug(
      LoggingLevel.INFO,
      'AutoNamingBatch completed for ' +
        this.objectApiName +
        '. Processed: ' +
        recordsProcessed +
        ', Updated: ' +
        recordsUpdated +
        ', Errors: ' +
        errorMessages.size()
    );
  }
}
