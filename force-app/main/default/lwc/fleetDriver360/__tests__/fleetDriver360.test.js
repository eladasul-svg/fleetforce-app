import { createElement } from "@lwc/engine-dom";
import FleetDriver360 from "c/fleetDriver360";
import getDriver360Data from "@salesforce/apex/FleetDriver360Controller.getDriver360Data";
import getAvailableVehicles from "@salesforce/apex/FleetDriver360Controller.getAvailableVehicles";
import toggleKeyAccess from "@salesforce/apex/FleetDriver360Controller.toggleKeyAccess";

jest.mock(
  "@salesforce/apex/FleetDriver360Controller.getDriver360Data",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetDriver360Controller.getAvailableVehicles",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetDriver360Controller.toggleKeyAccess",
  () => ({ default: jest.fn().mockResolvedValue() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetDriver360Controller.assignVehicle",
  () => ({ default: jest.fn().mockResolvedValue("a0C000000000001") }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetDriver360Controller.quickLogTrip",
  () => ({ default: jest.fn().mockResolvedValue("a0T000000000001") }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetDriver360Controller.quickLogFuel",
  () => ({ default: jest.fn().mockResolvedValue("a0F000000000001") }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetDriver360Controller.quickReportCitation",
  () => ({ default: jest.fn().mockResolvedValue("a0X000000000001") }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetDriver360Controller.addDriverQualification",
  () => ({ default: jest.fn().mockResolvedValue("a0Q000000000001") }),
  { virtual: true }
);

const MOCK_DRIVER_DATA = {
  summary: {
    contactId: "003000000000001",
    name: "Chloe Bennett",
    title: "Lead Route Driver",
    contactType: "Driver",
    driverStatus: "Active",
    safetyScore: 88,
    safetyRating: "Excellent",
    totalTrips: 6,
    monthlyMileage: 342.5,
    lifetimeMileage: 2840.0,
    distanceUnit: "mi",
    licenseNumber: "DL-908122",
    licenseClass: "Class A",
    licenseState: "CA",
    licenseExpiry: "2027-10-15",
    licenseDaysRemaining: 340,
    licenseExpiryStatus: "Valid",
    medicalCertDate: "2026-12-01",
    medicalDaysRemaining: 90,
    medicalExpiryStatus: "Valid",
    phone: "555-010-9988",
    email: "chloe.b@fleetforce.com",
    branchName: "West Coast Depot"
  },
  activeVehicle: {
    hasVehicle: true,
    vehicleId: "a0A000000000001",
    vehicleName: "VAN-009",
    make: "Ford",
    model: "E-Transit",
    modelYear: "2024",
    licensePlate: "6XYZ123",
    vin: "1FTBW90123984",
    vehicleStatus: "Available",
    vehicleClass: "Cargo Van",
    authorizationLevel: "Primary",
    authorizationId: "a0D000000000001",
    hasKey: true,
    keyTagId: "TAG-9011",
    fuelEnergyLevel: 85,
    fuelType: "Electric",
    odometer: 14200,
    distanceUnit: "mi"
  },
  telematics: {
    harshBrakingCount: 1,
    rapidAccelerationCount: 0,
    idlingCount: 2,
    speedingCount: 1,
    totalViolations: 4,
    riskLevel: "Moderate Risk"
  },
  mileageSplit: {
    businessMileage: 2414.0,
    privateMileage: 426.0,
    commuteMileage: 0.0,
    totalMileage: 2840.0,
    businessPct: 85,
    privatePct: 15,
    commutePct: 0
  },
  citations: {
    count: 1,
    totalFine: 125.0
  },
  qualificationCount: 2,
  activeSkillsCount: 2,
  qualifications: [
    {
      id: "a0Q000000000001",
      name: "EV High-Voltage Operator Badge",
      type: "Internal Skill",
      proficiency: "3 - Expert",
      proficiencyLevel: 3,
      proficiencyLabel: "Expert",
      status: "Valid",
      isValid: true,
      expiryStatus: "Valid (180d)",
      authority: "Fleet Academy",
      certId: "EV-88912",
      typeBadgeClass: "badge-skill",
      statusBadgeClass: "pill-active"
    },
    {
      id: "a0Q000000000002",
      name: "Defensive Driving Certification",
      type: "Certification",
      proficiency: "2 - Intermediate",
      proficiencyLevel: 2,
      proficiencyLabel: "Intermediate",
      status: "Valid",
      isValid: true,
      expiryStatus: "Expiring Soon (30d)",
      authority: "NSC",
      typeBadgeClass: "badge-cert",
      statusBadgeClass: "pill-warning"
    }
  ]
};

const MOCK_VEHICLES = [
  {
    id: "a0A000000000001",
    label: "VAN-009 (Ford E-Transit · 6XYZ123)",
    odometer: 14200
  },
  {
    id: "a0A000000000002",
    label: "TRK-002 (Chevrolet Silverado · 8ABC456)",
    odometer: 28900
  }
];

function mount() {
  const el = createElement("c-fleet-driver-360", { is: FleetDriver360 });
  el.recordId = "003000000000001";
  document.body.appendChild(el);
  return el;
}

const flush = () => Promise.resolve();

describe("c-fleet-driver-360", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders driver summary, KPIs, active vehicle and telematics", async () => {
    const el = mount();
    getDriver360Data.emit(MOCK_DRIVER_DATA);
    getAvailableVehicles.emit(MOCK_VEHICLES);
    await flush();

    const root = el.shadowRoot;
    expect(root.querySelector(".driver-name").textContent).toBe(
      "Chloe Bennett"
    );
    expect(root.querySelector(".pill-active").textContent).toBe("Active");
    expect(root.querySelector(".driver-initials").textContent).toBe("CB");

    // KPI values
    const kpiVals = [...root.querySelectorAll(".kpi-primary-val")].map((e) =>
      e.textContent.trim()
    );
    expect(kpiVals).toContain("88");
    expect(kpiVals).toContain("342.5");
    expect(kpiVals).toContain("340 Days Left");

    // Active vehicle
    expect(root.querySelector(".vehicle-name").textContent).toContain(
      "Ford E-Transit"
    );
    expect(root.querySelector(".plate-badge").textContent).toBe("6XYZ123");
    expect(root.querySelector(".key-headline").textContent).toBe(
      "Key Access Active"
    );

    // Telematics
    const counterVals = [...root.querySelectorAll(".t-counter-val")].map((e) =>
      e.textContent.trim()
    );
    expect(counterVals).toEqual(["1", "0", "2", "1"]);

    // Qualifications & Skills
    const skillTitles = [...root.querySelectorAll(".skill-card-title")].map(
      (e) => e.textContent.trim()
    );
    expect(skillTitles).toContain("EV High-Voltage Operator Badge");
    expect(skillTitles).toContain("Defensive Driving Certification");
  });

  it("handles key status toggle", async () => {
    const el = mount();
    getDriver360Data.emit(MOCK_DRIVER_DATA);
    getAvailableVehicles.emit(MOCK_VEHICLES);
    await flush();

    const root = el.shadowRoot;
    const buttons = Array.from(root.querySelectorAll("lightning-button"));
    const keyBtn = buttons.find((b) => b.label === "Key Issued ✓");
    expect(keyBtn).toBeDefined();
    keyBtn.click();
    await flush();

    expect(toggleKeyAccess).toHaveBeenCalledWith({
      authorizationId: "a0D000000000001",
      hasKey: false
    });
  });

  it("opens and closes assign vehicle modal", async () => {
    const el = mount();
    getDriver360Data.emit(MOCK_DRIVER_DATA);
    getAvailableVehicles.emit(MOCK_VEHICLES);
    await flush();

    const root = el.shadowRoot;
    const buttons = Array.from(root.querySelectorAll("lightning-button"));
    const assignBtn = buttons.find((b) => b.label === "Assign Vehicle");
    expect(assignBtn).toBeDefined();
    assignBtn.click();
    await flush();

    expect(root.querySelector(".slds-modal__container")).not.toBeNull();

    const closeBtn = root.querySelector(
      "lightning-button-icon.slds-modal__close"
    );
    closeBtn.click();
    await flush();

    expect(root.querySelector(".slds-modal__container")).toBeNull();
  });

  it("opens and closes add skill modal", async () => {
    const el = mount();
    getDriver360Data.emit(MOCK_DRIVER_DATA);
    getAvailableVehicles.emit(MOCK_VEHICLES);
    await flush();

    const root = el.shadowRoot;
    const buttons = Array.from(root.querySelectorAll("lightning-button"));
    const addSkillBtn = buttons.find((b) => b.label === "Add Skill / Cert");
    expect(addSkillBtn).toBeDefined();
    addSkillBtn.click();
    await flush();

    expect(root.querySelector(".slds-modal__container")).not.toBeNull();
    expect(root.querySelector(".slds-modal__title").textContent.trim()).toBe(
      "Add Driver Skill or Qualification"
    );

    const closeBtn = root.querySelector(
      "lightning-button-icon.slds-modal__close"
    );
    closeBtn.click();
    await flush();

    expect(root.querySelector(".slds-modal__container")).toBeNull();
  });
});
