# Session: Out-of-the-Box (OOTB) Canned Reports & Executive Dashboards

**Date:** 2026-11-14  
**Orgs:** `fleetforce-dev-13` (`customization-power-6735`, `00DWm000002fyrtMAA`), `fleetforce-dev-12` (`dream-speed-5521`, `00DWm000002fyjpMAA`)  
**Namespace:** `fleetforce`  
**Status:** Deployed & Verified

---

## 1. Summary of Delivered Work

Delivered a full suite of packageable, enterprise-grade Salesforce analytics comprising:

- **7 Custom Report Types (`force-app/main/default/reportTypes/`)**
- **5 Packaged Report Folders (`force-app/main/default/reports/`)**
- **16 Packaged Canned Reports** with custom summary formulas, filters, and chart visualizers
- **3 Canned Lightning Dashboards (`force-app/main/default/dashboards/FleetForce_Dashboards/`)** using `<dashboardType>LoggedInUser</dashboardType>` for multi-tenant ISV compatibility.

---

## 2. Inventory of Delivered Components

### Schema Adjustments

- Enabled `<enableReports>true</enableReports>` on:
  - `Service_Ticket__c`
  - `Fuel_Log__c`
  - `Citation__c`
  - `Reservation__c`
  - `Carbon_Log__c`
  - `Telemetry_Violation__c`
  - `Authorized_Driver__c`
  - `Driver_Qualification__c`
  - `Fuel_Card__c`

### Custom Report Types (CRTs)

1. `Fleet_Assets`: Core inventory, financial valuation, and country/branch scoping.
2. `Fleet_Assets_with_Service_Tickets`: Assets outer-joined with maintenance tickets, parts/labor breakdowns, vendors, and downtime.
3. `Fleet_Assets_with_Allocations`: Assets with motorpool checkout allocations, distance driven, and return branches.
4. `Fleet_Assets_with_Fuel_Logs`: Assets with fuel card transactions, energy consumption, and fuel economy.
5. `Fleet_Assets_with_Carbon_Logs`: Assets with Scope 1 direct fuel and Scope 2 EV charging greenhouse emissions.
6. `Fleet_Assets_with_Citations`: Assets with traffic citations, fines, and driver violations.
7. `Fleet_Assets_with_Documents`: Assets with regulatory permits, registrations, and expiration timelines.
8. `Fleet_Assets_with_Telemetry_Violations`: Assets with safety exceptions (harsh braking, speeding).

### Canned Reports (16 Reports across 5 Folders)

- **Fleet Financial & TCO (`FleetForce_Financial_Reports`):**
  - `Fleet_TCO_by_Country_and_Hub`: Net TCO (`Purchase Price + Maintenance - Residual Value`).
  - `Fleet_Cost_Per_Distance_by_Class`: Maintenance cost per odometer distance unit.
  - `Fleet_Capital_Lifecycle_Retention`: Value retention % by model year and ownership structure.
  - `High_Maintenance_Asset_Watchlist`: Ranked high-mileage/costly vehicles.
- **Fleet Maintenance & Service (`FleetForce_Maintenance_Reports`):**
  - `Maintenance_Spend_PM_vs_Corrective`: Scheduled PM vs breakdown spend ratio.
  - `Maintenance_Spend_by_Vendor`: Billed vendor rankings and average repair costs.
  - `Active_Work_Orders_and_Downtime`: In-shop shop-floor queue by priority.
- **Fleet Utilization & Motorpool (`FleetForce_Utilization_Reports`):**
  - `Fleet_Utilization_by_Branch`: Distance logged per branch.
  - `Trip_Distance_by_Vehicle_Class`: Average trip distance by class.
  - `Cross_Branch_One_Way_Allocations`: Inter-branch relocations.
- **Fleet Sustainability & Energy (`FleetForce_Sustainability_Reports`):**
  - `Fuel_Spend_and_Consumption_by_Class`: Energy spend and volume by class.
  - `Energy_Transition_Mix_ICE_vs_EV`: Propulsion mix (Electric, Hybrid, Diesel, Petrol).
  - `Carbon_Emissions_Scope_1_and_2`: Metric Tonnes CO2e by country and scope.
- **Fleet Safety, Risk & Compliance (`FleetForce_Compliance_Reports`):**
  - `Citations_and_Fines_by_Driver`: Traffic violations and fines.
  - `Asset_Document_Expiration_Radar`: Expired vs expiring &lt;30d vs valid documents.
  - `Telematics_Safety_Violations`: Driver safety exceptions by severity tier.

### Dashboards (`FleetForce_Dashboards`)

1. **Fleet Executive: Financial & Maintenance Operations** (`Fleet_Executive_Overview`)
2. **Fleet Operations & Sustainability** (`Fleet_Operations_Sustainability`)
3. **Fleet Safety, Risk & Compliance** (`Fleet_Risk_Compliance`)

---

## 3. Design Decisions & Packaging Considerations

- **Packaging Portability (`LoggedInUser`):** Dashboards use `<dashboardType>LoggedInUser</dashboardType>`, ensuring no hardcoded user IDs are embedded in package metadata.
- **Source-Format Relational Joins:** Custom Report Type child tables require the child relationship name in metadata format (e.g., `Fleet_Asset__c.Service_Tickets__r`).
- **Summary Formula Syntax:** Child fields referenced in report custom summary formulas use `ChildObject__c.Field__c:SUM` rather than relationship paths.
