import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getBrandSettings from "@salesforce/apex/FleetDisplaySettingsController.getBrandSettings";
import saveBrandIconStyle from "@salesforce/apex/FleetDisplaySettingsController.saveBrandIconStyle";

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
  activeEditSection = null; // null | 'style'
  error;

  serverSettings = {
    iconStyle: DEFAULT_STYLE,
    hasCustomTheme: false,
    activeThemeId: null,
    activeThemeName: "Salesforce Cosmos (Default)",
    activeThemeEditUrl: null,
    themesSetupUrl: "/lightning/setup/ThemingAndBranding/home",
    activeBrandColor: null,
    activeBrandImageUrl: null,
    overrideLoadingImage: false,
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

  get brandColorStyle() {
    const color = this.serverSettings && this.serverSettings.activeBrandColor;
    return color ? `background-color: ${color}; color: #ffffff;` : "";
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

  handleOpenActiveTheme() {
    if (this.serverSettings && this.serverSettings.activeThemeEditUrl) {
      window.open(this.serverSettings.activeThemeEditUrl, "_blank");
    }
  }

  handleOpenThemesSetup() {
    const url =
      (this.serverSettings && this.serverSettings.themesSetupUrl) ||
      "/lightning/setup/ThemingAndBranding/home";
    window.open(url, "_blank");
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
