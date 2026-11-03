import { createElement } from "@lwc/engine-dom";
import RoutePlanBoard from "c/routePlanBoard";
import getBoard from "@salesforce/apex/RoutePlanController.getBoard";
import optimize from "@salesforce/apex/RoutePlanController.optimize";
import publish from "@salesforce/apex/RoutePlanController.publish";
import { subscribe } from "lightning/empApi";

jest.mock(
  "@salesforce/apex/RoutePlanController.getBoard",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RoutePlanController.optimize",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/RoutePlanController.publish",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
jest.mock(
  "lightning/empApi",
  () => ({
    subscribe: jest.fn(() => Promise.resolve({ id: "sub" })),
    unsubscribe: jest.fn(),
    onError: jest.fn()
  }),
  { virtual: true }
);

const BOARD = {
  planId: "a0P000000000001",
  name: "Beer Sheva · morning",
  status: "Optimized",
  depot: "Beer Sheva Depot",
  revision: 1,
  totalDistanceKm: 42.5,
  totalDurationMin: 380,
  unassignedCount: 1,
  canOptimize: true,
  canPublish: true,
  channel: "/event/Route_Plan_Update__e",
  routes: [
    {
      id: "a0R000000000001",
      name: "BSV-01 · Dana Levi",
      vehicle: "BSV-01",
      driver: "Dana Levi",
      plannedStart: "2026-11-04T05:00:00.000Z",
      plannedEnd: "2026-11-04T11:00:00.000Z",
      distanceKm: 21.3,
      jobStops: 2,
      stops: [
        {
          id: "w1",
          sequence: 1,
          type: "Start",
          latitude: 31.25,
          longitude: 34.79,
          jobs: []
        },
        {
          id: "w2",
          sequence: 2,
          type: "Job Stop",
          latitude: 31.26,
          longitude: 34.8,
          eta: "2026-11-04T05:20:00.000Z",
          jobs: ["JOB-00001"],
          locked: true
        },
        {
          id: "w3",
          sequence: 3,
          type: "Charge",
          latitude: 31.26,
          longitude: 34.8,
          jobs: []
        },
        {
          id: "w4",
          sequence: 4,
          type: "Job Stop",
          latitude: 31.27,
          longitude: 34.81,
          jobs: ["JOB-00002"],
          lateMinutes: 12
        },
        {
          id: "w5",
          sequence: 5,
          type: "End",
          latitude: 31.25,
          longitude: 34.79,
          jobs: []
        }
      ]
    },
    {
      id: "a0R000000000002",
      name: "BSV-02 · Yossi Cohen",
      stops: [
        {
          id: "w6",
          sequence: 2,
          type: "Job Stop",
          latitude: 31.24,
          longitude: 34.78,
          jobs: ["JOB-00003"]
        }
      ]
    }
  ],
  unassigned: [
    {
      id: "a0J000000000009",
      name: "JOB-00009",
      reason: "skills: No vehicle has the skill(s): Refrigerated."
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe("c-route-plan-board", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  function mount() {
    const el = createElement("c-route-plan-board", { is: RoutePlanBoard });
    el.recordId = BOARD.planId;
    document.body.appendChild(el);
    return el;
  }

  it("renders KPIs, routes, stops and unassigned jobs", async () => {
    const el = mount();
    getBoard.emit(BOARD);
    await flush();
    const text = el.shadowRoot.textContent;
    expect(text).toContain("42.5");
    expect(text).toContain("BSV-01 · Dana Levi");
    expect(text).toContain("JOB-00001");
    expect(text).toContain("Charge");
    expect(text).toContain("Locked");
    expect(text).toContain("12 min late");
    expect(text).toContain("Refrigerated");
    expect(el.shadowRoot.querySelectorAll("section.route")).toHaveLength(2);
    // The start is not listed as a stop.
    expect(el.shadowRoot.querySelectorAll("li.stop")).toHaveLength(5);
    const map = el.shadowRoot.querySelector("lightning-map");
    expect(map.mapMarkers).toHaveLength(5);
    expect(subscribe).toHaveBeenCalledWith(
      "/event/Route_Plan_Update__e",
      -1,
      expect.any(Function)
    );
  });

  it("filters the map to the selected route", async () => {
    const el = mount();
    getBoard.emit(BOARD);
    await flush();
    el.shadowRoot.querySelector('section[data-id="a0R000000000002"]').click();
    await flush();
    expect(
      el.shadowRoot.querySelector("lightning-map").mapMarkers
    ).toHaveLength(1);
    expect(el.shadowRoot.querySelector("section.route--on")).not.toBeNull();
  });

  it("optimizes and publishes", async () => {
    optimize.mockResolvedValue("707000000000001");
    publish.mockResolvedValue();
    const el = mount();
    getBoard.emit(BOARD);
    await flush();
    const toasts = [];
    el.addEventListener("lightning__showtoast", (e) => toasts.push(e.detail));
    el.shadowRoot.querySelector('lightning-button[data-id="optimize"]').click();
    await flush();
    expect(optimize).toHaveBeenCalledWith({ planId: BOARD.planId });
    el.shadowRoot.querySelector('lightning-button[data-id="publish"]').click();
    await flush();
    expect(publish).toHaveBeenCalledWith({ planId: BOARD.planId });
    expect(toasts.map((t) => t.variant)).toEqual(["success", "success"]);
  });

  it("shows server errors as a toast and on the card", async () => {
    optimize.mockRejectedValue({
      body: { message: "No vehicle at the depot can be routed." }
    });
    const el = mount();
    getBoard.emit({
      ...BOARD,
      routes: [],
      unassigned: [],
      status: "Draft",
      revision: 0,
      error: "boom",
      canPublish: false
    });
    await flush();
    expect(el.shadowRoot.textContent).toContain(
      "Last optimization failed: boom"
    );
    expect(el.shadowRoot.textContent).toContain("No routes yet");
    const toasts = [];
    el.addEventListener("lightning__showtoast", (e) => toasts.push(e.detail));
    el.shadowRoot.querySelector('lightning-button[data-id="optimize"]').click();
    await flush();
    expect(toasts[0].variant).toBe("error");
    expect(toasts[0].message).toContain("No vehicle");
  });

  it("shows a load error", async () => {
    const el = mount();
    getBoard.error({ message: "Insufficient access" });
    await flush();
    expect(el.shadowRoot.querySelector(".error")).not.toBeNull();
  });
});
