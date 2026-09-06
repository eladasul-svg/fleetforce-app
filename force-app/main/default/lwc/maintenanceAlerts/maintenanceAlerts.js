import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMaintenanceAlerts from '@salesforce/apex/FleetKpiController.getMaintenanceAlerts';

export default class MaintenanceAlerts extends NavigationMixin(LightningElement) {
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

    handleAlertClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }
}