import { createElement } from "lwc";
import FleetBrandTheme from "c/fleetBrandTheme";
import { registerApexTestWireAdapter } from "@salesforce/sfdx-lwc-jest";
import getBrandSettings from "@salesforce/apex/FleetDisplaySettingsController.getBrandSettings";

const getBrandSettingsAdapter = registerApexTestWireAdapter(getBrandSettings);

jest.mock(
  "@salesforce/apex/FleetDisplaySettingsController.saveBrandIconStyle",
  () => ({
    default: jest.fn().mockResolvedValue({
      iconStyle: "modern",
      customLogoUrl: null,
      defaultLogoUrl: "/file-asset/Fleetforce_Waypoint_Logo",
      hasCustomLogo: false,
      settingId: "a00000000000001AAA",
      canEdit: true
    })
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetDisplaySettingsController.saveCustomLogo",
  () => ({
    default: jest.fn().mockResolvedValue({
      iconStyle: "silhouette",
      customLogoUrl:
        "/sfc/servlet.shepherd/version/download/068000000000001AAA",
      defaultLogoUrl: "/file-asset/Fleetforce_Waypoint_Logo",
      hasCustomLogo: true,
      settingId: "a00000000000001AAA",
      canEdit: true
    })
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetDisplaySettingsController.revertToDefaultLogo",
  () => ({
    default: jest.fn().mockResolvedValue({
      iconStyle: "silhouette",
      customLogoUrl: null,
      defaultLogoUrl: "/file-asset/Fleetforce_Waypoint_Logo",
      hasCustomLogo: false,
      settingId: "a00000000000001AAA",
      canEdit: true
    })
  }),
  { virtual: true }
);

const MOCK_BRAND_SETTINGS = {
  iconStyle: "silhouette",
  customLogoUrl: null,
  defaultLogoUrl: "/file-asset/Fleetforce_Waypoint_Logo",
  hasCustomLogo: false,
  settingId: "a00000000000001AAA",
  canEdit: true
};

describe("c-fleet-brand-theme", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders 2 brand cards in overview mode with default FleetForce logo", async () => {
    const element = createElement("c-fleet-brand-theme", {
      is: FleetBrandTheme
    });
    document.body.appendChild(element);

    getBrandSettingsAdapter.emit(MOCK_BRAND_SETTINGS);
    await Promise.resolve();

    const cards = element.shadowRoot.querySelectorAll(".brand-card");
    expect(cards.length).toBe(2);

    const headings = Array.from(cards).map(
      (c) => c.querySelector("h3").textContent
    );
    expect(headings[0]).toContain("Vehicle Icon Style");
    expect(headings[1]).toContain("Company Brand Logo");

    const logoImg = element.shadowRoot.querySelector(".logo-preview-img");
    expect(logoImg).not.toBeNull();
    expect(logoImg.src).toContain("Fleetforce_Waypoint_Logo");
  });

  it("toggles icon style editing mode when clicking Modify Icon Style", async () => {
    const element = createElement("c-fleet-brand-theme", {
      is: FleetBrandTheme
    });
    document.body.appendChild(element);

    getBrandSettingsAdapter.emit(MOCK_BRAND_SETTINGS);
    await Promise.resolve();

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    const modifyStyleBtn = Array.from(buttons).find(
      (b) => b.label === "Modify Icon Style"
    );
    expect(modifyStyleBtn).toBeDefined();

    modifyStyleBtn.click();
    await Promise.resolve();

    const tiles = element.shadowRoot.querySelectorAll(".tile");
    expect(tiles.length).toBe(5);
  });

  it("toggles logo upload mode when clicking Upload Company Logo", async () => {
    const element = createElement("c-fleet-brand-theme", {
      is: FleetBrandTheme
    });
    document.body.appendChild(element);

    getBrandSettingsAdapter.emit(MOCK_BRAND_SETTINGS);
    await Promise.resolve();

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    const uploadBtn = Array.from(buttons).find(
      (b) => b.label === "Upload Company Logo"
    );
    expect(uploadBtn).toBeDefined();

    uploadBtn.click();
    await Promise.resolve();

    const fileUpload = element.shadowRoot.querySelector(
      "lightning-file-upload"
    );
    expect(fileUpload).not.toBeNull();
  });
});
