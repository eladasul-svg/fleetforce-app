/**
 * @description Enqueues asynchronous Metadata API deployments for Custom Metadata Type records.
 * Uses native Metadata.Operations.enqueueDeployment with platform event callbacks.
 */
public with sharing class CmdtDeployService {
  public class ValidationException extends Exception {
  }

  @AuraEnabled
  public static String requestDeploy(
    String cmdtApiName,
    String developerName,
    String masterLabel,
    String requestKey,
    Map<String, Object> fieldValues
  ) {
    try {
      CmdtTypeRegistry.validate(cmdtApiName);

      if (String.isBlank(developerName) || String.isBlank(masterLabel)) {
        throw new ValidationException('Developer Name and Label are required.');
      }
      if (String.isBlank(requestKey)) {
        throw new ValidationException(
          'A request key is required to correlate the deploy result.'
        );
      }

      String cleanTypeName = CmdtTypeRegistry.stripNamespace(cmdtApiName);
      String cleanDevName = developerName.trim()
        .replaceAll('[^a-zA-Z0-9_]', '_');
      String namespace = getNamespacePrefix();
      String prefix = String.isNotBlank(namespace) ? namespace + '__' : '';

      String typePrefix = cleanTypeName.replace('__mdt', '');
      String mdFullName = prefix + typePrefix + '.' + cleanDevName;

      Metadata.CustomMetadata record = new Metadata.CustomMetadata();
      record.fullName = mdFullName;
      record.label = masterLabel.trim();

      if (fieldValues != null) {
        for (String fieldApiName : fieldValues.keySet()) {
          Metadata.CustomMetadataValue fieldValue = new Metadata.CustomMetadataValue();
          String cleanFieldName = CmdtTypeRegistry.stripNamespace(fieldApiName);
          fieldValue.field = prefix + cleanFieldName;
          fieldValue.value = fieldValues.get(fieldApiName);
          record.values.add(fieldValue);
        }
      }

      Metadata.DeployContainer container = new Metadata.DeployContainer();
      container.addMetadata(record);

      if (Test.isRunningTest()) {
        return 'TEST_DEPLOY_JOB_ID';
      }

      Id jobId = Metadata.Operations.enqueueDeployment(
        container,
        new CmdtDeployCallback(requestKey, cmdtApiName)
      );
      return jobId;
    } catch (Exception ex) {
      AuraHandledException ahe = new AuraHandledException(ex.getMessage());
      ahe.setMessage(ex.getMessage());
      throw ahe;
    }
  }

  private static String getNamespacePrefix() {
    String className = CmdtDeployService.class.getName();
    return className.contains('.') ? className.substringBefore('.') : '';
  }
}
