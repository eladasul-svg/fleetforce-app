import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getBrandSettings from "@salesforce/apex/FleetDisplaySettingsController.getBrandSettings";
import saveBrandSettings from "@salesforce/apex/FleetDisplaySettingsController.saveBrandSettings";
import { STYLE_OPTIONS, DEFAULT_STYLE } from "c/fleetVehicleStyles";

const SAMPLES = [
  { key: "s1", bodyType: "Sedan", color: "Blue", fuelType: "Gasoline" },
  { key: "s2", bodyType: "Pickup", color: "Red", fuelType: "Electric" },
  { key: "s3", bodyType: "Van", color: "Silver", fuelType: "Diesel" },
  { key: "s4", bodyType: "SUV", color: "Green", fuelType: "Hybrid" }
];

export default class FleetBrandTheme extends LightningElement {
  loading = true;
  saving = false;
  error;

  serverSettings = {
    iconStyle: DEFAULT_STYLE,
    useCustomTheme: false,
    customThemeName: "FleetForce Packaged Theme",
    customBrandColor: "#0F1E33",
    customLogoUrl: "",
    canEdit: true
  };

  draft = {
    iconStyle: DEFAULT_STYLE,
    useCustomTheme: false,
    customThemeName: "",
    customBrandColor: "#0F1E33",
    customLogoUrl: ""
  };

  themesSetupUrl = "/lightning/setup/ThemingAndBranding/home";

  @wire(getBrandSettings)
  wiredSettings({ data, error }) {
    this.loading = false;
    if (data) {
      this.serverSettings = data;
      this.resetDraft();
      this.error = undefined;
    } else if (error) {
      this.error =
        (error && error.body && error.body.message) ||
        "Could not load brand & theme settings.";
    }
  }

  resetDraft() {
    this.draft = {
      iconStyle: this.serverSettings.iconStyle || DEFAULT_STYLE,
      useCustomTheme: !!this.serverSettings.useCustomTheme,
      customThemeName: this.serverSettings.customThemeName || "",
      customBrandColor: this.serverSettings.customBrandColor || "#0F1E33",
      customLogoUrl: this.serverSettings.customLogoUrl || ""
    };
  }

  get isPackagedTheme() {
    return !this.draft.useCustomTheme;
  }

  get options() {
    return STYLE_OPTIONS.map((o) => ({
      ...o,
      isSelected: o.value === this.draft.iconStyle,
      tileClass: `tile${o.value === this.draft.iconStyle ? " tile--selected" : ""}`,
      ariaChecked: String(o.value === this.draft.iconStyle),
      samples: SAMPLES
    }));
  }

  get dirty() {
    return (
      this.draft.iconStyle !== this.serverSettings.iconStyle ||
      this.draft.useCustomTheme !== this.serverSettings.useCustomTheme ||
      this.draft.customThemeName !==
        (this.serverSettings.customThemeName || "") ||
      this.draft.customBrandColor !==
        (this.serverSettings.customBrandColor || "#0F1E33") ||
      this.draft.customLogoUrl !== (this.serverSettings.customLogoUrl || "")
    );
  }

  get saveDisabled() {
    return !this.dirty || this.saving || !this.serverSettings.canEdit;
  }

  handleSelectStyle(event) {
    this.draft = {
      ...this.draft,
      iconStyle: event.currentTarget.dataset.value
    };
  }

  handleKeyStyle(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.handleSelectStyle(event);
    }
  }

  handleThemeToggle(event) {
    this.draft = { ...this.draft, useCustomTheme: event.target.checked };
  }

  handleFieldChange(event) {
    const { name, value } = event.target;
    this.draft = { ...this.draft, [name]: value };
  }

  handleCancel() {
    this.resetDraft();
    this.error = undefined;
  }

  async handleSave() {
    this.saving = true;
    this.error = undefined;
    try {
      const updated = await saveBrandSettings({
        iconStyle: this.draft.iconStyle,
        useCustomTheme: this.draft.useCustomTheme,
        customThemeName: this.draft.customThemeName,
        customBrandColor: this.draft.customBrandColor,
        customLogoUrl: this.draft.customLogoUrl
      });
      this.serverSettings = updated;
      this.resetDraft();
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Brand & Theme Saved",
          message:
            "Brand preferences saved. Reload other FleetForce pages to view changes.",
          variant: "success"
        })
      );
    } catch (e) {
      this.error =
        (e && e.body && e.body.message) ||
        "The brand settings could not be saved.";
    } finally {
      this.saving = false;
    }
  }
}
