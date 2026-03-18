import { LightningElement, track, wire } from 'lwc';
import getGeotabSettings from '@salesforce/apex/GeotabSettingsController.getGeotabSettings';
import saveGeotabSettings from '@salesforce/apex/GeotabSettingsController.saveGeotabSettings';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class GeotabSettingsManager extends LightningElement {
    @track server = 'my.geotab.com';
    @track database = '';
    @track username = '';
    @track password = '';
    
    @track isLoading = true;
    @track jobId = null;

    connectedCallback() {
        this.loadSettings();
    }

    loadSettings() {
        this.isLoading = true;
        getGeotabSettings()
            .then(result => {
                if (result) {
                    this.server = result.server || 'my.geotab.com';
                    this.database = result.database || '';
                    this.username = result.username || '';
                    this.password = result.passwordMasked || '';
                }
                this.isLoading = false;
            })
            .catch(error => {
                console.error(error);
                this.isLoading = false;
            });
    }

    handleServerChange(event) { this.server = event.target.value; }
    handleDatabaseChange(event) { this.database = event.target.value; }
    handleUsernameChange(event) { this.username = event.target.value; }
    handlePasswordChange(event) { this.password = event.target.value; }

    get isButtonDisabled() {
        return !this.server || !this.database || !this.username || !this.password;
    }

    handleSave() {
        this.isLoading = true;
        this.jobId = null;

        saveGeotabSettings({ 
            database: this.database, 
            server: this.server, 
            username: this.username, 
            password: this.password 
        })
        .then(result => {
            this.isLoading = false;
            this.jobId = result;
            this.showToast('Success', 'Geotab configuration saved! Check Deployment Status.', 'success');
        })
        .catch(error => {
            this.isLoading = false;
            this.showToast('Error', error.body ? error.body.message : error.message, 'error');
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
