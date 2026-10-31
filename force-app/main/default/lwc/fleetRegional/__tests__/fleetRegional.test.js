import {
  distanceUnit,
  fuelEconomy,
  fuelLogUnit,
  formatDistance,
  formatInZone,
  formatMoney,
  milesIn,
  zoneLabel,
  zonedToUtc
} from "c/fleetRegional";

describe("c-fleet-regional", () => {
  it("defaults distance to km and converts EPA miles", () => {
    expect(distanceUnit(undefined)).toBe("km");
    expect(distanceUnit("mi")).toBe("mi");
    expect(Math.round(milesIn(100, "km"))).toBe(161);
    expect(milesIn(100, "mi")).toBe(100);
    expect(formatDistance(12400, "km")).toBe("12,400 km");
  });

  it("maps volume units to fuel log values", () => {
    expect(fuelLogUnit("gal_US")).toBe("Gallons (US)");
    expect(fuelLogUnit("gal_UK")).toBe("Gallons (UK)");
    expect(fuelLogUnit(undefined)).toBe("Liters");
  });

  it("shows fuel economy in each format", () => {
    const car = { mpgCombined: 25, mpgCity: 20, mpgHighway: 30 };
    expect(fuelEconomy(car, "MPG_US", "mi").short).toBe("25 MPG");
    expect(fuelEconomy(car, "MPG_UK", "mi").short).toBe("30 MPG (UK)");
    expect(fuelEconomy(car, "L_100km", "km")).toEqual({
      value: "9.4",
      unit: "L/100 km",
      detail: "11.8 city / 7.8 hwy",
      short: "9.4 L/100 km"
    });
    expect(fuelEconomy(car, "km_L", "km").short).toBe("10.6 km/L");
    expect(fuelEconomy({}, "MPG_US", "mi")).toBeNull();
  });

  it("labels electric figures correctly", () => {
    const ev = { mpgCombined: 120, evRangeMiles: 300 };
    expect(fuelEconomy(ev, "MPG_US", "mi")).toMatchObject({
      short: "120 MPGe",
      detail: "300 mi range"
    });
    expect(fuelEconomy(ev, "L_100km", "km")).toMatchObject({
      short: "17.5 kWh/100 km",
      detail: "483 km range"
    });
    expect(fuelEconomy(ev, "MPG_UK", "mi").short).toBe("3.6 mi/kWh");
  });

  it("formats money in the currency", () => {
    expect(formatMoney(12.5, "EUR")).toBe("€12.50");
    expect(formatMoney(null, "EUR")).toBe("");
  });

  it("names and converts branch time zones", () => {
    expect(zoneLabel("Europe/Lisbon")).toBe("Lisbon time");
    expect(zoneLabel("America/New_York")).toBe("New York time");
    expect(zoneLabel("Not/AZone")).toBe("");
    // 09:00 in Lisbon in summer (UTC+1) and winter (UTC+0), and in Tel Aviv (UTC+3 in summer)
    expect(zonedToUtc("2026-07-10T09:00", "Europe/Lisbon").toISOString()).toBe(
      "2026-07-10T08:00:00.000Z"
    );
    expect(zonedToUtc("2026-12-10T09:00", "Europe/Lisbon").toISOString()).toBe(
      "2026-12-10T09:00:00.000Z"
    );
    expect(zonedToUtc("2026-07-10T09:00", "Asia/Jerusalem").toISOString()).toBe(
      "2026-07-10T06:00:00.000Z"
    );
    expect(
      formatInZone("2026-07-10T08:00:00.000Z", "Europe/Lisbon", {
        hour: "2-digit",
        minute: "2-digit"
      })
    ).toBe("09:00");
  });
});
