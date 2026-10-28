import { LightningElement, api } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { encodeDefaultFieldValues } from "lightning/pageReferenceUtils";
import getHealth from "@salesforce/apex/AssetDataHealthController.getHealth";
import refreshHealth from "@salesforce/apex/AssetDataHealthController.refreshHealth";
import setAlertStatus from "@salesforce/apex/AssetDataHealthController.setAlertStatus";
import {
  healthStyle,
  streamStyle,
  alertTypeIcon,
  alertStatusStyle,
  toTimestamp,
  severityClass,
  reduceError
} from "c/dataTrustFormat";

export default class AssetDataHealth extends NavigationMixin(LightningElement) {
  @api recordId;

  health;
  error;
  loading = true;
  busy = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.health = await getHealth({ assetId: this.recordId });
      this.error = undefined;
    } catch (e) {
      this.fail("Could not load data health", e);
    } finally {
      this.loading = false;
    }
  }

  async handleRefresh() {
    this.busy = true;
    try {
      this.health = await refreshHealth({ assetId: this.recordId });
      this.error = undefined;
    } catch (e) {
      this.fail("Could not refresh data health", e);
    } finally {
      this.busy = false;
    }
  }

  async handleAlertAction(event) {
    event.stopPropagation();
    const { id, status } = event.currentTarget.dataset;
    this.busy = true;
    try {
      this.health = await setAlertStatus({ alertId: id, status });
      this.dispatchEvent(
        new ShowToastEvent({
          title: `Alert ${status.toLowerCase()}`,
          variant: "success"
        })
      );
    } catch (e) {
      this.fail("Could not update the alert", e);
    } finally {
      this.busy = false;
    }
  }

  handleCreateTask(event) {
    event.stopPropagation();
    const alert = this.health.alerts.find(
      (a) => a.id === event.currentTarget.dataset.id
    );
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: { objectApiName: "Task", actionName: "new" },
      state: {
        defaultFieldValues: encodeDefaultFieldValues({
          WhatId: alert.id,
          Subject: `Follow up: ${alert.title}`.slice(0, 255)
        }),
        navigationLocation: "RELATED_LIST"
      }
    });
  }

  handleOpenVendor(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }

  handleOpenAlert(event) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: event.currentTarget.dataset.id,
        actionName: "view"
      }
    });
  }

  handleAlertKey(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.handleOpenAlert(event);
    }
  }

  fail(title, e) {
    this.error = reduceError(e);
    this.dispatchEvent(
      new ShowToastEvent({ title, message: this.error, variant: "error" })
    );
  }

  // ------------------------------------------------------------------ view state

  get hasHealth() {
    return !this.loading && !this.error && !!this.health;
  }

  get isEmpty() {
    return (
      this.hasHealth &&
      this.health.streams.length === 0 &&
      this.health.alerts.length === 0
    );
  }

  get showBody() {
    return this.hasHealth && !this.isEmpty;
  }

  get hasScore() {
    return (
      this.health &&
      this.health.score !== null &&
      this.health.score !== undefined
    );
  }

  get scoreText() {
    return this.hasScore ? String(this.health.score) : "–";
  }

  get band() {
    return healthStyle(this.health && this.health.status);
  }

  get statusLabel() {
    return (this.health && this.health.status) || "Not calculated";
  }

  get gaugeStyle() {
    const pct = this.hasScore
      ? Math.max(0, Math.min(100, this.health.score))
      : 0;
    return `background: conic-gradient(${this.band.color} ${pct * 3.6}deg, #e5e5e5 0deg);`;
  }

  get gaugeLabel() {
    return this.hasScore
      ? `Data health score ${this.health.score} out of 100, ${this.statusLabel}`
      : "Data health score not calculated yet";
  }

  get calculatedOn() {
    return toTimestamp(this.health && this.health.calculatedOn);
  }

  get parts() {
    const h = this.health || {};
    return [
      { key: "f", label: "Freshness", weight: "40%", value: h.freshness },
      { key: "c", label: "Completeness", weight: "40%", value: h.completeness },
      { key: "k", label: "Consistency", weight: "20%", value: h.consistency }
    ].map((p) => ({
      ...p,
      text: p.value === null || p.value === undefined ? "–" : String(p.value),
      barStyle: `width: ${p.value || 0}%;`
    }));
  }

  get streams() {
    return (this.health ? this.health.streams : []).map((s) => {
      const st = streamStyle(s.status);
      return {
        ...s,
        statusText: s.status || "Unknown",
        statusIcon: st.icon,
        statusVariant: st.variant,
        chipClass: st.css,
        lastUpdateTs: toTimestamp(s.lastUpdate),
        vendorHref: s.vendorAccountId ? `/${s.vendorAccountId}` : null,
        vendorLabel: `Open the ${s.vendorName} account`,
        hasUrl: !!s.referenceUrl,
        linkLabel: `Open ${s.sourceName || "source"} (${s.dataType}) in a new tab`
      };
    });
  }

  get hasStreams() {
    return this.streams.length > 0;
  }

  // the server sends open alerts first (most severe first), then closed ones
  get alerts() {
    return (this.health ? this.health.alerts : []).map((a) => {
      const st = alertStatusStyle(a.status);
      return {
        ...a,
        typeIcon: alertTypeIcon(a.alertType),
        sevClass: severityClass(a.severity),
        rowClass: a.isOpen ? "row row_click" : "row row_click row_closed",
        statusIcon: st.icon,
        statusVariant: st.variant,
        statusClass: st.css,
        resolvedTs: toTimestamp(a.resolvedOn),
        canAcknowledge: a.status === "New",
        canCreateTask: !!a.isOpen
      };
    });
  }

  get hasAlerts() {
    return this.alerts.length > 0;
  }

  get alertCountLabel() {
    const n = this.alerts.length;
    const open = this.alerts.filter((a) => a.isOpen).length;
    return `${n} alert${n === 1 ? "" : "s"}, ${open} open`;
  }
}
