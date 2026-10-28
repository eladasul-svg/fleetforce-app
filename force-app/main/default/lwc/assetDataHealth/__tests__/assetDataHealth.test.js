import { createElement } from "@lwc/engine-dom";
import AssetDataHealth from "c/assetDataHealth";
import getHealth from "@salesforce/apex/AssetDataHealthController.getHealth";
import refreshHealth from "@salesforce/apex/AssetDataHealthController.refreshHealth";
import setAlertStatus from "@salesforce/apex/AssetDataHealthController.setAlertStatus";
import { encodeDefaultFieldValues } from "lightning/pageReferenceUtils";
const ShowToastEventName = "lightning__showtoast";

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
  "@salesforce/apex/AssetDataHealthController.getHealth",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AssetDataHealthController.refreshHealth",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/AssetDataHealthController.setAlertStatus",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const AT_RISK = {
  assetId: "a0C000000000001",
  score: 45,
  status: "At risk",
  freshness: 25,
  completeness: 75,
  consistency: 25,
  calculatedOn: "2026-10-28T08:00:00.000Z",
  profileName: "Standard",
  isSample: true,
  streams: [
    {
      id: "s1",
      sourceName: "Geotab telematics",
      sourceType: "Telematics",
      vendorAccountId: "001000000000001",
      vendorName: "Geotab",
      dataType: "Location",
      lastUpdate: "2026-10-19T08:00:00.000Z",
      status: "Stale",
      signals: 2,
      referenceUrl: "https://telematics.example.com/vehicles/TEL-1"
    },
    {
      id: "s2",
      sourceName: "Fuel card feed (sample)",
      dataType: "Fuel or charge",
      lastUpdate: null,
      status: "Missing",
      signals: 0
    }
  ],
  // as the server sends them: open alerts first, most severe first, then closed ones
  alerts: [
    {
      id: "al2",
      alertType: "Recall",
      severity: "Critical",
      status: "New",
      title: "Possible recall: airbag",
      dueDate: "2026-11-11",
      isOpen: true
    },
    {
      id: "al1",
      alertType: "Data gap",
      severity: "Medium",
      status: "Acknowledged",
      title: "Odometer data is stale",
      isOpen: true
    },
    {
      id: "al3",
      alertType: "Regulation",
      severity: "Low",
      status: "Resolved",
      title: "Digital driver documents",
      resolvedOn: "2026-10-27T10:00:00.000Z",
      isOpen: false
    }
  ]
};

const EMPTY = {
  assetId: "a0C000000000002",
  isSample: false,
  streams: [],
  alerts: []
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function mount() {
  const el = createElement("c-asset-data-health", { is: AssetDataHealth });
  el.recordId = "a0C000000000001";
  document.body.appendChild(el);
  await flush();
  return el;
}

describe("c-asset-data-health", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows the score, its three parts and the band with text, not colour alone", async () => {
    getHealth.mockResolvedValue(AT_RISK);
    const el = await mount();

    expect(getHealth).toHaveBeenCalledWith({ assetId: "a0C000000000001" });
    expect(el.shadowRoot.querySelector(".gauge-value").textContent).toBe("45");
    expect(el.shadowRoot.querySelector(".band-label").textContent).toBe(
      "At risk"
    );
    expect(el.shadowRoot.querySelector(".band lightning-icon").iconName).toBe(
      "utility:error"
    );
    const parts = [...el.shadowRoot.querySelectorAll(".part-value")].map(
      (n) => n.textContent
    );
    expect(parts).toEqual(["25", "75", "25"]);
    expect(
      el.shadowRoot.querySelector(".gauge").getAttribute("aria-label")
    ).toContain("45 out of 100, At risk");
  });

  it("shows dates as relative times, never as raw strings", async () => {
    getHealth.mockResolvedValue(AT_RISK);
    const el = await mount();
    const times = [
      ...el.shadowRoot.querySelectorAll("lightning-relative-date-time")
    ].map((t) => t.value);
    expect(times).toEqual([
      Date.parse("2026-10-28T08:00:00.000Z"),
      Date.parse("2026-10-19T08:00:00.000Z"),
      Date.parse("2026-10-27T10:00:00.000Z")
    ]);
    expect(el.shadowRoot.querySelector(".sample-banner")).toBeNull();
  });

  it("links a stream's vendor to its account", async () => {
    getHealth.mockResolvedValue(AT_RISK);
    const el = await mount();
    const vendor = el.shadowRoot.querySelector('a[data-id="001000000000001"]');
    expect(vendor.textContent).toBe("Geotab");
    vendor.click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: { recordId: "001000000000001", actionName: "view" }
    });
  });

  it("lists streams with a status chip and a source link that opens in a new tab", async () => {
    getHealth.mockResolvedValue(AT_RISK);
    const el = await mount();

    const chips = [
      ...el.shadowRoot.querySelectorAll(".rows")[0].querySelectorAll(".chip")
    ];
    expect(chips.map((c) => c.textContent.trim())).toEqual([
      "Stale",
      "Missing"
    ]);
    expect(chips[0].className).toContain("chip_warn");
    const links = el.shadowRoot.querySelectorAll("a.source-link");
    expect(links).toHaveLength(1);
    expect(links[0].href).toBe("https://telematics.example.com/vehicles/TEL-1");
    expect(links[0].target).toBe("_blank");
    expect(links[0].rel).toContain("noopener");
  });

  it("shows every alert with its status, and actions only on open ones", async () => {
    getHealth.mockResolvedValue(AT_RISK);
    const el = await mount();

    const alertRows = el.shadowRoot.querySelectorAll("li.row_click");
    expect(alertRows).toHaveLength(3);
    const labels = (row) =>
      [...row.querySelectorAll("lightning-button")].map((b) => b.label);
    expect(labels(alertRows[0])).toEqual(["Create task", "Acknowledge"]);
    expect(labels(alertRows[1])).toEqual(["Create task"]);
    expect(labels(alertRows[2])).toEqual([]);
    expect(alertRows[2].className).toContain("row_closed");
    const statuses = [...alertRows].map((r) =>
      r.querySelector(".row-meta .chip").textContent.trim()
    );
    expect(statuses).toEqual(["New", "Acknowledged", "Resolved"]);
    expect(
      el.shadowRoot.querySelectorAll(".section-title")[1].textContent
    ).toBe("3 alerts, 2 open");
  });

  it("opens a new task on the alert from Create task", async () => {
    getHealth.mockResolvedValue(AT_RISK);
    encodeDefaultFieldValues.mockReturnValue("encoded");
    const el = await mount();

    el.shadowRoot.querySelector('lightning-button[data-action="task"]').click();
    expect(encodeDefaultFieldValues).toHaveBeenCalledWith({
      WhatId: "al2",
      Subject: "Follow up: Possible recall: airbag"
    });
    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__objectPage",
      attributes: { objectApiName: "Task", actionName: "new" },
      state: {
        defaultFieldValues: "encoded",
        navigationLocation: "RELATED_LIST"
      }
    });
  });

  it("acknowledges an alert and shows the updated result", async () => {
    getHealth.mockResolvedValue(AT_RISK);
    const updated = {
      ...AT_RISK,
      alerts: [
        { ...AT_RISK.alerts[0], status: "Acknowledged" },
        AT_RISK.alerts[1],
        AT_RISK.alerts[2]
      ]
    };
    setAlertStatus.mockResolvedValue(updated);
    const el = await mount();
    const toast = jest.fn();
    el.addEventListener(ShowToastEventName, toast);

    el.shadowRoot
      .querySelector('lightning-button[data-status="Acknowledged"]')
      .click();
    await flush();

    expect(setAlertStatus).toHaveBeenCalledWith({
      alertId: "al2",
      status: "Acknowledged"
    });
    expect(
      el.shadowRoot.querySelectorAll(
        'lightning-button[data-status="Acknowledged"]'
      )
    ).toHaveLength(0);
    expect(toast).toHaveBeenCalled();
  });

  it("recalculates on Refresh", async () => {
    getHealth.mockResolvedValue(AT_RISK);
    refreshHealth.mockResolvedValue({ ...AT_RISK, score: 50, freshness: 38 });
    const el = await mount();

    el.shadowRoot.querySelector("lightning-button-icon").click();
    await flush();

    expect(refreshHealth).toHaveBeenCalledWith({ assetId: "a0C000000000001" });
    expect(el.shadowRoot.querySelector(".gauge-value").textContent).toBe("50");
  });

  it("shows the empty state when no sources are linked", async () => {
    getHealth.mockResolvedValue(EMPTY);
    const el = await mount();

    expect(el.shadowRoot.querySelector(".state").textContent).toContain(
      "No data sources linked yet"
    );
    expect(el.shadowRoot.querySelector(".gauge")).toBeNull();
    expect(el.shadowRoot.querySelector(".sample-banner")).toBeNull();
  });

  it("shows an error state and a toast when loading fails", async () => {
    getHealth.mockRejectedValue({ body: { message: "Insufficient access" } });
    const toast = jest.fn();
    const el = createElement("c-asset-data-health", { is: AssetDataHealth });
    el.recordId = "a0C000000000001";
    el.addEventListener(ShowToastEventName, toast);
    document.body.appendChild(el);
    await flush();

    expect(el.shadowRoot.querySelector(".state_error").textContent).toContain(
      "Insufficient access"
    );
    expect(toast).toHaveBeenCalled();
    expect(toast.mock.calls[0][0].detail.variant).toBe("error");
  });

  it("shows a dash when the score has not been calculated", async () => {
    getHealth.mockResolvedValue({
      ...AT_RISK,
      score: null,
      status: null,
      calculatedOn: null,
      isSample: false
    });
    const el = await mount();
    expect(el.shadowRoot.querySelector(".gauge-value").textContent).toBe("–");
    expect(el.shadowRoot.querySelector(".band-label").textContent).toBe(
      "Not calculated"
    );
  });
});
