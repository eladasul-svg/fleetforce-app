import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import USER_ID from "@salesforce/user/Id";
import getBrandSettings from "@salesforce/apex/FleetDisplaySettingsController.getBrandSettings";
import saveBrandIconStyle from "@salesforce/apex/FleetDisplaySettingsController.saveBrandIconStyle";
import saveCustomLogo from "@salesforce/apex/FleetDisplaySettingsController.saveCustomLogo";
import revertToDefaultLogo from "@salesforce/apex/FleetDisplaySettingsController.revertToDefaultLogo";

const DEFAULT_STYLE = "silhouette";

const STYLE_OPTIONS = [
  {
    value: "silhouette",
    label: "Silhouette",
    blurb: "Solid shapes with cut-outs. The default."
  },
  { value: "flat", label: "Flat", blurb: "Clean 2D side views." },
  {
    value: "classic",
    label: "Classic",
    blurb: "Retro curves, whitewalls and chrome."
  },
  {
    value: "modern",
    label: "Modern",
    blurb: "Sleek lines with crisp lights."
  },
  {
    value: "futuristic",
    label: "Futuristic",
    blurb: "Angular, faceted, light-bar front."
  }
];

const SAMPLES = [
  { key: "van", bodyType: "van", color: "blue", fuelType: "electric" },
  { key: "sedan", bodyType: "sedan", color: "green", fuelType: "hybrid" },
  { key: "truck", bodyType: "truck", color: "red", fuelType: "diesel" }
];

export default class FleetBrandTheme extends LightningElement {
  loading = true;
  saving = false;
  activeEditSection = null; // null | 'style' | 'logo'
  error;

  serverSettings = {
    iconStyle: DEFAULT_STYLE,
    customLogoUrl: null,
    defaultLogoUrl: "/file-asset/Fleetforce_Waypoint_Logo",
    hasCustomLogo: false,
    settingId: null,
    canEdit: true
  };

  draftStyle = DEFAULT_STYLE;

  @wire(getBrandSettings)
  wiredSettings({ data, error }) {
    this.loading = false;
    if (data) {
      this.serverSettings = data;
      this.draftStyle = data.iconStyle || DEFAULT_STYLE;
      this.error = undefined;
    } else if (error) {
      this.error =
        (error && error.body && error.body.message) ||
        "Could not load brand & theme settings.";
    }
  }

  get canEdit() {
    return this.serverSettings && this.serverSettings.canEdit;
  }

  get currentUserId() {
    return (
      (this.serverSettings && this.serverSettings.currentUserId) || USER_ID
    );
  }

  // Section 1: Icon Style
  get isStyleOverview() {
    return this.activeEditSection !== "style";
  }

  get isStyleEditing() {
    return this.activeEditSection === "style";
  }

  get activeStyleLabel() {
    const match = STYLE_OPTIONS.find(
      (o) => o.value === (this.serverSettings.iconStyle || DEFAULT_STYLE)
    );
    return match ? match.label : "Silhouette";
  }

  get activeStyleSamples() {
    return SAMPLES;
  }

  get options() {
    return STYLE_OPTIONS.map((o) => ({
      ...o,
      isSelected: o.value === this.draftStyle,
      tileClass: `tile${o.value === this.draftStyle ? " tile--selected" : ""}`,
      ariaChecked: String(o.value === this.draftStyle),
      samples: SAMPLES
    }));
  }

  // Section 2: Logo
  get isLogoOverview() {
    return this.activeEditSection !== "logo";
  }

  get isLogoEditing() {
    return this.activeEditSection === "logo";
  }

  get currentLogoUrl() {
    if (this.serverSettings.customLogoUrl) {
      return this.serverSettings.customLogoUrl;
    }
    return (
      this.serverSettings.defaultLogoUrl ||
      "/file-asset/Fleetforce_Waypoint_Logo"
    );
  }

  get logoStatusDescription() {
    if (this.serverSettings.hasCustomLogo) {
      return "Custom enterprise logo is active and displayed across all FleetForce navigation headers.";
    }
    return "Official FleetForce Waypoint logo is currently active as the system default.";
  }

  get acceptedFormats() {
    return [".png", ".jpg", ".jpeg", ".svg"];
  }

  handleEditStyle() {
    this.draftStyle = this.serverSettings.iconStyle || DEFAULT_STYLE;
    this.activeEditSection = "style";
    this.error = undefined;
  }

  handleCancelStyle() {
    this.draftStyle = this.serverSettings.iconStyle || DEFAULT_STYLE;
    this.activeEditSection = null;
    this.error = undefined;
  }

  handleSelectStyle(event) {
    this.draftStyle = event.currentTarget.dataset.value;
  }

  handleKeyStyle(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.handleSelectStyle(event);
    }
  }

  async handleSaveStyle() {
    this.saving = true;
    this.error = undefined;
    try {
      const updated = await saveBrandIconStyle({ iconStyle: this.draftStyle });
      this.serverSettings = updated;
      this.draftStyle = updated.iconStyle;
      this.activeEditSection = null;
      this.showToast(
        "Icon Style Saved",
        "Vehicle icon style updated across all fleet views.",
        "success"
      );
    } catch (e) {
      this.error =
        (e && e.body && e.body.message) || "Could not save icon style.";
    } finally {
      this.saving = false;
    }
  }

  handleEditLogo() {
    this.activeEditSection = "logo";
    this.error = undefined;
  }

  handleCancelLogo() {
    this.activeEditSection = null;
    this.error = undefined;
  }

  async handleUploadFinished(event) {
    const uploadedFiles = event.detail.files;
    if (!uploadedFiles || uploadedFiles.length === 0) {
      return;
    }

    const contentVersionId = uploadedFiles[0].contentVersionId;
    this.saving = true;
    this.error = undefined;
    try {
      const updated = await saveCustomLogo({ contentVersionId });
      this.serverSettings = updated;
      this.activeEditSection = null;
      this.showToast(
        "Company Logo Uploaded",
        "Your enterprise logo has been saved and applied to FleetForce headers.",
        "success"
      );
    } catch (e) {
      this.error =
        (e && e.body && e.body.message) || "Could not link uploaded logo.";
    } finally {
      this.saving = false;
    }
  }

  async handleRevertLogo() {
    this.saving = true;
    this.error = undefined;
    try {
      const updated = await revertToDefaultLogo();
      this.serverSettings = updated;
      this.activeEditSection = null;
      this.showToast(
        "Reverted to Default",
        "FleetForce standard logo restored.",
        "success"
      );
    } catch (e) {
      this.error = (e && e.body && e.body.message) || "Could not revert logo.";
    } finally {
      this.saving = false;
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
