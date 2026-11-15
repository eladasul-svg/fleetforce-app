import { createElement } from "lwc";
import FleetIntegrationsHub from "c/fleetIntegrationsHub";
import { registerApexTestWireAdapter } from "@salesforce/sfdx-lwc-jest";
import getConnectors from "@salesforce/apex/FleetIntegrationsController.getConnectors";

const getConnectorsAdapter = registerApexTestWireAdapter(getConnectors);

jest.mock(
  "@salesforce/apex/FleetIntegrationsController.getConnectorDetails",
  () => ({
    default: jest.fn().mockResolvedValue({
      server: "https://my.geotab.com",
      database: "demo_db",
      username: "admin@fleetforce.com",
      hasPassword: true,
      frequencyHours: 1
    })
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetIntegrationsController.testConnection",
  () => ({
    default: jest.fn().mockResolvedValue({
      success: true,
      provider: "Geotab MyGeotab",
      latencyMs: 120,
      message: "Connected"
    })
  }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/FleetIntegrationsController.triggerSync",
  () => ({
    default: jest.fn().mockResolvedValue("Sync queued")
  }),
  { virtual: true }
);

const MOCK_CONNECTORS = [
  {
    id: "mock-1",
    key: "geotab",
    name: "Geotab MyGeotab",
    vendor: "Geotab",
    sourceType: "Telematics",
    status: "Active",
    statusVariant: "success",
    endpoint: "https://my.geotab.com",
    protocol: "JSON-RPC 2.0",
    totalStreams: 10,
    healthyStreams: 8,
    staleStreams: 2,
    monitoredAssets: 5,
    description: "Geotab telematics connector",
    capabilities: ["GPS", "Odometer"],
    isConfigured: true
  },
  {
    id: "mock-2",
    key: "samsara",
    name: "Samsara Cloud Gateway",
    vendor: "Samsara",
    sourceType: "Telematics",
    status: "Available",
    statusVariant: "inverse",
    endpoint: "https://api.samsara.com",
    protocol: "REST API v2",
    totalStreams: 0,
    healthyStreams: 0,
    staleStreams: 0,
    monitoredAssets: 0,
    description: "Samsara cloud connector",
    capabilities: ["Live GPS", "HOS"],
    isConfigured: false
  }
];

describe("c-fleet-integrations-hub", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("renders header and KPI metrics with wired connectors", async () => {
    const element = createElement("c-fleet-integrations-hub", {
      is: FleetIntegrationsHub
    });
    document.body.appendChild(element);

    getConnectorsAdapter.emit(MOCK_CONNECTORS);

    await Promise.resolve();

    const card = element.shadowRoot.querySelector("lightning-card");
    expect(card).not.toBeNull();
    expect(card.title).toBe("Telematics Connectors & Integrations");

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    expect(buttons.length).toBeGreaterThan(0);
  });
});
