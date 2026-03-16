import { LightningElement, wire } from 'lwc';
import getMaintenanceAlerts from '@salesforce/apex/FleetKpiController.getMaintenanceAlerts';

export default class MaintenanceAlerts extends LightningElement {
    alerts = [];
    error;

    @wire(getMaintenanceAlerts)
    wiredAlerts({ error, data }) {
        if (data) {
            this.alerts = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            console.error('Error fetching Maintenance Alerts', error);
            this.alerts = [];
        }
    }

    get hasAlerts() {
        return this.alerts && this.alerts.length > 0;
    }
}