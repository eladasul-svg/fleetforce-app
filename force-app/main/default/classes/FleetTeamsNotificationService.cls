/**
 * @description Outbound Notification & Adaptive Card Dispatcher for Microsoft Teams & Copilot.
 * Subscribes to Fleet_Audit_Event__e platform events and pushes interactive
 * Adaptive Cards into enterprise Teams channels with deep links to Salesforce & Copilot.
 */
public with sharing class FleetTeamsNotificationService {
  public class NotificationResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public Integer statusCode;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String payload;
  }

  /**
   * @description Dispatches Teams Adaptive Cards for a list of Fleet Audit Events.
   */
  public static void dispatchEvents(List<Fleet_Audit_Event__e> events) {
    if (events == null || events.isEmpty()) {
      return;
    }

    Teams_Integration_Setting__mdt setting = getActiveSetting();
    if (
      setting == null ||
      !setting.Is_Active__c ||
      String.isBlank(setting.Webhook_URL__c)
    ) {
      System.debug(
        LoggingLevel.INFO,
        'Teams webhook integration is disabled or URL not configured.'
      );
      return;
    }

    for (Fleet_Audit_Event__e evt : events) {
      String payload = buildAdaptiveCardJson(
        evt,
        setting.Include_Copilot_Action__c
      );
      sendWebhook(setting.Webhook_URL__c, payload);
    }
  }

  /**
   * @description Sends a single webhook HTTP POST callout.
   */
  public static HttpResponse sendWebhook(
    String webhookUrl,
    String jsonPayload
  ) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(webhookUrl);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setBody(jsonPayload);
    req.setTimeout(15000);

    Http http = new Http();
    HttpResponse res;
    try {
      res = http.send(req);
      System.debug(
        LoggingLevel.INFO,
        'Teams Webhook response status: ' +
          res.getStatusCode() +
          ' - ' +
          res.getStatus()
      );
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.ERROR,
        'Failed to dispatch Teams webhook: ' + ex.getMessage()
      );
      res = new HttpResponse();
      res.setStatusCode(500);
      res.setStatus('Callout Exception: ' + ex.getMessage());
    }
    return res;
  }

  /**
   * @description Builds a standard Microsoft Teams Adaptive Card v1.4 JSON payload.
   */
  public static String buildAdaptiveCardJson(
    Fleet_Audit_Event__e evt,
    Boolean includeCopilotAction
  ) {
    String baseUrl = Url.getOrgDomainUrl().toExternalForm();
    String invoiceRecordUrl =
      baseUrl +
      '/lightning/r/fleetforce__Fleet_Invoice__c/' +
      evt.Invoice_Id__c +
      '/view';

    Boolean isCritical = (evt.Severity__c == 'Critical_Blocker');
    String headerTitle = isCritical
      ? '🚨 CRITICAL FLEET RECONCILIATION BREACH'
      : '⚠️ FLEET RECONCILIATION AUDIT ALERT';
    String headerColor = isCritical ? 'Attention' : 'Warning';
    String containerStyle = isCritical ? 'attention' : 'warning';

    // Pre-compose Copilot prompt for instant drill-down investigation
    String copilotPrompt =
      'Investigate reconciliation breach: ' +
      evt.Rule_Name__c +
      ' on vendor invoice doc #' +
      evt.Billing_Doc_Number__c +
      '. Show which specific vehicles and cost centers account for this variance.';
    String copilotUrl =
      'https://m365.cloud.microsoft/chat?prompt=' +
      EncodingUtil.urlEncode(copilotPrompt, 'UTF-8');

    // Construct Card Body
    List<Object> bodyItems = new List<Object>();

    // Header container
    bodyItems.add(
      new Map<String, Object>{
        'type' => 'Container',
        'style' => containerStyle,
        'items' => new List<Object>{
          new Map<String, Object>{
            'type' => 'TextBlock',
            'text' => headerTitle,
            'weight' => 'Bolder',
            'size' => 'Medium',
            'color' => headerColor
          },
          new Map<String, Object>{
            'type' => 'TextBlock',
            'text' => 'Automated threshold violation detected during invoice reconciliation. Review required prior to ERP payment release.',
            'isSubtle' => true,
            'wrap' => true
          }
        }
      }
    );

    // FactSet of breach metrics
    List<Map<String, String>> facts = new List<Map<String, String>>{
      new Map<String, String>{
        'title' => 'Billing Doc #',
        'value' => (evt.Billing_Doc_Number__c != null
          ? evt.Billing_Doc_Number__c
          : 'N/A')
      },
      new Map<String, String>{
        'title' => 'Rule Name',
        'value' => evt.Rule_Name__c
      },
      new Map<String, String>{
        'title' => 'Severity',
        'value' => (isCritical ? 'Critical Blocker' : evt.Severity__c)
      },
      new Map<String, String>{
        'title' => 'Metric Type',
        'value' => (evt.Metric_Type__c != null
          ? evt.Metric_Type__c.replace('_', ' ')
          : 'N/A')
      },
      new Map<String, String>{
        'title' => 'Configured Limit',
        'value' => String.valueOf(evt.Threshold_Value__c)
      },
      new Map<String, String>{
        'title' => 'Actual Computed',
        'value' => String.valueOf(evt.Actual_Value__c)
      }
    };

    if (evt.Breach_Amount__c != null && evt.Breach_Amount__c > 0) {
      facts.add(
        new Map<String, String>{
          'title' => 'Variance Amount',
          'value' => '£' + evt.Breach_Amount__c.format()
        }
      );
    }

    bodyItems.add(
      new Map<String, Object>{ 'type' => 'FactSet', 'facts' => facts }
    );

    // Finding Message Box
    if (String.isNotBlank(evt.Message__c)) {
      bodyItems.add(
        new Map<String, Object>{
          'type' => 'TextBlock',
          'text' => '**Audit Finding:** ' + evt.Message__c,
          'wrap' => true,
          'spacing' => 'Medium'
        }
      );
    }

    // Action Buttons
    List<Object> actions = new List<Object>();
    actions.add(
      new Map<String, Object>{
        'type' => 'Action.OpenUrl',
        'title' => 'Open in Salesforce FleetOps ↗',
        'url' => invoiceRecordUrl
      }
    );

    if (includeCopilotAction == true) {
      actions.add(
        new Map<String, Object>{
          'type' => 'Action.OpenUrl',
          'title' => 'Investigate with Copilot ↗',
          'url' => copilotUrl
        }
      );
    }

    // Assemble Adaptive Card
    Map<String, Object> adaptiveCard = new Map<String, Object>{
      '$schema' => 'http://adaptivecards.io/schemas/adaptive-card.json',
      'type' => 'AdaptiveCard',
      'version' => '1.4',
      'msteams' => new Map<String, Object>{ 'width' => 'Full' },
      'body' => bodyItems,
      'actions' => actions
    };

    // Standard Teams Webhook Message Wrapper
    Map<String, Object> messageWrapper = new Map<String, Object>{
      'type' => 'message',
      'attachments' => new List<Object>{
        new Map<String, Object>{
          'contentType' => 'application/vnd.microsoft.card.adaptive',
          'contentUrl' => null,
          'content' => adaptiveCard
        }
      }
    };

    return JSON.serialize(messageWrapper);
  }

  /**
   * @description Generates a preview of the Adaptive Card payload for the highest-severity alert on an invoice.
   */
  @AuraEnabled
  public static String previewInvoiceAdaptiveCard(Id invoiceId) {
    if (invoiceId == null) {
      throw new AuraHandledException('Invoice ID cannot be null.');
    }

    List<Audit_Alert__c> alerts = [
      SELECT
        Id,
        Fleet_Invoice__c,
        Fleet_Invoice__r.Billing_Doc_Number__c,
        Rule_Name__c,
        Severity__c,
        Metric_Type__c,
        Threshold_Value__c,
        Actual_Value__c,
        Breach_Amount__c,
        Message__c
      FROM Audit_Alert__c
      WHERE Fleet_Invoice__c = :invoiceId
      ORDER BY Severity__c ASC, Breach_Amount__c DESC
    ];

    if (alerts.isEmpty()) {
      return JSON.serialize(
        new Map<String, Object>{
          'type' => 'message',
          'text' => 'No active threshold alerts found on this invoice.'
        }
      );
    }

    Audit_Alert__c topAlert = alerts[0];
    Fleet_Audit_Event__e mockEvent = new Fleet_Audit_Event__e(
      Invoice_Id__c = String.valueOf(topAlert.Fleet_Invoice__c),
      Billing_Doc_Number__c = topAlert.Fleet_Invoice__r.Billing_Doc_Number__c,
      Rule_Name__c = topAlert.Rule_Name__c,
      Severity__c = topAlert.Severity__c,
      Metric_Type__c = topAlert.Metric_Type__c,
      Threshold_Value__c = topAlert.Threshold_Value__c,
      Actual_Value__c = topAlert.Actual_Value__c,
      Breach_Amount__c = topAlert.Breach_Amount__c,
      Message__c = topAlert.Message__c
    );

    return buildAdaptiveCardJson(mockEvent, true);
  }

  /**
   * @description Sends a test Teams webhook notification for verification.
   */
  @AuraEnabled
  public static NotificationResult sendTestTeamsCard(
    Id invoiceId,
    String customWebhookUrl
  ) {
    String cardJson = previewInvoiceAdaptiveCard(invoiceId);
    String targetUrl = String.isNotBlank(customWebhookUrl)
      ? customWebhookUrl
      : getActiveWebhookUrl();

    if (String.isBlank(targetUrl)) {
      NotificationResult err = new NotificationResult();
      err.success = false;
      err.statusCode = 400;
      err.message = 'No webhook URL provided or configured in Teams_Integration_Setting__mdt.';
      err.payload = cardJson;
      return err;
    }

    HttpResponse res = sendWebhook(targetUrl, cardJson);
    NotificationResult nr = new NotificationResult();
    nr.statusCode = res.getStatusCode();
    nr.success = (res.getStatusCode() >= 200 && res.getStatusCode() < 300);
    nr.message = nr.success
      ? 'Adaptive Card successfully delivered to Teams channel.'
      : 'Webhook returned error status: ' +
        res.getStatusCode() +
        ' - ' +
        res.getStatus();
    nr.payload = cardJson;
    return nr;
  }

  private static Teams_Integration_Setting__mdt getActiveSetting() {
    List<Teams_Integration_Setting__mdt> settings = [
      SELECT
        Webhook_URL__c,
        Is_Active__c,
        Channel_Name__c,
        Include_Copilot_Action__c
      FROM Teams_Integration_Setting__mdt
      WHERE Is_Active__c = TRUE
      LIMIT 1
    ];
    return settings.isEmpty() ? null : settings[0];
  }

  private static String getActiveWebhookUrl() {
    Teams_Integration_Setting__mdt s = getActiveSetting();
    return (s != null && s.Is_Active__c) ? s.Webhook_URL__c : null;
  }
}
