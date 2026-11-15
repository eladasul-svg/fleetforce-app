import { createElement } from "@lwc/engine-dom";
import DriverRoute from "c/driverRoute";
import getTodayRoute from "@salesforce/apex/DriverRouteController.getTodayRoute";
import scanDocument from "@salesforce/apex/DriverRouteScanController.scanDocument";
import geocodeAddress from "@salesforce/apex/DriverRouteScanController.geocodeAddress";
import createScannedJob from "@salesforce/apex/DriverRouteScanController.createScannedJob";
import addVisitToRoute from "@salesforce/apex/DriverRouteScanController.addVisitToRoute";

jest.mock(
  "@salesforce/apex/DriverRouteController.getTodayRoute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DriverRouteScanController.scanDocument",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DriverRouteScanController.geocodeAddress",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DriverRouteScanController.createScannedJob",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DriverRouteScanController.addVisitToRoute",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const ROUTE = {
  id: "a0R1",
  name: "BSV-01 · Dana Levi",
  vehiclePayloadKg: 900,
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
      address: "Beer Sheva Center",
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

const SCAN_RESULT = {
  docType: "Delivery Note",
  docNumber: "SH26011985",
  bolNumber: "7998",
  orderNumber: "SO26007097",
  customerName: 'חוליות גפני בע"מ',
  destinationAddress: "נצרת שכונת הגליל (אתר 1625800)",
  destinationCity: "נצרת",
  contactName: "מחבר",
  contactPhone: "054-9230336",
  truckPlate: "28598703",
  cargoSummary: 'גלית 30/30/6 אפור · 237.6 מ"ר',
  weightKg: 32076,
  latitude: 32.7021,
  longitude: 35.3027,
  geocodedLabel: "Nazareth, Northern District, Israel",
  geocodeWarning: 'Matched broader location "נצרת". Verify pin before adding.'
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function mockPdfFile() {
  return new File(["%PDF-1.4"], "bol.pdf", {
    type: "application/pdf",
    lastModified: Date.now()
  });
}

describe("c-driver-route", () => {
  const OriginalFileReader = global.FileReader;

  beforeEach(() => {
    global.FileReader = class {
      readAsDataURL() {
        this.result = "data:application/pdf;base64,JVBERi0xLjQ=";
        if (this.onload) this.onload();
      }
    };
  });

  afterEach(() => {
    global.FileReader = OriginalFileReader;
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
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
    expect(text).toContain("Beer Sheva Center");
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

  it("scans a delivery PDF, previews extracted stop, re-geocodes, and adds to route", async () => {
    getTodayRoute.mockResolvedValue(ROUTE);
    scanDocument.mockResolvedValue(SCAN_RESULT);
    geocodeAddress.mockResolvedValue({
      latitude: 32.705,
      longitude: 35.305,
      label: "Nazareth Center",
      warning: null
    });
    createScannedJob.mockResolvedValue({
      jobId: "a0J1",
      visitId: "a0V1",
      contentVersionId: "0681"
    });
    addVisitToRoute.mockResolvedValue({
      routeId: "a0R1",
      assigned: true,
      revision: 2
    });

    const el = mount("003D1");
    await flush();

    const fileInput = el.shadowRoot.querySelector("input.scan-input");
    Object.defineProperty(fileInput, "files", {
      value: [mockPdfFile()],
      configurable: true
    });
    fileInput.dispatchEvent(new CustomEvent("change"));
    await flush();
    await flush();

    expect(scanDocument).toHaveBeenCalledWith({
      base64Data: "JVBERi0xLjQ=",
      mimeType: "application/pdf",
      fileName: "bol.pdf"
    });

    const sheet = el.shadowRoot.querySelector("section.sheet");
    expect(sheet).not.toBeNull();
    expect(sheet.textContent).toContain("Confirm delivery stop");
    expect(sheet.textContent).toContain("exceeds vehicle capacity (900 kg)");

    // Weight input should be left blank when over vehicle capacity
    const loadInput = sheet.querySelector('input[data-field="loadKg"]');
    expect(loadInput.value).toBe("");

    // Re-geocode after editing destination
    const addrInput = sheet.querySelector(
      'input[data-field="destinationAddress"]'
    );
    addrInput.value = "נצרת מרכז";
    addrInput.dispatchEvent(new CustomEvent("input"));
    sheet.querySelector("button.link-btn").click();
    await flush();

    expect(geocodeAddress).toHaveBeenCalledWith({
      address: "נצרת מרכז",
      city: "נצרת"
    });

    // Confirm and add to route
    sheet.querySelector("footer.sheet__foot button.btn").click();
    await flush();
    await flush();

    expect(createScannedJob).toHaveBeenCalled();
    expect(addVisitToRoute).toHaveBeenCalledWith({
      routeId: "a0R1",
      visitId: "a0V1"
    });
    expect(el.shadowRoot.querySelector("section.sheet")).toBeNull();
    expect(el.shadowRoot.textContent).toContain("Stop added · route updated");
  });

  it("shows scan errors, validation errors, and unassigned warnings", async () => {
    getTodayRoute.mockResolvedValue({ ...ROUTE, vehiclePayloadKg: null });
    scanDocument.mockRejectedValue({
      body: { message: "Vision parse failed" }
    });

    const el = mount("003D1");
    await flush();

    const fileInput = el.shadowRoot.querySelector("input.scan-input");
    Object.defineProperty(fileInput, "files", {
      value: [mockPdfFile()],
      configurable: true
    });
    fileInput.dispatchEvent(new CustomEvent("change"));
    await flush();
    await flush();

    expect(el.shadowRoot.textContent).toContain("Vision parse failed");

    // Now return a result missing coordinates and validate sheet error
    scanDocument.mockResolvedValue({
      ...SCAN_RESULT,
      latitude: null,
      longitude: null
    });
    Object.defineProperty(fileInput, "files", {
      value: [mockPdfFile()],
      configurable: true
    });
    fileInput.dispatchEvent(new CustomEvent("change"));
    await flush();
    await flush();

    const sheet = el.shadowRoot.querySelector("section.sheet");
    expect(sheet.querySelector('input[data-field="loadKg"]').value).toBe(
      "32076"
    );
    sheet.querySelector("footer.sheet__foot button.btn").click();
    await flush();
    expect(sheet.textContent).toContain(
      "Valid latitude and longitude are required."
    );

    // Fill coords and test unassigned warning
    const latInput = sheet.querySelector('input[data-field="latitude"]');
    latInput.value = "32.7";
    latInput.dispatchEvent(new CustomEvent("input"));
    const lonInput = sheet.querySelector('input[data-field="longitude"]');
    lonInput.value = "35.3";
    lonInput.dispatchEvent(new CustomEvent("input"));

    createScannedJob.mockResolvedValue({ jobId: "a0J2", visitId: "a0V2" });
    addVisitToRoute.mockResolvedValue({
      routeId: "a0R1",
      assigned: false,
      unassignedReason: "no_room"
    });

    sheet.querySelector("footer.sheet__foot button.btn").click();
    await flush();
    await flush();
    expect(el.shadowRoot.textContent).toContain("could not fit on the route");
  });
});
