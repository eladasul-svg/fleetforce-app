import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getIconStyle from "@salesforce/apex/FleetDisplaySettingsController.getIconStyle";
import saveIconStyle from "@salesforce/apex/FleetDisplaySettingsController.saveIconStyle";
import getRegionalSettings from "@salesforce/apex/FleetDisplaySettingsController.getRegionalSettings";
import saveRegionalSettings from "@salesforce/apex/FleetDisplaySettingsController.saveRegionalSettings";
import { STYLE_OPTIONS, DEFAULT_STYLE } from "c/fleetVehicleStyles";

const SAMPLES = [
  { key: "s1", bodyType: "Sedan", color: "Blue", fuelType: "Gasoline" },
  { key: "s2", bodyType: "Pickup", color: "Red", fuelType: "Electric" },
  { key: "s3", bodyType: "Van", color: "Silver", fuelType: "Diesel" },
  { key: "s4", bodyType: "SUV", color: "Green", fuelType: "Hybrid" }
];

const REGIONAL_FIELDS = [
  "distanceUnit",
  "volumeUnit",
  "weightUnit",
  "country",
  "timeZone",
  "currencyCode"
];
const PROFILE_COLUMNS = [
  { label: "Code", fieldName: "code", initialWidth: 70 },
  { label: "Country", fieldName: "name" },
  { label: "Currency", fieldName: "currencyCode", initialWidth: 90 },
  { label: "Time zone", fieldName: "timeZone" },
  { label: "Distance", fieldName: "distanceUnit", initialWidth: 90 },
  { label: "Volume", fieldName: "volumeUnit", initialWidth: 90 },
  { label: "Weight", fieldName: "weightUnit", initialWidth: 90 },
  { label: "Fuel economy", fieldName: "fuelEconomy" },
  { label: "Regime", fieldName: "regime", initialWidth: 90 }
];

const pick = (r) =>
  Object.fromEntries(REGIONAL_FIELDS.map((f) => [f, r[f] || ""]));

export default class FleetSettings extends LightningElement {
  saved = DEFAULT_STYLE;
  selected = DEFAULT_STYLE;
  saving = false;
  error;

  regional;
  draft = pick({});
  regionalSaving = false;
  regionalError;
  profileColumns = PROFILE_COLUMNS;
  manageCurrenciesUrl = "/lightning/setup/CompanyCurrency/home";

  @wire(getIconStyle)
  wiredStyle({ data }) {
    if (data) {
      this.saved = data;
      this.selected = data;
    }
  }

  @wire(getRegionalSettings)
  wiredRegional({ data, error }) {
    if (data) {
      this.regional = data;
      this.draft = pick(data);
    } else if (error) {
      this.regionalError = "Regional settings could not be loaded.";
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
  }

  async handleSave() {
    this.saving = true;
    this.error = undefined;
    try {
      this.saved = await saveIconStyle({ style: this.selected });
      this.selected = this.saved;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Icon style saved",
          message: "Reload other FleetForce pages to see the new style.",
          variant: "success"
        })
      );
    } catch (e) {
      this.error =
        (e && e.body && e.body.message) || "The setting could not be saved.";
    } finally {
      this.saving = false;
    }
  }

  // ---------- regional settings ----------
  get regionalReadOnly() {
    return !this.regional || !this.regional.canEdit || this.regionalSaving;
  }

  get regionalDirty() {
    return (
      !!this.regional &&
      REGIONAL_FIELDS.some((f) => this.draft[f] !== (this.regional[f] || ""))
    );
  }

  get regionalSaveDisabled() {
    return !this.regionalDirty || this.regionalSaving;
  }

  get currencyIcon() {
    return this.regional && this.regional.multiCurrency
      ? "utility:success"
      : "utility:info";
  }

  get currencyHeadline() {
    if (!this.regional) return "";
    return this.regional.multiCurrency
      ? `Multi-currency is on. Corporate currency: ${this.regional.orgCurrency}.`
      : `Multi-currency is off. Every amount is in ${this.regional.orgCurrency}.`;
  }

  get currencyGuidance() {
    if (!this.regional) return "";
    return this.regional.multiCurrency
      ? "Reports convert branch costs to the corporate currency using the rates in"
      : "Branch currencies are recorded but not converted; to report costs across countries in one currency, enable it in";
  }

  handleRegional(event) {
    this.draft = { ...this.draft, [event.target.name]: event.detail.value };
    this.regionalError = undefined;
  }

  handleRegionalCancel() {
    this.draft = pick(this.regional);
    this.regionalError = undefined;
  }

  async handleRegionalSave() {
    this.regionalSaving = true;
    this.regionalError = undefined;
    try {
      this.regional = await saveRegionalSettings({ ...this.draft });
      this.draft = pick(this.regional);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Regional settings saved",
          message: "",
          variant: "success"
        })
      );
    } catch (e) {
      this.regionalError =
        (e && e.body && e.body.message) || "The settings could not be saved.";
    } finally {
      this.regionalSaving = false;
    }
  }
}
