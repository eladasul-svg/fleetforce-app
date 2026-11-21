@isTest
private class FleetInvoiceAuditServiceTest {
  @testSetup
  static void setupTestData() {
    Account vendor = new Account(Name = 'Ayvens Test Vendor');
    insert vendor;

    Cost_Center__c cc = new Cost_Center__c(
      Name = 'Clinical Ops 1',
      Cost_Center_Code__c = 'CC-TEST-001',
      Company_Code__c = 'GB01',
      Company_Name__c = 'Philips UK Test'
    );
    insert cc;

    Contact driver = new Contact(
      LastName = 'Test Driver',
      Payroll_ID__c = 'EMP-99999'
    );
    insert driver;

    Fleet_Asset__c asset = new Fleet_Asset__c(
      Name = 'TEST-VEHICLE-1',
      License_Plate__c = 'AB12CDE',
      Make__c = 'Peugeot',
      Model__c = '2008',
      Status__c = 'Assigned',
      Is_Active__c = true
    );
    insert asset;

    Fleet_Invoice__c invoice = new Fleet_Invoice__c(
      Name = 'Ayvens UK Test Bill #1',
      Billing_Doc_Number__c = 'BILL-TEST-001',
      Vendor_Account__c = vendor.Id,
      Billing_Date__c = Date.today(),
      Payment_Due_Date__c = Date.today().addDays(30),
      Status__c = 'Draft',
      Audit_Review_Status__c = 'Pending_Review'
    );
    insert invoice;

    List<Fleet_Invoice_Line__c> lines = new List<Fleet_Invoice_Line__c>{
      // Clean line
      new Fleet_Invoice_Line__c(
        Fleet_Invoice__c = invoice.Id,
        Fleet_Asset__c = asset.Id,
        Driver__c = driver.Id,
        Cost_Center__c = cc.Id,
        Invoice_Category__c = 'Monthly Payment',
        Gross_Amount__c = 450.00,
        Net_Amount__c = 375.00,
        VAT_Amount__c = 75.00,
        Audit_Status__c = 'Clean'
      ),
      // Unallocated asset line (£500 out of £8,350 = ~6%, which breaches 5% threshold)
      new Fleet_Invoice_Line__c(
        Fleet_Invoice__c = invoice.Id,
        Fleet_Asset__c = null,
        Invoice_Category__c = 'Monthly Payment',
        Gross_Amount__c = 500.00,
        Net_Amount__c = 416.67,
        VAT_Amount__c = 83.33
      ),
      // High value > 5k (£6,500)
      new Fleet_Invoice_Line__c(
        Fleet_Invoice__c = invoice.Id,
        Fleet_Asset__c = asset.Id,
        Driver__c = driver.Id,
        Cost_Center__c = cc.Id,
        Invoice_Category__c = 'Major Engine Overhaul',
        Gross_Amount__c = 6500.00,
        Net_Amount__c = 5416.67,
        VAT_Amount__c = 1083.33
      ),
      // Recharge / fine
      new Fleet_Invoice_Line__c(
        Fleet_Invoice__c = invoice.Id,
        Fleet_Asset__c = asset.Id,
        Driver__c = driver.Id,
        Cost_Center__c = cc.Id,
        Invoice_Category__c = 'Traffic Fine',
        Recharge_Type__c = 'Speeding Fine',
        Gross_Amount__c = 100.00,
        Net_Amount__c = 100.00,
        VAT_Amount__c = 0.00
      ),
      // Missing repair credit
      new Fleet_Invoice_Line__c(
        Fleet_Invoice__c = invoice.Id,
        Fleet_Asset__c = asset.Id,
        Driver__c = driver.Id,
        Cost_Center__c = cc.Id,
        Invoice_Category__c = 'End of Contract Damage Fee',
        Invoice_Concerning__c = 'Return inspection recharge',
        Credit_Allowance_Applied__c = 0,
        Gross_Amount__c = 800.00,
        Net_Amount__c = 666.67,
        VAT_Amount__c = 133.33
      )
    };
    insert lines;

    // Seed audit threshold rules
    List<Fleet_Audit_Threshold__c> thresholds = new List<Fleet_Audit_Threshold__c>{
      new Fleet_Audit_Threshold__c(
        Rule_Name__c = 'Unallocated Spend Warning',
        Metric_Type__c = 'Unallocated_Spend_Pct',
        Operator__c = 'Greater_Than',
        Threshold_Value__c = 5.00,
        Severity__c = 'Critical_Blocker',
        Notification_Target__c = 'Teams_Webhook',
        Is_Active__c = true
      ),
      new Fleet_Audit_Threshold__c(
        Rule_Name__c = 'Single Line High-Value Cap',
        Metric_Type__c = 'Single_Line_Max_Gross',
        Operator__c = 'Greater_Or_Equal',
        Threshold_Value__c = 5000.00,
        Severity__c = 'Warning',
        Notification_Target__c = 'Chatter',
        Is_Active__c = true
      ),
      new Fleet_Audit_Threshold__c(
        Rule_Name__c = 'Missing EoC Repair Credit Allowance',
        Metric_Type__c = 'Missing_Credit_Count',
        Operator__c = 'Greater_Than',
        Threshold_Value__c = 0.00,
        Severity__c = 'Critical_Blocker',
        Notification_Target__c = 'Platform_Event',
        Is_Active__c = true
      )
    };
    insert thresholds;
  }

  @isTest
  static void testGetInvoiceAuditSummary() {
    Fleet_Invoice__c inv = [SELECT Id FROM Fleet_Invoice__c LIMIT 1];

    Test.startTest();
    FleetInvoiceAuditService.InvoiceAuditSummaryDTO dto = FleetInvoiceAuditService.getInvoiceAuditSummary(
      inv.Id
    );
    Test.stopTest();

    Assert.areNotEqual(null, dto, 'DTO should not be null');
    Assert.areEqual(5, dto.lineCount, 'Should have 5 lines');
    Assert.areEqual(
      'BILL-TEST-001',
      dto.billingDocNumber,
      'Billing Doc should match'
    );
    Assert.areNotEqual(
      null,
      dto.activeThresholds,
      'Active thresholds should be populated'
    );
    Assert.areEqual(
      3,
      dto.activeThresholds.size(),
      'Should have 3 active threshold rules'
    );
    Assert.areNotEqual(null, dto.reportMap, 'Report map should be initialized');
  }

  @isTest
  static void testRunInvoiceAuditWithThresholdBreaches() {
    Fleet_Invoice__c inv = [SELECT Id FROM Fleet_Invoice__c LIMIT 1];

    Test.startTest();
    FleetInvoiceAuditService.InvoiceAuditSummaryDTO dto = FleetInvoiceAuditService.runInvoiceAudit(
      inv.Id
    );
    Test.stopTest();

    Assert.areNotEqual(null, dto, 'Summary should not be null');
    Assert.areEqual(
      1,
      dto.unallocatedAssetCount,
      'Should have 1 unallocated asset line'
    );
    Assert.areEqual(
      1,
      dto.flaggedOver6kCount,
      'Should have 1 flagged over 6k line'
    );
    Assert.areEqual(1, dto.rechargeCount, 'Should have 1 recharge line');
    Assert.areEqual(
      1,
      dto.missingCreditCount,
      'Should have 1 missing credit line'
    );
    Assert.areEqual(1, dto.cleanCount, 'Should have 1 clean line');
    Assert.areEqual('Audited', dto.status, 'Invoice status should be Audited');

    // Check threshold breaches
    Assert.isTrue(
      dto.hasThresholdBreaches,
      'Should have detected threshold breaches'
    );
    Assert.isTrue(
      dto.criticalBreachCount > 0,
      'Should have at least 1 critical breach'
    );
    Assert.areEqual(
      'Audit_Review_Required',
      dto.auditReviewStatus,
      'Critical breach should set status to Audit_Review_Required'
    );

    // Verify queues
    Assert.isTrue(dto.pendingCount > 0, 'Should have pending triage lines');
    Assert.areEqual(0, dto.delegatedCount, 'No tasks delegated yet');

    // Verify Audit_Alert__c records created in DB
    List<Audit_Alert__c> alerts = [
      SELECT
        Id,
        Rule_Name__c,
        Severity__c,
        Metric_Type__c,
        Status__c,
        Message__c
      FROM Audit_Alert__c
      WHERE Fleet_Invoice__c = :inv.Id
    ];
    Assert.isTrue(
      !alerts.isEmpty(),
      'Audit_Alert__c records should have been persisted'
    );
    Assert.areEqual(
      'Active',
      alerts[0].Status__c,
      'Alert status should be Active'
    );
  }

  @isTest
  static void testTaskDelegationWorkflow() {
    Fleet_Invoice__c inv = [SELECT Id FROM Fleet_Invoice__c LIMIT 1];
    // Run audit first so lines are evaluated
    FleetInvoiceAuditService.runInvoiceAudit(inv.Id);

    Fleet_Invoice_Line__c unallocatedLine = [
      SELECT Id, Follow_Up_Status__c
      FROM Fleet_Invoice_Line__c
      WHERE Fleet_Invoice__c = :inv.Id AND Audit_Status__c = 'Unallocated_Asset'
      LIMIT 1
    ];

    Test.startTest();
    // 1. Delegate task
    FleetInvoiceAuditService.InvoiceAuditSummaryDTO dtoAfterTask = FleetInvoiceAuditService.createLineFollowUpTask(
      unallocatedLine.Id,
      'Query Ayvens for unregistered vehicle plate',
      Date.today().addDays(2),
      'High',
      'Driver claimed vehicle was registered in UK fleet register.'
    );
    Test.stopTest();

    // Verify line shifted from pending to delegated
    Assert.areEqual(
      1,
      dtoAfterTask.delegatedCount,
      'Should now have 1 delegated task line'
    );
    Fleet_Invoice_Line__c updatedLine = [
      SELECT Follow_Up_Status__c, Active_Task_Id__c
      FROM Fleet_Invoice_Line__c
      WHERE Id = :unallocatedLine.Id
    ];
    Assert.areEqual(
      'Task_Assigned',
      updatedLine.Follow_Up_Status__c,
      'Line should have status Task_Assigned'
    );
    Assert.isTrue(
      String.isNotBlank(updatedLine.Active_Task_Id__c),
      'Active Task ID should be populated'
    );

    // Verify Task in database
    Task createdTask = [
      SELECT Id, Subject, Status, Priority
      FROM Task
      WHERE Id = :updatedLine.Active_Task_Id__c
    ];
    Assert.areEqual(
      'Query Ayvens for unregistered vehicle plate',
      createdTask.Subject
    );
    Assert.areEqual('Not Started', createdTask.Status);

    // 2. Resolve task
    FleetInvoiceAuditService.InvoiceAuditSummaryDTO dtoAfterResolve = FleetInvoiceAuditService.resolveLineTask(
      unallocatedLine.Id,
      'Ayvens confirmed vehicle registration; contract added.'
    );

    Fleet_Invoice_Line__c resolvedLine = [
      SELECT Follow_Up_Status__c, Audit_Status__c
      FROM Fleet_Invoice_Line__c
      WHERE Id = :unallocatedLine.Id
    ];
    Assert.areEqual(
      'Resolved',
      resolvedLine.Follow_Up_Status__c,
      'Status should be Resolved'
    );
    Assert.areEqual(
      'Clean',
      resolvedLine.Audit_Status__c,
      'Audit status should be Clean'
    );

    Task resolvedTask = [
      SELECT Id, Status
      FROM Task
      WHERE Id = :createdTask.Id
    ];
    Assert.areEqual(
      'Completed',
      resolvedTask.Status,
      'Task should be marked Completed'
    );
  }

  @isTest
  static void testUpdateInvoiceLineAndReviewStatus() {
    Fleet_Invoice_Line__c line = [SELECT Id FROM Fleet_Invoice_Line__c LIMIT 1];
    Fleet_Invoice__c inv = [SELECT Id FROM Fleet_Invoice__c LIMIT 1];

    Test.startTest();
    FleetInvoiceAuditService.updateInvoiceLineStatus(
      line.Id,
      'Disputed',
      'Testing manual dispute'
    );
    FleetInvoiceAuditService.updateInvoiceReviewStatus(inv.Id, 'Approved');
    Test.stopTest();

    Fleet_Invoice_Line__c updatedLine = [
      SELECT Audit_Status__c, Audit_Notes__c
      FROM Fleet_Invoice_Line__c
      WHERE Id = :line.Id
    ];
    Assert.areEqual(
      'Disputed',
      updatedLine.Audit_Status__c,
      'Status should be Disputed'
    );
    Assert.areEqual(
      'Testing manual dispute',
      updatedLine.Audit_Notes__c,
      'Notes should match'
    );

    Fleet_Invoice__c updatedInv = [
      SELECT Status__c, Audit_Review_Status__c
      FROM Fleet_Invoice__c
      WHERE Id = :inv.Id
    ];
    Assert.areEqual(
      'Approved',
      updatedInv.Status__c,
      'Invoice status should be Approved'
    );
    Assert.areEqual(
      'Approved',
      updatedInv.Audit_Review_Status__c,
      'Review status should be Approved'
    );
  }

  @isTest
  static void testGenerateDisputeMemo() {
    Fleet_Invoice__c inv = [SELECT Id FROM Fleet_Invoice__c LIMIT 1];

    Test.startTest();
    String memo = FleetInvoiceAuditService.generateDisputeMemo(inv.Id);
    Test.stopTest();

    Assert.isNotNull(memo, 'Dispute memo should not be null');
    Assert.isTrue(
      memo.contains('COMMERCIAL AUDIT DISPUTE NOTICE'),
      'Should contain dispute header'
    );
    Assert.isTrue(
      memo.contains('BILL-TEST-001'),
      'Should contain billing doc number'
    );
  }
}
