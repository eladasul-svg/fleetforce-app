import { createElement } from "lwc";
import FleetDigitalGlovebox from "c/fleetDigitalGlovebox";
import { registerApexTestWireAdapter } from "@salesforce/sfdx-lwc-jest";
import getGloveboxData from "@salesforce/apex/FleetDigitalGloveboxController.getGloveboxData";
import createAssetDocument from "@salesforce/apex/FleetDigitalGloveboxController.createAssetDocument";

const getGloveboxDataAdapter = registerApexTestWireAdapter(getGloveboxData);

jest.mock(
  "@salesforce/apex/FleetDigitalGloveboxController.createAssetDocument",
  () => ({
    default: jest.fn().mockResolvedValue("a0SWm000001mockDoc")
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
  maintenanceInfo: {
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
    ],
    applicablePlans: [
      {
        id: "a0RWm000001plan1",
        name: "Pickup Truck Severe Service Schedule",
        assetType: "Pickup",
        frequencyType: "Distance & Time",
        intervalValue: 5000,
        intervalMonths: 6,
        sopChecklist:
          "1. Drain motor oil & replace filter\n2. Inspect front/rear brake pads\n3. Rotate tires"
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

  it("renders vehicle banner, tabs, and documents when data arrives", async () => {
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
    expect(docCards.length).toBe(1);
    expect(docCards[0].textContent).toContain("Registration");
    expect(docCards[0].textContent).toContain("REG-IL-98442");

    // Check OEM manuals tab content
    const oemCards = element.shadowRoot.querySelectorAll(".oem-card");
    expect(oemCards.length).toBe(2);

    // Check video iframe
    const iframe = element.shadowRoot.querySelector(".video-iframe");
    expect(iframe).not.toBeNull();
    expect(iframe.src).toContain("youtube-nocookie.com/embed/dQw4w9WgXcQ");

    // Check maintenance plans
    const planCards = element.shadowRoot.querySelectorAll(".plan-card");
    expect(planCards.length).toBe(1);
    expect(planCards[0].textContent).toContain(
      "Pickup Truck Severe Service Schedule"
    );
  });

  it("renders empty state when there are no compliance documents", async () => {
    const emptyPayload = {
      ...MOCK_GLOVEBOX_PAYLOAD,
      complianceDocuments: []
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
