import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMaintenanceAlerts from '@salesforce/apex/FleetKpiController.getMaintenanceAlerts';

const BADGE_CLASS = {
    Critical: 'slds-badge slds-theme_error slds-m-left_small',
    High: 'slds-badge slds-theme_warning slds-m-left_small'
};

export default class MaintenanceAlerts extends NavigationMixin(LightningElement) {
    alerts = [];
    error;

    @wire(getMaintenanceAlerts)
    wiredAlerts({ error, data }) {
        if (data) {
            this.alerts = data.map((a) => ({ ...a, badgeClass: BADGE_CLASS[a.fleetforce__Priority__c] || 'slds-badge' }));
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