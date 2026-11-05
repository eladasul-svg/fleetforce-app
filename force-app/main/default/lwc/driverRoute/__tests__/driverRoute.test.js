import { createElement } from "@lwc/engine-dom";
import DriverRoute from "c/driverRoute";
import getTodayRoute from "@salesforce/apex/DriverRouteController.getTodayRoute";

jest.mock(
  "@salesforce/apex/DriverRouteController.getTodayRoute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const ROUTE = {
  id: "a0R1",
  name: "BSV-01 · Dana Levi",
  remaining: 2,
  plannedEnd: "2026-11-04T11:00:00.000Z",
  stops: [
    {
      id: "w2",
      sequence: 2,
      type: "Job Stop",
      label: "JOB-00001",
      done: true,
      eta: "2026-11-04T05:20:00.000Z"
    },
    {
      id: "w3",
      sequence: 3,
      type: "Job Stop",
      label: "JOB-00002",
      accessNotes: "Back gate",
      latitude: 31.26,
      longitude: 34.8,
      eta: "2026-11-04T05:40:00.000Z",
      windowEnd: "2026-11-04T09:00:00.000Z"
    },
    {
      id: "w4",
      sequence: 4,
      type: "End",
      label: "Back to depot",
      eta: "2026-11-04T11:00:00.000Z"
    }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("c-driver-route", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  function mount(driverId) {
    const el = createElement("c-driver-route", { is: DriverRoute });
    el.timeZone = "Asia/Jerusalem";
    el.driverId = driverId;
    document.body.appendChild(el);
    return el;
  }

  it("shows the next stop with notes and a navigate link", async () => {
    getTodayRoute.mockResolvedValue(ROUTE);
    const el = mount("003D1");
    await flush();
    expect(getTodayRoute).toHaveBeenCalledWith({ driverId: "003D1" });
    const text = el.shadowRoot.textContent;
    expect(text).toContain("2 stops left");
    expect(text).toContain("JOB-00002");
    expect(text).toContain("Back gate");
    expect(text).toContain("by 11:00"); // 09:00Z is 11:00 in Israel in November
    expect(el.shadowRoot.querySelector("a.btn").href).toContain(
      "destination=31.26,34.8"
    );
    expect(el.shadowRoot.querySelectorAll("li.stop--done")).toHaveLength(1);
  });

  it("says when there is no route and when loading fails", async () => {
    getTodayRoute.mockResolvedValue(null);
    const el = mount("003D2");
    await flush();
    expect(el.shadowRoot.textContent).toContain("No route for you today");

    getTodayRoute.mockRejectedValue({ body: { message: "Nope" } });
    await el.load();
    await flush();
    expect(el.shadowRoot.textContent).toContain("Nope");
  });
});
