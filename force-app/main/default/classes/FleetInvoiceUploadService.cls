/**
 * @description Ingestion & Batch Upload Service for Vendor Fleet Invoices.
 * Supports all 3 ingestion patterns:
 *   - Pattern A: Zero-touch inbound webhook / simulator
 *   - Pattern B: Copilot MCP file ingestion tool
 *   - Pattern C: Native Salesforce LWC Drag-and-Drop Dropzone
 */
public with sharing class FleetInvoiceUploadService {
  public class UploadResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Id invoiceId;
    @AuraEnabled
    public String billingDocNumber;
    @AuraEnabled
    public Integer linesInserted;
    @AuraEnabled
    public FleetInvoiceAuditService.InvoiceAuditSummaryDTO summary;
  }

  public class LineInputDTO {
    @AuraEnabled
    public String lineNumber;
    @AuraEnabled
    public String licensePlate;
    @AuraEnabled
    public String driverPayroll;
    @AuraEnabled
    public String costCenterCode;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String concerning;
    @AuraEnabled
    public String rechargeType;
    @AuraEnabled
    public Decimal netAmount;
    @AuraEnabled
    public Decimal vatAmount;
    @AuraEnabled
    public Decimal grossAmount;
    @AuraEnabled
    public String notes;
  }

  /**
   * @description Ingests a CSV payload from the LWC dropzone or API.
   */
  @AuraEnabled
  public static UploadResult importInvoiceCsv(
    String billingDocNumber,
    String vendorName,
    Date billingDate,
    String currencyIso,
    String csvData
  ) {
    if (String.isBlank(billingDocNumber) || String.isBlank(csvData)) {
      throw new AuraHandledException(
        'Billing Document Number and CSV content are required.'
      );
    }

    List<LineInputDTO> lines = parseCsv(csvData);
    return importInvoice(
      billingDocNumber,
      vendorName,
      billingDate,
      currencyIso,
      lines
    );
  }

  /**
   * @description Ingests a structured JSON line array from Copilot MCP or Inbound Webhook.
   */
  @AuraEnabled
  public static UploadResult importInvoiceJson(
    String billingDocNumber,
    String vendorName,
    Date billingDate,
    String currencyIso,
    List<LineInputDTO> lines
  ) {
    return importInvoice(
      billingDocNumber,
      vendorName,
      billingDate,
      currencyIso,
      lines
    );
  }

  private static UploadResult importInvoice(
    String billingDocNumber,
    String vendorName,
    Date billingDate,
    String currencyIso,
    List<LineInputDTO> lines
  ) {
    if (String.isBlank(billingDocNumber)) {
      throw new AuraHandledException('Billing Document Number is required.');
    }

    // 1. Resolve or create Vendor Account
    Id vendorAccountId = resolveVendorAccount(vendorName);

    // 2. Find or create Fleet_Invoice__c
    List<Fleet_Invoice__c> existingInvoices = [
      SELECT Id, Billing_Doc_Number__c, Total_Gross__c
      FROM Fleet_Invoice__c
      WHERE Billing_Doc_Number__c = :billingDocNumber
      LIMIT 1
    ];

    Fleet_Invoice__c inv;
    if (!existingInvoices.isEmpty()) {
      inv = existingInvoices[0];
      inv.Billing_Date__c = (billingDate != null ? billingDate : Date.today());
      inv.Invoice_Currency__c = (String.isNotBlank(currencyIso)
        ? currencyIso
        : 'GBP');
      if (vendorAccountId != null) {
        inv.Vendor_Account__c = vendorAccountId;
      }
      update inv;

      // Delete existing lines if re-importing
      delete [
        SELECT Id
        FROM Fleet_Invoice_Line__c
        WHERE Fleet_Invoice__c = :inv.Id
      ];
    } else {
      inv = new Fleet_Invoice__c(
        Name = (String.isNotBlank(vendorName) ? vendorName : 'Ayvens') +
          ' Bill #' +
          billingDocNumber,
        Billing_Doc_Number__c = billingDocNumber,
        Vendor_Account__c = vendorAccountId,
        Billing_Date__c = (billingDate != null ? billingDate : Date.today()),
        Payment_Due_Date__c = (billingDate != null
          ? billingDate.addDays(30)
          : Date.today().addDays(30)),
        Invoice_Currency__c = (String.isNotBlank(currencyIso)
          ? currencyIso
          : 'GBP'),
        Status__c = 'Draft',
        Audit_Review_Status__c = 'Pending_Review'
      );
      insert inv;
    }

    if (lines == null || lines.isEmpty()) {
      UploadResult res = new UploadResult();
      res.success = true;
      res.message = 'Invoice header created. No lines provided.';
      res.invoiceId = inv.Id;
      res.billingDocNumber = billingDocNumber;
      res.linesInserted = 0;
      return res;
    }

    // 3. Pre-cache reference records for fast bulk matching
    Set<String> plates = new Set<String>();
    Set<String> payrolls = new Set<String>();
    Set<String> ccCodes = new Set<String>();

    for (LineInputDTO l : lines) {
      if (String.isNotBlank(l.licensePlate))
        plates.add(l.licensePlate.trim().toUpperCase());
      if (String.isNotBlank(l.driverPayroll))
        payrolls.add(l.driverPayroll.trim());
      if (String.isNotBlank(l.costCenterCode))
        ccCodes.add(l.costCenterCode.trim());
    }

    Map<String, Id> assetByPlate = new Map<String, Id>();
    for (Fleet_Asset__c a : [
      SELECT Id, License_Plate__c
      FROM Fleet_Asset__c
      WHERE License_Plate__c IN :plates
    ]) {
      if (String.isNotBlank(a.License_Plate__c)) {
        assetByPlate.put(a.License_Plate__c.toUpperCase(), a.Id);
      }
    }

    Map<String, Id> driverByPayroll = new Map<String, Id>();
    for (Contact c : [
      SELECT Id, Payroll_ID__c
      FROM Contact
      WHERE Payroll_ID__c IN :payrolls
    ]) {
      if (String.isNotBlank(c.Payroll_ID__c)) {
        driverByPayroll.put(c.Payroll_ID__c, c.Id);
      }
    }

    Map<String, Id> ccByCode = new Map<String, Id>();
    for (Cost_Center__c cc : [
      SELECT Id, Cost_Center_Code__c, Name
      FROM Cost_Center__c
      WHERE Cost_Center_Code__c IN :ccCodes OR Name IN :ccCodes
    ]) {
      if (String.isNotBlank(cc.Cost_Center_Code__c))
        ccByCode.put(cc.Cost_Center_Code__c, cc.Id);
      ccByCode.put(cc.Name, cc.Id);
    }

    // 4. Construct Fleet_Invoice_Line__c records
    List<Fleet_Invoice_Line__c> insertList = new List<Fleet_Invoice_Line__c>();
    for (LineInputDTO l : lines) {
      String normPlate = String.isNotBlank(l.licensePlate)
        ? l.licensePlate.trim().toUpperCase()
        : null;
      Id assetId = (normPlate != null && assetByPlate.containsKey(normPlate))
        ? assetByPlate.get(normPlate)
        : null;
      Id driverId = (String.isNotBlank(l.driverPayroll) &&
        driverByPayroll.containsKey(l.driverPayroll.trim()))
        ? driverByPayroll.get(l.driverPayroll.trim())
        : null;
      Id costCenterId = (String.isNotBlank(l.costCenterCode) &&
        ccByCode.containsKey(l.costCenterCode.trim()))
        ? ccByCode.get(l.costCenterCode.trim())
        : null;

      Decimal gross = l.grossAmount != null ? l.grossAmount : 0;
      Decimal net = l.netAmount != null
        ? l.netAmount
        : (gross / 1.20).setScale(2);
      Decimal vat = l.vatAmount != null ? l.vatAmount : (gross - net);

      String cat = String.isNotBlank(l.category)
        ? l.category
        : 'Monthly Payment';

      Fleet_Invoice_Line__c lineRec = new Fleet_Invoice_Line__c(
        Fleet_Invoice__c = inv.Id,
        Fleet_Asset__c = assetId,
        Driver__c = driverId,
        Cost_Center__c = costCenterId,
        Invoice_Category__c = cat,
        Invoice_Concerning__c = l.concerning,
        Recharge_Type__c = l.rechargeType,
        Gross_Amount__c = gross,
        Net_Amount__c = net,
        VAT_Amount__c = vat,
        Audit_Notes__c = l.notes,
        Follow_Up_Status__c = 'None'
      );
      insertList.add(lineRec);
    }

    insert insertList;

    // 5. Automatically trigger the FleetForce Reconciliation & Threshold Audit Engine
    FleetInvoiceAuditService.InvoiceAuditSummaryDTO summary = FleetInvoiceAuditService.runInvoiceAudit(
      inv.Id
    );

    UploadResult res = new UploadResult();
    res.success = true;
    res.message =
      'Successfully ingested ' +
      insertList.size() +
      ' lines. Reconciliation audit complete.';
    res.invoiceId = inv.Id;
    res.billingDocNumber = billingDocNumber;
    res.linesInserted = insertList.size();
    res.summary = summary;
    return res;
  }

  private static Id resolveVendorAccount(String vendorName) {
    String name = String.isNotBlank(vendorName) ? vendorName : 'Ayvens UK';
    List<Account> accounts = [
      SELECT Id, Name
      FROM Account
      WHERE Name LIKE :('%' + name + '%')
      LIMIT 1
    ];
    if (!accounts.isEmpty()) {
      return accounts[0].Id;
    }
    Account a = new Account(Name = name);
    insert a;
    return a.Id;
  }

  /**
   * Helper to parse CSV string into LineInputDTOs.
   */
  private static List<LineInputDTO> parseCsv(String csvData) {
    List<LineInputDTO> result = new List<LineInputDTO>();
    List<String> rawLines = csvData.split('\n');
    if (rawLines.isEmpty()) {
      return result;
    }

    // Header mapping
    List<String> headers = rawLines[0].split(',');
    Map<String, Integer> colMap = new Map<String, Integer>();
    for (Integer i = 0; i < headers.size(); i++) {
      colMap.put(headers[i].trim().toLowerCase(), i);
    }

    for (Integer i = 1; i < rawLines.size(); i++) {
      String row = rawLines[i].trim();
      if (String.isBlank(row))
        continue;

      List<String> cols = parseCsvRow(row);
      if (cols.isEmpty())
        continue;

      LineInputDTO l = new LineInputDTO();
      l.lineNumber = getCol(cols, colMap, 'line_number', 'row-' + i);
      l.licensePlate = getCol(cols, colMap, 'license_plate', null);
      l.driverPayroll = getCol(cols, colMap, 'driver_payroll', null);
      l.costCenterCode = getCol(cols, colMap, 'cost_center_code', null);
      l.category = getCol(cols, colMap, 'category', 'Monthly Payment');
      l.concerning = getCol(cols, colMap, 'concerning', null);
      l.rechargeType = getCol(cols, colMap, 'recharge_type', null);

      String grossStr = getCol(cols, colMap, 'gross_amount', '0');
      String netStr = getCol(cols, colMap, 'net_amount', null);
      String vatStr = getCol(cols, colMap, 'vat_amount', null);

      try {
        l.grossAmount = Decimal.valueOf(grossStr.replaceAll('[^0-9.]', ''));
      } catch (Exception e) {
        l.grossAmount = 0;
      }
      if (netStr != null) {
        try {
          l.netAmount = Decimal.valueOf(netStr.replaceAll('[^0-9.]', ''));
        } catch (Exception e) {
          l.netAmount = null;
        }
      }
      if (vatStr != null) {
        try {
          l.vatAmount = Decimal.valueOf(vatStr.replaceAll('[^0-9.]', ''));
        } catch (Exception e) {
          l.vatAmount = null;
        }
      }

      l.notes = getCol(cols, colMap, 'notes', null);
      result.add(l);
    }
    return result;
  }

  private static String getCol(
    List<String> cols,
    Map<String, Integer> mapCols,
    String colName,
    String defVal
  ) {
    if (mapCols.containsKey(colName) && mapCols.get(colName) < cols.size()) {
      String val = cols[mapCols.get(colName)].trim();
      return String.isNotBlank(val) ? val : defVal;
    }
    return defVal;
  }

  private static List<String> parseCsvRow(String line) {
    List<String> result = new List<String>();
    Boolean inQuotes = false;
    String cur = '';
    for (Integer i = 0; i < line.length(); i++) {
      String c = line.substring(i, i + 1);
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        result.add(cur);
        cur = '';
      } else {
        cur += c;
      }
    }
    result.add(cur);
    return result;
  }
}
