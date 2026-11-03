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
// What a non-job stop shows on the map and in the list, in place of its number.
const MARKS = { Break: "B", Charge: "C", Depot: "D" };

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
  // Routes switched off in the driver filter; empty means every route is shown.
  hiddenRouteIds = [];
  filterOpen = false;
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
    const hidden = new Set(this.hiddenRouteIds);
    return this.board.routes.map((r, i) => {
      const color = COLORS[i % COLORS.length];
      const start = r.stops.find((s) => s.type === "Start");
      let n = 0;
      const stops = r.stops
        .filter((s) => s.type !== "Start" && s.type !== "End")
        .map((s) => {
          const label = s.jobs && s.jobs.length ? s.jobs.join(", ") : s.type;
          return {
            ...s,
            eta: formatTime(s.eta),
            label,
            mark: s.type === "Job Stop" ? String(++n) : MARKS[s.type] || "•",
            isLate: s.lateMinutes > 0,
            badge: s.type === "Job Stop" ? null : s.type
          };
        });
      const shown = !hidden.has(r.id);
      const who = [r.vehicle || r.name, r.driver].filter(Boolean).join(" · ");
      return {
        ...r,
        color,
        who,
        shown,
        stops,
        depot: start,
        swatchStyle: `background:${color}`,
        markStyle: `background:${color}`,
        cardClass: `route${shown ? "" : " route--off"}`,
        window: `${formatTime(r.plannedStart)}–${formatTime(r.plannedEnd)}`
      };
    });
  }

  /** What routeMap draws: only the routes ticked in the driver filter. */
  get mapRoutes() {
    return this.routes
      .filter((r) => r.shown)
      .map((r) => ({
        id: r.id,
        name: r.who,
        color: r.color,
        geometry: r.geometry,
        depot:
          r.depot && r.depot.latitude != null
            ? {
                lat: r.depot.latitude,
                lng: r.depot.longitude,
                title: this.board.depot
              }
            : null,
        stops: r.stops.map((s) => ({
          id: s.id,
          lat: s.latitude,
          lng: s.longitude,
          mark: s.mark,
          title: `${r.who} · stop ${s.mark}: ${s.label}`,
          detail: [
            s.eta ? `ETA ${s.eta}` : "",
            s.isLate ? `${s.lateMinutes} min late` : "",
            s.locked ? "Locked" : ""
          ]
            .filter(Boolean)
            .join(" · ")
        }))
      }));
  }
  get hasMapRoutes() {
    return this.mapRoutes.length > 0;
  }

  get filterOptions() {
    return this.routes.map((r) => ({
      id: r.id,
      label: r.who,
      checked: r.shown,
      swatchStyle: r.swatchStyle
    }));
  }
  get filterLabel() {
    const all = this.routes.length;
    const on = this.routes.filter((r) => r.shown).length;
    return on === all ? `All drivers (${all})` : `${on} of ${all} drivers`;
  }
  get filterClass() {
    return `slds-dropdown-trigger slds-dropdown-trigger_click filter${
      this.filterOpen ? " slds-is-open" : ""
    }`;
  }

  // ---------- actions ----------

  toggleFilter() {
    this.filterOpen = !this.filterOpen;
  }

  handleDriverToggle(event) {
    const id = event.target.dataset.id;
    const hidden = new Set(this.hiddenRouteIds);
    if (event.target.checked) hidden.delete(id);
    else hidden.add(id);
    this.hiddenRouteIds = [...hidden];
  }

  showAll() {
    this.hiddenRouteIds = [];
  }

  /** Clicking a route card shows only that route; clicking it again shows them all. */
  handleSelect(event) {
    const id = event.currentTarget.dataset.id;
    const others = this.board.routes.map((r) => r.id).filter((x) => x !== id);
    const onlyThis =
      this.hiddenRouteIds.length === others.length &&
      others.every((x) => this.hiddenRouteIds.includes(x));
    this.hiddenRouteIds = onlyThis ? [] : others;
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
