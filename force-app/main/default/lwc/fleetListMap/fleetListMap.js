import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getAssets from '@salesforce/apex/FleetAssetMapController.getAssets';

const STATUS_COLOR = {
    Available:      '#04844B',
    Assigned:       '#04844B',
    Decommissioned: '#706E6B',
    Ordered:        '#E07A12'
};

const STATUS_BADGE = {
    Available:      'slds-badge badge-green',
    Assigned:       'slds-badge badge-green',
    Decommissioned: 'slds-badge badge-gray',
    Ordered:        'slds-badge badge-amber'
};

const FILTERS = [
    { value: 'All',       label: 'All' },
    { value: 'Available', label: 'Available' },
    { value: 'InShop',    label: 'In Shop' },
    { value: 'Critical',  label: 'Critical' }
];

export default class FleetListMap extends NavigationMixin(LightningElement) {
    @track activeFilter = 'All';
    @track rawRecords = [];
    @track mapMarkers = [];
    @track selectedMarkerValue;

    error;

    get filters() {
        return FILTERS.map(f => ({
            ...f,
            variant: f.value === this.activeFilter ? 'brand' : 'neutral'
        }));
    }

    get vehicleCount() {
        return this.rawRecords.length;
    }

    @wire(getAssets, { filter: '$activeFilter' })
    wiredAssets({ error, data }) {
        if (data) {
            this.error = undefined;
            this.rawRecords = data.map(rec => {
                const status   = rec.fleetforce__Status__c || 'Assigned';
                const lat      = rec.fleetforce__Last_Location__Latitude__s;
                const lon      = rec.fleetforce__Last_Location__Longitude__s;
                const fuelType = rec.fleetforce__Fuel_Type__c || '';
                const isElec   = fuelType === 'Electric';
                const odo      = rec.fleetforce__Odometer__c;

                return {
                    Id:                   rec.Id,
                    Name:                 rec.Name,
                    statusText:           status,
                    hasCoords:            !!(lat && lon),
                    lat,
                    lon,
                    markerColor:          STATUS_COLOR[status] || '#04844B',
                    badgeClass:           STATUS_BADGE[status] || 'slds-badge badge-green',
                    licensePlate:         rec.fleetforce__License_Plate__c || 'N/A',
                    energyLevel:          rec.fleetforce__Fuel_Energy_Level__c ?? 0,
                    energyIcon:           isElec ? 'utility:lightning' : 'custom:custom6',
                    energyLabel:          isElec ? 'Charge' : 'Fuel',
                    formattedOdometer:    odo != null ? Math.round(odo).toLocaleString('en-US') : '0'
                };
            });

            this.mapMarkers = this.rawRecords
                .filter(r => r.hasCoords)
                .map(r => ({
                    location:    { Latitude: r.lat, Longitude: r.lon },
                    title:       `${r.Name} (${r.statusText})`,
                    description: `<b>License:</b> ${r.licensePlate}<br/><b>Status:</b> ${r.statusText}`,
                    value:       r.Id,
                    mapIcon: {
                        path:        'M 12,2 C 8.134,2 5,5.134 5,9 c 0,5.25 7,13 7,13 0,0 7,-7.75 7,-13 0,-3.866,-3.134,-7,-7,-7 z',
                        fillColor:   r.markerColor,
                        fillOpacity: 1,
                        strokeWeight: 1,
                        scale:       1.5,
                        anchor:      { x: 12, y: 22 }
                    }
                }));
        } else if (error) {
            this.error = JSON.stringify(error);
            this.rawRecords = [];
            this.mapMarkers = [];
        }
    }

    handleFilterChange(event) {
        this.rawRecords = [];
        this.mapMarkers = [];
        this.selectedMarkerValue = undefined;
        this.activeFilter = event.currentTarget.dataset.filter;
    }

    handleVehicleHover(event) {
        this.selectedMarkerValue = event.currentTarget.dataset.id;
    }

    handleVehicleClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    handleMarkerSelect(event) {
        const recordId = event.detail.selectedMarkerValue;
        if (recordId) {
            this.selectedMarkerValue = recordId;
            const row = this.template.querySelector(`[data-id="${recordId}"]`);
            if (row) {
                row.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
            }
        }
    }
}
