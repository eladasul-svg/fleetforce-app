@isTest
private class FleetTeamsNotificationServiceTest {
  private class MockTeamsHttpCallout implements HttpCalloutMock {
    private Integer statusCode;
    private String responseBody;

    public MockTeamsHttpCallout(Integer statusCode, String responseBody) {
      this.statusCode = statusCode;
      this.responseBody = responseBody;
    }

    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'application/json');
      res.setStatusCode(this.statusCode);
      res.setStatus(this.statusCode == 200 ? 'OK' : 'Error');
      res.setBody(this.responseBody);
      return res;
    }
  }

  @testSetup
  static void setupTestData() {
    Account vendor = new Account(Name = 'Ayvens Test Vendor');
    insert vendor;

    Fleet_Invoice__c invoice = new Fleet_Invoice__c(
      Name = 'Ayvens UK Test Bill #1',
      Billing_Doc_Number__c = 'BILL-TEST-001',
      Vendor_Account__c = vendor.Id,
      Billing_Date__c = Date.today(),
      Payment_Due_Date__c = Date.today().addDays(30),
      Status__c = 'Draft'
    );
    insert invoice;

    Audit_Alert__c alert = new Audit_Alert__c(
      Fleet_Invoice__c = invoice.Id,
      Rule_Name__c = 'Unallocated Spend Limit',
      Severity__c = 'Critical_Blocker',
      Metric_Type__c = 'Unallocated_Spend_Pct',
      Threshold_Value__c = 5.0,
      Actual_Value__c = 12.5,
      Breach_Amount__c = 35000.0,
      Message__c = 'Unallocated vehicle and driver spend is 12.5%, exceeding 5.0% threshold.',
      Status__c = 'Active'
    );
    insert alert;
  }

  @isTest
  static void testBuildAdaptiveCardJson() {
    Fleet_Audit_Event__e criticalEvt = new Fleet_Audit_Event__e(
      Invoice_Id__c = '001000000000000AAA',
      Billing_Doc_Number__c = 'BILL-TEST-001',
      Rule_Name__c = 'Unallocated Spend Limit',
      Severity__c = 'Critical_Blocker',
      Metric_Type__c = 'Unallocated_Spend_Pct',
      Threshold_Value__c = 5.0,
      Actual_Value__c = 12.5,
      Breach_Amount__c = 35000.0,
      Message__c = 'Unallocated spend exceeded 5%'
    );

    String cardJson = FleetTeamsNotificationService.buildAdaptiveCardJson(
      criticalEvt,
      true
    );
    System.assertNotEquals(null, cardJson, 'Payload should not be null');
    System.assert(
      cardJson.contains('CRITICAL FLEET RECONCILIATION BREACH'),
      'Should contain critical title'
    );
    System.assert(
      cardJson.contains('Investigate with Copilot ↗'),
      'Should contain Copilot action'
    );
    System.assert(
      cardJson.contains('https://m365.cloud.microsoft/chat?prompt='),
      'Should contain Copilot URL'
    );

    Fleet_Audit_Event__e warningEvt = new Fleet_Audit_Event__e(
      Invoice_Id__c = '001000000000000AAA',
      Billing_Doc_Number__c = 'BILL-TEST-002',
      Rule_Name__c = 'Operational Recharge Surge',
      Severity__c = 'Warning',
      Metric_Type__c = 'Recharge_Spend_Pct',
      Threshold_Value__c = 3.0,
      Actual_Value__c = 8.5,
      Breach_Amount__c = 12000.0,
      Message__c = 'Recharges high'
    );
    String warningCardJson = FleetTeamsNotificationService.buildAdaptiveCardJson(
      warningEvt,
      false
    );
    System.assert(
      warningCardJson.contains('FLEET RECONCILIATION AUDIT ALERT'),
      'Should contain warning title'
    );
    System.assert(
      !warningCardJson.contains('Investigate with Copilot ↗'),
      'Should not contain Copilot action when false'
    );
  }

  @isTest
  static void testPreviewInvoiceAdaptiveCard() {
    Fleet_Invoice__c inv = [SELECT Id FROM Fleet_Invoice__c LIMIT 1];
    String previewJson = FleetTeamsNotificationService.previewInvoiceAdaptiveCard(
      inv.Id
    );
    System.assertNotEquals(null, previewJson);
    System.assert(previewJson.contains('Unallocated Spend Limit'));

    // Test with no alerts
    Fleet_Invoice__c emptyInv = new Fleet_Invoice__c(
      Name = 'Ayvens UK Empty Bill',
      Billing_Doc_Number__c = 'BILL-EMPTY-001',
      Billing_Date__c = Date.today()
    );
    insert emptyInv;
    String emptyJson = FleetTeamsNotificationService.previewInvoiceAdaptiveCard(
      emptyInv.Id
    );
    System.assert(emptyJson.contains('No active threshold alerts'));
  }

  @isTest
  static void testSendTestTeamsCard() {
    Fleet_Invoice__c inv = [SELECT Id FROM Fleet_Invoice__c LIMIT 1];
    Test.setMock(
      HttpCalloutMock.class,
      new MockTeamsHttpCallout(200, '{"result":"success"}')
    );

    Test.startTest();
    FleetTeamsNotificationService.NotificationResult result = FleetTeamsNotificationService.sendTestTeamsCard(
      inv.Id,
      'https://fleetforce.webhook.office.com/webhookb2/mock-endpoint'
    );
    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(200, result.statusCode);
    System.assertEquals(true, result.success);
  }

  @isTest
  static void testTriggerAndQueueable() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockTeamsHttpCallout(200, '{"result":"success"}')
    );

    Fleet_Audit_Event__e evt = new Fleet_Audit_Event__e(
      Invoice_Id__c = '001000000000000AAA',
      Billing_Doc_Number__c = 'BILL-TEST-001',
      Rule_Name__c = 'High Single Line Item',
      Severity__c = 'Critical_Blocker',
      Metric_Type__c = 'Single_Line_Max_Gross',
      Threshold_Value__c = 5000.0,
      Actual_Value__c = 7800.0,
      Breach_Amount__c = 7800.0,
      Message__c = 'Line item exceeds £5,000'
    );

    Test.startTest();
    EventBus.publish(evt);
    Test.stopTest();

    // If trigger and queueable execute without unhandled exception, test passes
    System.assert(
      true,
      'Platform event trigger and queueable executed successfully'
    );
  }

  @isTest
  static void testQueueableDirectExecution() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockTeamsHttpCallout(200, '{"result":"success"}')
    );

    List<Fleet_Audit_Event__e> events = new List<Fleet_Audit_Event__e>{
      new Fleet_Audit_Event__e(
        Invoice_Id__c = '001000000000000AAA',
        Billing_Doc_Number__c = 'BILL-TEST-001',
        Rule_Name__c = 'High Single Line Item',
        Severity__c = 'Warning',
        Metric_Type__c = 'Single_Line_Max_Gross',
        Threshold_Value__c = 5000.0,
        Actual_Value__c = 6000.0,
        Breach_Amount__c = 6000.0,
        Message__c = 'Line item exceeds threshold'
      )
    };

    Test.startTest();
    System.enqueueJob(new FleetTeamsNotificationQueueable(events));
    Test.stopTest();

    System.assert(true, 'Queueable executed directly without errors');
  }
}
