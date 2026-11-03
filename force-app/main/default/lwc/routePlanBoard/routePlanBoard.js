import { LightningElement, api, wire } from "lwc";
import { refreshApex } from "@salesforce/apex";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { subscribe, unsubscribe, onError } from "lightning/empApi";
import getBoard from "@salesforce/apex/RoutePlanController.getBoard";
import optimize from "@salesforce/apex/RoutePlanController.optimize";
import publish from "@salesforce/apex/RoutePlanController.publish";

// One colour per route, readable on the map in light and dark themes.
const COLORS = [
  "#1b6ec2",
  "#d4462e",
  "#2e8540",
  "#8a4fc2",
  "#c27c0e",
  "#0e8a8a",
  "#b0336f",
  "#5a6b7d"
];
const PIN = "M12 2C8 2 5 5 5 9c0 5 7 13 7 13s7-8 7-13c0-4-3-7-7-7z";

export function formatTime(value) {
  if (!value) return "";
  return new Date(value).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit"
  });
}

export default class RoutePlanBoard extends LightningElement {
  @api recordId;
  board;
  error;
  busy = false;
  selectedRouteId;
  wired;
  subscription;

  @wire(getBoard, { planId: "$recordId" })
  wiredBoard(result) {
    this.wired = result;
    if (result.data) {
      this.board = result.data;
      this.error = undefined;
      this.listen();
    } else if (result.error) {
      this.error = result.error.body
        ? result.error.body.message
        : String(result.error);
    }
  }

  disconnectedCallback() {
    if (this.subscription) {
      unsubscribe(this.subscription, () => {});
      this.subscription = null;
    }
  }

  listen() {
    if (this.subscription || !this.board || !this.board.channel) return;
    onError(() => {});
    subscribe(this.board.channel, -1, (msg) => {
      const payload = (msg && msg.data && msg.data.payload) || {};
      const planId = Object.keys(payload).find((k) =>
        k.endsWith("Route_Plan_Id__c")
      );
      if (
        !planId ||
        payload[planId] === this.recordId ||
        payload[planId] === this.board.planId
      ) {
        this.refresh();
      }
    }).then((s) => {
      this.subscription = s;
    });
  }

  refresh() {
    return this.wired ? refreshApex(this.wired) : Promise.resolve();
  }

  // ---------- view model ----------

  get loaded() {
    return !!this.board;
  }
  get hasRoutes() {
    return this.loaded && this.board.routes.length > 0;
  }
  get hasUnassigned() {
    return this.loaded && this.board.unassigned.length > 0;
  }
  get isOptimizing() {
    return this.loaded && this.board.status === "Optimizing";
  }
  get optimizeDisabled() {
    return this.busy || !this.loaded || !this.board.canOptimize;
  }
  get publishDisabled() {
    return this.busy || !this.loaded || !this.board.canPublish;
  }
  get optimizeLabel() {
    return this.loaded && this.board.revision > 0 ? "Re-optimize" : "Optimize";
  }

  get kpis() {
    if (!this.loaded) return [];
    const b = this.board;
    return [
      { key: "routes", label: "Routes", value: b.routes.length },
      {
        key: "km",
        label: "Distance (km)",
        value: b.totalDistanceKm == null ? "–" : b.totalDistanceKm
      },
      {
        key: "min",
        label: "Driving + service (min)",
        value: b.totalDurationMin == null ? "–" : b.totalDurationMin
      },
      {
        key: "un",
        label: "Unassigned",
        value: b.unassignedCount == null ? 0 : b.unassignedCount
      },
      {
        key: "rev",
        label: "Revision",
        value: b.revision == null ? 0 : b.revision
      }
    ];
  }

  get routes() {
    if (!this.loaded) return [];
    return this.board.routes.map((r, i) => ({
      ...r,
      color: COLORS[i % COLORS.length],
      swatchStyle: `background:${COLORS[i % COLORS.length]}`,
      selected: r.id === this.selectedRouteId,
      cardClass: `route${r.id === this.selectedRouteId ? " route--on" : ""}`,
      window: `${formatTime(r.plannedStart)}–${formatTime(r.plannedEnd)}`,
      stops: r.stops
        .filter((s) => s.type !== "Start")
        .map((s) => ({
          ...s,
          eta: formatTime(s.eta),
          label: s.jobs && s.jobs.length ? s.jobs.join(", ") : s.type,
          isLate: s.lateMinutes > 0,
          badge: s.type === "Job Stop" ? null : s.type
        }))
    }));
  }

  get markers() {
    const out = [];
    this.routes.forEach((r) => {
      if (this.selectedRouteId && r.id !== this.selectedRouteId) return;
      r.stops.forEach((s) => {
        if (s.latitude == null || s.longitude == null) return;
        out.push({
          location: { Latitude: s.latitude, Longitude: s.longitude },
          title: `${r.name} · ${s.sequence}. ${s.label}`,
          description: s.eta ? `ETA ${s.eta}` : "",
          mapIcon: {
            path: PIN,
            fillColor: r.color,
            fillOpacity: 0.9,
            strokeWeight: 1,
            scale: 1.2
          }
        });
      });
    });
    return out;
  }
  get hasMarkers() {
    return this.markers.length > 0;
  }

  // ---------- actions ----------

  handleSelect(event) {
    const id = event.currentTarget.dataset.id;
    this.selectedRouteId = this.selectedRouteId === id ? undefined : id;
  }

  async handleOptimize() {
    await this.run(
      () => optimize({ planId: this.recordId }),
      "Optimizing",
      "The solver is planning the routes."
    );
  }

  async handlePublish() {
    await this.run(
      () => publish({ planId: this.recordId }),
      "Published",
      "Drivers and the motorpool can see the routes."
    );
  }

  async run(action, title, message) {
    this.busy = true;
    try {
      await action();
      this.dispatchEvent(
        new ShowToastEvent({ title, message, variant: "success" })
      );
      await this.refresh();
    } catch (e) {
      const msg = e && e.body ? e.body.message : String(e);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Something went wrong",
          message: msg,
          variant: "error"
        })
      );
    } finally {
      this.busy = false;
    }
  }
}
