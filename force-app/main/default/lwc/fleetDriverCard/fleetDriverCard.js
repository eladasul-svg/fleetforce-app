import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { NavigationMixin } from "lightning/navigation";
import getDriverCard from "@salesforce/apex/FleetDriverController.getDriverCard";

const DRIVER_FIELD = "fleetforce__Fleet_Asset__c.fleetforce__Driver__c";
// A licence expiring within this many days is flagged.
const LICENSE_WARN_DAYS = 60;
const DAY_MS = 24 * 60 * 60 * 1000;

export default class FleetDriverCard extends NavigationMixin(LightningElement) {
  /** Fleet Asset id (record page). */
  @api recordId;

  driverId;
  card;
  error;

  // The driver comes from the record through Lightning Data Service, so the card follows a change of driver
  // without a page reload, and disappears when the driver is cleared.
  @wire(getRecord, { recordId: "$recordId", fields: [DRIVER_FIELD] })
  wiredAsset({ data, error }) {
    if (data) {
      this.driverId = getFieldValue(data, DRIVER_FIELD) || undefined;
      if (!this.driverId) {
        this.card = undefined;
      }
    } else if (error) {
      this.error = error;
    }
  }

  @wire(getDriverCard, { driverId: "$driverId" })
  wiredCard({ data, error }) {
    if (data) {
      this.card = data;
      this.error = undefined;
    } else if (error) {
      this.card = undefined;
      this.error = error;
    }
  }

  get subtitle() {
    return this.card.title || "";
  }

  get statusClass() {
    const s = this.card.status;
    if (s === "Active") return "pill pill--active";
    if (s === "Suspended") return "pill pill--bad";
    if (s === "On Leave" || s === "Inactive") return "pill pill--warn";
    return "pill";
  }

  get contacts() {
    const c = this.card;
    const out = [];
    if (c.mobile) {
      out.push({
        key: "mobile",
        icon: "utility:phone_portrait",
        label: "Mobile",
        value: c.mobile,
        href: `tel:${c.mobile}`
      });
    }
    if (c.phone && c.phone !== c.mobile) {
      out.push({
        key: "phone",
        icon: "utility:call",
        label: "Phone",
        value: c.phone,
        href: `tel:${c.phone}`
      });
    }
    if (c.email) {
      out.push({
        key: "email",
        icon: "utility:email",
        label: "Email",
        value: c.email,
        href: `mailto:${c.email}`
      });
    }
    return out;
  }

  get facts() {
    const c = this.card;
    const out = [];
    if (c.branchName) {
      out.push({ key: "branch", label: "Branch", value: c.branchName });
    }
    if (c.licenseNumber) {
      const extra = [c.licenseClass, c.licenseState].filter(
        (v) => v && v !== "None"
      );
      out.push({
        key: "license",
        label: "License",
        value: extra.length
          ? `${c.licenseNumber} · ${extra.join(" · ")}`
          : c.licenseNumber
      });
    }
    if (c.licenseExpiry) {
      const days = this.daysUntil(c.licenseExpiry);
      let cls = "";
      if (days < 0) cls = "bad";
      else if (days <= LICENSE_WARN_DAYS) cls = "warn";
      out.push({
        key: "expiry",
        label: days < 0 ? "License expired" : "License expires",
        value: this.formatDate(c.licenseExpiry),
        cls
      });
    }
    if (c.safetyScore !== undefined && c.safetyScore !== null) {
      out.push({
        key: "safety",
        label: "Safety score",
        value: String(c.safetyScore)
      });
    }
    return out;
  }

  get warnings() {
    const c = this.card;
    const out = [];
    if (c.qualificationsExpired) {
      out.push({
        key: "expired",
        cls: "pill pill--bad",
        label: this.plural(
          c.qualificationsExpired,
          "qualification expired",
          "qualifications expired"
        )
      });
    }
    if (c.qualificationsExpiringSoon) {
      out.push({
        key: "soon",
        cls: "pill pill--warn",
        label: this.plural(
          c.qualificationsExpiringSoon,
          "qualification expiring soon",
          "qualifications expiring soon"
        )
      });
    }
    return out;
  }

  plural(n, one, many) {
    return `${n} ${n === 1 ? one : many}`;
  }

  // Dates arrive as "YYYY-MM-DD"; compare and format them as calendar dates, not instants.
  daysUntil(isoDate) {
    const [y, m, d] = isoDate.split("-").map(Number);
    const now = new Date();
    const today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
    return Math.round((Date.UTC(y, m - 1, d) - today) / DAY_MS);
  }

  formatDate(isoDate) {
    const [y, m, d] = isoDate.split("-").map(Number);
    return new Intl.DateTimeFormat(undefined, {
      day: "numeric",
      month: "short",
      year: "numeric",
      timeZone: "UTC"
    }).format(new Date(Date.UTC(y, m - 1, d)));
  }

  openDriver(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: this.card.id,
        objectApiName: "Contact",
        actionName: "view"
      }
    });
  }
}
