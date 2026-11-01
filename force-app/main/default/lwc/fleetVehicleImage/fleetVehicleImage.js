import { LightningElement, api, wire } from "lwc";
import getCard from "@salesforce/apex/FleetVehicleController.getCard";
import { formatDistance, fuelEconomy } from "c/fleetRegional";
import getIconStyle from "@salesforce/apex/FleetDisplaySettingsController.getIconStyle";
import {
  STYLES,
  DEFAULT_STYLE,
  PAINT,
  DEFAULT_PAINT,
  FUEL_BADGE
} from "c/fleetVehicleStyles";

// 2 * pi * r for the gauge ring (r = 27 in a 64 x 64 box).
const GAUGE_CIRCUMFERENCE = 169.65;

export default class FleetVehicleImage extends LightningElement {
  /** Fleet Asset id. When set, the component loads everything itself. */
  @api recordId;
  /** 'hero' (card with highlights) or 'icon' (silhouette only). */
  @api variant = "hero";
  /** Explicit values for list rows that already have the data; used when there is no recordId. */
  @api bodyType;
  @api fuelType;
  @api color;
  /** Force a style (used by the settings preview). Otherwise the org setting applies. */
  @api iconStyle;
  /** Icon width in px for the 'icon' variant. */
  @api size = 56;

  card;
  error;
  orgStyle;

  @wire(getIconStyle)
  wiredStyle({ data }) {
    if (data) this.orgStyle = data;
  }

  @wire(getCard, { assetId: "$recordId" })
  wiredCard({ data, error }) {
    if (data) {
      this.card = data;
      this.error = undefined;
    } else if (error) {
      this.card = undefined;
      this.error = error;
    }
  }

  get isHero() {
    return this.variant !== "icon";
  }

  get body() {
    return (this.card && this.card.bodyType) || this.bodyType;
  }

  get fuel() {
    return (this.card && this.card.fuelType) || this.fuelType;
  }

  get paint() {
    return PAINT[(this.card && this.card.color) || this.color] || DEFAULT_PAINT;
  }

  get styleName() {
    const s = this.iconStyle || this.orgStyle || DEFAULT_STYLE;
    return STYLES[s] ? s : DEFAULT_STYLE;
  }

  get shape() {
    const set = STYLES[this.styleName];
    return set[this.body] || set.SUV;
  }

  get isTraced() {
    return !!this.shape.traced;
  }

  get viewBox() {
    return this.shape.vb;
  }

  get shadowY() {
    return this.isTraced ? 97 : 72;
  }

  get underPath() {
    return this.shape.under || "";
  }

  get bodyPath() {
    return this.shape.body;
  }

  get bodyClass() {
    return this.isTraced ? "body body--traced" : "body";
  }

  get glassPath() {
    return this.shape.glass;
  }

  get details() {
    return this.shape.details.map((d, i) => ({
      key: `d${i}`,
      d: d.d,
      cls: `detail detail--${d.c}`
    }));
  }

  /** Every circle that makes up the wheels, bottom to top, so the template is a single loop. */
  get wheelParts() {
    const style = this.shape.wheelStyle || "flat";
    const parts = [];
    this.shape.wheels.forEach((w, i) => {
      const add = (k, radius, cls) =>
        parts.push({
          key: `w${i}${k}`,
          cx: w[0],
          cy: this.isTraced ? w[1] : 60,
          r: radius,
          cls
        });
      if (this.isTraced) {
        add("t", w[2] + 0.4, "tire");
        add("r", w[3], "rim");
        add("h", w[4], "hubdark");
        return;
      }
      const r = w[1];
      add("t", r, "tire");
      if (style === "classic") {
        add("a", r * 0.78, "whitewall");
        add("b", r * 0.55, "tire");
        add("c", r * 0.42, "hub");
      } else if (style === "modern") {
        add("a", r * 0.68, "alloy");
        add("b", r * 0.22, "tire");
      } else if (style === "future") {
        add("a", r * 0.62, "disc");
        add("b", r * 0.2, "glow");
      } else {
        add("a", Math.round(r * 0.4), "hub");
      }
    });
    return parts;
  }

  get badge() {
    const b = FUEL_BADGE[this.fuel];
    return b ? { ...b, style: `background:${b.color}` } : null;
  }

  get iconWidthStyle() {
    return `width:${this.size}px`;
  }

  get iconTitle() {
    return (
      (this.card && this.card.name) ||
      [this.body, this.fuel].filter(Boolean).join(" · ")
    );
  }

  get hasCard() {
    return !!this.card;
  }

  get mpgHeadline() {
    const c = this.card;
    if (!c || !c.epaRated) return null;
    const fe = fuelEconomy(c, c.fuelEconomyFormat, c.distanceUnit);
    return fe
      ? { value: fe.value, unit: `${fe.unit} combined`, detail: fe.detail }
      : null;
  }

  /** Fuel or charge level ring; null when the level is unknown. */
  get gauge() {
    const c = this.card;
    if (!c || c.fuelLevel === undefined || c.fuelLevel === null) return null;
    const level = Math.max(0, Math.min(100, Math.round(c.fuelLevel)));
    const electric = c.fuelType === "Electric";
    let cls = "gauge";
    if (level < 20) cls += " gauge--critical";
    else if (level < 50) cls += " gauge--low";
    return {
      cls,
      value: `${level}%`,
      label: electric ? "Charge" : "Fuel",
      title: `${electric ? "Battery charge" : "Fuel level"} ${level}%`,
      style: `--gauge-offset: ${(GAUGE_CIRCUMFERENCE * (100 - level)) / 100}`
    };
  }

  get mapMarkers() {
    const c = this.card;
    if (!c || c.latitude == null || c.longitude == null) return null;
    return [
      {
        location: { Latitude: c.latitude, Longitude: c.longitude },
        title: c.name
      }
    ];
  }

  get mapOptions() {
    return { disableDefaultUI: true, draggable: false, zoomControl: false };
  }

  get facts() {
    const c = this.card;
    if (!c) return [];
    const out = [];
    if (c.fuelType) out.push({ key: "fuel", label: "Fuel", value: c.fuelType });
    if (c.seatCount != null)
      out.push({ key: "seats", label: "Seats", value: String(c.seatCount) });
    if (c.odometer != null)
      out.push({
        key: "odo",
        label: "Odometer",
        value: formatDistance(c.odometer, c.distanceUnit)
      });
    if (c.bodyType) out.push({ key: "body", label: "Body", value: c.bodyType });
    return out;
  }
}
