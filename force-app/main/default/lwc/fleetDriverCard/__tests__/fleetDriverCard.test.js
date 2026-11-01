import { createElement } from "@lwc/engine-dom";
import FleetDriverCard from "c/fleetDriverCard";
import { getRecord } from "lightning/uiRecordApi";
import getDriverCard from "@salesforce/apex/FleetDriverController.getDriverCard";
import setDriverPhoto from "@salesforce/apex/FleetDriverController.setDriverPhoto";
import PhotoModal from "c/fleetDriverPhotoModal";

jest.mock(
  "@salesforce/apex/FleetDriverController.setDriverPhoto",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock("c/fleetDriverPhotoModal", () => ({
  __esModule: true,
  default: { open: jest.fn() }
}));

jest.mock(
  "@salesforce/apex/FleetDriverController.getDriverCard",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const ASSET_WITH_DRIVER = {
  fields: { fleetforce__Driver__c: { value: "003000000000001" } }
};
const ASSET_WITHOUT_DRIVER = {
  fields: { fleetforce__Driver__c: { value: null } }
};

const CARD = {
  id: "003000000000001",
  name: "Maya Patel",
  initials: "MP",
  title: "Delivery Courier",
  status: "Active",
  branchName: "London Hub",
  mobile: "+44 7700 900302",
  email: "maya.patel@example.com",
  licenseNumber: "PATEL905153MA9",
  licenseClass: "None",
  licenseExpiry: "2020-01-31",
  safetyScore: 92,
  qualificationsExpired: 1,
  qualificationsExpiringSoon: 2
};

function mount() {
  const el = createElement("c-fleet-driver-card", { is: FleetDriverCard });
  el.recordId = "a0C000000000001";
  document.body.appendChild(el);
  return el;
}

const flush = () => Promise.resolve();

describe("c-fleet-driver-card", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
    jest.clearAllMocks();
  });

  it("shows nothing when the vehicle has no driver", async () => {
    const el = mount();
    getRecord.emit(ASSET_WITHOUT_DRIVER);
    await flush();
    expect(el.shadowRoot.querySelector("article")).toBeNull();
  });

  it("shows the driver with initials, branch, contact details, license and warnings", async () => {
    const el = mount();
    getRecord.emit(ASSET_WITH_DRIVER);
    getDriverCard.emit(CARD);
    await flush();

    const root = el.shadowRoot;
    expect(root.querySelector(".title").textContent).toBe("Maya Patel");
    expect(root.querySelector(".avatar__initials").textContent).toBe("MP");
    expect(root.querySelector(".pill--active").textContent).toBe("Active");

    const contacts = [...root.querySelectorAll(".contact__item")].map((a) =>
      a.getAttribute("href")
    );
    expect(contacts).toEqual([
      "tel:+44 7700 900302",
      "mailto:maya.patel@example.com"
    ]);

    const facts = Object.fromEntries(
      [...root.querySelectorAll(".facts__item")].map((f) => [
        f.querySelector("dt").textContent,
        f.querySelector("dd")
      ])
    );
    expect(facts.Branch.textContent).toBe("London Hub");
    expect(facts.License.textContent).toBe("PATEL905153MA9");
    expect(facts["License expired"].className).toBe("bad");
    expect(facts["Safety score"].textContent).toBe("92");

    const warnings = [...root.querySelectorAll(".warnings .pill")].map(
      (w) => w.textContent
    );
    expect(warnings).toEqual([
      "1 qualification expired",
      "2 qualifications expiring soon"
    ]);
  });

  it("uses the photo when the driver has one", async () => {
    const el = mount();
    getRecord.emit(ASSET_WITH_DRIVER);
    getDriverCard.emit({ ...CARD, photoUrl: "https://example.com/p.jpg" });
    await flush();
    expect(
      el.shadowRoot.querySelector(".avatar__img").getAttribute("src")
    ).toBe("https://example.com/p.jpg");
    expect(el.shadowRoot.querySelector(".avatar__initials")).toBeNull();
  });

  it("disappears when the driver is cleared", async () => {
    const el = mount();
    getRecord.emit(ASSET_WITH_DRIVER);
    getDriverCard.emit(CARD);
    await flush();
    getRecord.emit(ASSET_WITHOUT_DRIVER);
    await flush();
    expect(el.shadowRoot.querySelector("article")).toBeNull();
  });

  it("has no pencil when the user cannot edit the driver", async () => {
    const el = mount();
    getRecord.emit(ASSET_WITH_DRIVER);
    getDriverCard.emit(CARD);
    await flush();
    expect(el.shadowRoot.querySelector(".avatar__edit")).toBeNull();
  });

  it("saves the photo chosen in the picker", async () => {
    PhotoModal.open.mockResolvedValue({ documentId: "069000000000001" });
    setDriverPhoto.mockResolvedValue();
    const el = mount();
    getRecord.emit(ASSET_WITH_DRIVER);
    getDriverCard.emit({ ...CARD, canEditPhoto: true });
    await flush();

    el.shadowRoot.querySelector(".avatar__edit").click();
    await flush();
    await flush();
    expect(PhotoModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ driverId: CARD.id, driverName: "Maya Patel" })
    );
    expect(setDriverPhoto).toHaveBeenCalledWith({
      driverId: CARD.id,
      documentId: "069000000000001"
    });
  });

  it("clears the photo when the picker says remove, and saves nothing on cancel", async () => {
    setDriverPhoto.mockResolvedValue();
    const el = mount();
    getRecord.emit(ASSET_WITH_DRIVER);
    getDriverCard.emit({
      ...CARD,
      canEditPhoto: true,
      photoDocumentId: "069000000000001"
    });
    await flush();

    PhotoModal.open.mockResolvedValue(undefined);
    el.shadowRoot.querySelector(".avatar__edit").click();
    await flush();
    await flush();
    expect(setDriverPhoto).not.toHaveBeenCalled();

    PhotoModal.open.mockResolvedValue({ remove: true });
    el.shadowRoot.querySelector(".avatar__edit").click();
    await flush();
    await flush();
    expect(setDriverPhoto).toHaveBeenCalledWith({
      driverId: CARD.id,
      documentId: null
    });
  });
});
