# Admin Console Refinements: Per-Setting Edit Lifecycle & AI Vault Separation

**Date:** November 15, 2026  
**Branch:** `feature/routing-module`  
**Target Scratch Org:** `fleetforce-dev-13`  
**Status:** Complete & Deployed

---

## 1. Summary of Changes

Based on executive review and UX feedback on `FleetForce_Admin.app`, we implemented key architectural and user experience refinements across **General Settings** and **AI Strategic Insights**:

### A. Independent Per-Setting Edit Lifecycle in General Settings

- Replaced the monolithic top-level "Modify General Settings" button that opened the entire page at once.
- Converted General Settings into 4 distinct, independently editable cards:
  1. **AI Foundation Models & BYOK Keys Vault** (Configure AI Keys button)
  2. **Digital Data Sanitization Protocol** (Modify Protocol button)
  3. **Maintenance & Work Order Automation** (Modify Automation button)
  4. **Telemetry Drift & Data Governance** (Modify Governance button)
- Each card maintains an independent 2-step Overview $\rightarrow$ Modify mode with its own dedicated Cancel and Save buttons, preventing accidental cross-field edits.

### B. AI Models & BYOK Vault Architecture

- **General Settings:** Acts as the centralized **AI Models & BYOK Keys Vault**. Admins configure and store API keys for Google Gemini, Anthropic Claude, and OpenAI with masked status badges (`Configured` / `Not Configured`).
- **AI Strategic Insights:** The insights console now features an **Active Strategic Engine Combobox** directly in the top status bar. Users can switch between configured foundational models on the fly (`setActiveAiModel`), while a `"Configure API Keys"` button links back to the General Settings vault for credential updates.

### C. Added High-Value Enterprise Fleet Settings

Added 4 new custom fields to `Fleet_Display_Setting__c`:

- `Auto_Create_DTC_Tickets__c`: Automatically creates Draft Service Tickets when critical Diagnostic Trouble Codes (DTCs) are ingested from telematics.
- `Maintenance_Grace_Days__c`: Days buffer past maintenance due date before flagging warranty voidance risk (default: 14 days).
- `Odometer_Drift_Threshold__c`: Allowable percentage variance between telematics and manual driver odometer readings before triggering an audit alert (default: 5%).
- `Telemetry_Retention_Days__c`: Retention limit for raw high-frequency GPS breadcrumbs in hot storage (default: 90 days).

---

## 2. Technical Components & Verification

1. **Schema & Security:**
   - 4 new fields on `Fleet_Display_Setting__c` deployed to `fleetforce-dev-13`.
   - Granted full FLS permissions in `FleetforceAdmin.permissionset-meta.xml`.
2. **Apex Controllers:**
   - `FleetDisplaySettingsController.cls`: Updated `GeneralSettings` DTO, `getGeneralSettings()`, and `saveGeneralSettings(...)` to support all 4 setting domains.
   - `FleetAiInsightsController.cls`: Added `ModelOptionDTO`, populated `availableModels`, and created `setActiveAiModel(String provider)`.
3. **Lightning Web Components:**
   - `fleetGeneralSettings`: Rebuilt with section-scoped edit states (`isAiEditing`, `isPrivacyEditing`, etc.).
   - `fleetAiInsights`: Added model selector combobox with live switching.
4. **Automated Testing:**
   - **Apex Unit Tests:** 36/36 tests passed (100% pass rate).
   - **Jest Unit Tests:** 18/18 test suites passed (67/67 tests).
