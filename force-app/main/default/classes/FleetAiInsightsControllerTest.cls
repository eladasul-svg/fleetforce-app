@isTest
private class FleetAiInsightsControllerTest {
  @testSetup
  static void setupTestData() {
    // Create Fleet Asset
    Fleet_Asset__c asset = new Fleet_Asset__c(
      Name = 'Insight Test Van',
      Make__c = 'Ford',
      Model__c = 'Transit',
      Status__c = 'Assigned'
    );
    insert asset;

    // Create Org Display Setting with AI Enabled
    Fleet_Display_Setting__c setting = new Fleet_Display_Setting__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Enable_AI_Insights__c = true,
      AI_Provider__c = 'Google Gemini',
      Google_Api_Key__c = 'AIzaSyTestKey123'
    );
    upsert setting;
  }

  @isTest
  static void testGetAiConfig() {
    Test.startTest();
    FleetAiInsightsController.AiConfigDTO config = FleetAiInsightsController.getAiConfig();
    Test.stopTest();

    System.assertNotEquals(null, config, 'AI Config should not be null');
    System.assertEquals(true, config.isAiEnabled, 'AI should be enabled');
    System.assertEquals(
      'Google Gemini',
      config.provider,
      'Provider should be Google Gemini'
    );
    System.assertEquals(true, config.hasKey, 'Should have key');
  }

  @isTest
  static void testGetPrebuiltInsights() {
    Test.startTest();
    List<FleetAiInsightsController.StrategicInsightDTO> insights = FleetAiInsightsController.getPrebuiltInsights();
    Test.stopTest();

    System.assertNotEquals(null, insights, 'Insights list should not be null');
    System.assert(
      insights.size() >= 3,
      'Should return at least 3 prebuilt insights'
    );

    FleetAiInsightsController.StrategicInsightDTO warrantyInsight = insights[0];
    System.assertEquals('INS-WARRANTY-01', warrantyInsight.id);
    System.assert(
      warrantyInsight.title.contains('Warranty'),
      'First insight should focus on warranty'
    );
    System.assertEquals(
      2,
      warrantyInsight.actions.size(),
      'Should have 2 actions'
    );
  }

  @isTest
  static void testQueryStrategicInsight() {
    Test.startTest();
    FleetAiInsightsController.StrategicInsightDTO warrantyQuery = FleetAiInsightsController.queryStrategicInsight(
      'Tell me about warranty risks in Beer Sheva'
    );
    FleetAiInsightsController.StrategicInsightDTO carbonQuery = FleetAiInsightsController.queryStrategicInsight(
      'How can we cut fuel and carbon emissions?'
    );
    FleetAiInsightsController.StrategicInsightDTO generalQuery = FleetAiInsightsController.queryStrategicInsight(
      'General fleet summary'
    );
    Test.stopTest();

    System.assert(warrantyQuery.title.contains('Warranty'));
    System.assert(carbonQuery.title.contains('Decarbonization'));
    System.assert(generalQuery.title.contains('Synthesis'));
  }

  @isTest
  static void testExecuteStrategicAction() {
    Test.startTest();
    String resultMaintenance = FleetAiInsightsController.executeStrategicAction(
      'CREATE_PRIORITY_MAINTENANCE',
      'INS-WARRANTY-01'
    );
    String resultAlert = FleetAiInsightsController.executeStrategicAction(
      'ALERT_BRANCH_MANAGERS',
      'INS-WARRANTY-01'
    );
    String resultOther = FleetAiInsightsController.executeStrategicAction(
      'SIMULATE_EV_TCO',
      'INS-CARBON-02'
    );
    Test.stopTest();

    System.assert(resultMaintenance.contains('Successfully created'));
    System.assert(resultAlert.contains('dispatched'));
    System.assert(resultOther.contains('EV Fleet Transition'));

    List<Service_Ticket__c> createdTickets = [
      SELECT Id, Summary__c, Priority__c
      FROM Service_Ticket__c
      WHERE Priority__c = 'High'
    ];
    System.assert(
      !createdTickets.isEmpty(),
      'Service ticket should have been inserted'
    );
  }

  @isTest
  static void testSetActiveAiModel() {
    Test.startTest();
    FleetAiInsightsController.AiConfigDTO updated = FleetAiInsightsController.setActiveAiModel(
      'Anthropic Claude'
    );
    Test.stopTest();

    System.assertEquals('Anthropic Claude', updated.provider);
    System.assertNotEquals(null, updated.availableModels);
    System.assertEquals(3, updated.availableModels.size());
  }
}
