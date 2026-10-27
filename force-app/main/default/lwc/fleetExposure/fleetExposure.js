import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getSummary from "@salesforce/apex/FleetExposureController.getSummary";
import getNotices from "@salesforce/apex/FleetExposureController.getNotices";
import getAffectedVehicles from "@salesforce/apex/FleetExposureController.getAffectedVehicles";
import getSourceHealth from "@salesforce/apex/FleetExposureController.getSourceHealth";
import { alertTypeIcon, reduceError } from "c/dataTrustFormat";

const ALL = "";

const NOTICE_COLUMNS = [
  {
    label: "Title",
    fieldName: "title",
    type: "button",
    wrapText: true,
    initialWidth: 280,
    typeAttributes: {
      label: { fieldName: "title" },
      name: "drill",
      variant: "base",
      title: "Show affected vehicles"
    }
  },
  { label: "Type", fieldName: "noticeType", initialWidth: 110 },
  { label: "Source", fieldName: "source", wrapText: true, initialWidth: 190 },
  { label: "Jurisdiction", fieldName: "jurisdictionText", initialWidth: 120 },
  {
    label: "Effective",
    fieldName: "effectiveOn",
    type: "date-local",
    initialWidth: 120,
    typeAttributes: { year: "numeric", month: "short", day: "numeric" }
  },
  {
    label: "Vehicles",
    fieldName: "affectedCount",
    type: "number",
    initialWidth: 95,
    cellAttributes: { alignment: "left" }
  },
  {
    label: "Status",
    fieldName: "statusText",
    initialWidth: 140,
    cellAttributes: { iconName: { fieldName: "statusIcon" } }
  }
];

const VEHICLE_COLUMNS = [
  {
    label: "Vehicle",
    fieldName: "assetUrl",
    type: "url",
    wrapText: true,
    typeAttributes: { label: { fieldName: "assetName" }, target: "_self" }
  },
  { label: "Plate", fieldName: "licensePlate", initialWidth: 110 },
  { label: "Country", fieldName: "country", initialWidth: 90 },
  {
    label: "Data health",
    fieldName: "healthText",
    initialWidth: 140,
    cellAttributes: { iconName: { fieldName: "healthIcon" } }
  },
  { label: "Alert status", fieldName: "alertStatus", initialWidth: 120 },
  {
    label: "Due",
    fieldName: "dueDate",
    type: "date-local",
    initialWidth: 120,
    typeAttributes: { year: "numeric", month: "short", day: "numeric" }
  }
];

const HEALTH_ICON = {
  Healthy: "utility:success",
  Watch: "utility:warning",
  "At risk": "utility:error"
};

export default class FleetExposure extends NavigationMixin(LightningElement) {
  summary;
  notices = [];
  sources = [];
  vehicles = [];
  selectedNotice;
  error;
  loading = true;
  loadingVehicles = false;

  typeFilter = ALL;
  jurisdictionFilter = ALL;
  statusFilter = ALL;

  noticeColumns = NOTICE_COLUMNS;
  vehicleColumns = VEHICLE_COLUMNS;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      const [summary, notices, sources] = await Promise.all([
        getSummary(),
        getNotices(),
        getSourceHealth()
      ]);
      this.summary = summary;
      this.notices = notices || [];
      this.sources = sources || [];
      this.error = undefined;
      if (this.selectedNotice) {
        this.selectedNotice = this.notices.find(
          (n) => n.id === this.selectedNotice.id
        );
        if (this.selectedNotice) {
          await this.loadVehicles(this.selectedNotice.id);
        }
      }
    } catch (e) {
      this.error = reduceError(e);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Could not load fleet exposure",
          message: this.error,
          variant: "error"
        })
      );
    } finally {
      this.loading = false;
    }
  }

  handleRefresh() {
    this.load();
  }

  handleTileClick(event) {
    const link = (this.summary.lists || {})[event.currentTarget.dataset.key];
    if (!link) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: { objectApiName: link.objectApiName, actionName: "list" },
      state: { filterName: link.listViewId }
    });
  }

  async loadVehicles(noticeId) {
    this.loadingVehicles = true;
    try {
      this.vehicles = (await getAffectedVehicles({ noticeId })) || [];
    } catch (e) {
      this.vehicles = [];
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Could not load affected vehicles",
          message: reduceError(e),
          variant: "error"
        })
      );
    } finally {
      this.loadingVehicles = false;
    }
  }

  handleNoticeAction(event) {
    const row = event.detail.row;
    this.selectedNotice = this.notices.find((n) => n.id === row.id);
    this.loadVehicles(row.id);
  }

  handleCloseDrill() {
    this.selectedNotice = undefined;
    this.vehicles = [];
  }

  handleOpenNotice() {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: { recordId: this.selectedNotice.id, actionName: "view" }
    });
  }

  handleFilter(event) {
    const { name, value } = event.target;
    this[name] = value;
  }

  handleClearFilters() {
    this.typeFilter = ALL;
    this.jurisdictionFilter = ALL;
    this.statusFilter = ALL;
  }

  // ------------------------------------------------------------------ view state

  get ready() {
    return !this.loading && !this.error && !!this.summary;
  }

  get isSample() {
    return !!this.summary && this.summary.isSample;
  }

  get tiles() {
    const s = this.summary;
    if (!s) {
      return [];
    }
    const byType = Object.fromEntries(
      (s.openByType || []).map((t) => [t.alertType, t.count])
    );
    const lists = s.lists || {};
    return [
      {
        key: "gap",
        label: "Open data gaps",
        value: byType["Data gap"] || 0,
        icon: alertTypeIcon("Data gap")
      },
      {
        key: "rcl",
        label: "Open recall alerts",
        value: byType.Recall || 0,
        icon: alertTypeIcon("Recall")
      },
      {
        key: "reg",
        label: "Open regulation alerts",
        value: byType.Regulation || 0,
        icon: alertTypeIcon("Regulation")
      },
      {
        key: "risk",
        label: "Vehicles at risk",
        value: s.vehiclesAtRisk || 0,
        icon: "utility:error"
      },
      {
        key: "new",
        label: "New notices, last 7 days",
        value: s.newNotices7d || 0,
        icon: "utility:notification"
      },
      {
        key: "avg",
        label: "Average fleet data health",
        value:
          s.averageHealth === null || s.averageHealth === undefined
            ? "–"
            : s.averageHealth,
        sub: `${s.scoredVehicles || 0} vehicles scored`,
        icon: "utility:shield"
      }
    ].map((t) => ({
      ...t,
      linked: !!lists[t.key],
      linkTitle: `Open the records behind "${t.label}"`
    }));
  }

  get typeOptions() {
    return [ALL, "Recall", "Regulation", "Service bulletin"].map((v) => ({
      label: v || "All types",
      value: v
    }));
  }

  get statusOptions() {
    return [ALL, "Active", "Draft", "Withdrawn"].map((v) => ({
      label: v || "All statuses",
      value: v
    }));
  }

  get jurisdictionOptions() {
    const codes = new Set();
    this.notices.forEach((n) =>
      splitCodes(n.jurisdiction).forEach((c) => codes.add(c))
    );
    return [{ label: "All jurisdictions", value: ALL }].concat(
      [...codes].sort().map((c) => ({ label: c, value: c }))
    );
  }

  get filteredNotices() {
    return this.notices
      .filter((n) => !this.typeFilter || n.noticeType === this.typeFilter)
      .filter((n) => !this.statusFilter || n.status === this.statusFilter)
      .filter((n) => {
        if (!this.jurisdictionFilter) {
          return true;
        }
        const codes = splitCodes(n.jurisdiction);
        return codes.length === 0 || codes.includes(this.jurisdictionFilter);
      })
      .map((n) => ({
        ...n,
        jurisdictionText: n.jurisdiction || "All",
        statusText:
          n.status === "Active" && !n.reviewed
            ? "Active, not reviewed"
            : n.status,
        statusIcon: noticeStatusIcon(n)
      }));
  }

  get hasNotices() {
    return this.filteredNotices.length > 0;
  }

  get noticeCountLabel() {
    const shown = this.filteredNotices.length;
    return shown === this.notices.length
      ? `${shown} notices`
      : `${shown} of ${this.notices.length} notices`;
  }

  get vehicleRows() {
    return this.vehicles.map((v) => ({
      ...v,
      assetUrl: `/${v.assetId}`,
      healthText:
        v.healthScore === null || v.healthScore === undefined
          ? "Not scored"
          : `${v.healthScore} ${v.healthStatus || ""}`.trim(),
      healthIcon: HEALTH_ICON[v.healthStatus] || "utility:help"
    }));
  }

  get hasVehicles() {
    return this.vehicles.length > 0;
  }

  get isRecall() {
    return this.selectedNotice && this.selectedNotice.noticeType === "Recall";
  }

  get drillTitle() {
    return this.selectedNotice
      ? `Affected vehicles: ${this.selectedNotice.title}`
      : "";
  }

  get sourceRows() {
    return this.sources.map((s) => ({
      ...s,
      staleLabel: `${s.stale} of ${s.streams} streams stale or missing (${s.staleShare}%)`,
      flagIcon: s.staleShare >= 25 ? "utility:warning" : "utility:success",
      flagText: s.staleShare >= 25 ? "Needs attention" : "OK"
    }));
  }

  get hasSources() {
    return this.sources.length > 0;
  }
}

function splitCodes(jurisdiction) {
  return (jurisdiction || "")
    .split(/[;,\s]+/)
    .map((c) => c.trim().toUpperCase())
    .filter((c) => c);
}

function noticeStatusIcon(n) {
  if (n.status === "Withdrawn") {
    return "utility:ban";
  }
  if (n.status === "Active" && n.reviewed) {
    return "utility:success";
  }
  return "utility:edit";
}
