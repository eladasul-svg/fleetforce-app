@isTest
private class FleetInvoiceUploadServiceTest {
  @testSetup
  static void setupTestData() {
    Account vendor = new Account(Name = 'Ayvens Ingestion Vendor');
    insert vendor;

    Cost_Center__c cc = new Cost_Center__c(
      Name = 'Clinical Systems 01',
      Cost_Center_Code__c = 'CC-INGEST-01',
      Company_Code__c = 'GB01',
      Company_Name__c = 'Philips UK'
    );
    insert cc;

    Contact driver = new Contact(
      LastName = 'Ingestion Driver',
      Payroll_ID__c = 'EMP-INGEST-01'
    );
    insert driver;

    Fleet_Asset__c asset = new Fleet_Asset__c(
      Name = 'INGEST-VEHICLE-1',
      License_Plate__c = 'IN24XYZ',
      Make__c = 'Peugeot',
      Model__c = '2008',
      Status__c = 'Assigned',
      Is_Active__c = true
    );
    insert asset;
  }

  @isTest
  static void testImportInvoiceCsv() {
    String csvContent =
      'line_number,license_plate,driver_payroll,cost_center_code,category,concerning,recharge_type,net_amount,vat_amount,gross_amount,notes\n' +
      '1,IN24XYZ,EMP-INGEST-01,CC-INGEST-01,Monthly Payment,Contract,Fixed Lease,400.00,80.00,480.00,Clean verified line\n' +
      '2,UNKNOWN_PLATE,,CC-INGEST-01,Recharge,Damage,Body Repair,300.00,60.00,360.00,Unallocated asset line\n';

    Test.startTest();
    FleetInvoiceUploadService.UploadResult result = FleetInvoiceUploadService.importInvoiceCsv(
      'TEST-DOC-CSV-999',
      'Ayvens Ingestion Vendor',
      Date.today(),
      'GBP',
      csvContent
    );
    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(true, result.success);
    System.assertEquals(2, result.linesInserted);
    System.assertNotEquals(null, result.invoiceId);
    System.assertNotEquals(null, result.summary);
    System.assertEquals(480.00 + 360.00, result.summary.totalGross);
  }

  @isTest
  static void testImportInvoiceJson() {
    List<FleetInvoiceUploadService.LineInputDTO> lines = new List<FleetInvoiceUploadService.LineInputDTO>();

    FleetInvoiceUploadService.LineInputDTO l1 = new FleetInvoiceUploadService.LineInputDTO();
    l1.lineNumber = 'row-1';
    l1.licensePlate = 'IN24XYZ';
    l1.driverPayroll = 'EMP-INGEST-01';
    l1.costCenterCode = 'CC-INGEST-01';
    l1.category = 'Monthly Payment';
    l1.grossAmount = 550.00;
    lines.add(l1);

    Test.startTest();
    FleetInvoiceUploadService.UploadResult result = FleetInvoiceUploadService.importInvoiceJson(
      'TEST-DOC-JSON-888',
      'Ayvens Ingestion Vendor',
      Date.today(),
      'EUR',
      lines
    );
    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(true, result.success);
    System.assertEquals(1, result.linesInserted);
    System.assertEquals('EUR', result.summary.currencyIso);
    System.assertEquals('€', result.summary.currencySymbol);
  }
}
