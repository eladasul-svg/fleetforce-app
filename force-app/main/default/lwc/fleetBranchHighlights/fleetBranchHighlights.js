import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import getBranchHighlights from "@salesforce/apex/FleetBranchController.getBranchHighlights";

export default class FleetBranchHighlights extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  highlights;
  error;
  isLoading = true;
  _wiredResult;

  @wire(getBranchHighlights, { branchId: "$recordId" })
  wiredBranch(result) {
    this._wiredResult = result;
    const { data, error } = result;
    this.isLoading = false;
    if (data) {
      this.highlights = data;
      this.error = undefined;
    } else if (error) {
      this.highlights = undefined;
      this.error = error;
    }
  }

  get hasData() {
    return !!this.highlights;
  }

  get mapMarkers() {
    if (!this.highlights) {
      return [];
    }
    const location = {};
    if (this.highlights.latitude && this.highlights.longitude) {
      location.Latitude = this.highlights.latitude;
      location.Longitude = this.highlights.longitude;
    } else if (this.highlights.fullAddress) {
      if (this.highlights.street) location.Street = this.highlights.street;
      if (this.highlights.city) location.City = this.highlights.city;
      if (this.highlights.state) location.State = this.highlights.state;
      if (this.highlights.zipCode)
        location.PostalCode = this.highlights.zipCode;
      if (this.highlights.country) location.Country = this.highlights.country;
    } else {
      return [];
    }

    return [
      {
        location,
        title: this.highlights.name,
        description: this.highlights.fullAddress || this.highlights.name,
        icon: "standard:location"
      }
    ];
  }

  get hasMap() {
    return this.mapMarkers.length > 0;
  }

  get statusBadgeClass() {
    const s = this.highlights?.status;
    if (s === "Active") return "badge badge-active";
    if (s === "Renovating") return "badge badge-warning";
    if (s?.startsWith("Closed")) return "badge badge-closed";
    return "badge badge-code";
  }

  get capacityFillClass() {
    const status = this.highlights?.capacityStatus;
    if (status === "critical")
      return "progress-bar-fill progress-fill-critical";
    if (status === "warning") return "progress-bar-fill progress-fill-warning";
    return "progress-bar-fill progress-fill-optimal";
  }

  get capacityFillStyle() {
    const pct = Math.min(
      Math.max(this.highlights?.capacityUtilizationPct || 0, 0),
      100
    );
    return `width: ${pct}%`;
  }

  get managerMailto() {
    return this.highlights?.manager?.email
      ? `mailto:${this.highlights.manager.email}`
      : null;
  }

  get managerTel() {
    const phone =
      this.highlights?.manager?.phone || this.highlights?.manager?.mobile;
    return phone ? `tel:${phone}` : null;
  }

  get branchMailto() {
    return this.highlights?.email ? `mailto:${this.highlights.email}` : null;
  }

  get branchTel() {
    return this.highlights?.phone ? `tel:${this.highlights.phone}` : null;
  }

  handleOpenMap() {
    if (this.highlights?.googleMapsUrl) {
      window.open(this.highlights.googleMapsUrl, "_blank");
    }
  }

  handleOpenManager(event) {
    event.preventDefault();
    if (this.highlights?.manager?.id) {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: this.highlights.manager.id,
          objectApiName: "Contact",
          actionName: "view"
        }
      });
    }
  }

  async handleRefresh() {
    this.isLoading = true;
    try {
      await refreshApex(this._wiredResult);
    } finally {
      this.isLoading = false;
    }
  }
}
