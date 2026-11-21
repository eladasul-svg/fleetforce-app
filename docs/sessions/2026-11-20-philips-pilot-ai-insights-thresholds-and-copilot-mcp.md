# Session Log — 2026-11-20: Philips Fleet Pilot — AI Strategic Insights, Threshold Engine & Copilot/MCP Integration

**Parent Session:** [`docs/sessions/2026-11-19-philips-financial-reconciliation-architecture.md`](file:///Users/elad.asulin/fleetforce-app/docs/sessions/2026-11-19-philips-financial-reconciliation-architecture.md)  
**Target Org:** `fleetforce-dev-13` (`00DWm000002fyrtMAA`, `test-fubqn3lghmcn@example.com`)  
**Context:** Philips European Fleet Pilot — Stage 2: Exception Thresholds, Executive AI Insights & Enterprise Copilot/MCP Architecture

---

## 1. Executive Summary & Session Objectives

Following the successful deployment of **Stage 1** (Financial Reconciliation data model, Apex audit engine, executive LWC console, and native filtered report charts), Stage 2 focuses on moving from _passive reporting_ to _active governance and intelligence_.

### Core Problem Statement

1. **LWC vs. Reports Specialization:** Standard reports are excellent at aggregating historical numbers (e.g., total spend by cost center). However, they cannot execute workflows (one-click disputes, credit reconciliations) or surface dynamic qualitative guidance.
2. **Configurable Thresholds:** Fleet managers need to set custom business rules (e.g., "Alert me if unallocated spend exceeds 10% on any invoice", "Flag maintenance lines over €6,000 without a PO") without developer intervention or code deployments.
3. **Conversational AI via Enterprise Copilot:** Philips already uses Microsoft 365 Copilot across its corporate desktop fleet. By connecting the **Salesforce Model Context Protocol (MCP)** server to Copilot, managers can query FleetForce in plain language using their existing enterprise interface.
4. **The "Push" Alerting Gap in Copilot:** Copilot is strictly _pull-based_ (reactive to user queries). When an invoice breaches an audit threshold, FleetForce must proactively _push_ structured alerts into the fleet team's Microsoft Teams channels and Salesforce notifications with deep links to the record and suggested Copilot investigation prompts.
5. **AI External Microservice / Enterprise Token Routing:** Enterprise customers require using their own cloud tokens (Azure OpenAI, Gemini, Anthropic) rather than paying exorbitant native Salesforce Einstein seat licenses.

---

## 2. Architecture: Configurable Threshold & Audit Rule Engine

### A. Data Model: `Fleet_Audit_Threshold__c` (or `_mdt`)

To allow business users to define and tune reconciliation rules:

| Field API Name           | Type           | Description / Example                                                                                                   |
| :----------------------- | :------------- | :---------------------------------------------------------------------------------------------------------------------- |
| `Rule_Name__c`           | Text (80)      | "Unallocated Cost Center Spend Warning", "Excessive Repair Limit"                                                       |
| `Metric_Type__c`         | Picklist       | `Unallocated_Spend_Pct`, `Single_Line_Max_Gross`, `Recharge_Spend_Pct`, `Missing_Credit_Count`, `Mileage_Deviation_Pct` |
| `Operator__c`            | Picklist       | `Greater_Than`, `Greater_Or_Equal`, `Less_Than`, `Equals`                                                               |
| `Threshold_Value__c`     | Decimal (16,2) | `10.0` (for 10%), `6000.00` (for €6k), `300.00` (for €300 repair limit)                                                 |
| `Severity__c`            | Picklist       | `Info`, `Warning`, `Critical_Blocker`                                                                                   |
| `Is_Active__c`           | Checkbox       | `true`                                                                                                                  |
| `Notification_Target__c` | Picklist       | `Chatter`, `Teams_Webhook`, `Platform_Event`, `Email_Digest`                                                            |

### B. Audit Service Integration Flow

When `FleetInvoiceAuditService` runs (on invoice upload, nightly reconciliation batch, or button trigger):

1. Loads active `Fleet_Audit_Threshold__c` records.
2. Evaluates computed invoice metrics (e.g., `Unallocated_Spend_Pct = 7.35%`).
3. If `Unallocated_Spend_Pct > 5.0%`:
   - Flags invoice `Audit_Review_Status__c = 'Audit_Review_Required'`.
   - Generates an `Audit_Alert__c` child record with the rule violation details.
   - Publishes `Fleet_Audit_Event__e` (Platform Event) for downstream push notifications.

---

## 3. Architecture: Bridging the Copilot "Push" Gap via Teams Adaptive Cards

```
┌────────────────────────────────────────────────────────────────────────┐
│                        FLEETFORCE (SALESFORCE)                         │
│                                                                        │
│  [Vendor Invoice Ingestion] ──> [FleetInvoiceAuditService]              │
│                                           │                            │
│                                           ▼                            │
│                             Evaluates Active Thresholds                │
│                                           │                            │
│                                    (Threshold Breached!)               │
│                                           ▼                            │
│                             Fires: [Fleet_Audit_Event__e]              │
└───────────────────────────────────────────┬────────────────────────────┘
                                            │
                                            ▼
┌────────────────────────────────────────────────────────────────────────┐
│               PUSH: POWER AUTOMATE / WEBHOOK INTEGRATION               │
│                                                                        │
│   Listens to Platform Event / Apex Callout                             │
│   Formats Adaptive Card with:                                          │
│     • Billed Gross: £284,039.86                                        │
│     • Breach: Unallocated Spend is 7.4% (Threshold: 5.0%)              │
│     • Button 1: [Open in Salesforce FleetOps]                          │
│     • Button 2: [Investigate with Copilot]                             │
└───────────────────────────────────────────┬────────────────────────────┘
                                            │
                                            ▼
┌────────────────────────────────────────────────────────────────────────┐
│            MICROSOFT TEAMS FLEET CHANNEL & M365 COPILOT               │
│                                                                        │
│  Manager sees Adaptive Card in Teams ──> Clicks "Investigate"           │
│                                                                        │
│  Copilot executes SOQL via [Salesforce MCP Server]:                    │
│    "Show me which vehicles account for the 7.4% unallocated spend"     │
│                                                                        │
│  Copilot returns:                                                      │
│    "Found 23 vehicles without active contracts. The top 3 are..."      │
└────────────────────────────────────────────────────────────────────────┘
```

### Key Elements of the Push-Pull Synergy:

1. **Push (Proactive):** The manager doesn't need to manually check Salesforce or remember to prompt Copilot. The system proactively alerts them in their primary workspace (Teams).
2. **Pull (Deep Investigation):** The manager uses Copilot powered by the **Salesforce MCP** to drill down into the exceptions without logging into Salesforce report builders.

---

## 4. Architecture: Salesforce MCP + Enterprise Copilot Data Contracts

The Salesforce Model Context Protocol (MCP) server provides a secure, token-governed bridge between Microsoft Copilot and FleetForce:

### Supported MCP Capabilities:

1. **`execute_soql`**:
   - Allows Copilot to run parameterized read queries against `Fleet_Invoice__c`, `Fleet_Invoice_Line__c`, `Fleet_Asset__c`, `Cost_Center__c`.
   - Constrained by the fleet manager's Salesforce OAuth permissions and FLD-level security.
2. **`describe_sobject`**:
   - Enables Copilot to dynamically discover object relationships, picklist values, and audit statuses.
3. **Predefined Semantic Tools (Custom MCP Prompts):**
   - `get_invoice_audit_summary(invoiceId)`: Returns structured JSON with clean vs. flagged lines and top cost center breakdowns.
   - `get_excess_mileage_exposure(assetId)`: Computes contract pace deviation and projected end-of-contract penalties.

---

## 5. Architecture: External AI Microservice & Enterprise Token Proxy

To allow enterprise customers (like Philips) to use their own corporate tokens (Azure OpenAI, Gemini Enterprise, or Claude):

1. **Named Credential in Salesforce:**
   - Endpoint: `https://ai-gateway.customer-domain.com/v1/fleet/reconciliation-summary`
   - Authentication: OAuth 2.0 / Client Credentials with mutual TLS.
2. **Lightweight Proxy / Serverless Gateway (Cloud Run / AWS Lambda / Azure Functions):**
   - Receives sanitized invoice summary payload from Salesforce Apex.
   - Injects the enterprise API key / system prompt.
   - Calls the LLM model endpoint.
   - Returns structured JSON insights (executive summary, cost center anomalies, risk recommendations).
3. **Zero Native Salesforce Einstein Seat Cost:**
   - Salesforce acts as the orchestrator and database.
   - Enterprise AI billing runs entirely under the client's existing enterprise agreement.

---

## 6. Action Plan & Next Milestones

1. **Milestone 1 — Data Model for Thresholds:** (Completed)
   - Create `Fleet_Audit_Threshold__c` custom object with fields for metric type, operator, value, severity, and active status.
   - Create pre-seeded audit thresholds for Philips UK (5% unallocated tolerance, €6k repair line cap, €300 EoC allowance, 3% recharge surge).
2. **Milestone 2 — Apex Threshold Evaluator:** (Completed)
   - Extend `FleetInvoiceAuditService.cls` to evaluate invoice lines and totals against active `Fleet_Audit_Threshold__c` records.
   - Surface active threshold violations dynamically on the `fleetInvoiceAuditSummary` LWC.
   - Persist violation records to `Audit_Alert__c` and fire `Fleet_Audit_Event__e` platform events.
3. **Milestone 3 — Teams Webhook / Alerting Simulator:**
   - Build an outbound notification dispatch service generating adaptive cards for breached thresholds.
4. **Milestone 4 — Salesforce MCP Query Catalog:**
   - Document the curated SOQL templates and tool definitions for Microsoft Copilot integration.

---

## 7. Implementation Log — Option A: Configurable Threshold Engine

### A. Delivered Metadata Components

1. **`Fleet_Audit_Threshold__c` (Custom Object & Tab):**
   - Fields: `Rule_Name__c`, `Metric_Type__c`, `Operator__c`, `Threshold_Value__c`, `Severity__c`, `Is_Active__c`, `Notification_Target__c`, `Description__c`.
   - Pre-seeded 4 active enterprise governance rules:
     - _Unallocated Spend Warning_ (> 5.0%, Critical Blocker, Teams Webhook)
     - _Single Line High-Value Cap_ (>= £5,000, Warning, Chatter)
     - _Missing EoC Repair Credit Allowance_ (> 0 lines, Critical Blocker, Platform Event)
     - _Operational Recharge Surge_ (> 3.0%, Warning, Email Digest)
2. **`Audit_Alert__c` (Custom Object):**
   - Child of `Fleet_Invoice__c` capturing real-time threshold breaches with `Actual_Value__c`, `Threshold_Value__c`, `Breach_Amount__c`, `Severity__c`, `Status__c`, and `Message__c`.
3. **`Fleet_Audit_Event__e` (Platform Event):**
   - High-volume platform event published upon threshold breach for Power Automate and Teams adaptive card triggers.
4. **`Fleet_Invoice__c.Audit_Review_Status__c` Picklist Value:**
   - Added `Audit_Review_Required` for invoices triggering `Critical_Blocker` threshold violations.
5. **Permissions & App Navigation:**
   - Updated `FleetforceFinancialAdmin` Permission Set and `FleetOps` App Navigation.

### B. Apex Reconciliation Engine Enhancements (`FleetInvoiceAuditService.cls`)

- Dynamically loads and applies active `Fleet_Audit_Threshold__c` rules during invoice auditing.
- Computes unallocated spend % vs. limit, peak single line values, recharge spend %, and missing credit allowances.
- Automatically generates persistent `Audit_Alert__c` records and publishes `Fleet_Audit_Event__e` events.
- Transitions invoice `Audit_Review_Status__c` to `Audit_Review_Required` when critical limits are breached.
- Full unit test coverage in `FleetInvoiceAuditServiceTest.cls` (100% pass rate).

### C. LWC Console UI Enhancements (`fleetInvoiceAuditSummary`)

- **Executive Threshold Governance Alert Banner:** Prominently flags critical blocker and warning breaches above KPIs with severity styling and target vs. actual metric chips.
- **Dedicated Tab 3 ("Audit Threshold Governance"):** Displays an enterprise audit matrix of all configured rules, limits, actual values, and real-time `PASS` / `BREACHED` statuses.

---

## 8. Implementation Log — Calm Executive Console & Dynamic Task Triage

**Blueprint Reference:** [`docs/plans/calm-executive-reconciliation-console.md`](file:///Users/elad.asulin/fleetforce-app/docs/plans/calm-executive-reconciliation-console.md)

### A. Problem Addressed

The initial threshold engine UI stacked full-width warning boxes (>280px tall) that pushed core financial KPIs below the fold, required heavy scrolling, and lacked an interactive way for a solo fleet manager to delegate and track investigation items.

### B. Solution Delivered

1. **Calm, Zero-Scroll Executive Viewport:**
   - Replaced massive warning boxes with a sleek, compact 36px inline alert bar: `⚠️ Governance Alert: 2 rules breached (1 critical, 1 warning). Resolution required before payment release. [View Rules & Targets ↗]`.
   - Clicking the pill switches directly to the **Audit Governance** tab without any vertical scrolling.
   - All 4 core KPI cards remain cleanly visible above the fold on standard desktop displays.

2. **Native Report Navigation (`↗`):**
   - Added subtle `utility:new_window` arrow icons to each KPI card header:
     - _Total Billed Gross_ ➔ Opens `Invoice_Spend_by_Category` report.
     - _Reconciled Clean_ ➔ Opens `Invoice_Reconciliation_Status` report.
     - _Unallocated Spend_ ➔ Opens `Invoice_Spend_by_Cost_Center` report.
     - _Recharges & Fines_ ➔ Opens `Invoice_Recharges_and_Fines` report.
   - Dynamic report ID lookup in Apex ensures environment portability.

3. **Dynamic "Inbox Zero" Queue-Shifting Workflow:**
   - **Schema Additions:** Added `Follow_Up_Status__c` (`None`, `Task_Assigned`, `In_Review`, `Resolved`) and `Active_Task_Id__c` to `Fleet_Invoice_Line__c`.
   - **Tab 1: "Needs Action" (`pendingQueueCount`):** Shows unresolved exception lines. Clicking `[+ Task]` opens a pre-populated delegation modal (suggested subject, 3-day due date, priority, instructions).
   - **Tab 2: "In Progress Tasks" (`delegatedQueueCount`):** When a task is assigned, the line immediately vanishes from "Needs Action" and appears in "In Progress Tasks". Displays Task Subject (deep-linked to standard Salesforce Task), Assignee, Due Date, Priority chip, and Status.
   - **Native Activity Timeline Synergy:** Created standard `Task` records (`WhatId = lineId`) automatically populate the native Salesforce Activity Timeline on the right pane.
   - **One-Click Resolution:** Clicking `[Resolve]` completes the Task, marks the line as `Resolved` / `Clean`, and removes it from open queues.

4. **Verification & Testing:**
   - `FleetInvoiceAuditServiceTest.cls` updated with `testTaskDelegationWorkflow`: 100% pass rate.
   - Verified live on Philips Bill `#731513513`: Line `INV-LINE-000425` successfully delegated to a standard Task, decremented pending count from 100 to 99, and incremented delegated queue to 1.

---

## 9. Implementation Log — Outbound Teams Push & Adaptive Cards (Milestone 3)

### A. Problem Addressed

While enterprise conversational AI (Microsoft 365 Copilot) is exceptionally powerful for interactive querying via the Salesforce MCP server, it is inherently **pull-based** (reactive to user queries). A fleet manager busy in meetings cannot know that a £284k monthly vendor bill has arrived with £38k unallocated spend or £40k in unexpected driver recharges unless the system proactively **pushes** an interactive notification into their primary workspace (Microsoft Teams).

### B. Solution Delivered

1. **Configurable Enterprise Teams Integration Schema:**
   - **`Teams_Integration_Setting__mdt`:** Custom metadata type storing `Webhook_URL__c`, `Is_Active__c`, `Channel_Name__c`, and `Include_Copilot_Action__c`. Allows administrators to toggle channels and Copilot actions declaratively.
   - **`Microsoft_Teams_Webhook`:** Remote Site Setting enabling secure outbound HTTP callouts to `*.webhook.office.com`.

2. **Adaptive Card v1.4 Payload Generator (`FleetTeamsNotificationService.cls`):**
   - Implemented standard Microsoft Teams Adaptive Card v1.4 structure with high-contrast attention/warning headers.
   - Built a dynamic **FactSet** detailing: Billing Document Number, Rule Name, Severity (`Critical Blocker` vs `Warning`), Metric Type, Configured Limit, Actual Computed Metric, and Total Variance Amount (£).
   - Injected the contextual **Audit Finding** narrative.
   - Generated two native interactive actions:
     - **Button 1 (`Open in Salesforce FleetOps ↗`):** Direct deep link into the `Fleet_Invoice__c` Lightning Record Page.
     - **Button 2 (`Investigate with Copilot ↗`):** Deep link into Microsoft 365 Copilot (`https://m365.cloud.microsoft/chat?prompt=...`) pre-populated with a targeted natural language investigation prompt (e.g., _"Investigate reconciliation breach: Operational Recharge Surge on vendor invoice doc #731513513. Show which specific vehicles and cost centers account for this variance."_).

3. **Asynchronous Platform Event Trigger & Queueable Dispatcher:**
   - **`FleetAuditEventTrigger.trigger`:** Listens to `Fleet_Audit_Event__e (after insert)` platform events fired by `FleetInvoiceAuditService`.
   - **`FleetTeamsNotificationQueueable.cls`:** Enqueues an asynchronous `Queueable` job implementing `Database.AllowsCallouts` to dispatch Teams webhooks without blocking synchronous database transactions or hitting trigger callout limits.

4. **Testing & Live Verification:**
   - **`FleetTeamsNotificationServiceTest.cls`:** Comprehensive unit tests with `HttpCalloutMock` validating JSON schema generation, mock HTTP 200 delivery, preview extraction, queueable execution, and platform event trigger propagation. 100% pass rate (11/11 tests passing across the audit suite).
   - **Live Validation on Philips UK Bill `#731513513`:** Verified generation of live v1.4 Adaptive Card payload with exact currency format (£40,830.55), breach metrics, and functional Salesforce and Copilot deep links.

---

## 10. Implementation Log — Salesforce MCP Server & Enterprise Copilot Data Contracts (Option 2)

### A. Problem Addressed

When a fleet manager receives an alert in Microsoft Teams and clicks **"Investigate with Copilot ↗"**, Microsoft 365 Copilot requires a standardized interface to query FleetForce data and execute follow-up actions without writing custom one-off integrations. By leveraging the **Model Context Protocol (MCP)**, Copilot can call structured tools to inspect reconciliation exceptions, aggregate cost center variance, delegate follow-up tasks, and resolve lines.

### B. Delivered Architecture & Components

1. **Enterprise Apex REST API (`FleetReconciliationRestController.cls`):**
   - Base endpoint: `/services/apexrest/fleetforce/fleet/v1/reconciliation/*`
   - **`GET /summary`:** Returns high-level financials (£ billed gross, net, VAT), match rate %, unallocated spend %, recharge spend %, and active threshold breaches.
   - **`GET /exceptions`:** Filters exception lines dynamically (`All`, `Unallocated`, `Unregistered_Vehicles`, `Unmapped_Driver`, `Recharges_and_Fines`, `High_Value_Lines`, `Missing_EoC_Credits`, `Disputed`).
   - **`GET /cost-centers`:** Returns spend allocation across cost centers and business units.
   - **`POST /delegate`:** Creates a standard Salesforce `Task` and links it to the line, moving it into the _In Progress_ queue.
   - **`POST /resolve`:** Closes the open `Task` and transitions the line to _Resolved_ / _Clean_.
   - **Test Suite:** `FleetReconciliationRestControllerTest.cls` deployed with 100% pass rate (17/17 tests passing across the entire financial test suite).

2. **Official Model Context Protocol (MCP) Server (`services/fleet-mcp-server/`):**
   - Implemented using the official `@modelcontextprotocol/sdk` on Node.js 22.
   - Connects to Salesforce using active CLI session (`sf org display` + `sf org auth show-access-token`) or environment credentials (`SALESFORCE_INSTANCE_URL`, `SALESFORCE_ACCESS_TOKEN`).
   - Handles Salesforce namespacing (`fleetforce/`) dynamically.
   - **6 Standard MCP Tools:**
     - `get_invoice_reconciliation_summary`
     - `query_reconciliation_exceptions`
     - `get_cost_center_variance`
     - `delegate_line_task`
     - `resolve_line_exception`
     - `execute_fleet_soql`
   - **2 Pre-Packaged MCP Prompts:**
     - `investigate_invoice_breach`: Orchestrates a 4-step Copilot root-cause drill-down.
     - `draft_vendor_dispute_notice`: Structures a commercial vendor dispute letter backed by specific unverified lines.

3. **Microsoft 365 Copilot Integration Package (`copilot/`):**
   - **`copilot/openapi.yaml`:** OpenAPI 3.0 specification for Microsoft Copilot Studio and Power Automate custom connectors.
   - **`copilot/declarative-agent.json`:** Declarative Agent manifest defining agent instructions, conversation starters, and action mappings.
   - **`services/fleet-mcp-server/README.md`:** Complete enterprise deployment and connection guide for Copilot, Claude Desktop, and Antigravity.

4. **Live Verification & E2E Testing (`test_mcp_client.js`):**
   - Executed end-to-end client against live Philips UK Bill `#731513513`.
   - Verified that `get_invoice_reconciliation_summary` returned: Total Billed Gross £284,039.86, Clean Match Rate: 67.1% (394 of 587 lines), Unallocated Spend: £38,119.15, Recharge Spend: £40,830.55, Active Breaches: 2.
   - Verified that `query_reconciliation_exceptions` returned exact vehicle lines (e.g., `INV-LINE-000423`, Plate: `KB23HKA`, Driver: `Field Driver 7306751`, Gross: `£3,625.97`, Recharge Type: `Body Repairs Damage`).

---

## 11. Implementation Log — The 3 Ingestion Paths (MVP), Multi-Currency Module & Vendor Dispute Generator

### A. The 3 Ingestion Patterns Delivered

To give Lital total flexibility across enterprise ingestion scenarios:

1. **Pattern C: Native Salesforce LWC Dropzone (`fleetInvoiceAuditSummary`)**
   - Added **`[Upload Bill]`** button in the LWC header.
   - Interactive modal supporting CSV drag-and-drop or direct text paste, document number entry, and currency selection (`GBP`, `EUR`, `USD`).
   - Powered by `FleetInvoiceUploadService.importInvoiceCsv`. Bulk parses lines, matches vehicles by plate, drivers by payroll ID, cost centers by code, inserts lines, and immediately executes the threshold audit engine.

2. **Pattern B: Copilot File Ingestion Tool via MCP Server (`import_vendor_invoice`)**
   - Added `import_vendor_invoice` tool to the Model Context Protocol server (`services/fleet-mcp-server/index.js`) and REST controller (`POST /services/apexrest/fleetforce/fleet/v1/reconciliation/import`).
   - Copilot can accept vendor CSV data or structured rows directly in chat and trigger background ingestion and audit.

3. **Pattern A: Zero-Touch Inbound Webhook Listener (`services/ingestion/inbound_invoice_listener.py`)**
   - Automated enterprise listener script simulating an unattended email attachment / SharePoint drop arriving from Ayvens.
   - Ingests the file, creates the invoice, links assets/drivers/cost centers, evaluates thresholds, and fires Microsoft Teams Adaptive Card alerts without human intervention.

### B. High-Value Capabilities Delivered

1. **Multi-Currency Engine Integration (`Invoice_Currency__c`):**
   - Custom field added to `Fleet_Invoice__c` (`GBP (£)`, `EUR (€)`, `USD ($)`).
   - Dynamic currency symbol resolution across Apex summary DTOs, LWC KPI formatting (`currency-code={currencyCode}`), Teams Adaptive Cards, and Dispute Memos.
2. **Commercial Vendor Dispute Generator (`generateDisputeMemo`):**
   - Added **`[Dispute Notice]`** button on the LWC and `get_dispute_memo` tool in the MCP server.
   - Formats a formal commercial audit dispute notice to Ayvens itemizing unallocated vehicle lines, unmapped HR drivers, missing refurbishment credits, and contested variance totals with copy-to-clipboard and `.md` download support.
3. **Verification & Testing:**
   - 100% pass rate across 23 Apex unit tests (`FleetInvoiceUploadServiceTest`, `FleetReconciliationRestControllerTest`, `FleetInvoiceAuditServiceTest`, `FleetTeamsNotificationServiceTest`).
   - End-to-end verified via `test_mcp_client.js` and `inbound_invoice_listener.py`.
