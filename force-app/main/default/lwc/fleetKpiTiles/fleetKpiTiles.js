import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getFleetKpis from '@salesforce/apex/FleetKpiController.getFleetKpis';

export default class FleetKpiTiles extends NavigationMixin(LightningElement) {
    kpis = {
        totalActive: 0,
        inMaintenance: 0,
        criticalViolations: 0,
        openTickets: 0
    };
    
    error;

    @wire(getFleetKpis)
    wiredKpis({ error, data }) {
        if (data) {
            this.kpis = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            console.error('Error fetching KPIs', error);
        }
    }

    navigateToActiveFleet() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'fleetforce__Fleet_Asset__c',
                actionName: 'list'
            },
            state: {
                filterName: 'fleetforce__Active_Fleet'
            }
        });
    }

    navigateToInShop() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'fleetforce__Service_Ticket__c',
                actionName: 'list'
            },
            state: {
                filterName: 'fleetforce__In_Shop'
            }
        });
    }

    navigateToViolations() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'fleetforce__Telemetry_Violation__c',
                actionName: 'list'
            },
            state: {
                filterName: 'fleetforce__Critical_Violations'
            }
        });
    }

    navigateToOpenTickets() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'fleetforce__Service_Ticket__c',
                actionName: 'list'
            },
            state: {
                filterName: 'fleetforce__Open_Tickets'
            }
        });
    }
}