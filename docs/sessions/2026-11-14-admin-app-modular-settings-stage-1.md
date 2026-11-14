# FleetForce Admin App Modular Transformation — Stage 1

**Date:** November 14, 2026  
**Milestone:** Stage 1: Modular Settings Architecture, Dedicated Navigation, and Regional / Brand UX  
**Branch:** `feature/routing-module`  
**Scratch Org:** `fleetforce-dev-13`

---

## 1. Context & Objectives

The FleetForce Admin App (`FleetForce_Admin.app`) previously hosted a single monolithic settings page combining display styles, regional parameters, country profiles, and naming rules. Following user guidance, Stage 1 decomposed the monolithic page into a modular, multi-tab enterprise admin experience with:

1. **Top-Level Navigation Tabs**:
   - `Fleetforce_General_Settings` (General & Feature Switches)
   - `Fleetforce_Brand_Theme` (Vehicle Icon Styles & Salesforce Theme Branding)
   - `Fleetforce_Regional_Settings` (Regional Defaults & Country Profiles)
   - `Fleetforce_Auto_Naming` (Record Auto-Naming Rules Workspace)
2. **2-Step Workflow for Regional Settings**:
   - Replacing direct-edit mode with a clean **Read-Only Overview** (summary KPI cards for Default Country, Time Zone, Currency, Distance Unit, Volume Unit, and Weight Unit) + a prominent **"Modify Regional Defaults"** action.
   - Dedicated **Edit Mode** with responsive input controls, "Save Regional Settings", and "Cancel".
3. **Decoupled Brand & Theme Experience**:
   - Radio tiles with real-time preview vehicle cards (`c-fleet-vehicle-image`) across all 5 styles (`silhouette`, `flat`, `classic`, `modern`, `futuristic`).
   - Custom theme loading spinner override guidance (`<shouldOverrideLoadingImage>true</shouldOverrideLoadingImage>`), brand palette swatches, and direct Setup deep links.
4. **General System Settings**:
   - Toggles and configuration for AI Strategic Insights Engine and Extended Vehicle Privacy Protocol (Privacy4Cars compliance standard).

---

## 2. Changes Delivered

### Apex & Data Model

- **`Fleet_Display_Setting__c` (Hierarchy Custom Setting)**:
  - Added custom fields: `Enable_AI_Insights__c` (Checkbox), `AI_Provider__c` (Text 50), `Enable_Extended_Privacy__c` (Checkbox).
- **`FleetDisplaySettingsController.cls`**:
  - Added `GeneralSettings` DTO and Option constructors.
  - Added AuraEnabled methods `@AuraEnabled(cacheable=true) public static GeneralSettings getGeneralSettings()` and `@AuraEnabled public static GeneralSettings saveGeneralSettings(...)` with FLS checks.
- **`FleetDisplaySettingsControllerTest.cls`**:
  - Added `generalSettingsAreRetrievedAndSaved()` test method. 100% pass rate (7/7 tests passed).

### Lightning Web Components

- **`c-fleet-general-settings`**:
  - Manages AI Strategic Insights engine activation, foundational model selection (Gemini 2.5 Flash, Gemini 2.5 Pro, Claude 3.5 Sonnet, GPT-4o), token policy, Privacy4Cars sanitization switch, and auto-naming navigation.
- **`c-fleet-brand-theme`**:
  - Visual selector for 5 vehicle icon styles with live multi-variant vehicle cards, theme loading override banner, color palette swatches, and direct Setup deep links.
- **`c-fleet-regional-settings`**:
  - Implements the 2-step Overview $\rightarrow$ Edit UX for org defaults, Multi-Currency indicator, and Country Profiles datatable.
- **`c-fleet-auto-naming-admin`**:
  - Promoted to a dedicated tab with real-time formula evaluation, field token inserter, and safety guards.

### Metadata & Navigation

- **Custom Tabs**:
  - `Fleetforce_General_Settings.tab-meta.xml` (`Custom67: Gears`)
  - `Fleetforce_Brand_Theme.tab-meta.xml` (`Custom38: Palette`)
  - `Fleetforce_Regional_Settings.tab-meta.xml` (`Custom31: Globe`)
  - `Fleetforce_Auto_Naming.tab-meta.xml` (`Custom83: Lightning`)
- **Flexipages**:
  - `Fleetforce_General_Settings.flexipage-meta.xml`
  - `Fleetforce_Brand_Theme.flexipage-meta.xml`
  - `Fleetforce_Regional_Settings.flexipage-meta.xml`
  - `Fleetforce_Auto_Naming.flexipage-meta.xml`
- **Application**:
  - Updated `FleetForce_Admin.app-meta.xml` navigation to include the 4 modular tabs.
- **Permission Sets**:
  - Updated `FleetforceAdmin.permissionset-meta.xml` with field permissions for new `Fleet_Display_Setting__c` fields and tab visibility for all 4 new tabs.

---

## 3. Verification & Test Results

- **Apex Tests**: 7/7 tests passing in `FleetDisplaySettingsControllerTest`, 6/6 tests passing in `AutoNamingServiceTest` (100% pass rate).
- **Jest Tests**: 14 test suites, 60/60 tests passing (`npm test`).
- **Scratch Org Deployment**: Deployed and verified in `fleetforce-dev-13`.
