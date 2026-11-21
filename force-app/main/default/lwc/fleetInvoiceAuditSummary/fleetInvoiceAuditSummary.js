import { LightningElement, api, wire, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import { NavigationMixin } from "lightning/navigation";
import getInvoiceAuditSummary from "@salesforce/apex/FleetInvoiceAuditService.getInvoiceAuditSummary";
import runInvoiceAudit from "@salesforce/apex/FleetInvoiceAuditService.runInvoiceAudit";
import updateInvoiceLineStatus from "@salesforce/apex/FleetInvoiceAuditService.updateInvoiceLineStatus";
import updateInvoiceReviewStatus from "@salesforce/apex/FleetInvoiceAuditService.updateInvoiceReviewStatus";
import createLineFollowUpTask from "@salesforce/apex/FleetInvoiceAuditService.createLineFollowUpTask";
import resolveLineTask from "@salesforce/apex/FleetInvoiceAuditService.resolveLineTask";
import generateDisputeMemo from "@salesforce/apex/FleetInvoiceAuditService.generateDisputeMemo";
import importInvoiceCsv from "@salesforce/apex/FleetInvoiceUploadService.importInvoiceCsv";

export default class FleetInvoiceAuditSummary extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  @track summary;
  @track isLoading = false;
  @track selectedFilter = "ALL";
  @track activeTab = "pending";

  // Delegation Modal State
  @track isTaskModalOpen = false;
  @track selectedLineForTask = null;
  @track taskSubject = "";
  @track taskDueDate = "";
  @track taskPriority = "High";
  @track taskComments = "";

  // Upload Modal State (Pattern C)
  @track isUploadModalOpen = false;
  @track uploadDocNumber = "";
  @track uploadCurrency = "GBP";
  @track uploadCsvContent = "";
  @track uploadFileName = "";
  @track uploadFileSizeBytes = 0;

  // Dispute Memo State
  @track isDisputeModalOpen = false;
  @track disputeMemoText = "";

  wiredSummaryResult;

  @wire(getInvoiceAuditSummary, { invoiceId: "$recordId" })
  wiredSummary(result) {
    this.wiredSummaryResult = result;
    if (result.data) {
      this.summary = result.data;
    } else if (result.error) {
      this.summary = null;
    }
  }

  get hasData() {
    return !!this.summary && this.summary.lineCount > 0;
  }

  get currencyCode() {
    return this.summary && this.summary.currencyIso
      ? this.summary.currencyIso
      : "GBP";
  }

  get currencySymbol() {
    return this.summary && this.summary.currencySymbol
      ? this.summary.currencySymbol
      : "£";
  }

  get currencyOptions() {
    return [
      { label: "GBP (£) — United Kingdom", value: "GBP" },
      { label: "EUR (€) — Continental Europe", value: "EUR" },
      { label: "USD ($) — International / Americas", value: "USD" }
    ];
  }

  get isUploadSubmitDisabled() {
    return (
      !this.uploadDocNumber ||
      (!this.uploadCsvContent && !this.uploadFileName) ||
      this.isLoading
    );
  }

  get reviewStatusBadgeClass() {
    if (!this.summary) return "slds-badge";
    const st = this.summary.auditReviewStatus;
    if (st === "Approved") return "slds-badge slds-theme_success";
    if (st === "Disputed" || st === "Audit_Review_Required")
      return "slds-badge slds-theme_error";
    return "slds-badge slds-theme_warning";
  }

  get reviewStatusLabel() {
    if (!this.summary) return "Pending Review";
    const st = this.summary.auditReviewStatus;
    if (st === "Approved") return "Approved for Payment";
    if (st === "Disputed") return "Disputed with Lessor";
    if (st === "Audit_Review_Required") return "Audit Review Required";
    return "Pending Review";
  }

  get hasThresholdBreaches() {
    return !!this.summary && this.summary.hasThresholdBreaches;
  }

  get breachAlertSummaryText() {
    if (!this.summary || !this.summary.breachedThresholds) return "";
    const crit = this.summary.criticalBreachCount || 0;
    const warn = this.summary.warningBreachCount || 0;
    return `${this.summary.breachedThresholds.length} rules breached (${crit} critical, ${warn} warning)`;
  }

  get pendingQueueCount() {
    return this.summary && this.summary.pendingCount != null
      ? this.summary.pendingCount
      : this.summary
        ? this.summary.exceptionCount
        : 0;
  }

  get delegatedQueueCount() {
    return this.summary && this.summary.delegatedCount != null
      ? this.summary.delegatedCount
      : 0;
  }

  get priorityOptions() {
    return [
      { label: "High", value: "High" },
      { label: "Normal", value: "Normal" },
      { label: "Low", value: "Low" }
    ];
  }

  get processedActiveThresholds() {
    if (!this.summary || !this.summary.activeThresholds) return [];
    return this.summary.activeThresholds.map((t) => {
      const isCritical = t.severity === "Critical_Blocker";
      return {
        ...t,
        statusBadgeClass: t.isBreached
          ? "slds-badge slds-theme_error"
          : "slds-badge slds-theme_success",
        statusLabel: t.isBreached ? "BREACHED" : "PASS",
        severityBadgeClass: isCritical
          ? "slds-badge slds-theme_error"
          : t.severity === "Warning"
            ? "slds-badge slds-theme_warning"
            : "slds-badge slds-theme_info",
        severityLabel: isCritical ? "Critical Blocker" : t.severity,
        operatorLabel: t.operator ? t.operator.replace("_", " ") : ""
      };
    });
  }

  // Filtered pending queue
  get filteredPendingLines() {
    if (!this.summary) return [];
    const lines = this.summary.pendingLines || this.summary.anomalyLines || [];
    if (this.selectedFilter === "ALL") {
      return lines;
    }
    return lines.filter((a) => a.auditStatus === this.selectedFilter);
  }

  get hasNoFilteredPendingLines() {
    return !this.filteredPendingLines || this.filteredPendingLines.length === 0;
  }

  // Delegated queue
  get delegatedLines() {
    return (this.summary && this.summary.delegatedLines) || [];
  }

  get hasNoDelegatedLines() {
    return !this.delegatedLines || this.delegatedLines.length === 0;
  }

  get isAllFilter() {
    return this.selectedFilter === "ALL";
  }
  get isUnallocatedAssetFilter() {
    return this.selectedFilter === "Unallocated_Asset";
  }
  get isUnallocatedDriverFilter() {
    return this.selectedFilter === "Unallocated_Driver";
  }
  get isRechargeFilter() {
    return this.selectedFilter === "Recharge_Payroll_Deduction";
  }
  get isOver6kFilter() {
    return this.selectedFilter === "Flagged_Over_6k";
  }
  get isMissingCreditFilter() {
    return this.selectedFilter === "Missing_Repair_Credit";
  }
  get isDisputedFilter() {
    return this.selectedFilter === "Disputed";
  }

  get allPillClass() {
    return `filter-pill ${this.isAllFilter ? "active" : ""}`;
  }
  get unallocatedAssetPillClass() {
    return `filter-pill ${this.isUnallocatedAssetFilter ? "active" : ""}`;
  }
  get unallocatedDriverPillClass() {
    return `filter-pill ${this.isUnallocatedDriverFilter ? "active" : ""}`;
  }
  get rechargePillClass() {
    return `filter-pill ${this.isRechargeFilter ? "active" : ""}`;
  }
  get over6kPillClass() {
    return `filter-pill ${this.isOver6kFilter ? "active" : ""}`;
  }
  get missingCreditPillClass() {
    return `filter-pill ${this.isMissingCreditFilter ? "active" : ""}`;
  }
  get disputedPillClass() {
    return `filter-pill ${this.isDisputedFilter ? "active" : ""}`;
  }

  handleFilterSelect(event) {
    this.selectedFilter = event.currentTarget.dataset.filter;
  }

  handleTabSelect(event) {
    this.activeTab = event.target.value;
  }

  handleSwitchToGovernanceTab() {
    this.activeTab = "governance";
  }

  // -----------------------------------------------------------------
  // Report Deep-Link Navigation
  // -----------------------------------------------------------------
  handleOpenReport(event) {
    const reportDevName = event.currentTarget.dataset.report;
    if (
      !this.summary ||
      !this.summary.reportMap ||
      !this.summary.reportMap[reportDevName]
    ) {
      this.showToast(
        "Report Unavailable",
        `Report ${reportDevName} not found in this environment.`,
        "info"
      );
      return;
    }

    const reportId = this.summary.reportMap[reportDevName];
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: reportId,
        objectApiName: "Report",
        actionName: "view"
      }
    });
  }

  // -----------------------------------------------------------------
  // Interactive Task Delegation Modal & Actions
  // -----------------------------------------------------------------
  handleOpenTaskModal(event) {
    const lineId = event.currentTarget.dataset.id;
    const allLines = this.summary.anomalyLines || [];
    const line = allLines.find((l) => l.lineId === lineId);

    if (!line) return;

    this.selectedLineForTask = line;

    // Context-aware subject pre-fill
    if (line.auditStatus === "Unallocated_Asset") {
      this.taskSubject = `Query Ayvens: vehicle ${line.assetPlate} unregistered on Bill #${this.summary.billingDocNumber}`;
    } else if (line.auditStatus === "Unallocated_Driver") {
      this.taskSubject = `HR Payroll Follow-up: map driver / cost center for ${line.assetPlate}`;
    } else if (line.auditStatus === "Flagged_Over_6k") {
      this.taskSubject = `Finance Approval: single line repair exceeds £5k threshold (£${line.grossAmount})`;
    } else if (line.auditStatus === "Missing_Repair_Credit") {
      this.taskSubject = `Lessor Credit Note Request: missing £250/€300 EoC refurbishment credit for ${line.assetPlate}`;
    } else if (line.auditStatus === "Recharge_Payroll_Deduction") {
      this.taskSubject = `Payroll Deduction Notice: ${line.rechargeType || line.category} for driver ${line.driverName}`;
    } else {
      this.taskSubject = `Reconciliation follow-up for line ${line.lineNumber} (${line.assetPlate})`;
    }

    // Default due date: 3 business days from today
    const defaultDue = new Date();
    defaultDue.setDate(defaultDue.getDate() + 3);
    this.taskDueDate = defaultDue.toISOString().split("T")[0];
    this.taskPriority = "High";
    this.taskComments = line.auditNotes || "";

    this.isTaskModalOpen = true;
  }

  handleCloseTaskModal() {
    this.isTaskModalOpen = false;
    this.selectedLineForTask = null;
  }

  handleSubjectChange(event) {
    this.taskSubject = event.target.value;
  }
  handleDueDateChange(event) {
    this.taskDueDate = event.target.value;
  }
  handlePriorityChange(event) {
    this.taskPriority = event.target.value;
  }
  handleCommentsChange(event) {
    this.taskComments = event.target.value;
  }

  async handleSaveTask() {
    if (!this.selectedLineForTask || !this.taskSubject) {
      this.showToast("Validation Error", "Task subject is required.", "error");
      return;
    }

    this.isLoading = true;
    try {
      const updatedSummary = await createLineFollowUpTask({
        lineId: this.selectedLineForTask.lineId,
        subject: this.taskSubject,
        dueDate: this.taskDueDate,
        priority: this.taskPriority,
        comments: this.taskComments
      });

      this.summary = updatedSummary;
      this.isTaskModalOpen = false;
      await refreshApex(this.wiredSummaryResult);
      this.showToast(
        "Task Created",
        `Assigned task and moved line ${this.selectedLineForTask.lineNumber} to 'In Progress Tasks'.`,
        "success"
      );
    } catch (error) {
      this.showToast(
        "Error Creating Task",
        error.body ? error.body.message : error.message,
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  async handleResolveLineTask(event) {
    const lineId = event.currentTarget.dataset.id;
    this.isLoading = true;
    try {
      const updatedSummary = await resolveLineTask({
        lineId: lineId,
        resolutionNotes: "Investigation completed and line approved"
      });
      this.summary = updatedSummary;
      await refreshApex(this.wiredSummaryResult);
      this.showToast(
        "Task Resolved",
        "Task completed and line marked as Clean / Reconciled.",
        "success"
      );
    } catch (error) {
      this.showToast(
        "Error",
        error.body ? error.body.message : error.message,
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  handleNavigateToTask(event) {
    const taskId = event.currentTarget.dataset.id;
    if (!taskId) return;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: taskId,
        actionName: "view"
      }
    });
  }

  // -----------------------------------------------------------------
  // Standard Audit & Invoice Review Handlers
  // -----------------------------------------------------------------
  async handleRunAudit() {
    this.isLoading = true;
    try {
      const updatedSummary = await runInvoiceAudit({
        invoiceId: this.recordId
      });
      this.summary = updatedSummary;
      await refreshApex(this.wiredSummaryResult);
      const breachMsg = updatedSummary.hasThresholdBreaches
        ? ` Triggered ${updatedSummary.breachedThresholds.length} threshold alerts.`
        : "";
      this.showToast(
        "Reconciliation Complete",
        `Audited ${updatedSummary.lineCount} lines. Found ${updatedSummary.exceptionCount} exceptions.${breachMsg}`,
        updatedSummary.hasThresholdBreaches ? "warning" : "success"
      );
    } catch (error) {
      this.showToast(
        "Audit Error",
        error.body ? error.body.message : error.message,
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  async handleApproveInvoice() {
    this.isLoading = true;
    try {
      await updateInvoiceReviewStatus({
        invoiceId: this.recordId,
        newReviewStatus: "Approved"
      });
      await refreshApex(this.wiredSummaryResult);
      this.showToast(
        "Invoice Approved",
        "Invoice status updated to Approved for Payment.",
        "success"
      );
    } catch (error) {
      this.showToast(
        "Approval Error",
        error.body ? error.body.message : error.message,
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  async handleDisputeInvoice() {
    this.isLoading = true;
    try {
      await updateInvoiceReviewStatus({
        invoiceId: this.recordId,
        newReviewStatus: "Disputed"
      });
      await refreshApex(this.wiredSummaryResult);
      this.showToast(
        "Invoice Disputed",
        "Invoice flagged as Disputed with Lessor.",
        "warning"
      );
    } catch (error) {
      this.showToast(
        "Error",
        error.body ? error.body.message : error.message,
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  async handleMarkLineDisputed(event) {
    const lineId = event.currentTarget.dataset.id;
    this.isLoading = true;
    try {
      await updateInvoiceLineStatus({
        lineId: lineId,
        newStatus: "Disputed",
        notes: "Manually flagged for lessor credit adjustment"
      });
      await refreshApex(this.wiredSummaryResult);
      this.showToast("Line Disputed", "Line item flagged for dispute.", "info");
    } catch (error) {
      this.showToast(
        "Error",
        error.body ? error.body.message : error.message,
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  async handleMarkLineClean(event) {
    const lineId = event.currentTarget.dataset.id;
    this.isLoading = true;
    try {
      await updateInvoiceLineStatus({
        lineId: lineId,
        newStatus: "Clean",
        notes: "Manually reviewed and approved by fleet manager"
      });
      await refreshApex(this.wiredSummaryResult);
      this.showToast("Line Approved", "Line marked as Clean.", "success");
    } catch (error) {
      this.showToast(
        "Error",
        error.body ? error.body.message : error.message,
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  handleExportExceptions() {
    if (
      !this.summary ||
      !this.summary.anomalyLines ||
      this.summary.anomalyLines.length === 0
    ) {
      this.showToast(
        "No Exceptions",
        "There are no exceptions to export.",
        "info"
      );
      return;
    }

    const headers = [
      "Line Number",
      "License Plate",
      "Model",
      "Driver",
      "Cost Center",
      "Category",
      "Recharge Type",
      "Gross Amount",
      "Audit Status",
      "Audit Notes"
    ];
    const csvRows = [headers.join(",")];

    for (const line of this.summary.anomalyLines) {
      const row = [
        `"${line.lineNumber || ""}"`,
        `"${line.assetPlate || ""}"`,
        `"${line.assetModel || ""}"`,
        `"${line.driverName || ""}"`,
        `"${line.costCenterName || ""}"`,
        `"${line.category || ""}"`,
        `"${line.rechargeType || ""}"`,
        `"${line.grossAmount || 0}"`,
        `"${line.auditStatus || ""}"`,
        `"${(line.auditNotes || "").replace(/"/g, '""')}"`
      ];
      csvRows.push(row.join(","));
    }

    const csvContent =
      "data:text/csv;charset=utf-8," + encodeURIComponent(csvRows.join("\n"));
    const downloadAnchor = document.createElement("a");
    downloadAnchor.setAttribute("href", csvContent);
    downloadAnchor.setAttribute(
      "download",
      `Invoice_${this.summary.billingDocNumber || "Exceptions"}_Dispute_Export.csv`
    );
    document.body.appendChild(downloadAnchor);
    downloadAnchor.click();
    downloadAnchor.remove();

    this.showToast(
      "CSV Exported",
      "Disputed lines exported for lessor communication.",
      "success"
    );
  }

  handleNavigateToAsset(event) {
    const assetId = event.currentTarget.dataset.id;
    if (!assetId) return;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: assetId,
        actionName: "view"
      }
    });
  }

  // --- Upload Modal Handlers (Pattern C) ---
  handleOpenUploadModal() {
    this.uploadDocNumber = this.summary ? this.summary.billingDocNumber : "";
    this.uploadCurrency =
      this.summary && this.summary.currencyIso
        ? this.summary.currencyIso
        : "GBP";
    this.uploadCsvContent = "";
    this.uploadFileName = "";
    this.uploadFileSizeBytes = 0;
    this.isUploadModalOpen = true;
  }

  handleCloseUploadModal() {
    this.isUploadModalOpen = false;
  }

  handleUploadDocNumberChange(e) {
    this.uploadDocNumber = e.target.value;
  }

  handleUploadCurrencyChange(e) {
    this.uploadCurrency = e.target.value;
  }

  handleUploadCsvChange(e) {
    this.uploadCsvContent = e.target.value;
  }

  handleFileChange(event) {
    const file = event.target.files[0];
    if (!file) return;

    this.uploadFileName = file.name;
    this.uploadFileSizeBytes = Math.round(file.size / 1024);

    const reader = new FileReader();
    reader.onload = () => {
      this.uploadCsvContent = reader.result;
    };
    reader.readAsText(file);
  }

  async handleUploadSubmit() {
    if (!this.uploadDocNumber || !this.uploadCsvContent) {
      this.showToast(
        "Validation Error",
        "Please provide a Billing Doc Number and select or paste CSV content.",
        "warning"
      );
      return;
    }

    this.isLoading = true;
    try {
      const vendor =
        this.summary && this.summary.vendorName
          ? this.summary.vendorName
          : "Ayvens UK";
      const result = await importInvoiceCsv({
        billingDocNumber: this.uploadDocNumber,
        vendorName: vendor,
        billingDate: null,
        currencyIso: this.uploadCurrency,
        csvData: this.uploadCsvContent
      });

      this.showToast("Upload Complete", result.message, "success");
      this.isUploadModalOpen = false;
      await refreshApex(this.wiredSummaryResult);
    } catch (error) {
      this.showToast(
        "Upload Error",
        error.body ? error.body.message : error.message,
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  // --- Dispute Notice Modal Handlers ---
  async handleOpenDisputeModal() {
    this.isLoading = true;
    try {
      const memo = await generateDisputeMemo({ invoiceId: this.recordId });
      this.disputeMemoText = memo;
      this.isDisputeModalOpen = true;
    } catch (error) {
      this.showToast(
        "Error",
        error.body ? error.body.message : error.message,
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  handleCloseDisputeModal() {
    this.isDisputeModalOpen = false;
  }

  handleCopyDisputeMemo() {
    if (!this.disputeMemoText) return;
    navigator.clipboard
      .writeText(this.disputeMemoText)
      .then(() => {
        this.showToast(
          "Copied",
          "Commercial dispute notice copied to clipboard.",
          "success"
        );
      })
      .catch((err) => {
        this.showToast("Error", "Unable to copy to clipboard: " + err, "error");
      });
  }

  handleDownloadDisputeMemo() {
    if (!this.disputeMemoText) return;
    const blob = new Blob([this.disputeMemoText], {
      type: "text/markdown;charset=utf-8"
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `Dispute_Notice_Bill_${this.summary ? this.summary.billingDocNumber : "Reconciliation"}.md`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
    this.showToast(
      "Downloaded",
      "Commercial dispute notice downloaded as Markdown.",
      "success"
    );
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
