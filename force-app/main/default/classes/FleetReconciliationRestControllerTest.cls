@isTest
private class FleetReconciliationRestControllerTest {
  @testSetup
  static void setupTestData() {
    Account vendor = new Account(Name = 'Ayvens REST Vendor');
    insert vendor;

    Cost_Center__c cc = new Cost_Center__c(
      Name = 'Philips Diagnostics',
      Cost_Center_Code__c = 'CC-REST-001',
      Company_Code__c = 'GB01',
      Company_Name__c = 'Philips UK'
    );
    insert cc;

    Contact driver = new Contact(
      LastName = 'REST Driver',
      Payroll_ID__c = 'EMP-REST-01'
    );
    insert driver;

    Fleet_Asset__c asset = new Fleet_Asset__c(
      Name = 'REST-VEHICLE-1',
      License_Plate__c = 'RE24XYZ',
      Make__c = 'Peugeot',
      Model__c = '2008',
      Status__c = 'Assigned',
      Is_Active__c = true
    );
    insert asset;

    Fleet_Invoice__c invoice = new Fleet_Invoice__c(
      Name = 'Ayvens Bill #REST123',
      Billing_Doc_Number__c = 'REST123',
      Vendor_Account__c = vendor.Id,
      Billing_Date__c = Date.today(),
      Payment_Due_Date__c = Date.today().addDays(30),
      Status__c = 'Draft'
    );
    insert invoice;

    List<Fleet_Invoice_Line__c> lines = new List<Fleet_Invoice_Line__c>{
      new Fleet_Invoice_Line__c(
        Fleet_Invoice__c = invoice.Id,
        Fleet_Asset__c = asset.Id,
        Driver__c = driver.Id,
        Cost_Center__c = cc.Id,
        Invoice_Category__c = 'Monthly Payment',
        Gross_Amount__c = 500.00,
        Net_Amount__c = 416.67,
        VAT_Amount__c = 83.33,
        Audit_Status__c = 'Clean'
      ),
      new Fleet_Invoice_Line__c(
        Fleet_Invoice__c = invoice.Id,
        Fleet_Asset__c = null,
        Driver__c = null,
        Cost_Center__c = null,
        Invoice_Category__c = 'Recharge',
        Recharge_Type__c = 'Speeding Fine',
        Gross_Amount__c = 150.00,
        Net_Amount__c = 150.00,
        VAT_Amount__c = 0.00,
        Audit_Status__c = 'Recharge_Payroll_Deduction'
      )
    };
    insert lines;
  }

  @isTest
  static void testHandleGetSummary() {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();

    req.requestURI = '/services/apexrest/fleet/v1/reconciliation/summary';
    req.httpMethod = 'GET';
    req.params.put('docNumber', 'REST123');

    RestContext.request = req;
    RestContext.response = res;

    Test.startTest();
    FleetReconciliationRestController.handleGet();
    Test.stopTest();

    System.assertEquals(200, res.statusCode);
    System.assert(res.responseBody.toString().contains('REST123'));
    System.assert(
      res.responseBody.toString()
        .contains('Reconciliation summary retrieved successfully')
    );
  }

  @isTest
  static void testHandleGetExceptions() {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();

    req.requestURI = '/services/apexrest/fleet/v1/reconciliation/exceptions';
    req.httpMethod = 'GET';
    req.params.put('docNumber', 'REST123');
    req.params.put('type', 'Recharges_and_Fines');

    RestContext.request = req;
    RestContext.response = res;

    Test.startTest();
    FleetReconciliationRestController.handleGet();
    Test.stopTest();

    System.assertEquals(200, res.statusCode);
    System.assert(res.responseBody.toString().contains('Recharges_and_Fines'));
  }

  @isTest
  static void testHandleGetCostCenters() {
    Fleet_Invoice__c inv = [
      SELECT Id
      FROM Fleet_Invoice__c
      WHERE Billing_Doc_Number__c = 'REST123'
      LIMIT 1
    ];
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();

    req.requestURI = '/services/apexrest/fleet/v1/reconciliation/cost-centers';
    req.httpMethod = 'GET';
    req.params.put('invoiceId', String.valueOf(inv.Id));

    RestContext.request = req;
    RestContext.response = res;

    Test.startTest();
    FleetReconciliationRestController.handleGet();
    Test.stopTest();

    System.assertEquals(200, res.statusCode);
    System.assert(res.responseBody.toString().contains('topCostCenters'));
  }

  @isTest
  static void testHandlePostDelegateAndResolve() {
    Fleet_Invoice_Line__c unallocatedLine = [
      SELECT Id
      FROM Fleet_Invoice_Line__c
      WHERE Audit_Status__c = 'Recharge_Payroll_Deduction'
      LIMIT 1
    ];

    // 1. Delegate
    RestRequest reqDel = new RestRequest();
    RestResponse resDel = new RestResponse();
    reqDel.requestURI = '/services/apexrest/fleet/v1/reconciliation/delegate';
    reqDel.httpMethod = 'POST';
    reqDel.requestBody = Blob.valueOf(
      JSON.serialize(
        new Map<String, Object>{
          'lineId' => unallocatedLine.Id,
          'subject' => 'Investigate speed ticket',
          'priority' => 'High',
          'instructions' => 'Contact employee manager for deduction form'
        }
      )
    );

    RestContext.request = reqDel;
    RestContext.response = resDel;

    Test.startTest();
    FleetReconciliationRestController.handlePost();

    System.assertEquals(200, resDel.statusCode);
    System.assert(
      resDel.responseBody.toString().contains('Task successfully assigned')
    );

    // 2. Resolve
    RestRequest reqRes = new RestRequest();
    RestResponse resRes = new RestResponse();
    reqRes.requestURI = '/services/apexrest/fleet/v1/reconciliation/resolve';
    reqRes.httpMethod = 'POST';
    reqRes.requestBody = Blob.valueOf(
      JSON.serialize(
        new Map<String, Object>{
          'lineId' => unallocatedLine.Id,
          'resolutionNotes' => 'Driver signed payroll deduction form'
        }
      )
    );

    RestContext.request = reqRes;
    RestContext.response = resRes;

    FleetReconciliationRestController.handlePost();
    Test.stopTest();

    System.assertEquals(200, resRes.statusCode);
    System.assert(
      resRes.responseBody.toString().contains('successfully resolved')
    );
  }

  @isTest
  static void testNotFoundInvoice() {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/fleet/v1/reconciliation/summary';
    req.httpMethod = 'GET';
    req.params.put('docNumber', 'NON_EXISTENT');

    RestContext.request = req;
    RestContext.response = res;

    Test.startTest();
    FleetReconciliationRestController.handleGet();
    Test.stopTest();

    System.assertEquals(404, res.statusCode);
  }

  @isTest
  static void testHandleGetDisputeMemo() {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/fleet/v1/reconciliation/dispute-memo';
    req.httpMethod = 'GET';
    req.params.put('docNumber', 'REST123');

    RestContext.request = req;
    RestContext.response = res;

    Test.startTest();
    FleetReconciliationRestController.handleGet();
    Test.stopTest();

    System.assertEquals(200, res.statusCode);
    System.assert(
      res.responseBody.toString().contains('COMMERCIAL AUDIT DISPUTE NOTICE')
    );
  }

  @isTest
  static void testHandlePostImport() {
    RestRequest req = new RestRequest();
    RestResponse res = new RestResponse();
    req.requestURI = '/services/apexrest/fleet/v1/reconciliation/import';
    req.httpMethod = 'POST';
    req.requestBody = Blob.valueOf(
      JSON.serialize(
        new Map<String, Object>{
          'billingDocNumber' => 'REST-IMPORT-777',
          'vendorName' => 'Ayvens REST Vendor',
          'currencyIso' => 'GBP',
          'csvData' => 'line_number,license_plate,gross_amount\n1,RE24XYZ,300.00\n'
        }
      )
    );

    RestContext.request = req;
    RestContext.response = res;

    Test.startTest();
    FleetReconciliationRestController.handlePost();
    Test.stopTest();

    System.assertEquals(200, res.statusCode);
    System.assert(res.responseBody.toString().contains('REST-IMPORT-777'));
  }
}
