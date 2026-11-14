import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getIconStyle from "@salesforce/apex/FleetDisplaySettingsController.getIconStyle";
import saveIconStyle from "@salesforce/apex/FleetDisplaySettingsController.saveIconStyle";
import { STYLE_OPTIONS, DEFAULT_STYLE } from "c/fleetVehicleStyles";

const SAMPLES = [
  { key: "s1", bodyType: "Sedan", color: "Blue", fuelType: "Gasoline" },
  { key: "s2", bodyType: "Pickup", color: "Red", fuelType: "Electric" },
  { key: "s3", bodyType: "Van", color: "Silver", fuelType: "Diesel" },
  { key: "s4", bodyType: "SUV", color: "Green", fuelType: "Hybrid" }
];

export default class FleetBrandTheme extends LightningElement {
  saved = DEFAULT_STYLE;
  selected = DEFAULT_STYLE;
  saving = false;
  error;

  themesSetupUrl = "/lightning/setup/ThemingAndBranding/home";

  @wire(getIconStyle)
  wiredStyle({ data, error }) {
    if (data) {
      this.saved = data;
      this.selected = data;
      this.error = undefined;
    } else if (error) {
      this.error =
        (error && error.body && error.body.message) ||
        "Could not load vehicle icon style.";
    }
  }

  get options() {
    return STYLE_OPTIONS.map((o) => ({
      ...o,
      isSelected: o.value === this.selected,
      tileClass: `tile${o.value === this.selected ? " tile--selected" : ""}`,
      ariaChecked: String(o.value === this.selected),
      samples: SAMPLES
    }));
  }

  get dirty() {
    return this.selected !== this.saved;
  }

  get saveDisabled() {
    return !this.dirty || this.saving;
  }

  handleSelect(event) {
    this.selected = event.currentTarget.dataset.value;
  }

  handleKey(event) {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      this.handleSelect(event);
    }
  }

  handleCancel() {
    this.selected = this.saved;
    this.error = undefined;
  }

  async handleSave() {
    this.saving = true;
    this.error = undefined;
    try {
      this.saved = await saveIconStyle({ style: this.selected });
      this.selected = this.saved;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Icon Style Saved",
          message:
            "Vehicle icon style updated. Reload other FleetForce pages to view changes.",
          variant: "success"
        })
      );
    } catch (e) {
      this.error =
        (e && e.body && e.body.message) || "The style could not be saved.";
    } finally {
      this.saving = false;
    }
  }
}
