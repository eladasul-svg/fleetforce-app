// Shared by assetDataHealth and fleetExposure, so a status looks the same everywhere.
// Every status is shown with an icon and text, never colour alone.

const HEALTH = {
  Healthy: { icon: "utility:success", variant: "success", color: "#2e844a" },
  Watch: { icon: "utility:warning", variant: "warning", color: "#a96404" },
  "At risk": { icon: "utility:error", variant: "error", color: "#ba0517" }
};

const STREAM = {
  Healthy: { icon: "utility:success", variant: "success", css: "chip chip_ok" },
  Stale: { icon: "utility:clock", variant: "warning", css: "chip chip_warn" },
  Missing: { icon: "utility:ban", variant: "error", css: "chip chip_bad" }
};

const ALERT_STATUS = {
  New: { icon: "utility:priority", variant: "error", css: "chip chip_bad" },
  Acknowledged: {
    icon: "utility:check",
    variant: "warning",
    css: "chip chip_warn"
  },
  "In progress": {
    icon: "utility:clock",
    variant: "warning",
    css: "chip chip_warn"
  },
  Resolved: {
    icon: "utility:success",
    variant: "success",
    css: "chip chip_ok"
  },
  Dismissed: { icon: "utility:ban", variant: "", css: "chip" }
};

const ALERT_TYPE = {
  "Data gap": "utility:offline",
  Recall: "utility:warning",
  Regulation: "utility:knowledge_base",
  Other: "utility:info"
};

const SEVERITY_RANK = { Critical: 0, High: 1, Medium: 2, Low: 3 };

const NEUTRAL = {
  icon: "utility:help",
  variant: "",
  color: "#747474",
  css: "chip"
};

export function healthStyle(status) {
  return HEALTH[status] || NEUTRAL;
}

export function streamStyle(status) {
  return STREAM[status] || NEUTRAL;
}

export function alertStatusStyle(status) {
  return ALERT_STATUS[status] || NEUTRAL;
}

/** Apex Datetimes arrive as ISO strings; the relative date component needs a timestamp. */
export function toTimestamp(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const ms = typeof value === "number" ? value : Date.parse(value);
  return Number.isNaN(ms) ? null : ms;
}

export function alertTypeIcon(type) {
  return ALERT_TYPE[type] || ALERT_TYPE.Other;
}

export function severityRank(severity) {
  return severity in SEVERITY_RANK ? SEVERITY_RANK[severity] : 4;
}

export function severityClass(severity) {
  return severity === "Critical" || severity === "High"
    ? "sev sev_high"
    : "sev";
}

/** Turns an Apex/LDS error into one readable line. */
export function reduceError(error) {
  if (!error) {
    return "Unknown error";
  }
  if (Array.isArray(error.body)) {
    return error.body.map((e) => e.message).join(", ");
  }
  if (error.body && typeof error.body.message === "string") {
    return error.body.message;
  }
  return typeof error.message === "string" ? error.message : "Unknown error";
}
