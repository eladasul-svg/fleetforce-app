import { api } from "lwc";
import LightningModal from "lightning/modal";
import getDriverPhotos from "@salesforce/apex/FleetDriverController.getDriverPhotos";

/**
 * Closes with { documentId } for an uploaded or chosen image, { remove: true } to clear the photo, or undefined
 * when cancelled. The caller saves the choice.
 */
export default class FleetDriverPhotoModal extends LightningModal {
  @api driverId;
  @api driverName;
  @api currentDocumentId;

  photos = [];
  loading = true;
  error;
  acceptedFormats = [".jpg", ".jpeg", ".png", ".gif", ".webp"];

  connectedCallback() {
    getDriverPhotos({ driverId: this.driverId })
      .then((photos) => {
        this.photos = photos || [];
      })
      .catch((e) => {
        this.error =
          (e && e.body && e.body.message) ||
          "The driver's files could not be loaded.";
      })
      .finally(() => {
        this.loading = false;
      });
  }

  get heading() {
    return this.driverName ? `Photo of ${this.driverName}` : "Driver photo";
  }

  get hasPhotos() {
    return this.photos.length > 0;
  }

  get photoTiles() {
    return this.photos.map((p) => ({
      ...p,
      cls:
        p.documentId === this.currentDocumentId ? "tile tile--current" : "tile"
    }));
  }

  handleUploadFinished(event) {
    const files = event.detail.files || [];
    if (files.length) {
      this.close({ documentId: files[0].documentId });
    }
  }

  handlePick(event) {
    this.close({ documentId: event.currentTarget.dataset.id });
  }

  handleRemove() {
    this.close({ remove: true });
  }

  handleCancel() {
    this.close();
  }
}
