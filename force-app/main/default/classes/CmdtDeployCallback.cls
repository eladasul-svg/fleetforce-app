/**
 * @description Callback executed when an asynchronous CMDT metadata deployment completes.
 * Publishes a Cmdt_Deploy_Result__e event to notify client LWCs without HTTP polling.
 */
public class CmdtDeployCallback implements Metadata.DeployCallback {
  private String requestKey;
  private String cmdtApiName;

  public CmdtDeployCallback(String requestKey, String cmdtApiName) {
    this.requestKey = requestKey;
    this.cmdtApiName = cmdtApiName;
  }

  public void handleResult(
    Metadata.DeployResult result,
    Metadata.DeployCallbackContext context
  ) {
    Boolean succeeded = (result != null &&
    result.status == Metadata.DeployStatus.Succeeded);

    Cmdt_Deploy_Result__e evt = new Cmdt_Deploy_Result__e(
      Request_Key__c = requestKey,
      Cmdt_Type__c = cmdtApiName,
      Success__c = succeeded,
      Error_Message__c = succeeded ? null : buildErrorMessage(result)
    );

    EventBus.publish(evt);
  }

  private String buildErrorMessage(Metadata.DeployResult result) {
    if (result == null) {
      return 'Deployment callback returned no result.';
    }

    List<String> problems = new List<String>();
    if (result.details != null && result.details.componentFailures != null) {
      for (Metadata.DeployMessage msg : result.details.componentFailures) {
        if (msg.problem != null) {
          problems.add(msg.problem);
        }
      }
    }

    if (!problems.isEmpty()) {
      return String.join(problems, ' | ');
    }
    if (String.isNotBlank(result.errorMessage)) {
      return result.errorMessage;
    }
    return 'Deployment failed with status: ' + result.status;
  }
}
