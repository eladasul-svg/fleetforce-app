import { createElement } from "@lwc/engine-dom";
import FleetVehicleImage from "c/fleetVehicleImage";
import getCard from "@salesforce/apex/FleetVehicleController.getCard";

jest.mock(
  "@salesforce/apex/FleetVehicleController.getCard",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/FleetDisplaySettingsController.getIconStyle",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const CARD = {
  id: "a0J000000000001",
  name: "2024 Ford F-150 Lightning Pro EV",
  bodyType: "Pickup",
  fuelType: "Electric",
  odometer: 8900,
  distanceUnit: "mi",
  fuelLevel: 46,
  latitude: 51.5399,
  longitude: -0.0985
};

function mount() {
  const el = createElement("c-fleet-vehicle-image", { is: FleetVehicleImage });
  el.recordId = CARD.id;
  document.body.appendChild(el);
  return el;
}

const flush = () => Promise.resolve();

describe("c-fleet-vehicle-image", () => {
  afterEach(() => {
    while (document.body.firstChild)
      document.body.removeChild(document.body.firstChild);
  });

  it("shows the charge level as an amber ring under half, and the last location on a map", async () => {
    const el = mount();
    getCard.emit(CARD);
    await flush();
    const gauge = el.shadowRoot.querySelector(".gauge");
    expect(gauge.className).toBe("gauge gauge--low");
    expect(gauge.querySelector(".gauge__value").textContent).toBe("46%");
    expect(gauge.querySelector(".gauge__label").textContent).toBe("Charge");
    const map = el.shadowRoot.querySelector("lightning-map");
    expect(map.mapMarkers[0].location).toEqual({
      Latitude: 51.5399,
      Longitude: -0.0985
    });
  });

  it("marks a nearly empty tank as critical", async () => {
    const el = mount();
    getCard.emit({ ...CARD, fuelType: "Gasoline", fuelLevel: 12 });
    await flush();
    const gauge = el.shadowRoot.querySelector(".gauge");
    expect(gauge.className).toBe("gauge gauge--critical");
    expect(gauge.querySelector(".gauge__label").textContent).toBe("Fuel");
  });

  it("has no ring or map when level and location are unknown", async () => {
    const el = mount();
    getCard.emit({ ...CARD, fuelLevel: null, latitude: null, longitude: null });
    await flush();
    expect(el.shadowRoot.querySelector(".gauge")).toBeNull();
    expect(el.shadowRoot.querySelector("lightning-map")).toBeNull();
  });
});
