@isTest
private class FleetIntegrationsControllerTest {
  @testSetup
  static void setupTestData() {
    // Create Data_Source__c records
    Data_Source__c dsGeotab = new Data_Source__c(
      Name = 'Geotab telematics',
      Vendor__c = 'Geotab',
      Source_Type__c = 'Telematics',
      Status__c = 'Active',
      Reference_URL__c = 'https://my.geotab.com',
      Expected_Frequency_Hours__c = 1,
      Last_Received__c = System.now()
    );
    Data_Source__c dsSamsara = new Data_Source__c(
      Name = 'Samsara telematics',
      Vendor__c = 'Samsara',
      Source_Type__c = 'Telematics',
      Status__c = 'Active',
      Reference_URL__c = 'https://api.samsara.com',
      Expected_Frequency_Hours__c = 1,
      Last_Received__c = System.now()
    );
    insert new List<Data_Source__c>{ dsGeotab, dsSamsara };

    // Create Fleet Asset
    Fleet_Asset__c asset = new Fleet_Asset__c(
      Name = 'Test Van',
      Make__c = 'Ford',
      Model__c = 'Transit',
      Status__c = 'Available'
    );
    insert asset;

    // Create Data Stream
    Data_Stream__c stream = new Data_Stream__c(
      Name = 'Geotab Location',
      Data_Source__c = dsGeotab.Id,
      Fleet_Asset__c = asset.Id,
      Data_Type__c = 'Location',
      Status__c = 'Healthy'
    );
    insert stream;
  }

  @isTest
  static void testGetConnectors() {
    Test.startTest();
    List<FleetIntegrationsController.ConnectorDTO> connectors = FleetIntegrationsController.getConnectors();
    Test.stopTest();

    System.assertNotEquals(null, connectors, 'Connectors should not be null');
    System.assertEquals(4, connectors.size(), 'Should return 4 connectors');

    Boolean foundGeotab = false;
    Boolean foundSamsara = false;
    Boolean foundCustom = false;
    for (FleetIntegrationsController.ConnectorDTO c : connectors) {
      if (c.key == 'geotab')
        foundGeotab = true;
      if (c.key == 'samsara')
        foundSamsara = true;
      if (c.key == 'custom')
        foundCustom = true;
    }
    System.assert(foundGeotab, 'Geotab connector should be present');
    System.assert(foundSamsara, 'Samsara connector should be present');
    System.assert(foundCustom, 'Custom webhook connector should be present');
  }

  @isTest
  static void testGetConnectorDetails() {
    Test.startTest();
    FleetIntegrationsController.ConfigDetails geotabDetails = FleetIntegrationsController.getConnectorDetails(
      'geotab'
    );
    FleetIntegrationsController.ConfigDetails samsaraDetails = FleetIntegrationsController.getConnectorDetails(
      'samsara'
    );
    FleetIntegrationsController.ConfigDetails customDetails = FleetIntegrationsController.getConnectorDetails(
      'custom'
    );
    Test.stopTest();

    System.assertNotEquals(null, geotabDetails, 'Geotab details should exist');
    System.assertNotEquals(
      null,
      samsaraDetails,
      'Samsara details should exist'
    );
    System.assertNotEquals(null, customDetails, 'Custom details should exist');
    System.assert(
      customDetails.webhookUrl.contains(
        '/services/apexrest/fleetforce/telemetry'
      ),
      'Webhook URL should be populated'
    );
  }

  @isTest
  static void testTestConnection() {
    Test.startTest();
    Map<String, Object> geotabPing = FleetIntegrationsController.testConnection(
      'geotab'
    );
    Map<String, Object> samsaraPing = FleetIntegrationsController.testConnection(
      'samsara'
    );
    Map<String, Object> customPing = FleetIntegrationsController.testConnection(
      'custom'
    );
    Test.stopTest();

    System.assertEquals(true, geotabPing.get('success'));
    System.assertEquals(true, samsaraPing.get('success'));
    System.assertEquals(true, customPing.get('success'));
  }

  @isTest
  static void testSaveConnector() {
    Test.startTest();
    String resultSamsara = FleetIntegrationsController.saveConnector(
      'samsara',
      'https://api.samsara.com/v2',
      null,
      null,
      null,
      'test_api_key_123',
      2
    );
    Test.stopTest();

    System.assertEquals('SUCCESS', resultSamsara);
    Data_Source__c ds = [
      SELECT Reference_URL__c, Expected_Frequency_Hours__c
      FROM Data_Source__c
      WHERE Vendor__c = 'Samsara'
      LIMIT 1
    ];
    System.assertEquals('https://api.samsara.com/v2', ds.Reference_URL__c);
    System.assertEquals(2, ds.Expected_Frequency_Hours__c);
  }

  @isTest
  static void testTriggerSync() {
    Test.startTest();
    String geotabSync = FleetIntegrationsController.triggerSync('geotab');
    String samsaraSync = FleetIntegrationsController.triggerSync('samsara');
    Test.stopTest();

    System.assert(geotabSync.contains('queued'), 'Geotab sync should queue');
    System.assert(
      samsaraSync.contains('triggered'),
      'Samsara sync should trigger'
    );
  }
}
