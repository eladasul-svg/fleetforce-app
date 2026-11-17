import { createElement } from "lwc";
import FleetGeneralSettings from "c/fleetGeneralSettings";
import { registerApexTestWireAdapter } from "@salesforce/sfdx-lwc-jest";
import getGeneralSettings from "@salesforce/apex/FleetDisplaySettingsController.getGeneralSettings";

const getGeneralSettingsAdapter =
  registerApexTestWireAdapter(getGeneralSettings);

jest.mock(
  "@salesforce/apex/FleetDisplaySettingsController.saveGeneralSettings",
  () => ({
    default: jest.fn().mockResolvedValue({
      enableAiInsights: true,
      aiProvider: "Google Gemini",
      enableExtendedPrivacy: true,
      autoCreateDtcTickets: true,
      maintenanceGraceDays: 14,
      odometerDriftThreshold: 5,
      telemetryRetentionDays: 90,
      hasGoogleKey: true,
      hasAnthropicKey: false,
      hasOpenAiKey: false,
      maskedGoogleKey: "AIzaSy••••••••",
      maskedAnthropicKey: "",
      maskedOpenAiKey: "",
      canEdit: true
    })
  }),
  { virtual: true }
);

const MOCK_SETTINGS = {
  enableAiInsights: true,
  aiProvider: "Google Gemini",
  enableExtendedPrivacy: false,
  autoCreateDtcTickets: true,
  maintenanceGraceDays: 14,
  odometerDriftThreshold: 5,
  telemetryRetentionDays: 90,
  hasGoogleKey: true,
  hasAnthropicKey: false,
  hasOpenAiKey: false,
  maskedGoogleKey: "AIzaSy••••••••",
  maskedAnthropicKey: "",
  maskedOpenAiKey: "",
  canEdit: true
};

describe("c-fleet-general-settings", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders 4 modular settings cards in overview mode", async () => {
    const element = createElement("c-fleet-general-settings", {
      is: FleetGeneralSettings
    });
    document.body.appendChild(element);

    getGeneralSettingsAdapter.emit(MOCK_SETTINGS);
    await Promise.resolve();

    const cards = element.shadowRoot.querySelectorAll(".setting-card");
    expect(cards.length).toBe(5);

    const headings = Array.from(cards).map(
      (c) => c.querySelector("h3").textContent
    );
    expect(headings[0]).toContain("AI Foundation Models");
    expect(headings[1]).toContain("Digital Data Sanitization Protocol");
    expect(headings[2]).toContain("Maintenance & Work Order Automation");
    expect(headings[3]).toContain("Telemetry Drift & Data Governance");
    expect(headings[4]).toContain("Driver App & Field Experience");
  });

  it("toggles independent edit mode when clicking Configure AI Keys", async () => {
    const element = createElement("c-fleet-general-settings", {
      is: FleetGeneralSettings
    });
    document.body.appendChild(element);

    getGeneralSettingsAdapter.emit(MOCK_SETTINGS);
    await Promise.resolve();

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    const aiConfigBtn = Array.from(buttons).find(
      (b) => b.label === "Configure AI Keys"
    );
    expect(aiConfigBtn).toBeDefined();

    aiConfigBtn.click();
    await Promise.resolve();

    const editBadge = element.shadowRoot.querySelector(
      ".slds-badge.slds-theme_warning"
    );
    expect(editBadge).not.toBeNull();
    expect(editBadge.textContent).toBe("Editing Keys");
  });
});
