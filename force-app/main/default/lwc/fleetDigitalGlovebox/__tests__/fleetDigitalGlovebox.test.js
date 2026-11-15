import { createElement } from "lwc";
import FleetDigitalGlovebox from "c/fleetDigitalGlovebox";
import { registerApexTestWireAdapter } from "@salesforce/sfdx-lwc-jest";
import getGloveboxData from "@salesforce/apex/FleetDigitalGloveboxController.getGloveboxData";
import createAssetDocument from "@salesforce/apex/FleetDigitalGloveboxController.createAssetDocument";
import assignMaintenancePlan from "@salesforce/apex/FleetDigitalGloveboxController.assignMaintenancePlan";

const getGloveboxDataAdapter = registerApexTestWireAdapter(getGloveboxData);

const mockNavigate = jest.fn();
jest.mock("lightning/navigation", () => {
  const Navigate = Symbol("Navigate");
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](pageRef) {
        mockNavigate(pageRef);
      }
    };
  NavigationMixin.Navigate = Navigate;
  return { NavigationMixin };
});

jest.mock(
  "@salesforce/apex/FleetDigitalGloveboxController.createAssetDocument",
  () => ({
    default: jest.fn().mockResolvedValue("a0SWm000001mockDoc")
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetDigitalGloveboxController.assignMaintenancePlan",
  () => ({
    default: jest.fn().mockResolvedValue(undefined)
  }),
  { virtual: true }
);

const MOCK_GLOVEBOX_PAYLOAD = {
  assetInfo: {
    id: "a00Wm000003mockAsset",
    name: "2025 Ford F-150 · NH73CXK",
    vin: "1FTFW1ED8NFA00001",
    licensePlate: "NH73CXK",
    make: "Ford",
    model: "F-150",
    modelYear: "2025",
    bodyType: "Pickup",
    fuelType: "Gasoline",
    odometer: 14250,
    distanceUnit: "mi",
    branchName: "Chicago Service Center",
    country: "US"
  },
  modelResources: {
    modelLabel: "Ford F-150 Lariat 4WD",
    manufacturerHandbookUrl: "https://www.ford.com/support/owner-manuals/",
    infotainmentVideoUrl: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    infotainmentVideoEmbedUrl:
      "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ",
    emergencyGuideUrl: "https://www.ford.com/roadside-assistance/",
    epaMpgCombined: 21,
    evRangeMiles: null,
    hasHandbook: true,
    hasVideo: true,
    hasEmergencyGuide: true
  },
  complianceDocuments: [
    {
      id: "a0SWm000001doc1",
      name: "DOC-001",
      docType: "Registration",
      docNumber: "REG-IL-98442",
      validFrom: "2025-01-01",
      validUntil: "2026-01-01",
      daysUntilExpiry: 45,
      status: "Current",
      complianceState: "Valid",
      expiryStatus: "good",
      expiryBadgeClass: "slds-badge slds-theme_success",
      expiryLabel: "Current (45d remaining)",
      docLink: "https://cyberdriveillinois.com",
      isRequired: true,
      issuingAuthority: "Illinois Secretary of State",
      hasFiles: true,
      fileId: "068Wm000000mockVer",
      fileName: "IL_Registration_2025.pdf",
      fileDownloadUrl:
        "/sfc/servlet.shepherd/version/download/068Wm000000mockVer"
    }
  ],
  systemLinkedDocuments: [
    {
      id: "069Wm000000mockDoc1",
      title: "Speeding_Citation_Notice.pdf",
      fileExtension: "PDF",
      fileSize: "142 KB",
      downloadUrl:
        "/sfc/servlet.shepherd/document/download/069Wm000000mockDoc1",
      sourceRecordId: "a0AWm000000mockCit",
      sourceRecordName: "CIT-LON-2026-981",
      sourceEntityType: "Citation",
      sourceBadgeClass: "slds-badge slds-theme_warning"
    }
  ],
  directAssetDocuments: [
    {
      id: "069Wm000000mockDoc2",
      title: "Vehicle_Title_Georgia.pdf",
      fileExtension: "PDF",
      fileSize: "1.2 MB",
      downloadUrl:
        "/sfc/servlet.shepherd/document/download/069Wm000000mockDoc2",
      sourceRecordId: "a00Wm000003mockAsset",
      sourceRecordName: "Asset Direct File",
      sourceEntityType: "Asset Document",
      sourceBadgeClass: "slds-badge slds-theme_success"
    }
  ],
  maintenanceInfo: {
    hasActivePlan: true,
    activePlan: {
      id: "a0RWm000001plan1",
      name: "Ford F-150 Commercial 3-Year / 36,000-Mi Program",
      assetType: "Pickup",
      frequencyType: "Distance & Time",
      intervalValue: 5000,
      intervalMonths: 6,
      sopChecklist: "Drain oil, rotate tires, multi-point inspection",
      isOverridden: true
    },
    hasNextMilestone: true,
    nextMilestoneDueOdometer: 25000,
    nextMilestoneMilesRemaining: 2600,
    nextMilestoneStatusBadgeClass: "slds-badge slds-theme_warning",
    nextMilestoneStatusLabel: "Due in 2,600 mi",
    nextMilestone: {
      id: "a0xWm000000line1",
      name: "Line 1",
      milestoneMileage: 25000,
      milestoneMonths: 24,
      sequence: 1,
      serviceCategory: "A-Service (Basic / Lube)",
      componentsServiced: "Engine Oil, Oil Filter, Tire Rotation",
      estimatedCost: 150.0,
      estimatedHours: 1.5,
      isNextDue: true,
      isCompleted: false,
      remainingMileage: 2600,
      isOverdue: false,
      statusBadgeClass: "slds-badge slds-theme_warning",
      statusLabel: "Due in 2,600 mi"
    },
    lineItems: [
      {
        id: "a0xWm000000line1",
        name: "Line 1",
        milestoneMileage: 25000,
        milestoneMonths: 24,
        sequence: 1,
        serviceCategory: "A-Service (Basic / Lube)",
        componentsServiced: "Engine Oil, Oil Filter, Tire Rotation",
        estimatedCost: 150.0,
        estimatedHours: 1.5,
        isNextDue: true,
        isCompleted: false,
        remainingMileage: 2600,
        isOverdue: false,
        statusBadgeClass: "slds-badge slds-theme_warning",
        statusLabel: "Due in 2,600 mi"
      }
    ],
    availablePlans: [
      {
        label: "Ford F-150 Commercial 3-Year / 36,000-Mi Program (Default)",
        value: "a0RWm000001plan1"
      },
      {
        label: "Severe Duty Heavy Haul 2-Year Program",
        value: "a0RWm000002plan2"
      }
    ],
    recentTickets: [
      {
        id: "a0TWm000001ticket1",
        name: "ST-00412",
        summary: "15,000 Mile Service - Oil & Filter Replacement",
        category: "Preventive",
        status: "Completed",
        dueDate: "2026-02-15",
        actualEnd: "2026-02-14",
        totalCost: 189.5,
        maintenancePlanName: "Master Schedule A"
      }
    ]
  }
};

describe("c-fleet-digital-glovebox", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders loading state initially", () => {
    const element = createElement("c-fleet-digital-glovebox", {
      is: FleetDigitalGlovebox
    });
    element.recordId = "a00Wm000003mockAsset";
    document.body.appendChild(element);

    const spinner = element.shadowRoot.querySelector("lightning-spinner");
    expect(spinner).not.toBeNull();
  });

  it("renders vehicle banner, tabs, compliance documents, and navigates on button click", async () => {
    const element = createElement("c-fleet-digital-glovebox", {
      is: FleetDigitalGlovebox
    });
    element.recordId = "a00Wm000003mockAsset";
    document.body.appendChild(element);

    getGloveboxDataAdapter.emit(MOCK_GLOVEBOX_PAYLOAD);
    await Promise.resolve();

    // Check banner details
    const banner = element.shadowRoot.querySelector(".vehicle-banner");
    expect(banner).not.toBeNull();
    expect(banner.textContent).toContain("2025 Ford F-150 · NH73CXK");
    expect(banner.textContent).toContain("1FTFW1ED8NFA00001");

    // Check compliance document card
    const docCards = element.shadowRoot.querySelectorAll(".doc-card");
    expect(docCards.length).toBeGreaterThan(0);
    expect(docCards[0].textContent).toContain("Registration");
    expect(docCards[0].textContent).toContain("REG-IL-98442");

    // Click "View Asset Document" button
    const viewAssetDocBtn = element.shadowRoot.querySelector(
      'button[data-id="a0SWm000001doc1"]'
    );
    expect(viewAssetDocBtn).not.toBeNull();
    viewAssetDocBtn.click();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "a0SWm000001doc1",
        actionName: "view"
      }
    });

    // Check OEM manuals tab content
    const oemCards = element.shadowRoot.querySelectorAll(".oem-card");
    expect(oemCards.length).toBe(2);

    // Check video iframe
    const iframe = element.shadowRoot.querySelector(".video-iframe");
    expect(iframe).not.toBeNull();
    expect(iframe.src).toContain("youtube-nocookie.com/embed/dQw4w9WgXcQ");
  });

  it("renders vehicle documents tab with system-linked and direct asset files", async () => {
    const element = createElement("c-fleet-digital-glovebox", {
      is: FleetDigitalGlovebox
    });
    element.recordId = "a00Wm000003mockAsset";
    document.body.appendChild(element);

    getGloveboxDataAdapter.emit(MOCK_GLOVEBOX_PAYLOAD);
    await Promise.resolve();

    // Check System-linked file title and badge
    expect(element.shadowRoot.textContent).toContain(
      "Speeding_Citation_Notice.pdf"
    );
    expect(element.shadowRoot.textContent).toContain("CIT-LON-2026-981");

    // Click "View Source Record" button on citation doc
    const viewSrcBtn = element.shadowRoot.querySelector(
      'button[data-id="a0AWm000000mockCit"]'
    );
    expect(viewSrcBtn).not.toBeNull();
    viewSrcBtn.click();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "a0AWm000000mockCit",
        actionName: "view"
      }
    });

    // Check Direct vehicle file title
    expect(element.shadowRoot.textContent).toContain(
      "Vehicle_Title_Georgia.pdf"
    );
  });

  it("renders maintenance master program, next milestone card, and opens change plan modal", async () => {
    const element = createElement("c-fleet-digital-glovebox", {
      is: FleetDigitalGlovebox
    });
    element.recordId = "a00Wm000003mockAsset";
    document.body.appendChild(element);

    getGloveboxDataAdapter.emit(MOCK_GLOVEBOX_PAYLOAD);
    await Promise.resolve();

    // Check Active Program banner
    const banner = element.shadowRoot.querySelector(".active-plan-banner");
    expect(banner).not.toBeNull();
    expect(banner.textContent).toContain(
      "Ford F-150 Commercial 3-Year / 36,000-Mi Program"
    );

    // Click "View Program Record"
    const viewProgBtn = element.shadowRoot.querySelector(
      'button[data-id="view-plan-record-btn"]'
    );
    expect(viewProgBtn).not.toBeNull();
    viewProgBtn.click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: "a0RWm000001plan1",
        actionName: "view"
      }
    });

    // Check Next Milestone card
    const nextMilestoneCard = element.shadowRoot.querySelector(
      ".next-milestone-card"
    );
    expect(nextMilestoneCard).not.toBeNull();
    expect(nextMilestoneCard.textContent).toContain("Line 1");
    expect(nextMilestoneCard.textContent).toContain("Due in 2,600 mi");

    // Check Milestone Roadmap Line Item Card
    const lineItemCards =
      element.shadowRoot.querySelectorAll(".line-item-card");
    expect(lineItemCards.length).toBe(1);
    expect(lineItemCards[0].textContent).toContain("A-Service (Basic / Lube)");

    // Click "Change Program" button to open modal
    const changePlanBtn = element.shadowRoot.querySelector(
      'button[data-id="change-plan-btn"]'
    );
    expect(changePlanBtn).not.toBeNull();
    changePlanBtn.click();
    await Promise.resolve();

    const planCombobox = element.shadowRoot.querySelector(
      'lightning-combobox[data-id="plan-select"]'
    );
    expect(planCombobox).not.toBeNull();

    // Change value and save
    planCombobox.dispatchEvent(
      new CustomEvent("change", { detail: { value: "a0RWm000002plan2" } })
    );
    await Promise.resolve();

    const savePlanBtn = element.shadowRoot.querySelector(
      'lightning-button[data-id="save-plan-btn"]'
    );
    savePlanBtn.click();
    await Promise.resolve();

    expect(assignMaintenancePlan).toHaveBeenCalledWith({
      assetId: "a00Wm000003mockAsset",
      planId: "a0RWm000002plan2"
    });
  });

  it("handles direct file upload finished event", async () => {
    const element = createElement("c-fleet-digital-glovebox", {
      is: FleetDigitalGlovebox
    });
    element.recordId = "a00Wm000003mockAsset";
    document.body.appendChild(element);

    getGloveboxDataAdapter.emit(MOCK_GLOVEBOX_PAYLOAD);
    await Promise.resolve();

    const fileUpload = element.shadowRoot.querySelector(
      "lightning-file-upload"
    );
    expect(fileUpload).not.toBeNull();

    // Trigger uploadfinished
    fileUpload.dispatchEvent(
      new CustomEvent("uploadfinished", {
        detail: {
          files: [{ name: "New_DOT_Inspection.pdf", documentId: "069newDoc" }]
        }
      })
    );
    await Promise.resolve();
    // Verify component handles event without error
    expect(
      element.shadowRoot.querySelector("lightning-file-upload")
    ).not.toBeNull();
  });

  it("renders empty state when there are no compliance documents", async () => {
    const emptyPayload = {
      ...MOCK_GLOVEBOX_PAYLOAD,
      complianceDocuments: [],
      systemLinkedDocuments: [],
      directAssetDocuments: []
    };

    const element = createElement("c-fleet-digital-glovebox", {
      is: FleetDigitalGlovebox
    });
    element.recordId = "a00Wm000003mockAsset";
    document.body.appendChild(element);

    getGloveboxDataAdapter.emit(emptyPayload);
    await Promise.resolve();

    const emptyState = element.shadowRoot.querySelector(".empty-state");
    expect(emptyState).not.toBeNull();
    expect(emptyState.textContent).toContain(
      "No Compliance Documents Uploaded"
    );
  });

  it("opens modal on Add Document click and submits createAssetDocument", async () => {
    const element = createElement("c-fleet-digital-glovebox", {
      is: FleetDigitalGlovebox
    });
    element.recordId = "a00Wm000003mockAsset";
    document.body.appendChild(element);

    getGloveboxDataAdapter.emit(MOCK_GLOVEBOX_PAYLOAD);
    await Promise.resolve();

    // Click "Add Document" button
    const addButton = element.shadowRoot.querySelector(
      'lightning-button[data-id="add-doc-btn"]'
    );
    addButton.click();
    await Promise.resolve();

    const modal = element.shadowRoot.querySelector(".slds-modal");
    expect(modal).not.toBeNull();

    // Trigger save
    const saveButton = element.shadowRoot.querySelector(
      'lightning-button[data-id="save-doc-btn"]'
    );
    saveButton.click();
    await Promise.resolve();

    expect(createAssetDocument).toHaveBeenCalledWith(
      expect.objectContaining({
        assetId: "a00Wm000003mockAsset",
        docType: "Registration"
      })
    );
  });

  it("renders error alert when wire emits error", async () => {
    const element = createElement("c-fleet-digital-glovebox", {
      is: FleetDigitalGlovebox
    });
    element.recordId = "a00Wm000003mockAsset";
    document.body.appendChild(element);

    getGloveboxDataAdapter.error(
      new Error("Record not found or access denied")
    );
    await Promise.resolve();

    const errorBox = element.shadowRoot.querySelector(".slds-theme_error");
    expect(errorBox).not.toBeNull();
    expect(errorBox.textContent).toContain("Record not found or access denied");
  });
});
