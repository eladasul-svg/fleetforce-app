import { LightningElement, api, wire, track } from 'lwc';
import getListViewRecords from '@salesforce/apex/ListViewService.getListViewRecords';
import getListViewLabel from '@salesforce/apex/ListViewService.getListViewLabel';
import { NavigationMixin } from 'lightning/navigation';

export default class FleetListMap extends NavigationMixin(LightningElement) {
    @api listViewDeveloperName = 'All'; 
    @api centerLatitude;
    @api centerLongitude;
    @api zoomLevel = 10;
    
    objectApiName = 'fleetforce__Fleet_Asset__c';
    
    @track rawRecords = [];
    @track mapMarkers = [];
    @track selectedMarkerValue;
    
    error;
    listViewLabel = '';

    get cardTitle() {
        return this.listViewLabel || 'Fleet Map Explorer';
    }

    get vehicleCount() {
        return this.rawRecords ? this.rawRecords.length : 0;
    }

    get mapCenter() {
        if (this.centerLatitude && this.centerLongitude) {
            return {
                location: {
                    Latitude: parseFloat(this.centerLatitude),
                    Longitude: parseFloat(this.centerLongitude)
                }
            };
        }
        return undefined; // Falls back to auto-fit
    }

    @wire(getListViewLabel, { objectApiName: '$objectApiName', listViewDevName: '$listViewDeveloperName' })
    wiredLabel({ error, data }) {
        if (data) {
            this.listViewLabel = data;
        }
    }

    @wire(getListViewRecords, { objectApiName: '$objectApiName', listViewDevName: '$listViewDeveloperName' })
    wiredRecords({ error, data }) {
        if (data) {
            this.rawRecords = data.map(rec => {
                // Try both flattened and original key
                const status = rec.Status__c || rec.fleetforce__Status__c || 'In Service';
                const lat = rec.Last_Location__Latitude__s || rec.fleetforce__Last_Location__Latitude__s;
                const lon = rec.Last_Location__Longitude__s || rec.fleetforce__Last_Location__Longitude__s;
                
                // Color Logic
                const statLower = (status + '').toLowerCase();
                let markerColor = '#04844B'; // Green
                let badgeClass = 'slds-badge badge-green';
                
                if (statLower.includes('maintenance') || statLower.includes('grounded')) {
                    markerColor = '#C23934'; // Red
                    badgeClass = 'slds-badge badge-red';
                } else if (statLower.includes('disposed') || statLower.includes('sold')) {
                    markerColor = '#706E6B'; // Gray
                    badgeClass = 'slds-badge badge-gray';
                }

                return {
                    ...rec,
                    statusText: status,
                    hasCoords: !!(lat && lon),
                    markerColor: markerColor,
                    badgeClass: badgeClass,
                    lat: lat,
                    lon: lon,
                    Fuel_Energy_Level__c: rec.Fuel_Energy_Level__c || rec.fleetforce__Fuel_Energy_Level__c || 0,
                    Odometer__c: rec.Odometer__c || rec.fleetforce__Odometer__c || 0,
                    License_Plate__c: rec.License_Plate__c || rec.fleetforce__License_Plate__c || 'N/A'
                };
            });

            this.mapMarkers = this.rawRecords
                .filter(rec => rec.hasCoords)
                .map(rec => ({
                    location: { Latitude: rec.lat, Longitude: rec.lon },
                    title: `${rec.Name} (${rec.statusText})`,
                    description: `<b>License:</b> ${rec.License_Plate__c}<br/><b>Status:</b> ${rec.statusText}`,
                    value: rec.Id,
                    mapIcon: {
                        path: 'M 12,2 C 8.134,2 5,5.134 5,9 c 0,5.25 7,13 7,13 0,0 7,-7.75 7,-13 0,-3.866,-3.134,-7,-7,-7 z',
                        fillColor: rec.markerColor,
                        fillOpacity: 1,
                        strokeWeight: 1,
                        scale: 1.5,
                        anchor: { x: 12, y: 22 }
                    }
                }));
            this.error = undefined;
        } else if (error) {
            this.error = JSON.stringify(error);
            this.rawRecords = [];
        }
    }

    handleVehicleHover(event) {
        this.selectedMarkerValue = event.currentTarget.dataset.id;
    }

    handleVehicleClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }

    handleMarkerSelect(event) {
        const recordId = event.detail.selectedMarkerValue;
        if (recordId) {
            this.selectedMarkerValue = recordId;
        }
    }
}