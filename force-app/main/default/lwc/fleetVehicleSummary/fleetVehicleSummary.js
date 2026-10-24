import { LightningElement, api } from 'lwc';

/**
 * One compact vehicle card: icon, name, license, and a status / energy / odometer line. Used for the rows in the
 * Fleet Map Explorer list and for the card shown over the map. Optional buttons open the record or close the card.
 */
export default class FleetVehicleSummary extends LightningElement {
    /** A vehicle already mapped by the Fleet Map Explorer (Id, Name, statusText, badgeClass, licensePlate, ...). */
    @api rec;
    @api showOpen = false;
    @api showClose = false;
    @api iconSize = 46;

    get hasActions() {
        return this.showOpen || this.showClose;
    }

    handleOpen(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('open', { detail: { id: this.rec.Id } }));
    }

    handleClose(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('close'));
    }
}
