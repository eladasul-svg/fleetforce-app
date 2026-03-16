import { LightningElement, wire } from 'lwc';
import getAssetLocations from '@salesforce/apex/FleetKpiController.getAssetLocations';

export default class FleetMapTracker extends LightningElement {
    mapMarkers = [];
    error;

    @wire(getAssetLocations)
    wiredLocations({ error, data }) {
        if (data) {
            this.error = undefined;
            this.mapMarkers = data.map(telemetry => {
                return {
                    location: {
                        Latitude: telemetry.fleetforce__Latitude__c,
                        Longitude: telemetry.fleetforce__Longitude__c
                    },
                    title: `Asset ID: ${telemetry.fleetforce__Asset_ID__c}`,
                    description: `Recorded: ${telemetry.fleetforce__Timestamp__c}`,
                    icon: 'standard:resource_capacity'
                };
            });
        } else if (error) {
            this.error = error;
            console.error('Error fetching Asset Locations', error);
            this.mapMarkers = [];
        }
    }
}