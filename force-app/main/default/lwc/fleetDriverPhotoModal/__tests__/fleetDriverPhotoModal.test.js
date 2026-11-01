import { createElement } from "@lwc/engine-dom";
import getDriverPhotos from "@salesforce/apex/FleetDriverController.getDriverPhotos";

const mockClose = jest.fn();
jest.mock(
  "lightning/modal",
  () => {
    const { LightningElement } = require("lwc");
    return {
      __esModule: true,
      default: class extends LightningElement {
        close(result) {
          mockClose(result);
        }
      }
    };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FleetDriverController.getDriverPhotos",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

// Imported after the lightning/modal mock so the component extends it.
const FleetDriverPhotoModal = require("c/fleetDriverPhotoModal").default;

const PHOTOS = [
  {
    documentId: "069000000000001",
    title: "Maya",
    url: "/sfc/servlet.shepherd/version/download/068000000000001"
  },
  {
    documentId: "069000000000002",
    title: "Maya 2023",
    url: "/sfc/servlet.shepherd/version/download/068000000000002"
  }
];

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function mount(props = {}) {
  const el = createElement("c-fleet-driver-photo-modal", {
    is: FleetDriverPhotoModal
  });
  Object.assign(
    el,
    { driverId: "003000000000001", driverName: "Maya Patel" },
    props
  );
  document.body.appendChild(el);
  return el;
}

describe("c-fleet-driver-photo-modal", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("lists the driver's images and marks the current photo", async () => {
    getDriverPhotos.mockResolvedValue(PHOTOS);
    const el = mount({ currentDocumentId: "069000000000002" });
    await flush();
    const tiles = el.shadowRoot.querySelectorAll(".tile");
    expect(tiles.length).toBe(2);
    expect(tiles[1].className).toContain("tile--current");
    expect(el.shadowRoot.querySelector("lightning-file-upload").recordId).toBe(
      "003000000000001"
    );
  });

  it("closes with the picked file", async () => {
    getDriverPhotos.mockResolvedValue(PHOTOS);
    const el = mount();
    await flush();
    el.shadowRoot.querySelectorAll(".tile")[0].click();
    expect(mockClose).toHaveBeenCalledWith({ documentId: "069000000000001" });
  });

  it("closes with the uploaded file", async () => {
    getDriverPhotos.mockResolvedValue([]);
    const el = mount();
    await flush();
    el.shadowRoot.querySelector("lightning-file-upload").dispatchEvent(
      new CustomEvent("uploadfinished", {
        detail: { files: [{ documentId: "069000000000009" }] }
      })
    );
    expect(mockClose).toHaveBeenCalledWith({ documentId: "069000000000009" });
  });

  it("offers Remove photo only when there is a photo", async () => {
    getDriverPhotos.mockResolvedValue([]);
    let el = mount();
    await flush();
    expect(el.shadowRoot.querySelector(".remove")).toBeNull();
    document.body.removeChild(el);

    el = mount({ currentDocumentId: "069000000000001" });
    await flush();
    el.shadowRoot.querySelector(".remove").click();
    expect(mockClose).toHaveBeenCalledWith({ remove: true });
  });
});
