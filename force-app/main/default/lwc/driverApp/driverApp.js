import { LightningElement, api } from "lwc";
import BRAND from "@salesforce/resourceUrl/FleetForceBrand";
import DRIVER_PWA from "@salesforce/resourceUrl/fleetforce_driver_pwa";
import getDrivers from "@salesforce/apex/DriverAppController.getDrivers";
import getDashboard from "@salesforce/apex/DriverAppController.getDashboard";
import startTrip from "@salesforce/apex/DriverAppController.startTrip";
import endTrip from "@salesforce/apex/DriverAppController.endTrip";
import logTrip from "@salesforce/apex/DriverAppController.logTrip";
import updateTrip from "@salesforce/apex/DriverAppController.updateTrip";
import reportIssue from "@salesforce/apex/DriverAppController.reportIssue";
import logFuel from "@salesforce/apex/DriverAppController.logFuel";
import attachPhoto from "@salesforce/apex/DriverAppController.attachPhoto";
import {
  distanceUnit,
  formatInZone,
  formatMoney,
  fuelEconomy,
  fuelLogUnit,
  volumeLabel,
  zoneLabel
} from "c/fleetRegional";

const CHECKS = [
  { key: "tires", label: "Tires and wheels" },
  { key: "lights", label: "Lights and indicators" },
  { key: "fluids", label: "Fluids / charge port" },
  { key: "brakes", label: "Brakes feel normal" },
  { key: "glass", label: "Windshield and mirrors" },
  { key: "clean", label: "Interior clean and tidy" }
];
const PRIORITIES = ["Low", "Medium", "High", "Critical"];
const ISSUE_CATEGORIES = [
  { value: "Corrective Repair", label: "Something is broken" },
  { value: "Inspection", label: "Needs an inspection" },
  { value: "Warranty", label: "Warranty / recall" },
  { value: "Other", label: "Something else" }
];
const TRIP_CATEGORIES = [
  { value: "Operations", label: "Operations" },
  { value: "Client Visit", label: "Client Visit" },
  { value: "Delivery", label: "Delivery" },
  { value: "Branch Transfer", label: "Branch Transfer" },
  { value: "Maintenance", label: "Maintenance" },
  { value: "Commute", label: "Commute" },
  { value: "Personal", label: "Personal" },
  { value: "Other", label: "Other" }
];
const MAX_PHOTOS = 3;
// Demo build: these drivers have a story in the seed data (scripts/apex/seed_driver_app.apex), so they lead the picker.
const FEATURED_DRIVERS = ["Chloe Bennett", "Hannah Lindqvist", "Carlos Gomez"];

const WEEKDAY = new Intl.DateTimeFormat("en-GB", {
  weekday: "short",
  day: "numeric",
  month: "short"
});
const WHEN_OPTIONS = {
  weekday: "short",
  day: "numeric",
  month: "short",
  hour: "2-digit",
  minute: "2-digit"
};
const CLOCK_OPTIONS = { hour: "2-digit", minute: "2-digit" };
function dateText(v) {
  return v
    ? WEEKDAY.format(new Date(v.length === 10 ? `${v}T12:00:00` : v))
    : "";
}
/** A date-time in the branch's time zone (the browser's when the branch has none). */
const whenText = (v, tz) => formatInZone(v, tz, WHEN_OPTIONS);
const number = (n) => (n == null ? "–" : Math.round(n).toLocaleString("en-US"));
const money = (n, currency) => formatMoney(n, currency);

function daysText(days) {
  if (days == null) return "";
  if (days < 0) return `expired ${-days} d ago`;
  if (days === 0) return "expires today";
  return `${days} d left`;
}
function daysClass(days, warnAt = 30) {
  if (days == null) return "chip";
  if (days < 0) return "chip chip--bad";
  return days <= warnAt ? "chip chip--warn" : "chip chip--ok";
}

/** Resize a photo on the device before upload (long edge 1280 px, JPEG) so uploads stay small on mobile data. */
function shrinkImage(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = reject;
    reader.onload = () => {
      const img = new Image();
      img.onerror = reject;
      img.onload = () => {
        const scale = Math.min(1, 1280 / Math.max(img.width, img.height));
        const canvas = document.createElement("canvas");
        canvas.width = Math.round(img.width * scale);
        canvas.height = Math.round(img.height * scale);
        canvas
          .getContext("2d")
          .drawImage(img, 0, 0, canvas.width, canvas.height);
        const dataUrl = canvas.toDataURL("image/jpeg", 0.72);
        resolve({ dataUrl, base64: dataUrl.split(",")[1] });
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}

const ALL_NAV_DEFINITIONS = [
  {
    key: "home",
    label: "Home",
    icon: "M3 11l9-8 9 8M5 10v10h5v-6h4v6h5V10"
  },
  {
    key: "vehicle",
    label: "Vehicle",
    icon: "M5 16l1.5-5a2 2 0 0 1 1.9-1.4h7.2a2 2 0 0 1 1.9 1.4L19 16M4 16h16v3H4zM7 19v1.5M17 19v1.5"
  },
  {
    key: "trips",
    label: "Trips",
    icon: "M5 4v16M5 5h11l-2 4 2 4H5"
  },
  {
    key: "route",
    label: "Route",
    icon: "M6 19a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM18 9a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM6 15V9a3 3 0 0 1 3-3h7M18 9v6a3 3 0 0 1-3 3H8"
  },
  {
    key: "me",
    label: "Me",
    icon: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0"
  }
];

export default class DriverApp extends LightningElement {
  @api motorpoolUrl;
  @api hideBookings = false;

  drivers = [];
  driverId;
  selectedAssetId;
  dash;
  loading = true;
  error;
  view = "home";
  sheet; // pretrip | endtrip | logTrip | issue | fuel | notices
  busy = false;
  sheetError;
  toast;

  // PWA & Offline
  showInstallBanner = false;
  showIosInstructions = false;
  isOffline = false;
  deferredPrompt;
  _onlineHandler;
  _offlineHandler;
  _beforeInstallHandler;

  // Drawer & Nav Customization
  isDrawerOpen = false;
  bottomNavKeys = ["home", "vehicle", "trips", "route"];
  _longPressTimer = null;

  // filters
  tripFilter = "all";

  // forms
  checks = {};
  odometer = "";
  energy = 50;
  notes = "";
  damage = false;
  issueCategory = "Corrective Repair";
  issuePriority = "Medium";
  fuelVolume = "";
  fuelCost = "";
  fuelStation = "";
  fuelFull = true;
  photos = [];

  // end trip reporting
  endTripType = "Business";
  endTripPurpose = "";
  endTripCategory = "Operations";

  // log / edit trip
  editingTripId;
  logTripAssetId;
  logTripType = "Business";
  logTripPurpose = "";
  logTripCategory = "Operations";
  logStartTime = "";
  logEndTime = "";
  logStartOdometer = "";
  logEndOdometer = "";
  logOrigin = "";
  logDestination = "";
  logNotes = "";

  _toastTimer;

  connectedCallback() {
    try {
      const saved = localStorage.getItem("fleetforce_driver_bottom_nav_keys");
      if (saved) {
        const parsed = JSON.parse(saved);
        if (Array.isArray(parsed) && parsed.length >= 2 && parsed.length <= 4) {
          this.bottomNavKeys = parsed;
        }
      }
    } catch {
      // ignore
    }
    this.init();
    this.initPwa();
  }

  disconnectedCallback() {
    clearTimeout(this._toastTimer);
    if (typeof window !== "undefined") {
      window.removeEventListener("online", this._onlineHandler);
      window.removeEventListener("offline", this._offlineHandler);
      window.removeEventListener(
        "beforeinstallprompt",
        this._beforeInstallHandler
      );
    }
  }

  initPwa() {
    if (typeof window === "undefined") return;

    this.isOffline = !navigator.onLine;
    this._onlineHandler = () => {
      this.isOffline = false;
      this.load();
    };
    this._offlineHandler = () => {
      this.isOffline = true;
    };
    window.addEventListener("online", this._onlineHandler);
    window.addEventListener("offline", this._offlineHandler);

    // Check standalone mode or dismissed state
    try {
      const dismissedAt = localStorage.getItem("ff_pwa_dismissed");
      const isDismissed =
        dismissedAt && Date.now() - Number(dismissedAt) < 7 * 86400000;
      const isStandalone =
        (window.matchMedia &&
          window.matchMedia("(display-mode: standalone)").matches) ||
        window.navigator.standalone === true;

      if (!isStandalone && !isDismissed) {
        if (this.isIos) {
          this.showInstallBanner = true;
        } else {
          this._beforeInstallHandler = (e) => {
            e.preventDefault();
            this.deferredPrompt = e;
            this.showInstallBanner = true;
          };
          window.addEventListener(
            "beforeinstallprompt",
            this._beforeInstallHandler
          );
        }
      }
    } catch {
      // LocalStorage access non-fatal
    }

    // Inject PWA metadata into document head if missing
    try {
      /* eslint-disable @lwc/lwc/no-document-query */
      if (!document.querySelector('link[rel="manifest"]')) {
        const m = document.createElement("link");
        m.rel = "manifest";
        m.href = `${DRIVER_PWA}/manifest.webmanifest`;
        document.head.appendChild(m);
      }
      if (
        !document.querySelector('meta[name="apple-mobile-web-app-capable"]')
      ) {
        const m1 = document.createElement("meta");
        m1.name = "apple-mobile-web-app-capable";
        m1.content = "yes";
        document.head.appendChild(m1);

        const m2 = document.createElement("meta");
        m2.name = "apple-mobile-web-app-status-bar-style";
        m2.content = "black-translucent";
        document.head.appendChild(m2);

        const icon = document.createElement("link");
        icon.rel = "apple-touch-icon";
        icon.href = `${DRIVER_PWA}/app-icon-192.png`;
        document.head.appendChild(icon);
      }
      /* eslint-enable @lwc/lwc/no-document-query */
      if ("serviceWorker" in navigator) {
        navigator.serviceWorker.register(`${DRIVER_PWA}/sw.js`).catch(() => {});
      }
    } catch {
      // Head injection non-fatal in restricted iframes
    }
  }

  get installButtonLabel() {
    return this.isIos ? "Install Guide" : "Install App";
  }

  async handleInstallClick() {
    if (this.deferredPrompt) {
      this.deferredPrompt.prompt();
      const choice = await this.deferredPrompt.userChoice;
      if (choice && choice.outcome === "accepted") {
        this.showInstallBanner = false;
      }
      this.deferredPrompt = null;
    } else if (this.isIos) {
      this.showIosInstructions = !this.showIosInstructions;
    }
  }

  handleDismissInstallBanner() {
    this.showInstallBanner = false;
    this.showIosInstructions = false;
    try {
      localStorage.setItem("ff_pwa_dismissed", String(Date.now()));
    } catch {
      // ignore
    }
  }

  async init() {
    try {
      const all = await getDrivers();
      const rank = (d) => {
        const i = FEATURED_DRIVERS.indexOf(d.name);
        return i === -1 ? FEATURED_DRIVERS.length : i;
      };
      this.drivers = (all || [])
        .map((d, i) => ({ d, i }))
        .sort((a, b) => rank(a.d) - rank(b.d) || a.i - b.i)
        .map((x) => x.d);

      if (this.drivers.length) {
        this.driverId = this.drivers[0].id;
      } else {
        this.driverId = null;
      }
      await this.load();
    } catch (e) {
      this.fail(e);
    }
  }

  async handleReload() {
    await this.init();
  }

  async load() {
    this.loading = true;
    this.error = undefined;
    try {
      this.dash = await getDashboard({
        driverId: this.driverId,
        selectedAssetId: this.selectedAssetId
      });
      if (this.dash && this.dash.driver && this.dash.driver.id) {
        this.driverId = this.dash.driver.id;
      }
      if (this.dash && this.dash.vehicle) {
        this.selectedAssetId = this.dash.vehicle.id;
      }
      // Cache for offline glovebox & dashboard access
      try {
        if (this.dash && this.dash.driver) {
          localStorage.setItem(
            `ff_dash_${this.driverId}`,
            JSON.stringify(this.dash)
          );
        }
      } catch {
        // ignore
      }
    } catch (e) {
      // Try offline cache fallback
      try {
        const cached = localStorage.getItem(`ff_dash_${this.driverId}`);
        if (cached) {
          this.dash = JSON.parse(cached);
          this.isOffline = true;
          this.loading = false;
          return;
        }
      } catch {
        // ignore
      }
      this.fail(e);
    } finally {
      this.loading = false;
    }
  }

  fail(e) {
    this.loading = false;
    this.error =
      (e && e.body && e.body.message) ||
      "Something went wrong. Please try again.";
  }

  showToast(message) {
    this.toast = message;
    clearTimeout(this._toastTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._toastTimer = setTimeout(() => {
      this.toast = undefined;
    }, 3500);
  }

  // ---------- header / navigation ----------
  get wordmarkUrl() {
    return `${BRAND}/wordmark-on-dark.png`;
  }

  get driverOptions() {
    return this.drivers.map((d) => ({
      value: d.id,
      label: d.vehicle ? `${d.name} · ${d.vehicle}` : `${d.name} · no vehicle`,
      selected: d.id === this.driverId
    }));
  }

  async handleDriver(event) {
    this.driverId = event.target.value;
    this.selectedAssetId = undefined;
    this.view = "home";
    await this.load();
  }

  get showAdminBar() {
    return this.dash && this.dash.isAdminMode === true;
  }

  get isUnlinked() {
    return this.dash && this.dash.isDriverLinked === false;
  }

  get unlinkedUserName() {
    return this.dash?.userName || "User";
  }

  get unlinkedUserEmail() {
    return this.dash?.userEmail || "";
  }

  get isGuestUser() {
    return this.dash?.isGuestUser === true;
  }

  get showHamburger() {
    if (this.isUnlinked && !this.showAdminBar) {
      return false;
    }
    return true;
  }

  get showBell() {
    if (this.isUnlinked && !this.showAdminBar) {
      return false;
    }
    return true;
  }

  get showBottomNav() {
    if (this.isUnlinked && !this.showAdminBar) {
      return false;
    }
    return true;
  }

  get driverInitials() {
    if (!this.dash?.driver?.name) return "DR";
    const parts = this.dash.driver.name.trim().split(/\s+/);
    if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  get driverName() {
    return this.dash?.driver?.name || "Driver";
  }

  get driverStatus() {
    return this.dash?.driver?.status || "Active";
  }

  get pwaStatusDotCls() {
    return `drawer__status-dot ${this.isOffline ? "drawer__status-dot--offline" : "drawer__status-dot--online"}`;
  }

  get pwaStatusText() {
    return this.isOffline ? "Offline Mode (Cached)" : "Online & Synchronized";
  }

  get vehicleDropdownOptions() {
    if (!this.authorized || !this.authorized.length) {
      return [];
    }
    return this.authorized.map((a) => {
      const typePart = a.authType ? ` [${a.authType}]` : "";
      const activePart = a.isCurrent ? " (Active)" : "";
      return {
        value: a.assetId,
        label: `${a.name}${a.plate ? " · " + a.plate : ""}${typePart}${activePart}`,
        selected: a.isCurrent
      };
    });
  }

  async handleSwitchVehicleSelect(event) {
    const assetId = event.target.value;
    if (assetId && assetId !== this.vehicle?.id) {
      this.selectedAssetId = assetId;
      await this.load();
    }
  }

  async handleSwitchVehicle(event) {
    const assetId = event.currentTarget.dataset.assetId;
    if (assetId && assetId !== this.selectedAssetId) {
      this.selectedAssetId = assetId;
      await this.load();
    }
  }

  openDrawer() {
    this.isDrawerOpen = true;
  }

  closeDrawer() {
    this.isDrawerOpen = false;
  }

  handleDrawerNav(event) {
    const view = event.currentTarget.dataset.view;
    if (view) {
      this.view = view;
      this.closeDrawer();
      this.scrollTop();
    }
  }

  handleOpenNavCustomizer() {
    this.closeDrawer();
    this.sheet = "navCustomizer";
  }

  get isNavCustomizerSheet() {
    return this.sheet === "navCustomizer";
  }

  get navCustomizerOptions() {
    return ALL_NAV_DEFINITIONS.map((def) => {
      const idx = this.bottomNavKeys.indexOf(def.key);
      return {
        ...def,
        checked: idx !== -1,
        slot: idx !== -1 ? idx + 1 : null
      };
    });
  }

  handleToggleBottomNavItem(event) {
    const key = event.target.dataset.key;
    const isChecked = event.target.checked;
    let current = [...this.bottomNavKeys];
    if (isChecked) {
      if (current.length >= 4) {
        current.pop();
      }
      current.push(key);
    } else {
      if (current.length <= 2) {
        this.showToast("At least 2 shortcuts required");
        event.target.checked = true;
        return;
      }
      current = current.filter((k) => k !== key);
    }
    this.bottomNavKeys = current;
    try {
      localStorage.setItem(
        "fleetforce_driver_bottom_nav_keys",
        JSON.stringify(current)
      );
    } catch {
      // ignore
    }
  }

  handleNavTouchStart() {
    this._startLongPress();
  }

  handleNavTouchEnd() {
    this._cancelLongPress();
  }

  handleNavMouseDown() {
    this._startLongPress();
  }

  handleNavMouseUp() {
    this._cancelLongPress();
  }

  _startLongPress() {
    this._cancelLongPress();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._longPressTimer = setTimeout(() => {
      this.sheet = "navCustomizer";
    }, 600);
  }

  _cancelLongPress() {
    if (this._longPressTimer) {
      clearTimeout(this._longPressTimer);
      this._longPressTimer = null;
    }
  }

  get navItems() {
    return ALL_NAV_DEFINITIONS.filter((item) =>
      this.bottomNavKeys.includes(item.key)
    ).map((n) => ({
      ...n,
      cls: `nav__btn${this.view === n.key ? " nav__btn--on" : ""}`,
      current: this.view === n.key ? "page" : "false"
    }));
  }

  get allNavOptions() {
    return ALL_NAV_DEFINITIONS.map((item) => ({
      ...item,
      drawerCls: `drawer__item${this.view === item.key ? " drawer__item--active" : ""}`,
      activeBadge: this.view === item.key ? "Active" : null
    }));
  }

  handleNav(event) {
    this.view = event.currentTarget.dataset.view;
    this.scrollTop();
  }

  scrollTop() {
    const body = this.template.querySelector(".body");
    if (body) body.scrollTop = 0;
  }

  get isHome() {
    return this.view === "home";
  }
  get isVehicle() {
    return this.view === "vehicle";
  }
  get isTrips() {
    return this.view === "trips";
  }
  get isRoute() {
    return this.view === "route";
  }
  get isMe() {
    return this.view === "me";
  }
  get ready() {
    return !this.loading && this.dash;
  }

  // ---------- home ----------
  get greeting() {
    const h = new Date().getHours();
    const part =
      h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
    return `${part}, ${this.dash.driver.firstName || this.dash.driver.name}`;
  }

  get hasVehicle() {
    return !!(this.dash && this.dash.vehicle);
  }
  get onTrip() {
    return !!(this.dash && this.dash.openTrip);
  }

  get tripBanner() {
    const t = this.dash.openTrip;
    if (!t) return null;
    const mins = Math.max(
      0,
      Math.round((Date.now() - new Date(t.checkOut).getTime()) / 60000)
    );
    const dur =
      mins >= 60
        ? `${Math.floor(mins / 60)} h ${mins % 60} min`
        : `${mins} min`;
    return {
      title: "You are on a trip",
      detail: `Started ${formatInZone(t.checkOut, this.zone, CLOCK_OPTIONS)} · ${dur} · odometer ${number(t.odometerStart)} ${this.distanceUnit}`
    };
  }

  get vehicle() {
    const v = this.dash.vehicle;
    const electric = v.fuelType === "Electric";
    const level =
      v.energyLevel == null
        ? null
        : Math.max(0, Math.min(100, Math.round(v.energyLevel)));
    return {
      ...v,
      energyLabel: electric ? "Charge" : "Fuel",
      energyText: level == null ? "–" : `${level}%`,
      energyBar: `width:${level == null ? 0 : level}%`,
      energyCls: `bar__fill${level != null && level < 20 ? " bar__fill--low" : ""}`,
      odometerText: number(v.odometer),
      distanceUnit: distanceUnit(v.distanceUnit),
      rangeText: v.epaRated ? this.rangeText(v) : "",
      seatsText: v.seats ? `${v.seats} seats` : ""
    };
  }

  rangeText(v) {
    const fe = fuelEconomy(v, v.fuelEconomyFormat, v.distanceUnit);
    if (!fe) return "";
    return v.evRangeMiles != null ? fe.detail : fe.short;
  }

  /** The branch time zone used for times on screen: the vehicle's, else the driver's branch. */
  get zone() {
    const d = this.dash;
    return (
      (d && d.vehicle && d.vehicle.timeZone) ||
      (d && d.driver && d.driver.timeZone) ||
      undefined
    );
  }

  zoneSuffix(tz) {
    const label = zoneLabel(tz || this.zone);
    return label ? ` · ${label}` : "";
  }

  get fuelCostLabel() {
    return this.currencyCode
      ? `Total cost (${this.currencyCode})`
      : "Total cost";
  }

  get distanceUnit() {
    return distanceUnit(
      this.dash && this.dash.vehicle && this.dash.vehicle.distanceUnit
    );
  }

  get currencyCode() {
    const d = this.dash;
    return (
      (d && d.vehicle && d.vehicle.currencyCode) ||
      (d && d.driver && d.driver.currencyCode) ||
      undefined
    );
  }

  get vehicleChips() {
    const v = this.dash.vehicle;
    return [
      v.fuelType,
      v.branch,
      this.vehicle.seatsText,
      this.vehicle.rangeText,
      v.authorizationType ? `${v.authorizationType} driver` : ""
    ]
      .filter(Boolean)
      .map((t, i) => ({ key: `c${i}`, text: t }));
  }

  get quickActions() {
    const trip = this.onTrip
      ? {
          key: "endtrip",
          label: "End trip",
          hint: "Return the vehicle",
          icon: "M5 4v16M5 5h11l-2 4 2 4H5"
        }
      : {
          key: "pretrip",
          label: "Pre-trip check",
          hint: "Start your trip",
          icon: "M9 12l2 2 4-4M12 3l8 3v6c0 4.5-3.2 7.7-8 9-4.8-1.3-8-4.5-8-9V6z"
        };
    return [
      trip,
      {
        key: "glovebox",
        label: "Digital Glovebox",
        hint: "Insurance & Reg",
        icon: "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zM14 2v6h6M16 13H8M16 17H8M10 9H8"
      },
      {
        key: "navigate",
        label: "Navigate to car",
        hint: "Open in maps",
        icon: "M12 21s-6-5.6-6-10a6 6 0 0 1 12 0c0 4.4-6 10-6 10zM12 13a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z"
      },
      {
        key: "issue",
        label: "Report an issue",
        hint: "Tell the workshop",
        icon: "M12 3l10 18H2zM12 10v5M12 18v.01"
      },
      {
        key: "fuel",
        label:
          this.vehicle.fuelType === "Electric" ? "Log charging" : "Log fuel",
        hint: "Fill-up or charge",
        icon: "M6 20V5a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v15M5 20h10M14 9h2.5a1.5 1.5 0 0 1 1.5 1.5V16a1.5 1.5 0 0 0 3 0V9l-3-3"
      }
    ].map((a) => ({
      ...a,
      cls: `action${a.key === "endtrip" || a.key === "pretrip" ? " action--primary" : ""}`
    }));
  }

  handleAction(event) {
    const key = event.currentTarget.dataset.key;
    if (key === "navigate") {
      this.navigate();
    } else if (key === "glovebox") {
      this.view = "vehicle";
      this.scrollTop();
    } else {
      this.openSheet(key);
    }
  }

  get notices() {
    return (this.dash.notices || []).map((n, i) => ({
      ...n,
      key: `n${i}`,
      cls: `notice notice--${n.level}`
    }));
  }

  get topNotices() {
    return this.notices.slice(0, 3);
  }
  get noticeCount() {
    return this.notices.length;
  }
  get hasNotices() {
    return this.notices.length > 0;
  }
  get noticeBadge() {
    return this.noticeCount > 9 ? "9+" : String(this.noticeCount);
  }

  get nextBooking() {
    const r = (this.dash.reservations || [])[0];
    return r
      ? {
          ...r,
          when: whenText(r.startTime, r.timeZone || this.zone),
          until: whenText(r.endTime, r.timeZone || this.zone),
          zoneSuffix: this.zoneSuffix(r.timeZone)
        }
      : null;
  }

  get showBookings() {
    return !this.hideBookings;
  }

  handleBook() {
    if (this.motorpoolUrl) {
      window.location.assign(this.motorpoolUrl);
      return;
    }
    // If hosted on /driver, navigate to the site root, else fallback to /motorpool
    const path = window.location.pathname || "";
    if (path.endsWith("/driver") || path.endsWith("/driver/")) {
      window.location.assign(path.replace(/\/driver\/?$/, ""));
    } else {
      window.location.assign("/motorpool");
    }
  }

  // ---------- vehicle ----------
  get hasLocation() {
    const v = this.dash && this.dash.vehicle;
    return !!(v && v.latitude != null && v.longitude != null);
  }

  get mapMarkers() {
    const v = this.dash.vehicle;
    return [
      {
        location: { Latitude: v.latitude, Longitude: v.longitude },
        title: v.name,
        description: v.plate || ""
      }
    ];
  }

  get mapCenter() {
    const v = this.dash.vehicle;
    return { location: { Latitude: v.latitude, Longitude: v.longitude } };
  }

  get isIos() {
    return /iPad|iPhone|iPod/.test(navigator.userAgent);
  }

  get navigateUrl() {
    const v = this.dash.vehicle;
    return this.isIos
      ? `https://maps.apple.com/?daddr=${v.latitude},${v.longitude}&dirflg=d`
      : `https://www.google.com/maps/dir/?api=1&destination=${v.latitude},${v.longitude}&travelmode=driving`;
  }

  get navigateLabel() {
    return this.isIos ? "Open in Apple Maps" : "Open in Google Maps";
  }

  navigate() {
    if (this.hasLocation) {
      window.open(this.navigateUrl, "_blank", "noopener");
    } else {
      this.view = "vehicle";
    }
  }

  get locationText() {
    return "Last known location";
  }

  get authorized() {
    return (this.dash.authorized || []).map((a) => ({
      ...a,
      key: a.assetId,
      sub: [a.plate, a.authType].filter(Boolean).join(" · "),
      until: a.endDate ? `until ${dateText(a.endDate)}` : "",
      keyText: a.hasKey ? "Key issued" : "",
      badgeText: a.isCurrent ? "Active" : a.isPrimary ? "Primary" : "Authorized"
    }));
  }

  get hasMultipleVehicles() {
    return (this.dash.authorized || []).length > 1;
  }

  get vehicleSelectorPills() {
    return (this.dash.authorized || []).map((a) => ({
      id: a.assetId,
      name: a.name,
      plate: a.plate,
      isCurrent: a.isCurrent,
      cls: `v-pill${a.isCurrent ? " v-pill--active" : ""}`
    }));
  }

  get documents() {
    return (this.dash.documents || []).map((d) => ({
      ...d,
      sub: [
        d.docNumber,
        d.validUntil ? `valid until ${dateText(d.validUntil)}` : "no expiry"
      ]
        .filter(Boolean)
        .join(" · "),
      chipText: daysText(d.daysLeft),
      chipCls: daysClass(d.daysLeft),
      hasLink: !!d.link
    }));
  }

  get tickets() {
    return (this.dash.tickets || []).map((t) => ({
      ...t,
      title: t.summary || t.category || t.name,
      sub: [
        t.name,
        t.status === "In-Shop" ? "In the workshop" : "Reported",
        t.scheduledStart ? `scheduled ${dateText(t.scheduledStart)}` : ""
      ]
        .filter(Boolean)
        .join(" · "),
      chipCls: `chip chip--${t.priority === "Critical" || t.priority === "High" ? "bad" : t.priority === "Medium" ? "warn" : "ok"}`
    }));
  }

  // ---------- trips ----------
  get tripSummary() {
    const d = this.dash || {};
    const total = d.monthTotalDistance || 0;
    const biz = d.monthBusinessDistance || 0;
    const priv = d.monthPrivateDistance || 0;
    const pct = total > 0 ? Math.round((biz / total) * 100) : 0;
    const unit = this.distanceUnit;
    return {
      totalText: `${number(total)} ${unit}`,
      businessText: `${number(biz)} ${unit}`,
      privateText: `${number(priv)} ${unit}`,
      businessPct: `${pct}%`,
      privatePct: `${100 - pct}%`,
      barStyle: `width:${pct}%`
    };
  }

  get tripFilterTabs() {
    return [
      { key: "all", label: "All Trips" },
      { key: "business", label: "Business" },
      { key: "private", label: "Private" },
      { key: "review", label: "Needs Review" }
    ].map((f) => ({
      ...f,
      cls: `filter-btn${this.tripFilter === f.key ? " filter-btn--active" : ""}`
    }));
  }

  handleTripFilter(event) {
    this.tripFilter = event.currentTarget.dataset.filter;
  }

  get filteredTripLogs() {
    const logs = (this.dash?.tripLogs || []).map((t) => {
      const isBiz = t.tripType === "Business";
      const isPriv = t.tripType === "Private";
      const status = t.approvalStatus;
      let statusCls = "chip";
      let statusLabel = status || "Submitted";
      if (status === "Auto-Approved" || status === "Approved") {
        statusCls = "chip chip--ok";
        statusLabel = status === "Auto-Approved" ? "Auto-Approved" : "Approved";
      } else if (status === "Rejected") {
        statusCls = "chip chip--bad";
        statusLabel = "Needs Revision";
      } else {
        statusCls = "chip chip--warn";
        statusLabel = "Pending Review";
      }
      return {
        ...t,
        isBusiness: isBiz,
        isPrivate: isPriv,
        typeCls: `chip ${isBiz ? "chip--info" : "chip--neutral"}`,
        typeLabel: t.tripType || "Business",
        statusCls,
        statusLabel,
        distanceText:
          t.distance != null
            ? `${number(t.distance)} ${distanceUnit(t.distanceUnit)}`
            : "–",
        whenText: whenText(t.startTime, this.zone),
        routeText:
          [t.originAddress, t.destinationAddress].filter(Boolean).join(" → ") ||
          "Local driving",
        canEdit: t.canEdit
      };
    });

    if (this.tripFilter === "business") {
      return logs.filter((t) => t.isBusiness);
    }
    if (this.tripFilter === "private") {
      return logs.filter((t) => t.isPrivate);
    }
    if (this.tripFilter === "review") {
      return logs.filter(
        (t) =>
          t.approvalStatus === "Submitted" || t.approvalStatus === "Rejected"
      );
    }
    return logs;
  }

  get hasFilteredTrips() {
    return this.filteredTripLogs.length > 0;
  }

  handleOpenLogTrip() {
    this.openSheet("logTrip");
  }

  handleTripClick(event) {
    const tripId = event.currentTarget.dataset.tripId;
    const trip = (this.dash?.tripLogs || []).find((t) => t.id === tripId);
    if (!trip || !trip.canEdit) return;

    this.sheetError = undefined;
    this.editingTripId = trip.id;
    this.logTripAssetId = trip.assetId;
    this.logTripType = trip.tripType || "Business";
    this.logTripPurpose = trip.businessPurpose || "";
    this.logTripCategory = trip.category || "Operations";
    this.logStartTime = trip.startTime
      ? new Date(trip.startTime).toISOString().slice(0, 16)
      : "";
    this.logEndTime = trip.endTime
      ? new Date(trip.endTime).toISOString().slice(0, 16)
      : "";
    this.logStartOdometer =
      trip.odometerStart != null ? String(trip.odometerStart) : "";
    this.logEndOdometer =
      trip.odometerEnd != null ? String(trip.odometerEnd) : "";
    this.logOrigin = trip.originAddress || "";
    this.logDestination = trip.destinationAddress || "";
    this.logNotes = trip.driverNotes || "";
    this.sheet = "logTrip";
  }

  get reservations() {
    return (this.dash.reservations || []).map((r) => ({
      ...r,
      when: whenText(r.startTime, r.timeZone || this.zone),
      until: whenText(r.endTime, r.timeZone || this.zone),
      zoneSuffix: this.zoneSuffix(r.timeZone),
      chipCls: `chip chip--${r.status === "Approved" || r.status === "Active" ? "ok" : "warn"}`
    }));
  }

  get hasReservations() {
    return this.reservations.length > 0;
  }

  get recentTrips() {
    return (this.dash.recentTrips || []).map((t) => ({
      ...t,
      when: whenText(t.checkOut, this.zone),
      distanceText:
        t.distance != null
          ? `${number(t.distance)} ${distanceUnit(t.distanceUnit)}`
          : "",
      damageText: t.newDamage ? "Damage reported" : ""
    }));
  }

  get hasTrips() {
    return this.recentTrips.length > 0;
  }

  // ---------- me ----------
  get driver() {
    const d = this.dash.driver;
    const score =
      d.safetyScore == null
        ? null
        : Math.max(0, Math.min(100, Math.round(d.safetyScore)));
    const circumference = 2 * Math.PI * 34;
    return {
      ...d,
      score: score == null ? "–" : String(score),
      ringStyle: `stroke-dasharray:${score == null ? 0 : (circumference * score) / 100} ${circumference}`,
      ringCls: `ring__value${score != null && score < 70 ? " ring__value--low" : ""}`,
      licenseSub: [
        d.licenseClass ? `Class ${d.licenseClass}` : "",
        d.licenseState,
        d.licenseNumber
      ]
        .filter(Boolean)
        .join(" · "),
      licenseChip: d.licenseExpiry ? daysText(d.licenseDaysLeft) : "",
      licenseCls: daysClass(d.licenseDaysLeft, 60),
      medicalSub: d.medicalCert
        ? `valid until ${dateText(d.medicalCert)}`
        : "not on file",
      medicalChip: d.medicalCert ? daysText(d.medicalDaysLeft) : "",
      medicalCls: daysClass(d.medicalDaysLeft, 60)
    };
  }

  get qualifications() {
    return (this.dash.qualifications || []).map((q) => ({
      ...q,
      title: q.authority ? `${q.qualType} · ${q.authority}` : q.qualType,
      sub: q.validUntil
        ? `valid until ${dateText(q.validUntil)}`
        : "does not expire",
      chipText: q.validUntil ? daysText(q.daysLeft) : "",
      chipCls: daysClass(q.daysLeft, 60)
    }));
  }

  get violations() {
    return (this.dash.violations || []).map((v) => ({
      ...v,
      sub: [whenText(v.occurredAt, this.zone), v.vehicle, v.value]
        .filter(Boolean)
        .join(" · "),
      chipCls: `chip chip--${v.severity === "Critical" || v.severity === "High" ? "bad" : v.severity === "Medium" ? "warn" : "ok"}`
    }));
  }

  get citations() {
    return (this.dash.citations || []).map((c) => ({
      ...c,
      title: c.violationType || "Citation",
      sub: [
        c.ticketNumber,
        c.citationDate ? dateText(c.citationDate) : "",
        c.courtDate ? `court ${dateText(c.courtDate)}` : ""
      ]
        .filter(Boolean)
        .join(" · "),
      amountText: money(c.amount, this.currencyCode),
      chipCls: `chip chip--${c.status === "New" ? "bad" : c.status === "Contested" ? "warn" : "ok"}`
    }));
  }

  get hasViolations() {
    return this.violations.length > 0;
  }
  get hasCitations() {
    return this.citations.length > 0;
  }
  get hasQualifications() {
    return this.qualifications.length > 0;
  }

  get fuelCard() {
    const f = this.dash.fuelCard;
    return f
      ? {
          ...f,
          number: f.lastDigits ? `•••• ${f.lastDigits}` : "",
          limitText: f.dailyLimit
            ? `${money(f.dailyLimit, this.currencyCode)} / day`
            : "",
          expiryText: f.expiry ? `expires ${dateText(f.expiry)}` : ""
        }
      : null;
  }

  // ---------- sheets ----------
  openSheet(key) {
    this.sheetError = undefined;
    this.photos = [];
    this.notes = "";
    this.damage = false;
    if (key === "pretrip" || key === "endtrip") {
      const v = this.dash.vehicle;
      this.odometer =
        v && v.odometer != null ? String(Math.round(v.odometer)) : "";
      this.energy = v && v.energyLevel != null ? Math.round(v.energyLevel) : 50;
      this.checks = CHECKS.reduce((m, c) => ({ ...m, [c.key]: true }), {});
      if (key === "endtrip") {
        this.endTripType = "Business";
        this.endTripPurpose = "";
        this.endTripCategory = "Operations";
      }
    }
    if (key === "logTrip") {
      this.editingTripId = undefined;
      this.logTripAssetId = this.vehicle
        ? this.vehicle.id
        : this.authorized[0] && this.authorized[0].assetId;
      this.logTripType = "Business";
      this.logTripPurpose = "";
      this.logTripCategory = "Operations";
      const now = new Date();
      this.logEndTime = now.toISOString().slice(0, 16);
      now.setHours(now.getHours() - 1);
      this.logStartTime = now.toISOString().slice(0, 16);
      const v = this.dash.vehicle;
      const curOdo = v && v.odometer != null ? Math.round(v.odometer) : 0;
      this.logStartOdometer = curOdo ? String(curOdo) : "";
      this.logEndOdometer = curOdo ? String(curOdo + 15) : "";
      this.logOrigin = (this.dash.driver && this.dash.driver.branch) || "";
      this.logDestination = "";
      this.logNotes = "";
    }
    if (key === "issue") {
      this.issueCategory = "Corrective Repair";
      this.issuePriority = "Medium";
    }
    if (key === "fuel") {
      this.fuelVolume = "";
      this.fuelCost = "";
      this.fuelStation = "";
      this.fuelFull = true;
      const v = this.dash.vehicle;
      this.odometer =
        v && v.odometer != null ? String(Math.round(v.odometer)) : "";
    }
    this.sheet = key;
  }

  closeSheet() {
    if (!this.busy) this.sheet = undefined;
  }

  get sheetOpen() {
    return !!this.sheet;
  }
  get isPretrip() {
    return this.sheet === "pretrip";
  }
  get isEndtrip() {
    return this.sheet === "endtrip";
  }
  get isEndTrip() {
    return this.sheet === "endtrip";
  }
  get isEndTripBusiness() {
    return this.endTripType === "Business";
  }
  get tripTypeBusinessCls() {
    return `btn ${this.endTripType === "Business" ? "btn--primary" : "btn--ghost"}`;
  }
  get tripTypePrivateCls() {
    return `btn ${this.endTripType === "Private" ? "btn--primary" : "btn--ghost"}`;
  }
  handleEndTripType(event) {
    this.endTripType = event.currentTarget.dataset.type;
  }

  get isLogTripSheet() {
    return this.sheet === "logTrip";
  }
  get isLogTripBusiness() {
    return this.logTripType === "Business";
  }
  get logTripBusinessCls() {
    return `btn ${this.logTripType === "Business" ? "btn--primary" : "btn--ghost"}`;
  }
  get logTripPrivateCls() {
    return `btn ${this.logTripType === "Private" ? "btn--primary" : "btn--ghost"}`;
  }
  handleLogTripType(event) {
    this.logTripType = event.currentTarget.dataset.type;
  }

  get logCalculatedDistanceText() {
    const s =
      this.logStartOdometer === "" ? null : Number(this.logStartOdometer);
    const e = this.logEndOdometer === "" ? null : Number(this.logEndOdometer);
    if (s != null && e != null && e >= s) {
      return `${number(e - s)} ${this.distanceUnit}`;
    }
    return "";
  }

  get tripCategoryOptions() {
    return TRIP_CATEGORIES;
  }

  get vehicleSelectOptions() {
    return (this.authorized || []).map((a) => ({
      value: a.assetId,
      label: `${a.name} (${a.plate || "No plate"})`
    }));
  }

  get isTripSheet() {
    return this.sheet === "pretrip" || this.sheet === "endtrip";
  }
  get isIssue() {
    return this.sheet === "issue";
  }
  get isFuel() {
    return this.sheet === "fuel";
  }
  get isNotices() {
    return this.sheet === "notices";
  }

  get sheetTitle() {
    return (
      {
        pretrip: "Pre-trip check",
        endtrip: "End your trip & log mileage",
        logTrip: this.editingTripId ? "Edit trip submission" : "Log a trip",
        issue: "Report an issue",
        fuel:
          this.vehicle && this.vehicle.fuelType === "Electric"
            ? "Log charging"
            : "Log fuel",
        navCustomizer: "Customize Bottom Bar",
        notices: "Notifications"
      }[this.sheet] || ""
    );
  }

  handleBell() {
    this.sheet = "notices";
  }

  handleInput(event) {
    this[event.currentTarget.dataset.field] = event.target.value;
    this.sheetError = undefined;
  }

  handleEnergy(event) {
    this.energy = Number(event.target.value);
  }

  handleCheckbox(event) {
    this[event.currentTarget.dataset.field] = event.target.checked;
  }

  get checkRows() {
    return CHECKS.map((c) => {
      const ok = this.checks[c.key] !== false;
      return {
        ...c,
        okCls: `seg__btn${ok ? " seg__btn--ok" : ""}`,
        issueCls: `seg__btn${ok ? "" : " seg__btn--issue"}`
      };
    });
  }

  handleCheck(event) {
    const { key, ok } = event.currentTarget.dataset;
    this.checks = { ...this.checks, [key]: ok === "true" };
  }

  get issueCount() {
    return CHECKS.filter((c) => this.checks[c.key] === false).length;
  }

  get anyIssue() {
    return this.issueCount > 0 || this.damage;
  }

  get notesLabel() {
    return this.anyIssue ? "Notes (required)" : "Notes (optional)";
  }

  get issueSummary() {
    return this.issueCount > 0
      ? `${this.issueCount} item${this.issueCount > 1 ? "s" : ""} flagged. A service ticket will be raised.`
      : "Everything looks fine.";
  }

  get energyLabel() {
    return this.vehicle && this.vehicle.fuelType === "Electric"
      ? "Charge level"
      : "Fuel level";
  }

  get energyValueText() {
    return `${this.energy}%`;
  }

  get categoryOptions() {
    return ISSUE_CATEGORIES.map((c) => ({
      ...c,
      cls: `pill${c.value === this.issueCategory ? " pill--on" : ""}`
    }));
  }

  get priorityOptions() {
    return PRIORITIES.map((p) => ({
      value: p,
      cls: `pill${p === this.issuePriority ? " pill--on" : ""}`
    }));
  }

  handleCategory(event) {
    this.issueCategory = event.currentTarget.dataset.value;
  }
  handlePriority(event) {
    this.issuePriority = event.currentTarget.dataset.value;
  }

  get fuelUnit() {
    return this.vehicle && this.vehicle.fuelType === "Electric"
      ? "kWh"
      : fuelLogUnit(this.vehicle && this.vehicle.volumeUnit);
  }
  get fuelUnitLabel() {
    return this.vehicle && this.vehicle.fuelType === "Electric"
      ? "kWh"
      : volumeLabel(this.vehicle && this.vehicle.volumeUnit);
  }

  // photos
  get isPhotoSheet() {
    return (
      this.sheet === "pretrip" ||
      this.sheet === "endtrip" ||
      this.sheet === "issue"
    );
  }
  get canAddPhoto() {
    return this.photos.length < MAX_PHOTOS;
  }
  get hasPhotos() {
    return this.photos.length > 0;
  }

  async handlePhoto(event) {
    const file = event.target.files && event.target.files[0];
    event.target.value = "";
    if (!file) return;
    try {
      const img = await shrinkImage(file);
      this.photos = [
        ...this.photos,
        {
          key: `p${Date.now()}`,
          name: `photo-${this.photos.length + 1}`,
          dataUrl: img.dataUrl,
          base64: img.base64
        }
      ];
    } catch {
      this.sheetError = "That photo could not be read.";
    }
  }

  handleRemovePhoto(event) {
    this.photos = this.photos.filter(
      (p) => p.key !== event.currentTarget.dataset.key
    );
  }

  async uploadPhotos(parentId) {
    // one at a time: each photo is a separate Apex call with a large payload
    for (const p of this.photos) {
      // eslint-disable-next-line no-await-in-loop
      await attachPhoto({ parentId, fileName: p.name, base64: p.base64 });
    }
  }

  // submit
  async submit() {
    this.busy = true;
    this.sheetError = undefined;
    try {
      if (this.isNavCustomizerSheet) {
        this.closeSheet();
        this.showToast("Bottom navigation updated.");
        this.busy = false;
        return;
      }
      const v = this.dash.vehicle;
      const odo = this.odometer === "" ? null : Number(this.odometer);
      if (this.isTripSheet) {
        const flagged = CHECKS.filter((c) => this.checks[c.key] === false).map(
          (c) => c.label
        );
        const report = [
          flagged.length ? `Flagged: ${flagged.join(", ")}.` : "",
          this.notes
        ]
          .filter(Boolean)
          .join(" ");
        if (this.anyIssue && !report.trim()) {
          this.sheetError = "Please describe what you found.";
          this.busy = false;
          return;
        }
        if (this.isPretrip) {
          const tripId = await startTrip({
            driverId: this.driverId,
            assetId: v.id,
            odometer: odo,
            energyPercent: this.energy,
            conditionNotes: report,
            newDamage: this.anyIssue
          });
          await this.uploadPhotos(tripId);
          this.showToast("Trip started. Drive safe!");
        } else {
          await endTrip({
            allocationId: this.dash.openTrip.id,
            odometer: odo,
            energyPercent: this.energy,
            conditionNotes: report,
            newDamage: this.anyIssue,
            tripType: this.endTripType || "Business",
            businessPurpose: this.endTripPurpose,
            category: this.endTripCategory
          });
          await this.uploadPhotos(this.dash.openTrip.id);
          this.showToast("Trip ended & mileage reported.");
        }
      } else if (this.isLogTripSheet) {
        if (!this.logTripAssetId) {
          this.sheetError = "Please select a vehicle.";
          this.busy = false;
          return;
        }
        if (this.logTripType === "Business" && !this.logTripPurpose?.trim()) {
          this.sheetError = "Please enter a business purpose for this trip.";
          this.busy = false;
          return;
        }
        const sOdo =
          this.logStartOdometer === "" ? null : Number(this.logStartOdometer);
        const eOdo =
          this.logEndOdometer === "" ? null : Number(this.logEndOdometer);
        if (sOdo != null && eOdo != null && eOdo < sOdo) {
          this.sheetError = "End odometer cannot be less than start odometer.";
          this.busy = false;
          return;
        }
        if (this.editingTripId) {
          await updateTrip({
            tripId: this.editingTripId,
            driverId: this.driverId,
            tripType: this.logTripType,
            businessPurpose: this.logTripPurpose,
            category: this.logTripCategory,
            startTime: this.logStartTime
              ? new Date(this.logStartTime).toISOString()
              : null,
            endTime: this.logEndTime
              ? new Date(this.logEndTime).toISOString()
              : null,
            startOdometer: sOdo,
            endOdometer: eOdo,
            originAddress: this.logOrigin,
            destinationAddress: this.logDestination,
            driverNotes: this.logNotes
          });
          this.showToast("Trip updated and resubmitted.");
        } else {
          await logTrip({
            driverId: this.driverId,
            assetId: this.logTripAssetId,
            tripType: this.logTripType,
            businessPurpose: this.logTripPurpose,
            category: this.logTripCategory,
            startTime: this.logStartTime
              ? new Date(this.logStartTime).toISOString()
              : null,
            endTime: this.logEndTime
              ? new Date(this.logEndTime).toISOString()
              : null,
            startOdometer: sOdo,
            endOdometer: eOdo,
            originAddress: this.logOrigin,
            destinationAddress: this.logDestination,
            driverNotes: this.logNotes
          });
          this.showToast("Trip logged successfully.");
        }
      } else if (this.isIssue) {
        if (!this.notes.trim()) {
          this.sheetError = "Please describe the issue.";
          this.busy = false;
          return;
        }
        const ticketId = await reportIssue({
          driverId: this.driverId,
          assetId: v.id,
          category: this.issueCategory,
          priority: this.issuePriority,
          description: this.notes
        });
        await this.uploadPhotos(ticketId);
        this.showToast("Report sent to the workshop.");
      } else if (this.isFuel) {
        await logFuel({
          driverId: this.driverId,
          assetId: v.id,
          volume: Number(this.fuelVolume),
          unit: this.fuelUnit,
          totalCost: this.fuelCost === "" ? null : Number(this.fuelCost),
          odometer: odo,
          fullTank: this.fuelFull,
          stationName: this.fuelStation
        });
        this.showToast(
          this.vehicle.fuelType === "Electric"
            ? "Charging session saved."
            : "Fuel entry saved."
        );
      }
      this.sheet = undefined;
      await this.load();
    } catch (e) {
      this.sheetError =
        (e && e.body && e.body.message) ||
        "Something went wrong. Please try again.";
    } finally {
      this.busy = false;
    }
  }

  get submitLabel() {
    if (this.busy) return "Saving…";
    return (
      {
        pretrip: "Start trip",
        endtrip: "End & Submit",
        logTrip: this.editingTripId ? "Update & Resubmit" : "Submit Trip Log",
        issue: "Send report",
        navCustomizer: "Done",
        fuel: "Save"
      }[this.sheet] || "Save"
    );
  }
}
