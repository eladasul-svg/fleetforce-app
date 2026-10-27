import { createElement } from "@lwc/engine-dom";
import FleetExposure from "c/fleetExposure";
import getSummary from "@salesforce/apex/FleetExposureController.getSummary";
import getNotices from "@salesforce/apex/FleetExposureController.getNotices";
import getAffectedVehicles from "@salesforce/apex/FleetExposureController.getAffectedVehicles";
import getSourceHealth from "@salesforce/apex/FleetExposureController.getSourceHealth";

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
const ShowToastEventName = "lightning__showtoast";

jest.mock(
  "@salesforce/apex/FleetExposureController.getSummary",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FleetExposureController.getNotices",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FleetExposureController.getAffectedVehicles",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FleetExposureController.getSourceHealth",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const SUMMARY = {
  openByType: [
    { alertType: "Data gap", count: 17 },
    { alertType: "Recall", count: 13 },
    { alertType: "Regulation", count: 20 }
  ],
  openAlerts: 50,
  vehiclesAtRisk: 6,
  newNotices7d: 2,
  averageHealth: 86,
  scoredVehicles: 60,
  isSample: true,
  lists: {
    gap: { objectApiName: "Asset_Alert__c", listViewId: "00B000000000001" },
    rcl: { objectApiName: "Asset_Alert__c", listViewId: "00B000000000002" },
    reg: { objectApiName: "Asset_Alert__c", listViewId: "00B000000000003" },
    risk: { objectApiName: "Fleet_Asset__c", listViewId: "00B000000000004" },
    new: { objectApiName: "External_Notice__c", listViewId: "00B000000000005" },
    avg: { objectApiName: "Fleet_Asset__c", listViewId: "00B000000000006" }
  }
};

const NOTICES = [
  {
    id: "n1",
    title: "Ford F-150: rear axle bolt (sample)",
    noticeType: "Recall",
    source: "Manufacturer recall (sample)",
    jurisdiction: null,
    effectiveOn: "2026-11-27",
    affectedCount: 9,
    status: "Active",
    reviewed: true
  },
  {
    id: "n2",
    title: "Low-emission zone (sample)",
    noticeType: "Regulation",
    source: "Regulation digest (sample)",
    jurisdiction: "PT;ES;FR",
    effectiveOn: "2026-12-12",
    affectedCount: 4,
    status: "Active",
    reviewed: true
  },
  {
    id: "n3",
    title: "Driver documents (sample)",
    noticeType: "Regulation",
    source: "Regulation digest (sample)",
    jurisdiction: "PT;ES;IT",
    effectiveOn: "2027-01-26",
    affectedCount: 16,
    status: "Draft",
    reviewed: false
  }
];

const SOURCES = [
  {
    id: "src1",
    name: "Telematics vendor (sample)",
    referenceUrl: "https://telematics.example.com",
    streams: 180,
    stale: 27,
    staleShare: 15
  },
  {
    id: "src2",
    name: "FMC maintenance file (sample)",
    referenceUrl: null,
    streams: 4,
    stale: 2,
    staleShare: 50
  }
];

const VEHICLES = [
  {
    alertId: "al1",
    assetId: "a01",
    assetName: "2023 Ford F-150 Lariat 4WD",
    licensePlate: "AA-11-BB",
    country: "PT",
    healthScore: 45,
    healthStatus: "At risk",
    alertStatus: "New",
    dueDate: "2026-11-27"
  },
  {
    alertId: "al2",
    assetId: "a02",
    assetName: "2024 Ford F-150 STX 4WD",
    licensePlate: "CC-22-DD",
    country: "PT",
    healthScore: null,
    healthStatus: null,
    alertStatus: "Acknowledged",
    dueDate: "2026-11-27"
  }
];

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function mount() {
  const el = createElement("c-fleet-exposure", { is: FleetExposure });
  document.body.appendChild(el);
  await flush();
  return el;
}

function mockAll() {
  getSummary.mockResolvedValue(SUMMARY);
  getNotices.mockResolvedValue(NOTICES);
  getSourceHealth.mockResolvedValue(SOURCES);
  getAffectedVehicles.mockResolvedValue(VEHICLES);
}

describe("c-fleet-exposure", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("shows the KPI tiles and the sample banner", async () => {
    mockAll();
    const el = await mount();

    const values = [...el.shadowRoot.querySelectorAll(".tile-value")].map(
      (n) => n.textContent
    );
    expect(values).toEqual(["17", "13", "20", "6", "2", "86"]);
    expect(el.shadowRoot.querySelector(".tile-sub").textContent).toBe(
      "60 vehicles scored"
    );
    expect(el.shadowRoot.querySelector(".sample-banner").textContent).toContain(
      "Sample data set"
    );
  });

  it("opens the list view behind a tile when it is clicked", async () => {
    mockAll();
    const el = await mount();

    const tiles = el.shadowRoot.querySelectorAll("button.tile_link");
    expect(tiles.length).toBe(6);
    el.shadowRoot.querySelector('button.tile_link[data-key="reg"]').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__objectPage",
      attributes: { objectApiName: "Asset_Alert__c", actionName: "list" },
      state: { filterName: "00B000000000003" }
    });
  });

  it("keeps tiles as plain text when no list view is available", async () => {
    getSummary.mockResolvedValue({ ...SUMMARY, lists: {} });
    getNotices.mockResolvedValue(NOTICES);
    getSourceHealth.mockResolvedValue(SOURCES);
    const el = await mount();

    expect(el.shadowRoot.querySelectorAll("button.tile_link").length).toBe(0);
    expect(el.shadowRoot.querySelectorAll(".tile").length).toBe(6);
  });

  it("lists every notice and filters by type, jurisdiction and status", async () => {
    mockAll();
    const el = await mount();
    const table = () => el.shadowRoot.querySelector("lightning-datatable");
    expect(table().data).toHaveLength(3);
    expect(table().data[2].statusText).toBe("Draft");

    const [type, jurisdiction, status] =
      el.shadowRoot.querySelectorAll("lightning-combobox");
    expect(jurisdiction.options.map((o) => o.value)).toEqual([
      "",
      "ES",
      "FR",
      "IT",
      "PT"
    ]);

    type.dispatchEvent(
      new CustomEvent("change", { detail: { value: "Regulation" } })
    );
    type.value = "Regulation";
    type.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(table().data.map((n) => n.id)).toEqual(["n2", "n3"]);

    jurisdiction.value = "FR";
    jurisdiction.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(table().data.map((n) => n.id)).toEqual(["n2"]);

    el.shadowRoot.querySelector(".filters-clear").click();
    await flush();
    status.value = "Draft";
    status.dispatchEvent(new CustomEvent("change"));
    await flush();
    expect(table().data.map((n) => n.id)).toEqual(["n3"]);
  });

  it("treats a notice without jurisdiction as applying everywhere", async () => {
    mockAll();
    const el = await mount();
    const jurisdiction =
      el.shadowRoot.querySelectorAll("lightning-combobox")[1];
    jurisdiction.value = "IT";
    jurisdiction.dispatchEvent(new CustomEvent("change"));
    await flush();
    const ids = el.shadowRoot
      .querySelector("lightning-datatable")
      .data.map((n) => n.id);
    expect(ids).toEqual(["n1", "n3"]);
  });

  it("drills into a notice and lists its affected vehicles, with the possible-match note for recalls", async () => {
    mockAll();
    const el = await mount();

    el.shadowRoot.querySelector("lightning-datatable").dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "drill" }, row: NOTICES[0] }
      })
    );
    await flush();

    expect(getAffectedVehicles).toHaveBeenCalledWith({ noticeId: "n1" });
    expect(el.shadowRoot.querySelector(".possible").textContent).toContain(
      "Confirm each vehicle by VIN"
    );
    const tables = el.shadowRoot.querySelectorAll("lightning-datatable");
    expect(tables).toHaveLength(2);
    const rows = tables[1].data;
    expect(rows[0].assetUrl).toBe("/a01");
    expect(rows[0].healthText).toBe("45 At risk");
    expect(rows[0].healthIcon).toBe("utility:error");
    expect(rows[1].healthText).toBe("Not scored");

    // close
    const buttons = el.shadowRoot.querySelectorAll(".drill lightning-button");
    buttons[1].click();
    await flush();
    expect(el.shadowRoot.querySelectorAll("lightning-datatable")).toHaveLength(
      1
    );
  });

  it("does not show the possible-match note for a regulation, and shows an empty drill-down", async () => {
    mockAll();
    getAffectedVehicles.mockResolvedValue([]);
    const el = await mount();
    el.shadowRoot.querySelector("lightning-datatable").dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "drill" }, row: NOTICES[2] }
      })
    );
    await flush();
    expect(el.shadowRoot.querySelector(".possible")).toBeNull();
    expect(el.shadowRoot.querySelector(".drill").textContent).toContain(
      "No vehicles match this notice"
    );
  });

  it("shows data health by source with text, not colour alone", async () => {
    mockAll();
    const el = await mount();
    const sources = el.shadowRoot.querySelectorAll(".source");
    expect(sources).toHaveLength(2);
    expect(sources[0].textContent).toContain(
      "27 of 180 streams stale or missing (15%)"
    );
    expect(sources[0].querySelector(".chip").textContent.trim()).toBe("OK");
    expect(sources[1].querySelector(".chip").textContent.trim()).toBe(
      "Needs attention"
    );
    expect(sources[0].querySelector("a").href).toBe(
      "https://telematics.example.com/"
    );
    expect(sources[1].querySelector("a")).toBeNull();
  });

  it("shows empty states when there are no notices or sources", async () => {
    getSummary.mockResolvedValue({
      ...SUMMARY,
      isSample: false,
      averageHealth: null,
      scoredVehicles: 0
    });
    getNotices.mockResolvedValue([]);
    getSourceHealth.mockResolvedValue([]);
    const el = await mount();
    expect(el.shadowRoot.querySelector(".sample-banner")).toBeNull();
    expect(el.shadowRoot.textContent).toContain("No notices");
    expect(el.shadowRoot.textContent).toContain("No data sources linked yet");
    const values = [...el.shadowRoot.querySelectorAll(".tile-value")].map(
      (n) => n.textContent
    );
    expect(values[5]).toBe("–");
  });

  it("shows an error state and a toast when loading fails", async () => {
    getSummary.mockRejectedValue({ body: { message: "Boom" } });
    getNotices.mockResolvedValue([]);
    getSourceHealth.mockResolvedValue([]);
    const toast = jest.fn();
    const el = createElement("c-fleet-exposure", { is: FleetExposure });
    el.addEventListener(ShowToastEventName, toast);
    document.body.appendChild(el);
    await flush();
    expect(el.shadowRoot.querySelector(".state").textContent).toContain("Boom");
    expect(el.shadowRoot.querySelector(".tiles")).toBeNull();
    expect(toast).toHaveBeenCalled();
  });

  it("reloads on refresh and keeps the open drill-down", async () => {
    mockAll();
    const el = await mount();
    el.shadowRoot.querySelector("lightning-datatable").dispatchEvent(
      new CustomEvent("rowaction", {
        detail: { action: { name: "drill" }, row: NOTICES[0] }
      })
    );
    await flush();
    el.shadowRoot.querySelector("lightning-button-icon").click();
    await flush();
    expect(getSummary).toHaveBeenCalledTimes(2);
    expect(getAffectedVehicles).toHaveBeenCalledTimes(2);
    expect(el.shadowRoot.querySelectorAll("lightning-datatable")).toHaveLength(
      2
    );
  });
});
