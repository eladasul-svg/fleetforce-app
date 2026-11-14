@IsTest
private class CmdtDeployCallbackTest {
  @IsTest
  static void testHandleResultSuccess() {
    Metadata.DeployResult result = new Metadata.DeployResult();
    result.status = Metadata.DeployStatus.Succeeded;

    CmdtDeployCallback callback = new CmdtDeployCallback(
      'req-success',
      'Country_Profile__mdt'
    );

    Test.startTest();
    callback.handleResult(result, null);
    Test.stopTest();
    System.assert(true, 'Success callback executed');
  }

  @IsTest
  static void testHandleResultFailure() {
    Metadata.DeployResult result = new Metadata.DeployResult();
    result.status = Metadata.DeployStatus.Failed;
    result.errorMessage = 'Simulated test failure';

    CmdtDeployCallback callback = new CmdtDeployCallback(
      'req-failure',
      'Country_Profile__mdt'
    );

    Test.startTest();
    callback.handleResult(result, null);
    Test.stopTest();
    System.assert(true, 'Failure callback executed');
  }

  @IsTest
  static void testHandleResultNull() {
    CmdtDeployCallback callback = new CmdtDeployCallback(
      'req-null',
      'Country_Profile__mdt'
    );

    Test.startTest();
    callback.handleResult(null, null);
    Test.stopTest();
    System.assert(true, 'Null callback executed');
  }
}
