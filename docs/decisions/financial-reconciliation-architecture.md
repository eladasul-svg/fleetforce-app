# FleetForce Financial Reconciliation & Billing Architecture

**Date:** Nov 19, 2026 · @Elad Asulin  
**Context:** Periodic Ingestion, Vendor Audit, and ERP Cost Attribution (Philips European Fleet Pilot)

## Summary of Decisions

1. **Standard `Invoice` vs. Custom `Fleet_Invoice__c`**:
   - Standard Salesforce `Invoice` and `InvoiceLine` objects were evaluated. Testing confirmed that standard `Invoice` has `createable: false` via standard API / Apex DML in core developer and enterprise orgs (`DML operation Insert not allowed on Invoice`) unless managed via Salesforce Billing / Revenue Cloud order-posting engines.
   - **Decision:** Establish `Fleet_Invoice__c` and `Fleet_Invoice_Line__c` as the official Fleetforce managed objects for third-party leasing vendor statements and recharges.
   - **Advantage:** Grants full read/write API access, native Master-Detail roll-ups (`Total_Gross__c`, `Total_Net__c`, `Total_VAT__c`), zero external package dependencies for AppExchange subscribers, and direct audit flag support.

2. **Corporate ERP Hierarchy (`Cost_Center__c`)**:
   - To support enterprise customers with complex SAP / Workday cost attribution (such as Philips' 188 cost centers across `Ashcombe Systems`, `Care`, and `Consumer`), a dedicated `Cost_Center__c` custom object was introduced.
   - Both `Fleet_Asset__c` and `Fleet_Invoice_Line__c` maintain direct Lookups to `Cost_Center__c`, eliminating unallocated overhead leakage.

3. **End-of-Contract (EoC) Mileage Exposure Engine**:
   - `Fleet_Asset__c` is enhanced with predictive fields (`EoC_Projected_Mileage__c`, `Contract_Mileage_Deviation_Pct__c`, `EoC_Penalty_Exposure__c`).
   - Identifies vehicles exceeding contracted bands by >20% early to enable mid-term lease rescheduling before lease-end penalty recharges are incurred.

4. **Audit Exception Automation**:
   - `Fleet_Invoice_Line__c` incorporates automated audit fields (`Audit_Status__c`, `Audit_Notes__c`, `Credit_Allowance_Applied__c`) to capture:
     - Charges exceeding the €6,000 threshold for executive sign-off.
     - Contractual repair credits (such as Philips' €300 end-of-contract allowance) omitted by the leasing vendor.
     - Fines processing fees to trigger automatic driver citation redirection.
