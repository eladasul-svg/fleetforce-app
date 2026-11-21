/**
 * @description Enterprise Apex REST controller for FleetForce Financial Reconciliation & Governance.
 * Exposes standardized REST endpoints consumed by the FleetForce Model Context Protocol (MCP) server
 * and Microsoft 365 Copilot plugins.
 *
 * Base Endpoint: /services/apexrest/fleet/v1/reconciliation/*
 */
@RestResource(urlMapping='/fleet/v1/reconciliation/*')
global with sharing class FleetReconciliationRestController {
  global class ActionResponse {
    global Boolean success;
    global String message;
    global Object data;

    global ActionResponse(Boolean success, String message, Object data) {
      this.success = success;
      this.message = message;
      this.data = data;
    }
  }

  global class DelegationRequest {
    global String lineId;
    global String subject;
    global Date dueDate;
    global String priority;
    global String instructions;
  }

  global class ResolutionRequest {
    global String lineId;
    global String resolutionNotes;
  }

  global class ImportRequest {
    global String billingDocNumber;
    global String vendorName;
    global Date billingDate;
    global String currencyIso;
    global String csvData;
    global List<FleetInvoiceUploadService.LineInputDTO> lines;
  }

  @HttpGet
  global static void handleGet() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json');

    String path = req.requestURI.substringAfter('/fleet/v1/reconciliation/');
    if (String.isBlank(path)) {
      path = 'summary';
    }

    try {
      Id invoiceId = resolveInvoiceId(req);
      if (invoiceId == null) {
        res.statusCode = 404;
        res.responseBody = Blob.valueOf(
          JSON.serialize(
            new ActionResponse(
              false,
              'Invoice not found. Provide a valid invoiceId or docNumber parameter.',
              null
            )
          )
        );
        return;
      }

      if (path.startsWithIgnoreCase('summary')) {
        FleetInvoiceAuditService.InvoiceAuditSummaryDTO summary = FleetInvoiceAuditService.getInvoiceAuditSummary(
          invoiceId
        );
        res.statusCode = 200;
        res.responseBody = Blob.valueOf(
          JSON.serialize(
            new ActionResponse(
              true,
              'Reconciliation summary retrieved successfully.',
              summary
            )
          )
        );
        return;
      } else if (path.startsWithIgnoreCase('exceptions')) {
        String filterType = req.params.get('type');
        if (String.isBlank(filterType)) {
          filterType = 'All';
        }
        Integer maxRows = 100;
        if (String.isNotBlank(req.params.get('limit'))) {
          try {
            maxRows = Math.min(Integer.valueOf(req.params.get('limit')), 200);
          } catch (Exception ex) {
            maxRows = 100;
          }
        }

        FleetInvoiceAuditService.InvoiceAuditSummaryDTO summary = FleetInvoiceAuditService.getInvoiceAuditSummary(
          invoiceId
        );
        List<FleetInvoiceAuditService.AnomalyLineDTO> filtered = filterLines(
          summary.pendingLines,
          filterType,
          maxRows
        );

        Map<String, Object> resultData = new Map<String, Object>{
          'invoiceId' => invoiceId,
          'filterType' => filterType,
          'totalPendingExceptions' => summary.pendingLines != null
            ? summary.pendingLines.size()
            : 0,
          'returnedCount' => filtered.size(),
          'lines' => filtered
        };

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(
          JSON.serialize(
            new ActionResponse(
              true,
              'Exceptions retrieved successfully.',
              resultData
            )
          )
        );
        return;
      } else if (path.startsWithIgnoreCase('cost-centers')) {
        FleetInvoiceAuditService.InvoiceAuditSummaryDTO summary = FleetInvoiceAuditService.getInvoiceAuditSummary(
          invoiceId
        );
        Decimal unallocTotal =
          (summary.unallocatedAssetAmount != null
            ? summary.unallocatedAssetAmount
            : 0) +
          (summary.unallocatedDriverAmount != null
            ? summary.unallocatedDriverAmount
            : 0);
        Map<String, Object> ccData = new Map<String, Object>{
          'invoiceId' => invoiceId,
          'topCostCenters' => summary.topCostCenters,
          'unallocatedSpend' => unallocTotal,
          'exceptionPercentage' => summary.exceptionPercentage
        };

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(
          JSON.serialize(
            new ActionResponse(
              true,
              'Cost center breakdown retrieved successfully.',
              ccData
            )
          )
        );
        return;
      } else if (path.startsWithIgnoreCase('dispute-memo')) {
        String memo = FleetInvoiceAuditService.generateDisputeMemo(invoiceId);
        res.statusCode = 200;
        res.responseBody = Blob.valueOf(
          JSON.serialize(
            new ActionResponse(
              true,
              'Dispute memo generated successfully.',
              memo
            )
          )
        );
        return;
      } else {
        res.statusCode = 400;
        res.responseBody = Blob.valueOf(
          JSON.serialize(
            new ActionResponse(
              false,
              'Unknown reconciliation sub-path: ' + path,
              null
            )
          )
        );
        return;
      }
    } catch (Exception ex) {
      res.statusCode = 500;
      res.responseBody = Blob.valueOf(
        JSON.serialize(
          new ActionResponse(
            false,
            'Error executing reconciliation query: ' + ex.getMessage(),
            null
          )
        )
      );
    }
  }

  @HttpPost
  global static void handlePost() {
    RestRequest req = RestContext.request;
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json');

    String path = req.requestURI.substringAfter('/fleet/v1/reconciliation/');
    String body = req.requestBody != null ? req.requestBody.toString() : '';

    try {
      if (path.startsWithIgnoreCase('delegate')) {
        DelegationRequest delReq = (DelegationRequest) JSON.deserialize(
          body,
          DelegationRequest.class
        );
        if (String.isBlank(delReq.lineId)) {
          res.statusCode = 400;
          res.responseBody = Blob.valueOf(
            JSON.serialize(
              new ActionResponse(
                false,
                'lineId is required for task delegation.',
                null
              )
            )
          );
          return;
        }

        Date dueDate = delReq.dueDate != null
          ? delReq.dueDate
          : Date.today().addDays(3);
        String priority = String.isNotBlank(delReq.priority)
          ? delReq.priority
          : 'Normal';
        String subject = String.isNotBlank(delReq.subject)
          ? delReq.subject
          : 'Investigate Invoice Line Exception';

        FleetInvoiceAuditService.InvoiceAuditSummaryDTO updatedSummary = FleetInvoiceAuditService.createLineFollowUpTask(
          (Id) delReq.lineId,
          subject,
          dueDate,
          priority,
          delReq.instructions
        );

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(
          JSON.serialize(
            new ActionResponse(
              true,
              'Task successfully assigned to invoice line.',
              updatedSummary
            )
          )
        );
        return;
      } else if (path.startsWithIgnoreCase('resolve')) {
        ResolutionRequest resReq = (ResolutionRequest) JSON.deserialize(
          body,
          ResolutionRequest.class
        );
        if (String.isBlank(resReq.lineId)) {
          res.statusCode = 400;
          res.responseBody = Blob.valueOf(
            JSON.serialize(
              new ActionResponse(
                false,
                'lineId is required for resolution.',
                null
              )
            )
          );
          return;
        }

        FleetInvoiceAuditService.InvoiceAuditSummaryDTO updatedSummary = FleetInvoiceAuditService.resolveLineTask(
          (Id) resReq.lineId,
          resReq.resolutionNotes
        );
        res.statusCode = 200;
        res.responseBody = Blob.valueOf(
          JSON.serialize(
            new ActionResponse(
              true,
              'Invoice line exception successfully resolved.',
              updatedSummary
            )
          )
        );
        return;
      } else if (path.startsWithIgnoreCase('import')) {
        ImportRequest impReq = (ImportRequest) JSON.deserialize(
          body,
          ImportRequest.class
        );
        if (String.isBlank(impReq.billingDocNumber)) {
          res.statusCode = 400;
          res.responseBody = Blob.valueOf(
            JSON.serialize(
              new ActionResponse(
                false,
                'billingDocNumber is required for import.',
                null
              )
            )
          );
          return;
        }

        FleetInvoiceUploadService.UploadResult upRes;
        if (String.isNotBlank(impReq.csvData)) {
          upRes = FleetInvoiceUploadService.importInvoiceCsv(
            impReq.billingDocNumber,
            impReq.vendorName,
            impReq.billingDate,
            impReq.currencyIso,
            impReq.csvData
          );
        } else {
          upRes = FleetInvoiceUploadService.importInvoiceJson(
            impReq.billingDocNumber,
            impReq.vendorName,
            impReq.billingDate,
            impReq.currencyIso,
            impReq.lines
          );
        }
        res.statusCode = 200;
        res.responseBody = Blob.valueOf(
          JSON.serialize(new ActionResponse(true, upRes.message, upRes))
        );
        return;
      } else {
        res.statusCode = 400;
        res.responseBody = Blob.valueOf(
          JSON.serialize(
            new ActionResponse(false, 'Unknown POST sub-path: ' + path, null)
          )
        );
      }
    } catch (Exception ex) {
      res.statusCode = 500;
      res.responseBody = Blob.valueOf(
        JSON.serialize(
          new ActionResponse(
            false,
            'Error executing action: ' + ex.getMessage(),
            null
          )
        )
      );
    }
  }

  private static Id resolveInvoiceId(RestRequest req) {
    String invoiceIdParam = req.params.get('invoiceId');
    if (String.isNotBlank(invoiceIdParam)) {
      try {
        return (Id) invoiceIdParam;
      } catch (Exception e) {
        // fall through to docNumber
      }
    }

    String docNumber = req.params.get('docNumber');
    if (String.isNotBlank(docNumber)) {
      List<Fleet_Invoice__c> invoices = [
        SELECT Id
        FROM Fleet_Invoice__c
        WHERE Billing_Doc_Number__c = :docNumber
        LIMIT 1
      ];
      if (!invoices.isEmpty()) {
        return invoices[0].Id;
      }
    }
    return null;
  }

  private static List<FleetInvoiceAuditService.AnomalyLineDTO> filterLines(
    List<FleetInvoiceAuditService.AnomalyLineDTO> lines,
    String filterType,
    Integer maxRows
  ) {
    List<FleetInvoiceAuditService.AnomalyLineDTO> result = new List<FleetInvoiceAuditService.AnomalyLineDTO>();
    if (lines == null || lines.isEmpty()) {
      return result;
    }

    for (FleetInvoiceAuditService.AnomalyLineDTO line : lines) {
      Boolean match = false;
      if (filterType == 'All') {
        match = true;
      } else if (
        filterType == 'Unallocated' &&
        (line.assetId == null ||
        line.driverId == null)
      ) {
        match = true;
      } else if (
        filterType == 'Unregistered_Vehicles' &&
        line.assetId == null
      ) {
        match = true;
      } else if (filterType == 'Unmapped_Driver' && line.driverId == null) {
        match = true;
      } else if (
        filterType == 'Recharges_and_Fines' &&
        (line.category == 'Recharge' ||
        line.category == 'Fine')
      ) {
        match = true;
      } else if (filterType == 'High_Value_Lines' && line.grossAmount >= 5000) {
        match = true;
      } else if (
        filterType == 'Missing_EoC_Credits' &&
        line.auditStatus == 'Missing_Credit'
      ) {
        match = true;
      } else if (filterType == 'Disputed' && line.auditStatus == 'Disputed') {
        match = true;
      }

      if (match) {
        result.add(line);
        if (result.size() >= maxRows) {
          break;
        }
      }
    }
    return result;
  }
}
