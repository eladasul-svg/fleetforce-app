/**
 * @description Enterprise Audit & Reconciliation Engine for Fleet Invoices.
 * Performs deterministic 3-way matching, threshold anomaly detection,
 * EoC repair credit leakage audits, operational recharge classification,
 * configurable threshold governance, and interactive follow-up task delegation.
 */
public with sharing class FleetInvoiceAuditService {
  public class CategorySpendDTO {
    @AuraEnabled
    public String category;
    @AuraEnabled
    public Decimal grossAmount;
    @AuraEnabled
    public Decimal netAmount;
    @AuraEnabled
    public Integer lineCount;
    @AuraEnabled
    public Decimal percentage;
  }

  public class CostCenterSpendDTO {
    @AuraEnabled
    public String costCenterId;
    @AuraEnabled
    public String costCenterName;
    @AuraEnabled
    public String companyName;
    @AuraEnabled
    public Decimal grossAmount;
    @AuraEnabled
    public Integer lineCount;
  }

  public class AnomalyLineDTO {
    @AuraEnabled
    public String lineId;
    @AuraEnabled
    public String lineNumber;
    @AuraEnabled
    public String assetId;
    @AuraEnabled
    public String assetPlate;
    @AuraEnabled
    public String assetModel;
    @AuraEnabled
    public String driverId;
    @AuraEnabled
    public String driverName;
    @AuraEnabled
    public String costCenterName;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public String concerning;
    @AuraEnabled
    public String rechargeType;
    @AuraEnabled
    public Decimal grossAmount;
    @AuraEnabled
    public String auditStatus;
    @AuraEnabled
    public String auditNotes;

    // Task Delegation & Queue State
    @AuraEnabled
    public String followUpStatus;
    @AuraEnabled
    public String taskId;
    @AuraEnabled
    public String taskSubject;
    @AuraEnabled
    public Date taskDueDate;
    @AuraEnabled
    public String taskPriority;
    @AuraEnabled
    public String taskStatus;
    @AuraEnabled
    public String taskOwnerName;
  }

  public class ThresholdRuleDTO {
    @AuraEnabled
    public String thresholdId;
    @AuraEnabled
    public String ruleName;
    @AuraEnabled
    public String metricType;
    @AuraEnabled
    public String operator;
    @AuraEnabled
    public Decimal thresholdValue;
    @AuraEnabled
    public Decimal actualValue;
    @AuraEnabled
    public String severity;
    @AuraEnabled
    public String notificationTarget;
    @AuraEnabled
    public String description;
    @AuraEnabled
    public Boolean isBreached;
    @AuraEnabled
    public Decimal breachAmount;
    @AuraEnabled
    public String formattedThreshold;
    @AuraEnabled
    public String formattedActual;
    @AuraEnabled
    public String message;
  }

  public class InvoiceAuditSummaryDTO {
    @AuraEnabled
    public String invoiceId;
    @AuraEnabled
    public String invoiceReference;
    @AuraEnabled
    public String billingDocNumber;
    @AuraEnabled
    public String vendorName;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String auditReviewStatus;
    @AuraEnabled
    public Date billingDate;
    @AuraEnabled
    public Date paymentDueDate;
    @AuraEnabled
    public String currencyIso;
    @AuraEnabled
    public String currencySymbol;

    // Financial totals
    @AuraEnabled
    public Decimal totalGross;
    @AuraEnabled
    public Decimal totalNet;
    @AuraEnabled
    public Decimal totalVat;
    @AuraEnabled
    public Integer lineCount;

    // Reconciliation metrics
    @AuraEnabled
    public Integer cleanCount;
    @AuraEnabled
    public Decimal cleanAmount;
    @AuraEnabled
    public Decimal cleanPercentage;

    @AuraEnabled
    public Integer exceptionCount;
    @AuraEnabled
    public Decimal exceptionAmount;
    @AuraEnabled
    public Decimal exceptionPercentage;

    // Breakdown counts & amounts
    @AuraEnabled
    public Integer unallocatedAssetCount;
    @AuraEnabled
    public Decimal unallocatedAssetAmount;

    @AuraEnabled
    public Integer unallocatedDriverCount;
    @AuraEnabled
    public Decimal unallocatedDriverAmount;

    @AuraEnabled
    public Integer flaggedOver6kCount;
    @AuraEnabled
    public Decimal flaggedOver6kAmount;

    @AuraEnabled
    public Integer missingCreditCount;
    @AuraEnabled
    public Decimal missingCreditAmount;

    @AuraEnabled
    public Integer rechargeCount;
    @AuraEnabled
    public Decimal rechargeAmount;

    @AuraEnabled
    public Integer disputedCount;
    @AuraEnabled
    public Decimal disputedAmount;

    // Single line peak
    @AuraEnabled
    public Decimal maxSingleLineGross;

    // Threshold Engine Metrics
    @AuraEnabled
    public List<ThresholdRuleDTO> activeThresholds;
    @AuraEnabled
    public List<ThresholdRuleDTO> breachedThresholds;
    @AuraEnabled
    public Boolean hasThresholdBreaches;
    @AuraEnabled
    public Integer criticalBreachCount;
    @AuraEnabled
    public Integer warningBreachCount;
    @AuraEnabled
    public Integer infoBreachCount;

    // Interactive Task Queues (Needs Action vs In Progress)
    @AuraEnabled
    public Integer pendingCount;
    @AuraEnabled
    public Integer delegatedCount;
    @AuraEnabled
    public List<AnomalyLineDTO> pendingLines;
    @AuraEnabled
    public List<AnomalyLineDTO> delegatedLines;

    // Native Report Navigation Links
    @AuraEnabled
    public Map<String, String> reportMap;

    // Collections
    @AuraEnabled
    public List<CategorySpendDTO> categoryBreakdown;
    @AuraEnabled
    public List<CostCenterSpendDTO> topCostCenters;
    @AuraEnabled
    public List<AnomalyLineDTO> anomalyLines;
  }

  @AuraEnabled(cacheable=true)
  public static InvoiceAuditSummaryDTO getInvoiceAuditSummary(Id invoiceId) {
    if (invoiceId == null) {
      throw new AuraHandledException('Invoice ID cannot be null.');
    }
    return computeAuditSummary(invoiceId);
  }

  @AuraEnabled
  public static InvoiceAuditSummaryDTO runInvoiceAudit(Id invoiceId) {
    if (invoiceId == null) {
      throw new AuraHandledException('Invoice ID cannot be null.');
    }

    // 1. Fetch active threshold rules to configure audit dynamic thresholds
    List<Fleet_Audit_Threshold__c> activeThresholds = [
      SELECT
        Id,
        Rule_Name__c,
        Metric_Type__c,
        Operator__c,
        Threshold_Value__c,
        Severity__c,
        Notification_Target__c,
        Description__c
      FROM Fleet_Audit_Threshold__c
      WHERE Is_Active__c = TRUE
    ];

    Decimal singleLineLimit = 5000.00;
    for (Fleet_Audit_Threshold__c t : activeThresholds) {
      if (
        t.Metric_Type__c == 'Single_Line_Max_Gross' &&
        t.Threshold_Value__c != null
      ) {
        singleLineLimit = t.Threshold_Value__c;
        break;
      }
    }

    List<Fleet_Invoice_Line__c> lines = [
      SELECT
        Id,
        Name,
        Fleet_Asset__c,
        Driver__c,
        Cost_Center__c,
        Invoice_Category__c,
        Invoice_Concerning__c,
        Recharge_Type__c,
        Net_Amount__c,
        VAT_Amount__c,
        Gross_Amount__c,
        Credit_Allowance_Applied__c,
        Audit_Status__c,
        Audit_Notes__c,
        Follow_Up_Status__c,
        Active_Task_Id__c
      FROM Fleet_Invoice_Line__c
      WHERE Fleet_Invoice__c = :invoiceId
    ];

    List<Fleet_Invoice_Line__c> linesToUpdate = new List<Fleet_Invoice_Line__c>();

    for (Fleet_Invoice_Line__c line : lines) {
      String initialStatus = line.Audit_Status__c;
      String newStatus = 'Clean';
      String newNotes = 'Passed 3-way reconciliation audit';

      Decimal gross = line.Gross_Amount__c != null ? line.Gross_Amount__c : 0;
      String cat = line.Invoice_Category__c != null
        ? line.Invoice_Category__c
        : '';
      String rech = line.Recharge_Type__c != null ? line.Recharge_Type__c : '';
      String conc = line.Invoice_Concerning__c != null
        ? line.Invoice_Concerning__c
        : '';

      // Rule 1: Disputed by user manually takes precedence
      if (initialStatus == 'Disputed') {
        continue;
      }

      // Rule 2: Unallocated Vehicle Asset
      if (line.Fleet_Asset__c == null) {
        newStatus = 'Unallocated_Asset';
        newNotes = 'Vehicle plate not matched in active fleet register';
      }
      // Rule 3: High-Value Anomaly (Configurable threshold, default £5,000 / €6,000)
      else if (
        gross >= singleLineLimit &&
        !cat.containsIgnoreCase('Rental') &&
        !cat.containsIgnoreCase('Monthly')
      ) {
        newStatus = 'Flagged_Over_6k';
        newNotes =
          'Exceeds high-value threshold (£' +
          singleLineLimit.format() +
          ') - requires senior approval';
      }
      // Rule 4: Missing Contractual Repair Credit (End-of-Contract return with no credit)
      else if (
        (cat.containsIgnoreCase('Contract') ||
        conc.containsIgnoreCase('End of Contract') ||
        conc.containsIgnoreCase('Return')) &&
        gross > 0 &&
        (line.Credit_Allowance_Applied__c == null ||
        line.Credit_Allowance_Applied__c == 0)
      ) {
        newStatus = 'Missing_Repair_Credit';
        newNotes = 'Missing contractual £250/€300 refurbishment credit allowance';
      }
      // Rule 5: Operational Recharge / Traffic Fine
      else if (
        (cat.equalsIgnoreCase('Recharge') ||
        cat.equalsIgnoreCase('Traffic Fine')) ||
        (String.isNotBlank(rech) &&
        !rech.equalsIgnoreCase('Other') &&
        !rech.equalsIgnoreCase('None'))
      ) {
        newStatus = 'Recharge_Payroll_Deduction';
        newNotes =
          'Operational recharge (' +
          (String.isNotBlank(rech) ? rech.replace('_', ' ') : cat) +
          ') flagged for payroll deduction / driver notification';
      }
      // Rule 6: Unallocated Driver / Cost Center (Asset exists, but driver or cost center missing)
      else if (line.Driver__c == null || line.Cost_Center__c == null) {
        newStatus = 'Unallocated_Driver';
        newNotes = 'Driver payroll ID or ERP Cost Center not mapped';
      }

      if (
        line.Audit_Status__c != newStatus ||
        line.Audit_Notes__c != newNotes
      ) {
        line.Audit_Status__c = newStatus;
        line.Audit_Notes__c = newNotes;
        linesToUpdate.add(line);
      }
    }

    if (!linesToUpdate.isEmpty()) {
      update linesToUpdate;
    }

    // 2. Compute full summary metrics & evaluate thresholds
    InvoiceAuditSummaryDTO summary = computeAuditSummary(invoiceId);

    // 3. Persist Audit_Alert__c records and publish Fleet_Audit_Event__e
    delete [SELECT Id FROM Audit_Alert__c WHERE Fleet_Invoice__c = :invoiceId];

    List<Audit_Alert__c> alertsToInsert = new List<Audit_Alert__c>();
    List<Fleet_Audit_Event__e> eventsToPublish = new List<Fleet_Audit_Event__e>();

    if (summary.breachedThresholds != null) {
      for (ThresholdRuleDTO breach : summary.breachedThresholds) {
        Audit_Alert__c alert = new Audit_Alert__c(
          Fleet_Invoice__c = invoiceId,
          Fleet_Audit_Threshold__c = String.isNotBlank(breach.thresholdId)
            ? (Id) breach.thresholdId
            : null,
          Rule_Name__c = breach.ruleName,
          Severity__c = breach.severity,
          Metric_Type__c = breach.metricType,
          Operator__c = breach.operator,
          Threshold_Value__c = breach.thresholdValue,
          Actual_Value__c = breach.actualValue,
          Breach_Amount__c = breach.breachAmount,
          Message__c = breach.message,
          Status__c = 'Active'
        );
        alertsToInsert.add(alert);

        eventsToPublish.add(
          new Fleet_Audit_Event__e(
            Invoice_Id__c = String.valueOf(invoiceId),
            Billing_Doc_Number__c = summary.billingDocNumber,
            Rule_Name__c = breach.ruleName,
            Severity__c = breach.severity,
            Metric_Type__c = breach.metricType,
            Threshold_Value__c = breach.thresholdValue,
            Actual_Value__c = breach.actualValue,
            Breach_Amount__c = breach.breachAmount,
            Message__c = breach.message
          )
        );
      }
    }

    if (!alertsToInsert.isEmpty()) {
      insert alertsToInsert;
    }

    if (!eventsToPublish.isEmpty()) {
      EventBus.publish(eventsToPublish);
    }

    // 4. Update Invoice Audit_Review_Status__c based on threshold severity
    Fleet_Invoice__c inv = [
      SELECT Id, Status__c, Audit_Review_Status__c
      FROM Fleet_Invoice__c
      WHERE Id = :invoiceId
    ];

    inv.Status__c = 'Audited';
    if (summary.criticalBreachCount > 0) {
      inv.Audit_Review_Status__c = 'Audit_Review_Required';
    } else if (summary.exceptionCount > 0 || summary.warningBreachCount > 0) {
      inv.Audit_Review_Status__c = 'Pending_Review';
    } else {
      inv.Audit_Review_Status__c = 'Approved';
    }
    update inv;

    summary.status = inv.Status__c;
    summary.auditReviewStatus = inv.Audit_Review_Status__c;

    return summary;
  }

  @AuraEnabled
  public static void updateInvoiceLineStatus(
    Id lineId,
    String newStatus,
    String notes
  ) {
    if (lineId == null || String.isBlank(newStatus)) {
      throw new AuraHandledException('Line ID and status are required.');
    }
    Fleet_Invoice_Line__c line = [
      SELECT Id, Audit_Status__c, Audit_Notes__c
      FROM Fleet_Invoice_Line__c
      WHERE Id = :lineId
    ];
    line.Audit_Status__c = newStatus;
    if (String.isNotBlank(notes)) {
      line.Audit_Notes__c = notes;
    }
    update line;
  }

  @AuraEnabled
  public static void updateInvoiceReviewStatus(
    Id invoiceId,
    String newReviewStatus
  ) {
    if (invoiceId == null || String.isBlank(newReviewStatus)) {
      throw new AuraHandledException(
        'Invoice ID and review status are required.'
      );
    }
    Fleet_Invoice__c inv = [
      SELECT Id, Audit_Review_Status__c, Status__c
      FROM Fleet_Invoice__c
      WHERE Id = :invoiceId
    ];
    inv.Audit_Review_Status__c = newReviewStatus;
    if (newReviewStatus == 'Approved') {
      inv.Status__c = 'Approved';
    } else if (newReviewStatus == 'Disputed') {
      inv.Status__c = 'Disputed';
    }
    update inv;
  }

  /**
   * @description Creates a standard Salesforce Task assigned to follow up on an invoice exception.
   * Automatically transitions the line into the 'Delegated / In Progress' queue.
   */
  @AuraEnabled
  public static InvoiceAuditSummaryDTO createLineFollowUpTask(
    Id lineId,
    String subject,
    Date dueDate,
    String priority,
    String comments
  ) {
    if (lineId == null || String.isBlank(subject)) {
      throw new AuraHandledException(
        'Line ID and Subject are required to delegate a task.'
      );
    }

    Fleet_Invoice_Line__c line = [
      SELECT Id, Fleet_Invoice__c, Follow_Up_Status__c, Audit_Notes__c, Name
      FROM Fleet_Invoice_Line__c
      WHERE Id = :lineId
    ];

    Task t = new Task(
      WhatId = line.Id,
      Subject = subject,
      ActivityDate = (dueDate != null ? dueDate : Date.today().addDays(3)),
      Priority = (String.isNotBlank(priority) ? priority : 'High'),
      Status = 'Not Started',
      Description = comments,
      OwnerId = UserInfo.getUserId()
    );
    insert t;

    line.Follow_Up_Status__c = 'Task_Assigned';
    line.Active_Task_Id__c = t.Id;
    if (String.isNotBlank(comments)) {
      line.Audit_Notes__c = comments;
    }
    update line;

    return computeAuditSummary(line.Fleet_Invoice__c);
  }

  /**
   * @description Resolves an open follow-up task and marks the line as Clean / Reconciled.
   */
  @AuraEnabled
  public static InvoiceAuditSummaryDTO resolveLineTask(
    Id lineId,
    String resolutionNotes
  ) {
    if (lineId == null) {
      throw new AuraHandledException('Line ID is required.');
    }

    Fleet_Invoice_Line__c line = [
      SELECT
        Id,
        Fleet_Invoice__c,
        Active_Task_Id__c,
        Follow_Up_Status__c,
        Audit_Status__c,
        Audit_Notes__c
      FROM Fleet_Invoice_Line__c
      WHERE Id = :lineId
    ];

    if (String.isNotBlank(line.Active_Task_Id__c)) {
      List<Task> tasks = [
        SELECT Id, Status
        FROM Task
        WHERE Id = :line.Active_Task_Id__c
      ];
      if (!tasks.isEmpty()) {
        tasks[0].Status = 'Completed';
        update tasks;
      }
    }

    line.Follow_Up_Status__c = 'Resolved';
    line.Audit_Status__c = 'Clean';
    line.Audit_Notes__c = String.isNotBlank(resolutionNotes)
      ? resolutionNotes
      : 'Resolved via completed task investigation';
    update line;

    return computeAuditSummary(line.Fleet_Invoice__c);
  }

  private static InvoiceAuditSummaryDTO computeAuditSummary(Id invoiceId) {
    Fleet_Invoice__c inv = [
      SELECT
        Id,
        Name,
        Billing_Doc_Number__c,
        Vendor_Account__r.Name,
        Status__c,
        Audit_Review_Status__c,
        Billing_Date__c,
        Payment_Due_Date__c,
        Total_Gross__c,
        Total_Net__c,
        Total_VAT__c,
        Line_Count__c,
        Invoice_Currency__c
      FROM Fleet_Invoice__c
      WHERE Id = :invoiceId
    ];

    List<Fleet_Invoice_Line__c> lines = [
      SELECT
        Id,
        Name,
        Fleet_Asset__c,
        Fleet_Asset__r.Name,
        Fleet_Asset__r.License_Plate__c,
        Fleet_Asset__r.Model__c,
        Driver__c,
        Driver__r.Name,
        Cost_Center__c,
        Cost_Center__r.Name,
        Cost_Center__r.Company_Name__c,
        Invoice_Category__c,
        Invoice_Concerning__c,
        Recharge_Type__c,
        Net_Amount__c,
        VAT_Amount__c,
        Gross_Amount__c,
        Credit_Allowance_Applied__c,
        Audit_Status__c,
        Audit_Notes__c,
        Follow_Up_Status__c,
        Active_Task_Id__c
      FROM Fleet_Invoice_Line__c
      WHERE Fleet_Invoice__c = :invoiceId
      ORDER BY Gross_Amount__c DESC
    ];

    // Collect Line IDs and Active Task IDs
    Set<Id> lineIds = new Set<Id>();
    Set<Id> taskIds = new Set<Id>();
    for (Fleet_Invoice_Line__c l : lines) {
      lineIds.add(l.Id);
      if (String.isNotBlank(l.Active_Task_Id__c)) {
        try {
          taskIds.add((Id) l.Active_Task_Id__c);
        } catch (Exception e) {
        }
      }
    }

    // Query Tasks associated with these lines
    Map<Id, Task> taskByLineId = new Map<Id, Task>();
    Map<Id, Task> taskById = new Map<Id, Task>();
    if (!lineIds.isEmpty() || !taskIds.isEmpty()) {
      for (Task t : [
        SELECT
          Id,
          WhatId,
          Subject,
          Status,
          Priority,
          ActivityDate,
          CreatedDate,
          Owner.Name
        FROM Task
        WHERE WhatId IN :lineIds OR Id IN :taskIds
      ]) {
        if (t.WhatId != null) {
          taskByLineId.put(t.WhatId, t);
        }
        taskById.put(t.Id, t);
      }
    }

    // Fetch Native Report IDs for 1-Click Navigation
    Map<String, String> reportMap = new Map<String, String>();
    for (Report r : [
      SELECT Id, DeveloperName
      FROM Report
      WHERE
        DeveloperName IN (
          'Invoice_Spend_by_Category',
          'Invoice_Reconciliation_Status',
          'Invoice_Spend_by_Cost_Center',
          'Invoice_Recharges_and_Fines'
        )
    ]) {
      reportMap.put(r.DeveloperName, r.Id);
    }

    InvoiceAuditSummaryDTO dto = new InvoiceAuditSummaryDTO();
    dto.invoiceId = inv.Id;
    dto.invoiceReference = inv.Name;
    dto.billingDocNumber = inv.Billing_Doc_Number__c;
    dto.vendorName = inv.Vendor_Account__r != null
      ? inv.Vendor_Account__r.Name
      : 'Ayvens UK';
    dto.status = inv.Status__c;
    dto.auditReviewStatus = inv.Audit_Review_Status__c;
    dto.billingDate = inv.Billing_Date__c;
    dto.paymentDueDate = inv.Payment_Due_Date__c;
    dto.currencyIso = (String.isNotBlank(inv.Invoice_Currency__c)
      ? inv.Invoice_Currency__c
      : 'GBP');
    dto.currencySymbol = (dto.currencyIso == 'EUR'
      ? '€'
      : (dto.currencyIso == 'USD' ? '$' : '£'));
    dto.totalGross = inv.Total_Gross__c != null ? inv.Total_Gross__c : 0;
    dto.totalNet = inv.Total_Net__c != null ? inv.Total_Net__c : 0;
    dto.totalVat = inv.Total_VAT__c != null ? inv.Total_VAT__c : 0;
    dto.lineCount = inv.Line_Count__c != null
      ? Integer.valueOf(inv.Line_Count__c)
      : lines.size();
    dto.reportMap = reportMap;

    dto.cleanCount = 0;
    dto.cleanAmount = 0;
    dto.exceptionCount = 0;
    dto.exceptionAmount = 0;
    dto.unallocatedAssetCount = 0;
    dto.unallocatedAssetAmount = 0;
    dto.unallocatedDriverCount = 0;
    dto.unallocatedDriverAmount = 0;
    dto.flaggedOver6kCount = 0;
    dto.flaggedOver6kAmount = 0;
    dto.missingCreditCount = 0;
    dto.missingCreditAmount = 0;
    dto.rechargeCount = 0;
    dto.rechargeAmount = 0;
    dto.disputedCount = 0;
    dto.disputedAmount = 0;
    dto.maxSingleLineGross = 0;

    Map<String, CategorySpendDTO> catMap = new Map<String, CategorySpendDTO>();
    Map<String, CostCenterSpendDTO> ccMap = new Map<String, CostCenterSpendDTO>();
    List<AnomalyLineDTO> anomalyList = new List<AnomalyLineDTO>();
    List<AnomalyLineDTO> pendingList = new List<AnomalyLineDTO>();
    List<AnomalyLineDTO> delegatedList = new List<AnomalyLineDTO>();

    for (Fleet_Invoice_Line__c l : lines) {
      Decimal gross = l.Gross_Amount__c != null ? l.Gross_Amount__c : 0;
      Decimal net = l.Net_Amount__c != null ? l.Net_Amount__c : 0;
      String st = String.isNotBlank(l.Audit_Status__c)
        ? l.Audit_Status__c
        : 'Clean';
      String cat = l.Invoice_Category__c != null ? l.Invoice_Category__c : '';
      String followUp = String.isNotBlank(l.Follow_Up_Status__c)
        ? l.Follow_Up_Status__c
        : 'None';

      // Track highest non-leasing single line
      if (
        !cat.containsIgnoreCase('Rental') &&
        !cat.containsIgnoreCase('Monthly') &&
        gross > dto.maxSingleLineGross
      ) {
        dto.maxSingleLineGross = gross;
      }

      if (st == 'Clean') {
        dto.cleanCount++;
        dto.cleanAmount += gross;
      } else {
        dto.exceptionCount++;
        dto.exceptionAmount += gross;

        if (st == 'Unallocated_Asset') {
          dto.unallocatedAssetCount++;
          dto.unallocatedAssetAmount += gross;
        } else if (st == 'Unallocated_Driver') {
          dto.unallocatedDriverCount++;
          dto.unallocatedDriverAmount += gross;
        } else if (st == 'Flagged_Over_6k') {
          dto.flaggedOver6kCount++;
          dto.flaggedOver6kAmount += gross;
        } else if (st == 'Missing_Repair_Credit') {
          dto.missingCreditCount++;
          dto.missingCreditAmount += gross;
        } else if (st == 'Recharge_Payroll_Deduction') {
          dto.rechargeCount++;
          dto.rechargeAmount += gross;
        } else if (st == 'Disputed') {
          dto.disputedCount++;
          dto.disputedAmount += gross;
        }

        if (anomalyList.size() < 100) {
          AnomalyLineDTO a = new AnomalyLineDTO();
          a.lineId = l.Id;
          a.lineNumber = l.Name;
          a.assetId = l.Fleet_Asset__c;
          a.assetPlate = l.Fleet_Asset__r != null
            ? l.Fleet_Asset__r.License_Plate__c
            : 'Unmatched Vehicle';
          a.assetModel = l.Fleet_Asset__r != null
            ? l.Fleet_Asset__r.Model__c
            : '';
          a.driverId = l.Driver__c;
          a.driverName = l.Driver__r != null
            ? l.Driver__r.Name
            : 'Unmatched Driver';
          a.costCenterName = l.Cost_Center__r != null
            ? l.Cost_Center__r.Name
            : 'Unassigned';
          a.category = String.isNotBlank(l.Invoice_Category__c)
            ? l.Invoice_Category__c.replace('_', ' ')
            : '';
          a.concerning = l.Invoice_Concerning__c;
          a.rechargeType = String.isNotBlank(l.Recharge_Type__c)
            ? l.Recharge_Type__c.replace('_', ' ')
            : '';
          a.grossAmount = gross;
          a.auditStatus = st;
          a.auditNotes = l.Audit_Notes__c;
          a.followUpStatus = followUp;

          // Match task
          Task matchedTask = null;
          if (
            String.isNotBlank(l.Active_Task_Id__c) &&
            taskById.containsKey((Id) l.Active_Task_Id__c)
          ) {
            matchedTask = taskById.get((Id) l.Active_Task_Id__c);
          } else if (taskByLineId.containsKey(l.Id)) {
            matchedTask = taskByLineId.get(l.Id);
          }

          if (matchedTask != null) {
            a.taskId = matchedTask.Id;
            a.taskSubject = matchedTask.Subject;
            a.taskDueDate = matchedTask.ActivityDate;
            a.taskPriority = matchedTask.Priority;
            a.taskStatus = matchedTask.Status;
            a.taskOwnerName = matchedTask.Owner != null
              ? matchedTask.Owner.Name
              : 'Fleet Ops';
          }

          anomalyList.add(a);

          // Split into interactive queues
          if (followUp == 'Task_Assigned') {
            delegatedList.add(a);
          } else {
            pendingList.add(a);
          }
        }
      }

      // Categorical roll-up
      String rawCat = String.isNotBlank(l.Invoice_Category__c)
        ? l.Invoice_Category__c
        : 'Other';
      String catName = rawCat.replace('_', ' ');
      if (!catMap.containsKey(catName)) {
        CategorySpendDTO cd = new CategorySpendDTO();
        cd.category = catName;
        cd.grossAmount = 0;
        cd.netAmount = 0;
        cd.lineCount = 0;
        catMap.put(catName, cd);
      }
      CategorySpendDTO existingCat = catMap.get(catName);
      existingCat.grossAmount += gross;
      existingCat.netAmount += net;
      existingCat.lineCount++;

      // Cost Center roll-up
      if (l.Cost_Center__c != null) {
        String ccId = l.Cost_Center__c;
        if (!ccMap.containsKey(ccId)) {
          CostCenterSpendDTO ccd = new CostCenterSpendDTO();
          ccd.costCenterId = ccId;
          ccd.costCenterName = l.Cost_Center__r.Name;
          ccd.companyName = l.Cost_Center__r.Company_Name__c;
          ccd.grossAmount = 0;
          ccd.lineCount = 0;
          ccMap.put(ccId, ccd);
        }
        CostCenterSpendDTO existingCC = ccMap.get(ccId);
        existingCC.grossAmount += gross;
        existingCC.lineCount++;
      }
    }

    // Calculate percentages
    if (dto.lineCount > 0) {
      dto.cleanPercentage = (Decimal.valueOf(dto.cleanCount) /
        Decimal.valueOf(dto.lineCount) *
        100)
        .setScale(1);
      dto.exceptionPercentage = (Decimal.valueOf(dto.exceptionCount) /
        Decimal.valueOf(dto.lineCount) *
        100)
        .setScale(1);
    } else {
      dto.cleanPercentage = 100;
      dto.exceptionPercentage = 0;
    }

    // Finalize category list with percentages
    List<CategorySpendDTO> catList = catMap.values();
    for (CategorySpendDTO c : catList) {
      if (dto.totalGross != 0) {
        c.percentage = (c.grossAmount / dto.totalGross * 100).setScale(1);
      } else {
        c.percentage = 0;
      }
    }
    dto.categoryBreakdown = catList;
    dto.topCostCenters = ccMap.values();
    dto.anomalyLines = anomalyList;
    dto.pendingLines = pendingList;
    dto.delegatedLines = delegatedList;
    dto.pendingCount = pendingList.size();
    dto.delegatedCount = delegatedList.size();

    // Evaluate Threshold Rules
    evaluateThresholds(dto);

    return dto;
  }

  private static void evaluateThresholds(InvoiceAuditSummaryDTO dto) {
    List<Fleet_Audit_Threshold__c> rules = [
      SELECT
        Id,
        Rule_Name__c,
        Metric_Type__c,
        Operator__c,
        Threshold_Value__c,
        Severity__c,
        Notification_Target__c,
        Description__c,
        Is_Active__c
      FROM Fleet_Audit_Threshold__c
      WHERE Is_Active__c = TRUE
      ORDER BY Severity__c DESC, Rule_Name__c ASC
    ];

    List<ThresholdRuleDTO> activeList = new List<ThresholdRuleDTO>();
    List<ThresholdRuleDTO> breachedList = new List<ThresholdRuleDTO>();
    Integer criticalCount = 0;
    Integer warningCount = 0;
    Integer infoCount = 0;

    Decimal unallocatedTotal =
      dto.unallocatedAssetAmount + dto.unallocatedDriverAmount;
    Decimal unallocatedPct = dto.totalGross > 0
      ? (unallocatedTotal / dto.totalGross * 100).setScale(2)
      : 0;
    Decimal rechargePct = dto.totalGross > 0
      ? (dto.rechargeAmount / dto.totalGross * 100).setScale(2)
      : 0;

    for (Fleet_Audit_Threshold__c rule : rules) {
      ThresholdRuleDTO t = new ThresholdRuleDTO();
      t.thresholdId = rule.Id;
      t.ruleName = rule.Rule_Name__c;
      t.metricType = rule.Metric_Type__c;
      t.operator = rule.Operator__c;
      t.thresholdValue = rule.Threshold_Value__c != null
        ? rule.Threshold_Value__c
        : 0;
      t.severity = rule.Severity__c;
      t.notificationTarget = rule.Notification_Target__c;
      t.description = rule.Description__c;
      t.isBreached = false;
      t.breachAmount = 0;

      Decimal actual = 0;
      String unit = '';

      if (rule.Metric_Type__c == 'Unallocated_Spend_Pct') {
        actual = unallocatedPct;
        unit = '%';
        t.breachAmount = unallocatedTotal;
        t.formattedThreshold = t.thresholdValue + '%';
        t.formattedActual =
          actual +
          '% (' +
          dto.currencySymbol +
          unallocatedTotal.format() +
          ')';
      } else if (rule.Metric_Type__c == 'Single_Line_Max_Gross') {
        actual = dto.maxSingleLineGross;
        unit = dto.currencySymbol;
        t.breachAmount = dto.flaggedOver6kAmount > 0
          ? dto.flaggedOver6kAmount
          : dto.maxSingleLineGross;
        t.formattedThreshold = dto.currencySymbol + t.thresholdValue.format();
        t.formattedActual = dto.currencySymbol + actual.format();
      } else if (rule.Metric_Type__c == 'Missing_Credit_Count') {
        actual = dto.missingCreditCount;
        t.breachAmount = dto.missingCreditAmount;
        t.formattedThreshold = String.valueOf(t.thresholdValue.intValue());
        t.formattedActual =
          actual.intValue() +
          ' missing line' +
          (actual.intValue() != 1 ? 's' : '');
      } else if (rule.Metric_Type__c == 'Recharge_Spend_Pct') {
        actual = rechargePct;
        unit = '%';
        t.breachAmount = dto.rechargeAmount;
        t.formattedThreshold = t.thresholdValue + '%';
        t.formattedActual =
          actual +
          '% (' +
          dto.currencySymbol +
          dto.rechargeAmount.format() +
          ')';
      } else if (rule.Metric_Type__c == 'Mileage_Deviation_Pct') {
        actual = 0;
        t.formattedThreshold = t.thresholdValue + '%';
        t.formattedActual = actual + '%';
      }

      t.actualValue = actual;

      // Evaluate comparison operator
      Boolean breached = false;
      if (rule.Operator__c == 'Greater_Than') {
        breached = (actual > t.thresholdValue);
      } else if (rule.Operator__c == 'Greater_Or_Equal') {
        breached = (actual >= t.thresholdValue && actual > 0);
      } else if (rule.Operator__c == 'Less_Than') {
        breached = (actual < t.thresholdValue);
      } else if (rule.Operator__c == 'Equals') {
        breached = (actual == t.thresholdValue);
      }

      t.isBreached = breached;

      if (breached) {
        if (rule.Metric_Type__c == 'Unallocated_Spend_Pct') {
          t.message =
            'Unallocated vehicle and driver spend is ' +
            actual +
            '% (' +
            dto.currencySymbol +
            unallocatedTotal.format() +
            '), exceeding governance tolerance limit of ' +
            t.thresholdValue +
            '%.';
        } else if (rule.Metric_Type__c == 'Single_Line_Max_Gross') {
          t.message =
            'Single line gross reached ' +
            dto.currencySymbol +
            actual.format() +
            ', breaching high-value cap (' +
            dto.currencySymbol +
            t.thresholdValue.format() +
            '). Requires senior management approval.';
        } else if (rule.Metric_Type__c == 'Missing_Credit_Count') {
          t.message =
            'Identified ' +
            actual.intValue() +
            ' End-of-Contract return line(s) lacking contractual refurbishment credit allowance.';
        } else if (rule.Metric_Type__c == 'Recharge_Spend_Pct') {
          t.message =
            'Operational recharges and traffic fines represent ' +
            actual +
            '% (' +
            dto.currencySymbol +
            dto.rechargeAmount.format() +
            ') of invoice, exceeding ' +
            t.thresholdValue +
            '% threshold.';
        } else {
          t.message =
            rule.Rule_Name__c +
            ' breached (Actual: ' +
            actual +
            ', Threshold: ' +
            t.thresholdValue +
            ').';
        }

        breachedList.add(t);

        if (rule.Severity__c == 'Critical_Blocker') {
          criticalCount++;
        } else if (rule.Severity__c == 'Warning') {
          warningCount++;
        } else {
          infoCount++;
        }
      }

      activeList.add(t);
    }

    dto.activeThresholds = activeList;
    dto.breachedThresholds = breachedList;
    dto.hasThresholdBreaches = !breachedList.isEmpty();
    dto.criticalBreachCount = criticalCount;
    dto.warningBreachCount = warningCount;
    dto.infoBreachCount = infoCount;
  }

  /**
   * @description Generates a commercial vendor dispute letter backed by unallocated and contested line items.
   */
  @AuraEnabled
  public static String generateDisputeMemo(Id invoiceId) {
    if (invoiceId == null) {
      throw new AuraHandledException('Invoice ID cannot be null.');
    }

    InvoiceAuditSummaryDTO summary = getInvoiceAuditSummary(invoiceId);
    String sym = String.isNotBlank(summary.currencySymbol)
      ? summary.currencySymbol
      : '£';

    List<AnomalyLineDTO> disputedLines = new List<AnomalyLineDTO>();
    Decimal totalDisputedGross = 0;
    if (summary.pendingLines != null) {
      for (AnomalyLineDTO line : summary.pendingLines) {
        if (
          line.auditStatus == 'Unallocated_Asset' ||
          line.auditStatus == 'Unallocated_Driver' ||
          line.auditStatus == 'Disputed' ||
          line.auditStatus == 'Missing_Repair_Credit' ||
          line.auditStatus == 'Flagged_Over_6k'
        ) {
          disputedLines.add(line);
          totalDisputedGross += (line.grossAmount != null
            ? line.grossAmount
            : 0);
        }
      }
    }

    String todayFormatted = DateTime.now().format('dd MMMM yyyy');
    String memo = '';
    memo += '# COMMERCIAL AUDIT DISPUTE NOTICE\n\n';
    memo += '**Date:** ' + todayFormatted + '\n';
    memo +=
      '**To:** ' +
      (String.isNotBlank(summary.vendorName)
        ? summary.vendorName
        : 'Ayvens Fleet Management') +
      ' Commercial Relations & Billing Team\n';
    memo += '**From:** Philips Global Fleet Operations\n';
    memo +=
      '**Subject:** Formal Reconciliation Dispute — Billing Document #' +
      summary.billingDocNumber +
      '\n\n';
    memo += '---\n\n';
    memo += '### Executive Summary\n';
    memo +=
      'Following our automated fleet financial audit of Billing Document **#' +
      summary.billingDocNumber +
      '** (dated ' +
      String.valueOf(summary.billingDate) +
      '), Philips Global Fleet Operations has identified **' +
      disputedLines.size() +
      ' contested line items** totaling **' +
      sym +
      totalDisputedGross.format() +
      '** that fail contractual reconciliation criteria.\n\n';
    memo += '**Dispute Breakdown:**\n';
    memo +=
      '- **Unallocated Vehicle Spend:** ' +
      summary.unallocatedAssetCount +
      ' lines (' +
      sym +
      summary.unallocatedAssetAmount.format() +
      ') for license plates not matching our authorized fleet asset registry.\n';
    memo +=
      '- **Unallocated Driver / Cost Center:** ' +
      summary.unallocatedDriverCount +
      ' lines (' +
      sym +
      summary.unallocatedDriverAmount.format() +
      ') lacking valid HR payroll ID or cost allocation.\n';
    if (summary.missingCreditCount > 0) {
      memo +=
        '- **Missing Contractual Credits:** ' +
        summary.missingCreditCount +
        ' lines (' +
        sym +
        summary.missingCreditAmount.format() +
        ') where agreed end-of-contract allowances were omitted.\n';
    }
    memo += '\n';
    memo += '### Contested Line Items (Top Exceptions)\n\n';
    memo +=
      '| Line Number | License Plate | Driver / Ref | Cost Center | Category | Amount (' +
      sym +
      ') | Reason |\n';
    memo += '| :--- | :--- | :--- | :--- | :--- | :--- | :--- |\n';

    Integer displayLimit = Math.min(disputedLines.size(), 15);
    for (Integer i = 0; i < displayLimit; i++) {
      AnomalyLineDTO l = disputedLines[i];
      memo +=
        '| ' +
        l.lineNumber +
        ' | ' +
        (l.assetPlate != null ? l.assetPlate : 'N/A') +
        ' | ' +
        (l.driverName != null ? l.driverName : 'Unassigned') +
        ' | ' +
        (l.costCenterName != null ? l.costCenterName : 'Unmapped') +
        ' | ' +
        l.category +
        ' | ' +
        sym +
        l.grossAmount.format() +
        ' | ' +
        (l.auditNotes != null ? l.auditNotes : 'Audit exception') +
        ' |\n';
    }
    if (disputedLines.size() > displayLimit) {
      memo +=
        '\n*(...and ' +
        (disputedLines.size() - displayLimit) +
        ' additional contested lines itemized in attached schedule)*\n\n';
    }
    memo += '\n### Required Commercial Action\n';
    memo +=
      '1. In accordance with the Master Fleet Services Agreement, payment on the disputed variance amount of **' +
      sym +
      totalDisputedGross.format() +
      '** is placed under operational administrative hold.\n';
    memo +=
      '2. The undisputed clean balance of **' +
      sym +
      summary.cleanAmount.format() +
      '** (' +
      summary.cleanPercentage +
      '% of invoice) will proceed for standard ERP payment release.\n';
    memo += '3. Please review the itemized schedule above and provide either proof of assignment or an adjusted Credit Note within five (5) business days.\n\n';
    memo += '**Authorized Signatory:**\n';
    memo += 'Lital — Global Fleet Manager, Philips Operations\n';

    return memo;
  }
}
