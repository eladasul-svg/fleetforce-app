# Stage 4: AI Strategic Insights Engine & Executive Console

**Date:** November 14, 2026  
**Branch:** `feature/routing-module`  
**Target Scratch Org:** `fleetforce-dev-13`  
**Status:** Complete & Deployed

---

## 1. Context & Objectives

Following Stages 1 (Admin Modularization), 2 (CMDT Control Panel), and 3 (Telematics Hub), Stage 4 delivers an **AI Strategic Insights Engine** directly inside the FleetForce Admin App (`FleetForce_Admin.app`).

### Global Fleet Manager Challenge

A global fleet manager overseeing 10,000+ vehicles across multiple operating branches and countries cannot sift through thousands of individual vehicle records, odometer readings, and service work orders every day. Instead, they require strategic, cross-depot anomaly detection that highlights systemic risks before they cause financial loss or operational disruption:

- **Warranty Lapse Prevention:** Identifying depots or branches where vehicles are systematically late to scheduled preventive maintenance, which threatens to void OEM powertrain warranties.
- **Electric Vehicle Transition Hotspots:** Surfacing high-mileage, localized urban routes where internal combustion engine (ICE) vehicles have excessive fuel burn and carbon emissions, making them prime candidates for EV replacement.
- **Telematics Signal Loss & Blind Spots:** Pinpointing branches or vehicle cohorts with deteriorating telemetry stream health (missing pings, stale GPS data), creating blind spots in compliance and duty-of-care tracking.

---

## 2. Technical Architecture & Components Created

### A. Apex Backend Controller (`FleetAiInsightsController.cls`)

- **`getAiConfig()`:** Inspects `Fleet_Display_Setting__c.Org_Default` to retrieve active AI settings, configured foundational models (Google Gemini, Anthropic Claude, OpenAI), and API key readiness without exposing raw keys.
- **`getPrebuiltInsights()`:** Performs cross-object aggregations across `Fleet_Asset__c`, `Fleet_Branch__c`, `Carbon_Log__c`, `Service_Ticket__c`, and `Data_Stream__c`:
  - **Warranty Lapse Risk:** Detects assets where overdue maintenance exceeds warranty grace periods and highlights the offending branches.
  - **EV Transition Candidates:** Identifies high-emission routes from `Carbon_Log__c` and calculates projected fuel/carbon savings.
  - **Telematics Signal Degradation:** Aggregates streams marked `Stale` or `Missing` and flags branch hardware issues.
- **`queryStrategicInsight(prompt)`:** Natural language query processor that parses executive questions and returns structured, actionable responses with root causes, quantified financial impact, and affected branches.
- **`executeStrategicAction(actionKey, insightId)`:** Allows one-click execution of remediations, such as automatically generating priority `Service_Ticket__c` records (with `Status__c = 'Draft'` and `Category__c = 'Preventive Maintenance'`), dispatching branch manager SLA notices, or triggering telematics re-synchronization.

### B. Lightning Web Component (`fleetAiInsights`)

- **AI Engine Status Banner:** Displays active model provider, BYOK status, and quick link to General Settings for key management.
- **Executive Natural Language Bar:** Interactive prompt box with one-click quick inquiry chips:
  - _"Which branches have warranty risk?"_
  - _"Show EV transition candidates"_
  - _"Detect telematics signal loss"_
- **Live Analytical Query Card:** Dynamically displays query results with root causes, financial/warranty exposure metrics, and impacted operational branches.
- **Pre-Built Anomaly Stream:** Executive feed of current fleet anomalies with severity badges (`Critical`, `Warning`, `Opportunity`), impacted branch tags, and direct action triggers.
- **Remediation Action Handlers:** Confirms actions via toast notifications and triggers backend automated ticket creation or executive alerts.

### C. Application Navigation & Permissions

- **Custom Tab:** `Fleetforce_AI_Insights.tab-meta.xml` (Label: `AI Insights`, Motif: `Custom63: Chip`).
- **Flexipage:** `Fleetforce_AI_Insights.flexipage-meta.xml` (Standard App Page hosting `c-fleet-ai-insights`).
- **Admin App Integration:** Added `Fleetforce_AI_Insights` as a top-level tab in `FleetForce_Admin.app-meta.xml`.
- **Permission Set:** Granted tab visibility and Apex class access in `FleetforceAdmin.permissionset-meta.xml`.

---

## 3. Testing & Verification

1. **Apex Unit Tests (`FleetAiInsightsControllerTest.cls`):**
   - Verified `getAiConfig()`, `getPrebuiltInsights()`, `queryStrategicInsight()`, and `executeStrategicAction()`.
   - Verified ticket generation respects restricted picklists (`Category__c = 'Preventive Maintenance'`, `Status__c = 'Draft'`).
   - All 35 Apex tests across Stages 1–4 passed with 100% pass rate in `fleetforce-dev-13`.
2. **Jest Component Unit Tests (`fleetAiInsights.test.js`):**
   - Verified wire adapters for AI configuration and pre-built insights.
   - Tested natural language submission and dynamic result card rendering.
   - Tested action button dispatch.
   - All 17 Jest test suites (65 tests) passed.
3. **Anonymous Apex Verification:**
   - Ran live in `fleetforce-dev-13`, returning 3 pre-built strategic insights and executing sample warranty queries without exception.
