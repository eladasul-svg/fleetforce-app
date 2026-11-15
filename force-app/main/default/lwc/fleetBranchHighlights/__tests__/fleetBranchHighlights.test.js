import { createElement } from "@lwc/engine-dom";
import FleetBranchHighlights from "c/fleetBranchHighlights";
import getBranchHighlights from "@salesforce/apex/FleetBranchController.getBranchHighlights";

jest.mock(
  "@salesforce/apex/FleetBranchController.getBranchHighlights",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const MOCK_BRANCH_DATA = {
  branchId: "a0KWm000005av3JMAQ",
  name: "Tel Aviv Satellite",
  branchCode: "BR-TLV",
  status: "Active",
  locationType: "Satellite",
  capacity: 35,
  street: "Rothschild Blvd 45",
  city: "Tel Aviv-Yafo",
  state: "Tel Aviv",
  zipCode: "65784",
  country: "IL",
  phone: "+972-3-555-0100",
  email: "tlv@fleetforce.com",
  latitude: 32.0636,
  longitude: 34.7722,
  fullAddress: "Rothschild Blvd 45, Tel Aviv-Yafo, Tel Aviv, 65784, IL",
  googleMapsUrl:
    "https://www.google.com/maps/search/?api=1&query=32.0636,34.7722",
  manager: {
    id: "003Wm00000Hk0h1IAB",
    name: "Elena Reyes",
    title: "Operations Manager",
    email: "elena@fleetforce.com",
    phone: "+972-3-555-0199",
    initials: "ER",
    photoUrl: null
  },
  totalVehicles: 28,
  activeVehicles: 24,
  inShopVehicles: 4,
  assignedDrivers: 16,
  activeRoutePlans: 5,
  openServiceTickets: 3,
  capacityUtilizationPct: 80.0,
  capacityStatus: "warning"
};

describe("c-fleet-branch-highlights", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders branch highlights card with all sections when data arrives", async () => {
    const element = createElement("c-fleet-branch-highlights", {
      is: FleetBranchHighlights
    });
    element.recordId = "a0KWm000005av3JMAQ";
    document.body.appendChild(element);

    getBranchHighlights.emit(MOCK_BRANCH_DATA);
    await Promise.resolve();

    const titleEl = element.shadowRoot.querySelector(".branch-title");
    expect(titleEl.textContent).toBe("Tel Aviv Satellite");

    const codeEl = element.shadowRoot.querySelector(".badge-code");
    expect(codeEl.textContent).toBe("BR-TLV");

    const statusEl = element.shadowRoot.querySelector(".badge-active");
    expect(statusEl.textContent).toBe("Active");

    const managerName = element.shadowRoot.querySelector(".manager-name");
    expect(managerName.textContent.trim()).toBe("Elena Reyes");

    const managerInitials =
      element.shadowRoot.querySelector(".avatar-initials");
    expect(managerInitials.textContent).toBe("ER");

    const metricValues = element.shadowRoot.querySelectorAll(".metric-value");
    expect(metricValues[0].textContent).toBe("24"); // activeVehicles
    expect(metricValues[1].textContent).toBe("4"); // inShopVehicles
    expect(metricValues[2].textContent).toBe("16"); // assignedDrivers
    expect(metricValues[3].textContent).toBe("5"); // activeRoutePlans
  });

  it("triggers map navigation when Open in Maps is clicked", async () => {
    const windowSpy = jest.spyOn(window, "open").mockImplementation(() => {});
    const element = createElement("c-fleet-branch-highlights", {
      is: FleetBranchHighlights
    });
    element.recordId = "a0KWm000005av3JMAQ";
    document.body.appendChild(element);

    getBranchHighlights.emit(MOCK_BRANCH_DATA);
    await Promise.resolve();

    const mapBtn = element.shadowRoot.querySelector(".open-maps-btn");
    expect(mapBtn).not.toBeNull();
    mapBtn.click();

    expect(windowSpy).toHaveBeenCalledWith(
      "https://www.google.com/maps/search/?api=1&query=32.0636,34.7722",
      "_blank"
    );
    windowSpy.mockRestore();
  });

  it("renders fallback message when no manager is assigned", async () => {
    const element = createElement("c-fleet-branch-highlights", {
      is: FleetBranchHighlights
    });
    element.recordId = "a0KWm000005av3JMAQ";
    document.body.appendChild(element);

    const dataWithoutManager = {
      ...MOCK_BRANCH_DATA,
      manager: null
    };
    getBranchHighlights.emit(dataWithoutManager);
    await Promise.resolve();

    const noManagerEl = element.shadowRoot.querySelector(".no-manager-card");
    expect(noManagerEl).not.toBeNull();
    expect(noManagerEl.textContent).toContain("No Branch Manager Assigned");
  });
});
