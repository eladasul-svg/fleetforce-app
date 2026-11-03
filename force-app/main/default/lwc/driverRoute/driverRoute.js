import { LightningElement, api } from "lwc";
import getTodayRoute from "@salesforce/apex/DriverRouteController.getTodayRoute";

export default class DriverRoute extends LightningElement {
  _driverId;
  route;
  loading = false;
  error;

  /** IANA time zone for times on screen (the vehicle's branch), passed in by driverApp. */
  @api timeZone;

  @api
  get driverId() {
    return this._driverId;
  }
  set driverId(value) {
    const changed = value !== this._driverId;
    this._driverId = value;
    if (changed && value) {
      this.load();
    }
  }

  @api
  async load() {
    this.loading = true;
    this.error = undefined;
    try {
      this.route = await getTodayRoute({ driverId: this._driverId });
    } catch (e) {
      this.error = e && e.body ? e.body.message : "Could not load your route.";
      this.route = undefined;
    } finally {
      this.loading = false;
    }
  }

  time(value) {
    if (!value) return "";
    const opts = { hour: "2-digit", minute: "2-digit" };
    if (this.timeZone) opts.timeZone = this.timeZone;
    return new Date(value).toLocaleTimeString([], opts);
  }

  get hasRoute() {
    return !!this.route;
  }
  get empty() {
    return !this.loading && !this.error && !this.route;
  }
  get summary() {
    if (!this.route) return "";
    const end = this.time(this.route.plannedEnd);
    return `${this.route.remaining} stop${this.route.remaining === 1 ? "" : "s"} left${end ? ` · back about ${end}` : ""}`;
  }
  get next() {
    if (!this.route) return null;
    const s = this.route.stops.find((x) => !x.done);
    return s ? { ...s, eta: this.time(s.eta) } : null;
  }
  get navigateUrl() {
    const n = this.next;
    return n && n.latitude != null
      ? `https://www.google.com/maps/dir/?api=1&destination=${n.latitude},${n.longitude}`
      : null;
  }
  get stops() {
    if (!this.route) return [];
    return this.route.stops.map((s) => ({
      ...s,
      eta: this.time(s.eta),
      until: s.windowEnd ? `by ${this.time(s.windowEnd)}` : "",
      cls: `stop${s.done ? " stop--done" : ""}`
    }));
  }
}
