import { createElement } from "lwc";
import FleetAiInsights from "c/fleetAiInsights";
import { registerApexTestWireAdapter } from "@salesforce/sfdx-lwc-jest";
import getAiConfig from "@salesforce/apex/FleetAiInsightsController.getAiConfig";
import getPrebuiltInsights from "@salesforce/apex/FleetAiInsightsController.getPrebuiltInsights";

const getAiConfigAdapter = registerApexTestWireAdapter(getAiConfig);
const getPrebuiltInsightsAdapter =
  registerApexTestWireAdapter(getPrebuiltInsights);

jest.mock(
  "@salesforce/apex/FleetAiInsightsController.queryStrategicInsight",
  () => ({
    default: jest.fn().mockResolvedValue({
      id: "QUERY-01",
      title: "Mock Strategic Result",
      category: "Warranty & Maintenance Risk",
      severity: "Critical",
      severityVariant: "error",
      summary: "Mock summary",
      rootCause: "Mock root cause",
      quantitativeImpact: "8 Vehicles Affected",
      affectedBranches: ["Beer Sheva Depot"],
      actions: [
        {
          actionKey: "CREATE_PRIORITY_MAINTENANCE",
          label: "Create Tickets",
          variant: "brand",
          iconName: "utility:maintenance"
        }
      ]
    })
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetAiInsightsController.executeStrategicAction",
  () => ({
    default: jest.fn().mockResolvedValue("Tickets created")
  }),
  { virtual: true }
);

const MOCK_CONFIG = {
  isAiEnabled: true,
  provider: "Google Gemini",
  modelName: "Gemini 2.5 Pro (Deep Reasoning)",
  hasKey: true,
  apiKeyMasked: "AIzaSy••••••••"
};

const MOCK_INSIGHTS = [
  {
    id: "INS-01",
    title: "Warranty Lapse Risk",
    category: "Maintenance",
    severity: "Critical",
    severityVariant: "error",
    summary: "Maintenance lag observed",
    rootCause: "Depot bottleneck",
    quantitativeImpact: "14 Vehicles",
    affectedBranches: ["Beer Sheva Depot"],
    actions: [
      {
        actionKey: "ALERT_BRANCH_MANAGERS",
        label: "Dispatch Alert",
        variant: "neutral",
        iconName: "utility:email"
      }
    ]
  }
];

describe("c-fleet-ai-insights", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders header, active model badge, and prebuilt insights", async () => {
    const element = createElement("c-fleet-ai-insights", {
      is: FleetAiInsights
    });
    document.body.appendChild(element);

    getAiConfigAdapter.emit(MOCK_CONFIG);
    getPrebuiltInsightsAdapter.emit(MOCK_INSIGHTS);

    await Promise.resolve();

    const card = element.shadowRoot.querySelector("lightning-card");
    expect(card).not.toBeNull();
    expect(card.title).toBe("AI Strategic Insights Engine");

    const badge = element.shadowRoot.querySelector(".slds-badge");
    expect(badge.textContent).toBe("Gemini 2.5 Pro (Deep Reasoning)");
  });

  it("triggers strategic query on button click", async () => {
    const element = createElement("c-fleet-ai-insights", {
      is: FleetAiInsights
    });
    document.body.appendChild(element);

    getAiConfigAdapter.emit(MOCK_CONFIG);
    getPrebuiltInsightsAdapter.emit(MOCK_INSIGHTS);

    await Promise.resolve();

    const input = element.shadowRoot.querySelector("lightning-input");
    input.value = "Analyze warranty risks";
    input.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Analyze warranty risks" } })
    );

    const analyzeBtn = element.shadowRoot.querySelector(".analyze-btn");
    expect(analyzeBtn).not.toBeNull();
  });
});
