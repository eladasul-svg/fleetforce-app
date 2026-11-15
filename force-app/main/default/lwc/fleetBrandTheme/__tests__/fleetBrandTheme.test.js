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
      hasCustomTheme: true,
      activeThemeId: "0S1Wm000000046rKAA",
      activeThemeName: "Fleetforce",
      activeThemeEditUrl:
        "/lightning/setup/ThemingAndBranding/0S1Wm000000046rKAA/edit",
      themesSetupUrl: "/lightning/setup/ThemingAndBranding/home",
      activeBrandColor: "#0176D3",
      activeBrandImageUrl: "/file-asset/fleetforce__lockuphorizontallight?v=1",
      overrideLoadingImage: true,
      canEdit: true
    })
  }),
  { virtual: true }
);

const MOCK_BRAND_SETTINGS = {
  iconStyle: "silhouette",
  hasCustomTheme: true,
  activeThemeId: "0S1Wm000000046rKAA",
  activeThemeName: "Fleetforce",
  activeThemeEditUrl:
    "/lightning/setup/ThemingAndBranding/0S1Wm000000046rKAA/edit",
  themesSetupUrl: "/lightning/setup/ThemingAndBranding/home",
  activeBrandColor: "#0176D3",
  activeBrandImageUrl: "/file-asset/fleetforce__lockuphorizontallight?v=1",
  overrideLoadingImage: true,
  canEdit: true
};

describe("c-fleet-brand-theme", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders 2 brand cards in overview mode with active custom theme", async () => {
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
    expect(headings[1]).toContain("Salesforce Themes & Branding");

    // Check active theme link and name
    const themeLink = element.shadowRoot.querySelector("a");
    expect(themeLink).not.toBeNull();
    expect(themeLink.textContent.trim()).toBe("Fleetforce");
    expect(themeLink.href).toContain(
      "/lightning/setup/ThemingAndBranding/0S1Wm000000046rKAA/edit"
    );

    // Check vehicle images rendered with icon variant and iconStyle
    const vehicleImages = element.shadowRoot.querySelectorAll(
      "c-fleet-vehicle-image"
    );
    expect(vehicleImages.length).toBe(3);
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

  it("opens theme edit and setup URLs when buttons are clicked", async () => {
    const windowOpenSpy = jest
      .spyOn(window, "open")
      .mockImplementation(() => {});

    const element = createElement("c-fleet-brand-theme", {
      is: FleetBrandTheme
    });
    document.body.appendChild(element);

    getBrandSettingsAdapter.emit(MOCK_BRAND_SETTINGS);
    await Promise.resolve();

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    const editThemeBtn = Array.from(buttons).find(
      (b) => b.label === "Edit Active Theme"
    );
    const openSetupBtn = Array.from(buttons).find(
      (b) => b.label === "Open Themes & Branding in Setup"
    );

    expect(editThemeBtn).toBeDefined();
    expect(openSetupBtn).toBeDefined();

    editThemeBtn.click();
    expect(windowOpenSpy).toHaveBeenCalledWith(
      "/lightning/setup/ThemingAndBranding/0S1Wm000000046rKAA/edit",
      "_blank"
    );

    openSetupBtn.click();
    expect(windowOpenSpy).toHaveBeenCalledWith(
      "/lightning/setup/ThemingAndBranding/home",
      "_blank"
    );

    windowOpenSpy.mockRestore();
  });
});
