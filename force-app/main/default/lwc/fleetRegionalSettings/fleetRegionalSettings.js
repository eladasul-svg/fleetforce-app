import { LightningElement, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getRegionalSettings from "@salesforce/apex/FleetDisplaySettingsController.getRegionalSettings";
import saveRegionalSettings from "@salesforce/apex/FleetDisplaySettingsController.saveRegionalSettings";

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
  Object.fromEntries(REGIONAL_FIELDS.map((f) => [f, (r && r[f]) || ""]));

export default class FleetRegionalSettings extends LightningElement {
  loading = true;
  isEditing = false;
  regional;
  draft = pick({});
  regionalSaving = false;
  regionalError;
  profileColumns = PROFILE_COLUMNS;
  manageCurrenciesUrl = "/lightning/setup/CompanyCurrency/home";

  @wire(getRegionalSettings)
  wiredRegional({ data, error }) {
    this.loading = false;
    if (data) {
      this.regional = data;
      this.draft = pick(data);
      this.regionalError = undefined;
    } else if (error) {
      this.regionalError =
        (error && error.body && error.body.message) ||
        "Regional settings could not be loaded.";
    }
  }

  get isOverview() {
    return !this.isEditing;
  }

  get canEdit() {
    return this.regional && this.regional.canEdit;
  }

  get profileCount() {
    return (
      (this.regional &&
        this.regional.profiles &&
        this.regional.profiles.length) ||
      0
    );
  }

  // Helper getters to show human-readable labels in Overview Mode
  get displayCountry() {
    if (!this.regional || !this.regional.countries)
      return this.draft.country || "Not Set";
    const match = this.regional.countries.find(
      (c) => c.value === this.draft.country
    );
    return match
      ? `${match.label} (${match.value})`
      : this.draft.country || "Not Set";
  }

  get displayTimeZone() {
    if (!this.regional || !this.regional.timeZones)
      return this.draft.timeZone || "Not Set";
    const match = this.regional.timeZones.find(
      (tz) => tz.value === this.draft.timeZone
    );
    return match ? match.label : this.draft.timeZone || "Not Set";
  }

  get displayCurrency() {
    if (!this.regional || !this.regional.currencies)
      return this.draft.currencyCode || "Not Set";
    const match = this.regional.currencies.find(
      (c) => c.value === this.draft.currencyCode
    );
    return match ? match.label : this.draft.currencyCode || "Not Set";
  }

  get displayDistanceUnit() {
    if (!this.regional || !this.regional.distanceUnits)
      return this.draft.distanceUnit || "Not Set";
    const match = this.regional.distanceUnits.find(
      (u) => u.value === this.draft.distanceUnit
    );
    return match ? match.label : this.draft.distanceUnit || "Not Set";
  }

  get displayVolumeUnit() {
    if (!this.regional || !this.regional.volumeUnits)
      return this.draft.volumeUnit || "Not Set";
    const match = this.regional.volumeUnits.find(
      (u) => u.value === this.draft.volumeUnit
    );
    return match ? match.label : this.draft.volumeUnit || "Not Set";
  }

  get displayWeightUnit() {
    if (!this.regional || !this.regional.weightUnits)
      return this.draft.weightUnit || "Not Set";
    const match = this.regional.weightUnits.find(
      (u) => u.value === this.draft.weightUnit
    );
    return match ? match.label : this.draft.weightUnit || "Not Set";
  }

  get dirty() {
    return (
      !!this.regional &&
      REGIONAL_FIELDS.some(
        (f) => (this.draft[f] || "") !== (this.regional[f] || "")
      )
    );
  }

  get saveDisabled() {
    return !this.dirty || this.regionalSaving;
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

  handleStartEdit() {
    this.draft = pick(this.regional);
    this.isEditing = true;
    this.regionalError = undefined;
  }

  handleCancelEdit() {
    this.draft = pick(this.regional);
    this.isEditing = false;
    this.regionalError = undefined;
  }

  handleInputChange(event) {
    this.draft = { ...this.draft, [event.target.name]: event.detail.value };
    this.regionalError = undefined;
  }

  async handleSave() {
    this.regionalSaving = true;
    this.regionalError = undefined;
    try {
      this.regional = await saveRegionalSettings({ ...this.draft });
      this.draft = pick(this.regional);
      this.isEditing = false;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Regional Settings Saved",
          message: "Org regional defaults have been successfully updated.",
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
