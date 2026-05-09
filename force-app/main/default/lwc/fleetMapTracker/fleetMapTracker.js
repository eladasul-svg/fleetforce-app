import { LightningElement, wire } from 'lwc';
import getAssetLocations from '@salesforce/apex/FleetKpiController.getAssetLocations';

export default class FleetMapTracker extends LightningElement {
    mapMarkers = [];
    error;

    @wire(getAssetLocations)
    wiredLocations({ error, data }) {
        if (data) {
            this.error = undefined;
            this.mapMarkers = data.map(asset => {
                // Build a description showing driver and branch when available.
                const driverName = asset.fleetforce__Driver__r 
                    ? asset.fleetforce__Driver__r.Name 
                    : 'Unassigned';
                const branchName = asset.fleetforce__Branch__r 
                    ? asset.fleetforce__Branch__r.Name 
                    : 'No branch';
                const status = asset.fleetforce__Availability_Status__c 
                    || asset.fleetforce__Status__c 
                    || 'Unknown';

                return {
                    location: {
                        Latitude: asset.fleetforce__Last_Location__Latitude__s,
                        Longitude: asset.fleetforce__Last_Location__Longitude__s
                    },
                    title: asset.Name,
                    description: `Driver: ${driverName} • Branch: ${branchName} • Status: ${status}`,
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