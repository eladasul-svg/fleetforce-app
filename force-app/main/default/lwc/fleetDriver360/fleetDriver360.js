import { LightningElement, api, wire, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";

import getDriver360Data from "@salesforce/apex/FleetDriver360Controller.getDriver360Data";
import getAvailableVehicles from "@salesforce/apex/FleetDriver360Controller.getAvailableVehicles";
import toggleKeyAccess from "@salesforce/apex/FleetDriver360Controller.toggleKeyAccess";
import assignVehicle from "@salesforce/apex/FleetDriver360Controller.assignVehicle";
import quickLogTrip from "@salesforce/apex/FleetDriver360Controller.quickLogTrip";
import quickLogFuel from "@salesforce/apex/FleetDriver360Controller.quickLogFuel";
import quickReportCitation from "@salesforce/apex/FleetDriver360Controller.quickReportCitation";
import addDriverQualification from "@salesforce/apex/FleetDriver360Controller.addDriverQualification";

export default class FleetDriver360 extends NavigationMixin(LightningElement) {
  @api recordId;

  data;
  error;
  isLoading = true;
  wiredDriverResult;
  wiredVehiclesResult;

  @track vehicleOptions = [];

  // Modal display flags
  showAssignVehicleModal = false;
  showLogTripModal = false;
  showLogFuelModal = false;
  showReportCitationModal = false;
  showSkillModal = false;
  isSubmitting = false;
  isSavingSkill = false;

  // Add Skill form fields
  newSkillTitle = "";
  newSkillType = "Internal Skill";
  newSkillProficiency = "3 - Expert";
  newSkillValidUntil = "";
  newSkillCertId = "";
  newSkillAuthority = "";

  skillTypeOptions = [
    { label: "Internal Skill", value: "Internal Skill" },
    { label: "Certification", value: "Certification" },
    { label: "Access Badge", value: "Access Badge." },
    { label: "Language", value: "Language" }
  ];

  skillProficiencyOptions = [
    { label: "1 - Beginner", value: "1 - Beginner" },
    { label: "2 - Intermediate", value: "2 - Intermediate" },
    { label: "3 - Expert", value: "3 - Expert" },
    { label: "4 - Native", value: "4 - Native." }
  ];

  // Assign Vehicle form fields
  selectedVehicleId = "";
  selectedAuthType = "Primary";
  assignIssueKey = true;

  // Log Trip form fields
  tripVehicleId = "";
  tripType = "Business";
  tripPurpose = "";
  tripStartTime = "";
  tripEndTime = "";
  tripDistance = 0;
  tripStartOdo = 0;
  tripEndOdo = 0;
  tripOrigin = "";
  tripDestination = "";

  // Log Fuel form fields
  fuelVehicleId = "";
  fuelDate = "";
  fuelProductType = "Diesel";
  fuelVolume = 0;
  fuelCost = 0;
  fuelOdometer = 0;

  // Report Citation form fields
  citationVehicleId = "";
  citationTicketNumber = "";
  citationDate = "";
  citationViolationType = "Speeding";
  citationFineAmount = 0;
  citationAuthority = "";

  @wire(getDriver360Data, { contactId: "$recordId" })
  wiredDriver(result) {
    this.wiredDriverResult = result;
    const { data, error } = result;
    if (data) {
      this.data = data;
      this.error = undefined;
      this.isLoading = false;
    } else if (error) {
      this.error = error;
      this.data = undefined;
      this.isLoading = false;
    }
  }

  @wire(getAvailableVehicles)
  wiredVehicles(result) {
    this.wiredVehiclesResult = result;
    const { data, error } = result;
    if (data) {
      this.vehicleOptions = data.map((v) => ({
        label: v.label,
        value: v.id,
        odometer: v.odometer
      }));
    } else if (error) {
      this.vehicleOptions = [];
    }
  }

  // --- Getters for Data & UI State ---

  get hasData() {
    return !!this.data && !!this.data.summary;
  }

  get summary() {
    return this.data ? this.data.summary : {};
  }

  get activeVehicle() {
    return this.data && this.data.activeVehicle ? this.data.activeVehicle : {};
  }

  get telematics() {
    return this.data && this.data.telematics ? this.data.telematics : {};
  }

  get mileageSplit() {
    return this.data && this.data.mileageSplit ? this.data.mileageSplit : {};
  }

  get citations() {
    return this.data && this.data.citations
      ? this.data.citations
      : { count: 0, totalFine: 0 };
  }

  get errorMessage() {
    if (!this.error) return "";
    return this.error.body
      ? this.error.body.message
      : JSON.stringify(this.error);
  }

  get initials() {
    const name = this.summary.name || "";
    const parts = name.trim().split(" ");
    if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  get isDriverType() {
    return this.summary.contactType === "Driver";
  }

  get phoneHref() {
    return this.summary.phone ? `tel:${this.summary.phone}` : "#";
  }

  get emailHref() {
    return this.summary.email ? `mailto:${this.summary.email}` : "#";
  }

  get statusBadgeClass() {
    const s = (this.summary.driverStatus || "").toLowerCase();
    if (s === "active") return "pill pill-active";
    if (s === "on leave" || s === "inactive") return "pill pill-warn";
    if (s === "suspended") return "pill pill-bad";
    return "pill pill-neutral";
  }

  get safetyRatingBadgeClass() {
    const s = this.summary.safetyScore;
    if (s >= 85) return "pill pill-active";
    if (s >= 70) return "pill pill-warn";
    return "pill pill-bad";
  }

  get safetyScoreCircleClass() {
    const s = this.summary.safetyScore;
    if (s >= 85) return "safety-score-circle score-excellent";
    if (s >= 70) return "safety-score-circle score-good";
    return "safety-score-circle score-bad";
  }

  get licenseBadgeClass() {
    const st = this.summary.licenseExpiryStatus;
    if (st === "Valid") return "pill pill-active";
    if (st === "Expiring Soon") return "pill pill-warn";
    if (st === "Expired") return "pill pill-bad";
    return "pill pill-neutral";
  }

  get licenseDaysDisplay() {
    const days = this.summary.licenseDaysRemaining;
    if (days === undefined || days === null) return "No Expiry Date";
    if (days < 0) return `${Math.abs(days)} Days Expired`;
    if (days === 0) return "Expires Today";
    return `${days} Days Left`;
  }

  get licenseMetaText() {
    const parts = [];
    if (this.summary.licenseClass) parts.push(this.summary.licenseClass);
    if (this.summary.licenseNumber) {
      let num = this.summary.licenseNumber;
      if (this.summary.licenseState) num += ` (${this.summary.licenseState})`;
      parts.push(num);
    }
    return parts.length ? parts.join(" · ") : "License records on file";
  }

  get medicalBadgeClass() {
    const st = this.summary.medicalExpiryStatus;
    if (st === "Valid") return "pill pill-active";
    if (st === "Expiring Soon") return "pill pill-warn";
    if (st === "Expired") return "pill pill-bad";
    return "pill pill-neutral";
  }

  get medicalDaysDisplay() {
    const days = this.summary.medicalDaysRemaining;
    if (days === undefined || days === null) return "No Cert Date";
    if (days < 0) return `${Math.abs(days)} Days Expired`;
    if (days === 0) return "Due Today";
    return `${days} Days Left`;
  }

  get medicalMetaText() {
    if (!this.summary.medicalCertDate) return "Medical evaluation pending";
    return `Cert Date: ${this.summary.medicalCertDate}`;
  }

  get authLevelBadgeClass() {
    const a = (this.activeVehicle.authorizationLevel || "").toLowerCase();
    if (a === "primary") return "pill pill-active";
    if (a === "secondary") return "pill pill-neutral";
    return "pill pill-warn";
  }

  get vehicleHeadline() {
    const v = this.activeVehicle;
    const parts = [v.modelYear, v.make, v.model].filter(Boolean);
    return parts.length ? parts.join(" ") : v.vehicleName || "Assigned Vehicle";
  }

  get keyHeadlineText() {
    return this.activeVehicle.hasKey ? "Key Access Active" : "No Key Issued";
  }

  get keyTagDisplay() {
    return this.activeVehicle.keyTagId || "Standard Digital Key";
  }

  get keyIconVariant() {
    return this.activeVehicle.hasKey ? "success" : "warning";
  }

  get keyButtonLabel() {
    return this.activeVehicle.hasKey ? "Key Issued ✓" : "Issue Key";
  }

  get keyButtonVariant() {
    return this.activeVehicle.hasKey ? "success" : "neutral";
  }

  get keyToggleActionLabel() {
    return this.activeVehicle.hasKey ? "Return Key" : "Issue Key";
  }

  get fuelProgressStyle() {
    const pct = Math.min(
      Math.max(this.activeVehicle.fuelEnergyLevel || 0, 0),
      100
    );
    return `width: ${pct}%;`;
  }

  get formattedOdometer() {
    const odo = this.activeVehicle.odometer;
    if (odo === undefined || odo === null) return "0";
    return new Intl.NumberFormat().format(odo);
  }

  get riskLevelBadgeClass() {
    const r = (this.telematics.riskLevel || "").toLowerCase();
    if (r.includes("low")) return "pill pill-active";
    if (r.includes("mod")) return "pill pill-warn";
    return "pill pill-bad";
  }

  get businessBarWidth() {
    return `width: ${this.mileageSplit.businessPct || 0}%;`;
  }

  get privateBarWidth() {
    return `width: ${this.mileageSplit.privatePct || 0}%;`;
  }

  get commuteBarWidth() {
    return `width: ${this.mileageSplit.commutePct || 0}%;`;
  }

  get hasCommuteMileage() {
    return (this.mileageSplit.commutePct || 0) > 0;
  }

  get businessTooltip() {
    return `Business: ${this.mileageSplit.businessMileage} ${this.summary.distanceUnit} (${this.mileageSplit.businessPct}%)`;
  }

  get privateTooltip() {
    return `Private: ${this.mileageSplit.privateMileage} ${this.summary.distanceUnit} (${this.mileageSplit.privatePct}%)`;
  }

  get commuteTooltip() {
    return `Commute: ${this.mileageSplit.commuteMileage} ${this.summary.distanceUnit} (${this.mileageSplit.commutePct}%)`;
  }

  get qualifications() {
    if (!this.data || !this.data.qualifications) return [];
    return this.data.qualifications.map((q) => {
      const level = q.proficiencyLevel || 2;
      return {
        ...q,
        dot2Class: level >= 2 ? "dot filled" : "dot empty",
        dot3Class: level >= 3 ? "dot filled" : "dot empty",
        dot4Class: level >= 4 ? "dot filled" : "dot empty"
      };
    });
  }

  get hasQualifications() {
    return this.qualifications.length > 0;
  }

  get qualificationCount() {
    return this.data?.qualificationCount || 0;
  }

  get activeSkillsCount() {
    return this.data?.activeSkillsCount || 0;
  }

  // --- Modal Picklists ---

  get vehicleOptionsList() {
    return this.vehicleOptions;
  }

  get authTypeOptions() {
    return [
      { label: "Primary Driver (Dedicated / Fleet Lead)", value: "Primary" },
      { label: "Secondary Driver (Shared pool / Backup)", value: "Secondary" },
      { label: "Occasional (Temporary / On Demand)", value: "Occasional" }
    ];
  }

  get tripTypeOptions() {
    return [
      { label: "Business (Standard Operating Mileage)", value: "Business" },
      { label: "Private (Personal Usage)", value: "Private" },
      { label: "Commute (Home to Branch)", value: "Commute" }
    ];
  }

  get fuelProductTypeOptions() {
    return [
      { label: "Diesel", value: "Diesel" },
      { label: "Petrol", value: "Petrol" },
      { label: "AdBlue (DEF)", value: "AdBlue (DEF)" },
      { label: "Electric Charge", value: "Electric Charge." }
    ];
  }

  get citationViolationTypeOptions() {
    return [
      { label: "Speeding", value: "Speeding" },
      { label: "Parking", value: "Parking" },
      { label: "Red Light Camera", value: "Red Light Camera" },
      { label: "Toll Evasion", value: "Toll Evasion" },
      { label: "Expired Tags", value: "Expired Tags." }
    ];
  }

  // --- Quick Action Handlers ---

  handleRefresh() {
    this.isLoading = true;
    refreshApex(this.wiredDriverResult).finally(() => {
      this.isLoading = false;
    });
  }

  async handleToggleKey() {
    if (!this.activeVehicle.authorizationId) {
      this.showToast(
        "Notice",
        "No active vehicle authorization found to update key status.",
        "warning"
      );
      return;
    }
    const newStatus = !this.activeVehicle.hasKey;
    try {
      await toggleKeyAccess({
        authorizationId: this.activeVehicle.authorizationId,
        hasKey: newStatus
      });
      this.showToast(
        "Key Status Updated",
        newStatus
          ? "Physical key issued and registered."
          : "Key returned to depot custody.",
        "success"
      );
      await refreshApex(this.wiredDriverResult);
    } catch (e) {
      this.showToast(
        "Error updating key status",
        this.extractMessage(e),
        "error"
      );
    }
  }

  handleNavigateVehicle() {
    if (!this.activeVehicle.vehicleId) return;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: this.activeVehicle.vehicleId,
        objectApiName: "fleetforce__Fleet_Asset__c",
        actionName: "view"
      }
    });
  }

  // --- Modal 1: Assign Vehicle Handlers ---

  handleOpenAssignModal() {
    this.selectedVehicleId =
      this.activeVehicle.vehicleId ||
      (this.vehicleOptions.length ? this.vehicleOptions[0].value : "");
    this.selectedAuthType = "Primary";
    this.assignIssueKey = true;
    this.showAssignVehicleModal = true;
  }

  handleCloseAssignModal() {
    this.showAssignVehicleModal = false;
  }

  handleAssignVehicleChange(e) {
    this.selectedVehicleId = e.detail.value;
  }

  handleAssignAuthTypeChange(e) {
    this.selectedAuthType = e.detail.value;
  }

  handleAssignKeyChange(e) {
    this.assignIssueKey = e.target.checked;
  }

  async handleSaveAssignVehicle() {
    if (!this.selectedVehicleId) {
      this.showToast(
        "Validation",
        "Please select a vehicle to assign.",
        "error"
      );
      return;
    }
    this.isSubmitting = true;
    try {
      await assignVehicle({
        contactId: this.recordId,
        vehicleId: this.selectedVehicleId,
        authType: this.selectedAuthType,
        issueKey: this.assignIssueKey
      });
      this.showToast(
        "Vehicle Assigned",
        "Vehicle authorized successfully for driver.",
        "success"
      );
      this.showAssignVehicleModal = false;
      await refreshApex(this.wiredDriverResult);
    } catch (e) {
      this.showToast("Assignment Failed", this.extractMessage(e), "error");
    } finally {
      this.isSubmitting = false;
    }
  }

  // --- Modal 2: Log Trip Handlers ---

  handleOpenTripModal() {
    this.tripVehicleId =
      this.activeVehicle.vehicleId ||
      (this.vehicleOptions.length ? this.vehicleOptions[0].value : "");
    this.tripType = "Business";
    this.tripPurpose = "";
    const now = new Date();
    const oneHourAgo = new Date(now.getTime() - 60 * 60 * 1000);
    this.tripStartTime = oneHourAgo.toISOString();
    this.tripEndTime = now.toISOString();
    this.tripDistance = 15;
    this.tripStartOdo = this.activeVehicle.odometer || 0;
    this.tripEndOdo = (this.activeVehicle.odometer || 0) + 15;
    this.tripOrigin = this.summary.branchName || "Fleet Depot";
    this.tripDestination = "";
    this.showLogTripModal = true;
  }

  handleCloseTripModal() {
    this.showLogTripModal = false;
  }

  handleTripVehicleChange(e) {
    this.tripVehicleId = e.detail.value;
    const match = this.vehicleOptions.find(
      (v) => v.value === this.tripVehicleId
    );
    if (match && match.odometer) {
      this.tripStartOdo = match.odometer;
      this.tripEndOdo = match.odometer + (parseFloat(this.tripDistance) || 0);
    }
  }

  handleTripTypeChange(e) {
    this.tripType = e.detail.value;
  }

  handleTripPurposeChange(e) {
    this.tripPurpose = e.detail.value;
  }

  handleTripStartTimeChange(e) {
    this.tripStartTime = e.detail.value;
  }

  handleTripEndTimeChange(e) {
    this.tripEndTime = e.detail.value;
  }

  handleTripDistanceChange(e) {
    this.tripDistance = parseFloat(e.detail.value) || 0;
    this.tripEndOdo = (parseFloat(this.tripStartOdo) || 0) + this.tripDistance;
  }

  handleTripStartOdoChange(e) {
    this.tripStartOdo = parseFloat(e.detail.value) || 0;
    if (this.tripEndOdo && this.tripEndOdo > this.tripStartOdo) {
      this.tripDistance = this.tripEndOdo - this.tripStartOdo;
    }
  }

  handleTripEndOdoChange(e) {
    this.tripEndOdo = parseFloat(e.detail.value) || 0;
    if (this.tripEndOdo && this.tripStartOdo) {
      this.tripDistance = Math.max(0, this.tripEndOdo - this.tripStartOdo);
    }
  }

  handleTripOriginChange(e) {
    this.tripOrigin = e.detail.value;
  }

  handleTripDestinationChange(e) {
    this.tripDestination = e.detail.value;
  }

  async handleSaveTrip() {
    if (!this.tripVehicleId) {
      this.showToast(
        "Validation",
        "Please select a vehicle for this trip.",
        "error"
      );
      return;
    }
    if (!this.tripDistance || this.tripDistance <= 0) {
      this.showToast(
        "Validation",
        "Please enter a valid trip distance.",
        "error"
      );
      return;
    }

    this.isSubmitting = true;
    try {
      await quickLogTrip({
        contactId: this.recordId,
        vehicleId: this.tripVehicleId,
        tripType: this.tripType,
        purpose: this.tripPurpose,
        startTime: this.tripStartTime
          ? new Date(this.tripStartTime).toISOString()
          : null,
        endTime: this.tripEndTime
          ? new Date(this.tripEndTime).toISOString()
          : null,
        distance: this.tripDistance,
        distanceUnit: this.summary.distanceUnit || "mi",
        startOdo: this.tripStartOdo,
        endOdo: this.tripEndOdo,
        origin: this.tripOrigin,
        destination: this.tripDestination
      });
      this.showToast(
        "Trip Recorded",
        "Trip successfully logged and submitted.",
        "success"
      );
      this.showLogTripModal = false;
      await refreshApex(this.wiredDriverResult);
    } catch (e) {
      this.showToast("Error Logging Trip", this.extractMessage(e), "error");
    } finally {
      this.isSubmitting = false;
    }
  }

  // --- Modal 3: Log Fuel Handlers ---

  handleOpenFuelModal() {
    this.fuelVehicleId =
      this.activeVehicle.vehicleId ||
      (this.vehicleOptions.length ? this.vehicleOptions[0].value : "");
    this.fuelDate = new Date().toISOString().split("T")[0];
    this.fuelProductType = "Diesel";
    this.fuelVolume = 12.5;
    this.fuelCost = 45.0;
    this.fuelOdometer = this.activeVehicle.odometer || 0;
    this.showLogFuelModal = true;
  }

  handleCloseFuelModal() {
    this.showLogFuelModal = false;
  }

  handleFuelVehicleChange(e) {
    this.fuelVehicleId = e.detail.value;
    const match = this.vehicleOptions.find(
      (v) => v.value === this.fuelVehicleId
    );
    if (match && match.odometer) {
      this.fuelOdometer = match.odometer;
    }
  }

  handleFuelDateChange(e) {
    this.fuelDate = e.detail.value;
  }

  handleFuelProductTypeChange(e) {
    this.fuelProductType = e.detail.value;
  }

  handleFuelVolumeChange(e) {
    this.fuelVolume = parseFloat(e.detail.value) || 0;
  }

  handleFuelCostChange(e) {
    this.fuelCost = parseFloat(e.detail.value) || 0;
  }

  handleFuelOdometerChange(e) {
    this.fuelOdometer = parseFloat(e.detail.value) || 0;
  }

  async handleSaveFuel() {
    if (!this.fuelVehicleId) {
      this.showToast("Validation", "Please select a vehicle.", "error");
      return;
    }
    if (!this.fuelVolume || this.fuelVolume <= 0) {
      this.showToast(
        "Validation",
        "Please specify fuel/charge volume.",
        "error"
      );
      return;
    }

    this.isSubmitting = true;
    try {
      await quickLogFuel({
        contactId: this.recordId,
        vehicleId: this.fuelVehicleId,
        txDate: this.fuelDate,
        volume: this.fuelVolume,
        totalCost: this.fuelCost,
        odometer: this.fuelOdometer,
        productType: this.fuelProductType
      });
      this.showToast(
        "Fuel Logged",
        "Transaction recorded into fleet audit ledger.",
        "success"
      );
      this.showLogFuelModal = false;
      await refreshApex(this.wiredDriverResult);
    } catch (e) {
      this.showToast("Error Recording Fuel", this.extractMessage(e), "error");
    } finally {
      this.isSubmitting = false;
    }
  }

  // --- Modal 4: Report Citation Handlers ---

  handleOpenCitationModal() {
    this.citationVehicleId =
      this.activeVehicle.vehicleId ||
      (this.vehicleOptions.length ? this.vehicleOptions[0].value : "");
    this.citationTicketNumber = "";
    this.citationDate = new Date().toISOString().split("T")[0];
    this.citationViolationType = "Speeding";
    this.citationFineAmount = 100.0;
    this.citationAuthority = "";
    this.showReportCitationModal = true;
  }

  handleCloseCitationModal() {
    this.showReportCitationModal = false;
  }

  handleCitationVehicleChange(e) {
    this.citationVehicleId = e.detail.value;
  }

  handleCitationTicketNumberChange(e) {
    this.citationTicketNumber = e.detail.value;
  }

  handleCitationDateChange(e) {
    this.citationDate = e.detail.value;
  }

  handleCitationViolationTypeChange(e) {
    this.citationViolationType = e.detail.value;
  }

  handleCitationFineAmountChange(e) {
    this.citationFineAmount = parseFloat(e.detail.value) || 0;
  }

  handleCitationAuthorityChange(e) {
    this.citationAuthority = e.detail.value;
  }

  async handleSaveCitation() {
    if (!this.citationVehicleId) {
      this.showToast("Validation", "Please select a vehicle.", "error");
      return;
    }
    if (!this.citationTicketNumber) {
      this.showToast(
        "Validation",
        "Please enter ticket/citation number.",
        "error"
      );
      return;
    }

    this.isSubmitting = true;
    try {
      await quickReportCitation({
        contactId: this.recordId,
        vehicleId: this.citationVehicleId,
        citationDate: this.citationDate,
        ticketNumber: this.citationTicketNumber,
        violationType: this.citationViolationType,
        fineAmount: this.citationFineAmount,
        issuingAuthority: this.citationAuthority
      });
      this.showToast(
        "Citation Logged",
        "Citation filed for driver record review.",
        "success"
      );
      this.showReportCitationModal = false;
      await refreshApex(this.wiredDriverResult);
    } catch (e) {
      this.showToast(
        "Error Reporting Citation",
        this.extractMessage(e),
        "error"
      );
    } finally {
      this.isSubmitting = false;
    }
  }

  // --- Modal 5: Add Skill / Qualification Handlers ---

  handleOpenSkillModal() {
    this.newSkillTitle = "";
    this.newSkillType = "Internal Skill";
    this.newSkillProficiency = "3 - Expert";
    this.newSkillValidUntil = "";
    this.newSkillCertId = "";
    this.newSkillAuthority = "";
    this.showSkillModal = true;
  }

  handleCloseSkillModal() {
    this.showSkillModal = false;
  }

  handleSkillTitleChange(e) {
    this.newSkillTitle = e.detail.value;
  }

  handleSkillTypeChange(e) {
    this.newSkillType = e.detail.value;
  }

  handleSkillProficiencyChange(e) {
    this.newSkillProficiency = e.detail.value;
  }

  handleSkillValidUntilChange(e) {
    this.newSkillValidUntil = e.detail.value;
  }

  handleSkillCertIdChange(e) {
    this.newSkillCertId = e.detail.value;
  }

  handleSkillAuthorityChange(e) {
    this.newSkillAuthority = e.detail.value;
  }

  async handleSaveSkill() {
    if (!this.newSkillTitle || !this.newSkillTitle.trim()) {
      this.showToast(
        "Validation",
        "Please enter qualification or skill title.",
        "error"
      );
      return;
    }

    this.isSavingSkill = true;
    try {
      await addDriverQualification({
        contactId: this.recordId,
        title: this.newSkillTitle,
        qualType: this.newSkillType,
        proficiency: this.newSkillProficiency,
        validUntil: this.newSkillValidUntil || null,
        certId: this.newSkillCertId,
        authority: this.newSkillAuthority
      });
      this.showToast(
        "Qualification Added",
        "Driver qualification recorded successfully.",
        "success"
      );
      this.showSkillModal = false;
      await refreshApex(this.wiredDriverResult);
    } catch (e) {
      this.showToast(
        "Error Adding Qualification",
        this.extractMessage(e),
        "error"
      );
    } finally {
      this.isSavingSkill = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  extractMessage(e) {
    if (e && e.body && e.body.message) return e.body.message;
    if (e && e.message) return e.message;
    return "An unexpected error occurred.";
  }
}
