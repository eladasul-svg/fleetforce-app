/**
 * Regional display helpers shared by FleetForce components: distance and volume units, fuel economy in the
 * vehicle's format, money in a currency, and times in a branch's IANA time zone.
 *
 * Stored values keep the unit they were entered in; these helpers convert for display only. EPA figures from
 * Vehicle_Model__mdt are US MPG / MPGe and miles of range.
 */
export const KM_PER_MILE = 1.609344;
const KWH_PER_GALLON_EQUIVALENT = 33.705;
const UK_GALLON_PER_US_GALLON = 1.20095;
const L_100KM_X_MPG = 235.215;
const KM_L_PER_MPG = 0.425144;

/** 'mi' or 'km' (anything else, including blank, is km). */
export function distanceUnit(unit) {
  return unit === "mi" ? "mi" : "km";
}

const VOLUME_LABELS = {
  L: "litres",
  gal_US: "US gallons",
  gal_UK: "UK gallons"
};
const FUEL_LOG_UOM = {
  L: "Liters",
  gal_US: "Gallons (US)",
  gal_UK: "Gallons (UK)"
};

/** Plain-language volume unit for labels: litres, US gallons, UK gallons. */
export function volumeLabel(unit) {
  return VOLUME_LABELS[unit] || VOLUME_LABELS.L;
}

/** The Fuel_Log__c.UOM__c value for a volume unit. */
export function fuelLogUnit(unit) {
  return FUEL_LOG_UOM[unit] || FUEL_LOG_UOM.L;
}

export function formatNumber(n, decimals = 0) {
  if (n == null || isNaN(n)) return "–";
  return Number(n).toLocaleString("en-GB", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals
  });
}

/** "12,400 km", in the given unit (the value is already in that unit). */
export function formatDistance(n, unit) {
  return n == null ? "" : `${formatNumber(n)} ${distanceUnit(unit)}`;
}

/** A distance in miles (EPA range) shown in the given unit. */
export function milesIn(miles, unit) {
  if (miles == null) return null;
  return distanceUnit(unit) === "km" ? miles * KM_PER_MILE : miles;
}

const one = (n) => formatNumber(n, 1);
const whole = (n) => formatNumber(n, 0);

function liquid(mpg, format) {
  if (mpg == null || mpg <= 0) return null;
  switch (format) {
    case "MPG_UK":
      return { text: whole(mpg * UK_GALLON_PER_US_GALLON), unit: "MPG (UK)" };
    case "L_100km":
      return { text: one(L_100KM_X_MPG / mpg), unit: "L/100 km" };
    case "km_L":
      return { text: one(mpg * KM_L_PER_MPG), unit: "km/L" };
    default:
      return { text: whole(mpg), unit: "MPG" };
  }
}

function electric(mpge, format) {
  if (mpge == null || mpge <= 0) return null;
  switch (format) {
    case "MPG_UK":
      return { text: one(mpge / KWH_PER_GALLON_EQUIVALENT), unit: "mi/kWh" };
    case "L_100km":
    case "km_L":
      return {
        text: one((KWH_PER_GALLON_EQUIVALENT * 100) / (mpge * KM_PER_MILE)),
        unit: "kWh/100 km"
      };
    default:
      return { text: whole(mpge), unit: "MPGe" };
  }
}

/**
 * Fuel economy for display. figures: { mpgCombined, mpgCity, mpgHighway, evRangeMiles } (EPA, US).
 * format: MPG_US | MPG_UK | L_100km | km_L. Returns null without figures, else
 * { value, unit, detail, short } such as { value: '9.4', unit: 'L/100 km', detail: '11.8 city / 7.8 hwy', short: '9.4 L/100 km' }.
 */
export function fuelEconomy(figures, format, unit) {
  if (!figures || figures.mpgCombined == null) return null;
  const isElectric = figures.evRangeMiles != null;
  const convert = isElectric ? electric : liquid;
  const combined = convert(figures.mpgCombined, format);
  if (!combined) return null;
  let detail = "";
  if (isElectric) {
    detail = `${formatDistance(milesIn(figures.evRangeMiles, unit), unit)} range`;
  } else {
    const city = convert(figures.mpgCity, format);
    const hwy = convert(figures.mpgHighway, format);
    if (city && hwy) detail = `${city.text} city / ${hwy.text} hwy`;
  }
  return {
    value: combined.text,
    unit: combined.unit,
    detail,
    short: `${combined.text} ${combined.unit}`
  };
}

/** "€12.50" in the given ISO currency (falls back to the plain number). */
export function formatMoney(n, currency) {
  if (n == null || n === "") return "";
  try {
    return new Intl.NumberFormat("en-GB", {
      style: "currency",
      currency: currency || "USD"
    }).format(Number(n));
  } catch {
    return `${Number(n).toFixed(2)} ${currency || ""}`.trim();
  }
}

function validZone(tz) {
  if (!tz) return false;
  try {
    return !!new Intl.DateTimeFormat("en-GB", {
      timeZone: tz
    }).resolvedOptions().timeZone;
  } catch {
    return false;
  }
}

/** "Lisbon time" for Europe/Lisbon, "New York time" for America/New_York; '' when blank or unknown. */
export function zoneLabel(tz) {
  if (!validZone(tz)) return "";
  const city = tz.split("/").pop().replace(/_/g, " ");
  return tz === "UTC" || tz === "Etc/UTC" ? "UTC" : `${city} time`;
}

/** Minutes the zone is ahead of UTC at the given instant (Lisbon in summer: 60). */
export function offsetMinutes(tz, date) {
  const parts = {};
  new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  })
    .formatToParts(date)
    .forEach((p) => {
      parts[p.type] = p.value;
    });
  const asUtc = Date.UTC(
    +parts.year,
    +parts.month - 1,
    +parts.day,
    +parts.hour % 24,
    +parts.minute,
    +parts.second
  );
  return Math.round((asUtc - Math.floor(date.getTime() / 1000) * 1000) / 60000);
}

/**
 * The instant for a wall-clock time ("YYYY-MM-DDTHH:mm") in a time zone, whatever the browser's own zone is.
 * Without a valid zone the browser's zone is used.
 */
export function zonedToUtc(local, tz) {
  if (!validZone(tz)) return new Date(local);
  const [d, t = "00:00"] = local.split("T");
  const [y, m, day] = d.split("-").map(Number);
  const [h, min] = t.split(":").map(Number);
  const wall = Date.UTC(y, m - 1, day, h, min);
  let utc = wall - offsetMinutes(tz, new Date(wall)) * 60000;
  const again = wall - offsetMinutes(tz, new Date(utc)) * 60000;
  if (again !== utc) utc = again;
  return new Date(utc);
}

/** Formats a date-time in the zone (browser zone when blank or unknown). options are Intl.DateTimeFormat options. */
export function formatInZone(value, tz, options) {
  if (!value) return "";
  const opts = validZone(tz) ? { ...options, timeZone: tz } : options;
  return new Intl.DateTimeFormat("en-GB", opts).format(new Date(value));
}
