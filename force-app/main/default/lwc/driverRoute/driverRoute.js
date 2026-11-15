import { LightningElement, api } from "lwc";
import getTodayRoute from "@salesforce/apex/DriverRouteController.getTodayRoute";
import scanDocument from "@salesforce/apex/DriverRouteScanController.scanDocument";
import geocodeAddress from "@salesforce/apex/DriverRouteScanController.geocodeAddress";
import createScannedJob from "@salesforce/apex/DriverRouteScanController.createScannedJob";
import addVisitToRoute from "@salesforce/apex/DriverRouteScanController.addVisitToRoute";

const MAX_PDF_BYTES = 3.5 * 1024 * 1024;

function readFilePayload(file) {
  const name = file.name || "scan";
  const isPdf =
    file.type === "application/pdf" || name.toLowerCase().endsWith(".pdf");
  if (isPdf) {
    if (file.size > MAX_PDF_BYTES) {
      return Promise.reject(
        new Error(
          "PDF is too large (max 3.5 MB). Please upload a smaller scan."
        )
      );
    }
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(new Error("Could not read PDF file."));
      reader.onload = () => {
        const result = String(reader.result || "");
        resolve({
          base64: result.includes(",") ? result.split(",")[1] : result,
          mimeType: "application/pdf",
          fileName: name
        });
      };
      reader.readAsDataURL(file);
    });
  }

  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("Could not read image file."));
    reader.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error("That photo could not be decoded."));
      img.onload = () => {
        const scale = Math.min(1, 1280 / Math.max(img.width, img.height));
        const canvas = document.createElement("canvas");
        canvas.width = Math.round(img.width * scale);
        canvas.height = Math.round(img.height * scale);
        canvas
          .getContext("2d")
          .drawImage(img, 0, 0, canvas.width, canvas.height);
        const dataUrl = canvas.toDataURL("image/jpeg", 0.72);
        resolve({
          base64: dataUrl.split(",")[1],
          mimeType: "image/jpeg",
          fileName: name.replace(/\.[^.]+$/, "") + ".jpg"
        });
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}

function errorMessage(e, fallback) {
  if (e && e.body && e.body.message) return e.body.message;
  if (e && e.message) return e.message;
  return fallback;
}

export default class DriverRoute extends LightningElement {
  _driverId;
  route;
  loading = false;
  error;

  scanning = false;
  scanError;
  showSheet = false;
  saving = false;
  geocoding = false;
  sheetError;
  toast;
  _toastTimer;

  _scanFile;
  form = {};

  /** IANA time zone for times on screen (the vehicle's branch), passed in by driverApp. */
  @api timeZone;

  @api
  get driverId() {
    return this._driverId;
  }
  set driverId(value) {
    const changed = value !== this._driverId;
    this._driverId = value;
    if (changed && value) {
      this.load();
    }
  }

  @api
  async load() {
    this.loading = true;
    this.error = undefined;
    try {
      this.route = await getTodayRoute({ driverId: this._driverId });
    } catch (e) {
      this.error = errorMessage(e, "Could not load your route.");
      this.route = undefined;
    } finally {
      this.loading = false;
    }
  }

  disconnectedCallback() {
    clearTimeout(this._toastTimer);
  }

  showToast(message) {
    this.toast = message;
    clearTimeout(this._toastTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._toastTimer = setTimeout(() => {
      this.toast = undefined;
    }, 4000);
  }

  time(value) {
    if (!value) return "";
    const opts = { hour: "2-digit", minute: "2-digit" };
    if (this.timeZone) opts.timeZone = this.timeZone;
    return new Date(value).toLocaleTimeString([], opts);
  }

  get hasRoute() {
    return !!this.route;
  }
  get empty() {
    return !this.loading && !this.error && !this.route;
  }
  get summary() {
    if (!this.route) return "";
    const end = this.time(this.route.plannedEnd);
    return `${this.route.remaining} stop${this.route.remaining === 1 ? "" : "s"} left${end ? ` · back about ${end}` : ""}`;
  }
  get next() {
    if (!this.route) return null;
    const s = this.route.stops.find((x) => !x.done);
    return s ? { ...s, eta: this.time(s.eta) } : null;
  }
  get navigateUrl() {
    const n = this.next;
    return n && n.latitude != null
      ? `https://www.google.com/maps/dir/?api=1&destination=${n.latitude},${n.longitude}`
      : null;
  }
  get stops() {
    if (!this.route) return [];
    return this.route.stops.map((s) => ({
      ...s,
      eta: this.time(s.eta),
      until: s.windowEnd ? `by ${this.time(s.windowEnd)}` : "",
      cls: `stop${s.done ? " stop--done" : ""}`
    }));
  }

  get scanButtonLabel() {
    return this.scanning ? "Scanning…" : "Scan delivery note";
  }
  get scanButtonClass() {
    return `scan-btn${this.scanning ? " scan-btn--busy" : ""}`;
  }
  get geocodeBtnLabel() {
    return this.geocoding ? "Locating…" : "Locate address";
  }
  get confirmLabel() {
    return this.saving ? "Adding to route…" : "Add stop to route";
  }
  get sheetSubtitle() {
    const parts = [
      this.form.docType,
      this.form.truckPlate ? `Truck ${this.form.truckPlate}` : null
    ].filter(Boolean);
    return parts.join(" · ");
  }
  get coordHint() {
    if (
      this.form.latitude == null ||
      this.form.longitude == null ||
      this.form.latitude === "" ||
      this.form.longitude === ""
    ) {
      return "Coordinates missing — tap Locate address or enter manually.";
    }
    const coords = `${Number(this.form.latitude).toFixed(4)}, ${Number(this.form.longitude).toFixed(4)}`;
    return this.form.geocodedLabel
      ? `${coords} · ${this.form.geocodedLabel}`
      : coords;
  }
  get weightHint() {
    const ext = this.form.extractedWeightKg;
    if (ext == null || ext === "") return "";
    const cap = this.route && this.route.vehiclePayloadKg;
    const formatted = Math.round(Number(ext)).toLocaleString("en-US");
    if (cap != null && Number(ext) > Number(cap)) {
      return `Extracted ${formatted} kg exceeds vehicle capacity (${cap} kg) — omitted from solver load by default.`;
    }
    return `Extracted from document: ${formatted} kg`;
  }

  async handleFileChange(event) {
    const file = event.target.files && event.target.files[0];
    event.target.value = "";
    if (!file) return;

    this.scanning = true;
    this.scanError = undefined;
    try {
      const payload = await readFilePayload(file);
      this._scanFile = payload;
      const extracted = await scanDocument({
        base64Data: payload.base64,
        mimeType: payload.mimeType,
        fileName: payload.fileName
      });
      this.openSheetWithResult(extracted);
    } catch (e) {
      this.scanError = errorMessage(e, "Could not scan the delivery document.");
    } finally {
      this.scanning = false;
    }
  }

  openSheetWithResult(res) {
    const cap = this.route && this.route.vehiclePayloadKg;
    const extWeight = res.weightKg;
    const overCapacity =
      extWeight != null && cap != null && Number(extWeight) > Number(cap);
    this.form = {
      docType: res.docType || "Delivery Note",
      docNumber: res.docNumber || "",
      bolNumber: res.bolNumber || "",
      orderNumber: res.orderNumber || "",
      customerName: res.customerName || "",
      destinationAddress: res.destinationAddress || res.destinationCity || "",
      destinationCity: res.destinationCity || "",
      contactName: res.contactName || "",
      contactPhone: res.contactPhone || "",
      truckPlate: res.truckPlate || "",
      cargoSummary: res.cargoSummary || "",
      extractedWeightKg: extWeight,
      loadKg: extWeight != null && !overCapacity ? String(extWeight) : "",
      latitude: res.latitude != null ? String(res.latitude) : "",
      longitude: res.longitude != null ? String(res.longitude) : "",
      geocodedLabel: res.geocodedLabel || "",
      geocodeWarning: res.geocodeWarning || ""
    };
    this.sheetError = undefined;
    this.showSheet = true;
  }

  closeSheet() {
    if (this.saving) return;
    this.showSheet = false;
    this.sheetError = undefined;
  }

  handleFieldInput(event) {
    const key = event.target.dataset.field;
    if (!key) return;
    this.form = { ...this.form, [key]: event.target.value };
  }

  async handleRegeocode() {
    const address = (this.form.destinationAddress || "").trim();
    if (!address) {
      this.sheetError = "Enter a destination address first.";
      return;
    }
    this.geocoding = true;
    this.sheetError = undefined;
    try {
      const pt = await geocodeAddress({
        address,
        city: this.form.destinationCity || null
      });
      this.form = {
        ...this.form,
        latitude:
          pt.latitude != null ? String(pt.latitude) : this.form.latitude,
        longitude:
          pt.longitude != null ? String(pt.longitude) : this.form.longitude,
        geocodedLabel: pt.label || "",
        geocodeWarning: pt.warning || ""
      };
    } catch (e) {
      this.sheetError = errorMessage(e, "Could not locate address.");
    } finally {
      this.geocoding = false;
    }
  }

  async handleConfirmScan() {
    const address = (this.form.destinationAddress || "").trim();
    const lat = this.form.latitude === "" ? null : Number(this.form.latitude);
    const lon = this.form.longitude === "" ? null : Number(this.form.longitude);

    if (!address) {
      this.sheetError = "Destination address is required.";
      return;
    }
    if (lat == null || Number.isNaN(lat) || lon == null || Number.isNaN(lon)) {
      this.sheetError = "Valid latitude and longitude are required.";
      return;
    }

    this.saving = true;
    this.sheetError = undefined;
    try {
      const payload = {
        docNumber: this.form.docNumber,
        bolNumber: this.form.bolNumber,
        orderNumber: this.form.orderNumber,
        customerName: this.form.customerName,
        destinationAddress: address,
        contactName: this.form.contactName,
        contactPhone: this.form.contactPhone,
        cargoSummary: this.form.cargoSummary,
        extractedWeightKg: this.form.extractedWeightKg,
        loadKg: this.form.loadKg === "" ? null : Number(this.form.loadKg),
        latitude: lat,
        longitude: lon
      };

      const created = await createScannedJob({
        routeId: this.route.id,
        driverId: this._driverId,
        payloadJson: JSON.stringify(payload),
        base64Data: this._scanFile ? this._scanFile.base64 : null,
        mimeType: this._scanFile ? this._scanFile.mimeType : null,
        fileName: this._scanFile ? this._scanFile.fileName : null
      });

      const added = await addVisitToRoute({
        routeId: this.route.id,
        visitId: created.visitId
      });

      this.showSheet = false;
      this._scanFile = undefined;
      await this.load();

      if (added && added.assigned === false) {
        this.scanError = `Stop saved, but could not fit on the route (${added.unassignedReason || "unassigned"}).`;
      } else {
        this.showToast("Stop added · route updated");
      }
    } catch (e) {
      this.sheetError = errorMessage(e, "Could not add stop to route.");
    } finally {
      this.saving = false;
    }
  }
}
