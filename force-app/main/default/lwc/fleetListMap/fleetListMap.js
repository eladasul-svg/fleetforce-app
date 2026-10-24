import { LightningElement, api, track, wire } from 'lwc';
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

const SELECTED_COLOR = '#0070D2';
const FOCUS_ZOOM = 15;

const FILTERS = [
    { value: 'All',       label: 'All' },
    { value: 'Available', label: 'Available' },
    { value: 'InShop',    label: 'In Shop' },
    { value: 'Critical',  label: 'Critical' }
];

export default class FleetListMap extends NavigationMixin(LightningElement) {
    /** True on the dedicated full-size page, where the 'open large map' button is not needed. */
    @api fullPage = false;

    @track activeFilter = 'All';
    @track rawRecords = [];
    @track mapMarkers = [];
    @track selectedId;
    @track mapCenter;
    @track zoomLevel;

    error;
    _resizeObserver;

    renderedCallback() {
        if (this._resizeObserver) {
            return;
        }
        const map = this.template.querySelector('lightning-map');
        if (!map) {
            return;
        }
        // Keep the list exactly as tall as the map, whatever size the map ends up at on this device.
        this._resizeObserver = new ResizeObserver(() => this.syncListHeight());
        this._resizeObserver.observe(map);
        this.syncListHeight();
    }

    disconnectedCallback() {
        if (this._resizeObserver) {
            this._resizeObserver.disconnect();
            this._resizeObserver = undefined;
        }
    }

    syncListHeight() {
        const map = this.template.querySelector('lightning-map');
        const sidebar = this.template.querySelector('.sidebar');
        if (!map || !sidebar) {
            return;
        }
        const height = map.getBoundingClientRect().height;
        if (height > 0) {
            sidebar.style.height = `${Math.round(height)}px`;
        }
    }

    get filters() {
        return FILTERS.map(f => ({
            ...f,
            variant: f.value === this.activeFilter ? 'brand' : 'neutral'
        }));
    }

    get showOpenLarge() {
        return !this.fullPage;
    }

    handleOpenLarge() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'fleetforce__Fleet_Map_Explorer' }
        });
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
                    bodyType:             rec.fleetforce__Body_Type__c,
                    paintColor:           rec.fleetforce__Color__c,
                    fuelType,
                    licensePlate:         rec.fleetforce__License_Plate__c || 'N/A',
                    energyLevel:          rec.fleetforce__Fuel_Energy_Level__c ?? 0,
                    energyIcon:           isElec ? 'utility:lightning' : 'custom:custom6',
                    energyLabel:          isElec ? 'Charge' : 'Fuel',
                    formattedOdometer:    odo != null ? Math.round(odo).toLocaleString('en-US') : '0'
                };
            });

            this.rebuildMarkers();
        } else if (error) {
            this.error = JSON.stringify(error);
            this.rawRecords = [];
            this.mapMarkers = [];
        }
    }

    get rows() {
        return this.rawRecords.map(r => ({
            ...r,
            rowClass: `vehicle-row slds-p-around_small slds-border_bottom${r.Id === this.selectedId ? ' vehicle-row--selected' : ''}`
        }));
    }

    get selectedRec() {
        return this.selectedId ? this.rawRecords.find(r => r.Id === this.selectedId) : undefined;
    }

    /** Pins have no built-in info window (no title/description); the selected one is drawn larger and highlighted. */
    rebuildMarkers() {
        this.mapMarkers = this.rawRecords
            .filter(r => r.hasCoords)
            .map(r => {
                const selected = r.Id === this.selectedId;
                return {
                    location: { Latitude: r.lat, Longitude: r.lon },
                    value:    r.Id,
                    mapIcon: {
                        path:         'M 12,2 C 8.134,2 5,5.134 5,9 c 0,5.25 7,13 7,13 0,0 7,-7.75 7,-13 0,-3.866,-3.134,-7,-7,-7 z',
                        fillColor:    selected ? SELECTED_COLOR : r.markerColor,
                        fillOpacity:  1,
                        strokeColor:  selected ? '#FFFFFF' : '#000000',
                        strokeWeight: selected ? 2 : 1,
                        scale:        selected ? 2.4 : 1.5,
                        anchor:       { x: 12, y: 22 }
                    }
                };
            });
    }

    handleFilterChange(event) {
        this.rawRecords = [];
        this.mapMarkers = [];
        this.selectedId = undefined;
        this.mapCenter = undefined;
        this.zoomLevel = undefined;
        this.activeFilter = event.currentTarget.dataset.filter;
    }

    /** Clicking a list card flies the map to that vehicle and shows its card over the map. */
    handleVehicleClick(event) {
        const rec = this.rawRecords.find(r => r.Id === event.currentTarget.dataset.id);
        if (!rec) {
            return;
        }
        this.selectedId = rec.Id;
        if (rec.hasCoords) {
            this.mapCenter = { location: { Latitude: rec.lat, Longitude: rec.lon } };
            this.zoomLevel = FOCUS_ZOOM;
        }
        this.rebuildMarkers();
    }

    /** Clicking a pin shows that vehicle's card over the map without moving the map. */
    handleMarkerSelect(event) {
        const id = event.detail.selectedMarkerValue;
        if (id) {
            this.selectedId = id;
            this.rebuildMarkers();
        }
    }

    handleCloseCard() {
        this.selectedId = undefined;
        this.rebuildMarkers();
        this.fitAll();
    }

    handleOpenRecord(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.detail.id, actionName: 'view' }
        });
    }

    /** Re-frames the map around every pin (Web Mercator maths, so it works for any city and any map size). */
    fitAll() {
        const pts = this.rawRecords.filter(r => r.hasCoords);
        const map = this.template.querySelector('lightning-map');
        if (!pts.length || !map) {
            return;
        }
        const merc = lat => Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360));
        const lats = pts.map(p => p.lat);
        const lons = pts.map(p => p.lon);
        const [minLat, maxLat] = [Math.min(...lats), Math.max(...lats)];
        const [minLon, maxLon] = [Math.min(...lons), Math.max(...lons)];
        const { width, height } = map.getBoundingClientRect();
        const lonFrac = Math.max((maxLon - minLon) / 360, 1e-6);
        const latFrac = Math.max((merc(maxLat) - merc(minLat)) / (2 * Math.PI), 1e-6);
        const pad = 1.25;
        const zoom = Math.min(
            Math.log2(width / (256 * lonFrac * pad)),
            Math.log2(height / (256 * latFrac * pad))
        );
        this.mapCenter = { location: { Latitude: (minLat + maxLat) / 2, Longitude: (minLon + maxLon) / 2 } };
        this.zoomLevel = Math.max(3, Math.min(FOCUS_ZOOM, Math.floor(zoom)));
    }
}
