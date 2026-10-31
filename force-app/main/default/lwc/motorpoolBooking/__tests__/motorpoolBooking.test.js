// jest.config.js runs every test on Los Angeles time: the guest's browser is there, the branches are not.
import { createElement } from "@lwc/engine-dom";
import MotorpoolBooking from "c/motorpoolBooking";
import getLocations from "@salesforce/apex/MotorpoolBookingController.getLocations";
import searchAt from "@salesforce/apex/MotorpoolBookingController.searchAt";

jest.mock(
  "@salesforce/apex/MotorpoolBookingController.getLocations",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MotorpoolBookingController.searchAt",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/MotorpoolBookingController.book",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const LOCATIONS = [
  {
    id: "a0B000000000001",
    name: "Lisbon",
    country: "PT",
    timeZone: "Europe/Lisbon"
  },
  {
    id: "a0B000000000002",
    name: "Tel Aviv",
    country: "IL",
    timeZone: "Asia/Jerusalem"
  }
];

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe("c-motorpool-booking", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("books in the branch time zone, not the guest browser zone", async () => {
    expect(new Date("2027-07-10T12:00:00Z").getTimezoneOffset()).toBe(420); // the guest really is on LA time
    searchAt.mockResolvedValue({
      options: [],
      availableCount: 0,
      unavailableCount: 0
    });
    const element = createElement("c-motorpool-booking", {
      is: MotorpoolBooking
    });
    document.body.appendChild(element);
    getLocations.emit(LOCATIONS);
    await flush();

    const select = element.shadowRoot.querySelector("select");
    expect(select).not.toBeNull();
    expect(select.options[0].textContent).toBe("Lisbon · Lisbon time");

    const pickup = element.shadowRoot.querySelector(
      'input[data-field="pickupDate"]'
    );
    pickup.value = "2027-07-10";
    pickup.dispatchEvent(new CustomEvent("change"));
    await flush();
    element.shadowRoot.querySelector(".search__go").click();
    await flush();

    expect(searchAt).toHaveBeenCalledTimes(1);
    const args = searchAt.mock.calls[0][0];
    // 09:00 Lisbon summer time is 08:00 UTC; 17:00 the next day is 16:00 UTC
    expect(args.startTime).toBe("2027-07-10T08:00:00.000Z");
    expect(args.endTime).toBe("2027-07-11T16:00:00.000Z");
    expect(args.tzOffsetMinutes).toBe(60);
    expect(args.branchId).toBe("a0B000000000001");
    expect(
      element.shadowRoot.querySelector(".results__window").textContent
    ).toContain("09:00");
    expect(
      element.shadowRoot.querySelector(".results__window").textContent
    ).toContain("(Lisbon time)");
  });

  it("switches zone with the location", async () => {
    searchAt.mockResolvedValue({
      options: [],
      availableCount: 0,
      unavailableCount: 0
    });
    const element = createElement("c-motorpool-booking", {
      is: MotorpoolBooking
    });
    document.body.appendChild(element);
    getLocations.emit(LOCATIONS);
    await flush();

    const select = element.shadowRoot.querySelector("select");
    select.value = "a0B000000000002";
    select.dispatchEvent(new CustomEvent("change"));
    const pickup = element.shadowRoot.querySelector(
      'input[data-field="pickupDate"]'
    );
    pickup.value = "2027-07-10";
    pickup.dispatchEvent(new CustomEvent("change"));
    await flush();
    element.shadowRoot.querySelector(".search__go").click();
    await flush();

    // 09:00 in Tel Aviv (UTC+3 in summer)
    expect(searchAt.mock.calls[0][0].startTime).toBe(
      "2027-07-10T06:00:00.000Z"
    );
    expect(searchAt.mock.calls[0][0].tzOffsetMinutes).toBe(180);
  });
});
