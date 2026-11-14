import { LightningElement, wire, track, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import {
  subscribe,
  unsubscribe,
  onError as empOnError
} from "lightning/empApi";
import { refreshApex } from "@salesforce/apex";

import getSupportedTypes from "@salesforce/apex/CmdtTypeRegistry.getSupportedTypes";
import getFieldDescribes from "@salesforce/apex/CmdtSchemaService.getFieldDescribes";
import getTypeInfo from "@salesforce/apex/CmdtSchemaService.getTypeInfo";
import getRecords from "@salesforce/apex/CmdtRecordService.getRecords";
import requestDeploy from "@salesforce/apex/CmdtDeployService.requestDeploy";

const DEPLOY_RESULT_CHANNEL = "/event/Cmdt_Deploy_Result__e";
const DEPLOY_TIMEOUT_MS = 60000;

export default class CmdtControlPanel extends LightningElement {
  @api initialType;
  _selectedType = "Country_Profile__mdt";

  @api
  get selectedType() {
    return this._selectedType;
  }
  set selectedType(value) {
    this._selectedType = value;
  }

  @track typeOptions = [];
  @track fieldDescribes = [];
  @track records = [];
  @track typeInfo;

  isLoadingSchema = false;
  isLoadingRecords = false;

  showModal = false;
  modalMode = "add"; // 'add' | 'edit'
  developerName = "";
  masterLabel = "";
  @track formValues = {};

  isDeploying = false;
  pendingRequestKey = null;
  deployTimeoutId = null;

  subscription = null;
  wiredRecordsResult;

  connectedCallback() {
    if (this.initialType) {
      this._selectedType = this.initialType;
    }
    this.subscribeToDeployResults();
  }

  disconnectedCallback() {
    if (this.subscription) {
      unsubscribe(this.subscription);
      this.subscription = null;
    }
    this.clearDeployTimeout();
  }

  subscribeToDeployResults() {
    empOnError((error) => {
      console.error(
        "EMP API error on Cmdt_Deploy_Result__e channel",
        JSON.stringify(error)
      );
    });

    subscribe(DEPLOY_RESULT_CHANNEL, -1, (event) => {
      const payload = event && event.data && event.data.payload;
      if (payload && payload.Request_Key__c === this.pendingRequestKey) {
        this.handleDeployResult(payload);
      }
    }).then((response) => {
      this.subscription = response;
    });
  }

  @wire(getSupportedTypes)
  wiredSupportedTypes({ data, error }) {
    if (data) {
      this.typeOptions = data.map((t) => ({
        label: t.label,
        value: t.value,
        description: t.description
      }));
      if (!this._selectedType && this.typeOptions.length > 0) {
        this._selectedType = this.typeOptions[0].value;
      }
    } else if (error) {
      this.showToast("Error", this.extractErrorMessage(error), "error");
    }
  }

  @wire(getFieldDescribes, { cmdtApiName: "$_selectedType" })
  wiredFieldDescribes({ data, error }) {
    if (!this._selectedType) {
      this.fieldDescribes = [];
      return;
    }
    this.isLoadingSchema = false;
    if (data) {
      this.fieldDescribes = data;
    } else if (error) {
      this.fieldDescribes = [];
      this.showToast("Error", this.extractErrorMessage(error), "error");
    }
  }

  @wire(getTypeInfo, { cmdtApiName: "$_selectedType" })
  wiredTypeInfo({ data, error }) {
    if (!this._selectedType) {
      this.typeInfo = undefined;
      return;
    }
    if (data) {
      this.typeInfo = data;
    } else if (error) {
      this.typeInfo = undefined;
      console.error("Failed to load CMDT type info", JSON.stringify(error));
    }
  }

  @wire(getRecords, { cmdtApiName: "$_selectedType" })
  wiredRecords(result) {
    this.wiredRecordsResult = result;
    if (!this._selectedType) {
      this.records = [];
      return;
    }
    this.isLoadingRecords = false;
    if (result.data) {
      this.records = result.data;
    } else if (result.error) {
      this.records = [];
      this.showToast("Error", this.extractErrorMessage(result.error), "error");
    }
  }

  handleTypeChange(event) {
    this._selectedType = event.detail.value;
    this.isLoadingSchema = true;
    this.isLoadingRecords = true;
  }

  handleRefresh() {
    this.isLoadingRecords = true;
    refreshApex(this.wiredRecordsResult).finally(() => {
      this.isLoadingRecords = false;
    });
  }

  get modalTitle() {
    return this.modalMode === "edit"
      ? `Edit ${this.masterLabel || "Record"}`
      : `New ${this.selectedTypeLabel} Record`;
  }

  get modalSubtitle() {
    return this.modalMode === "edit"
      ? "Update metadata attributes. Changes are deployed as native metadata and reflected org-wide."
      : "Create and enqueue a new custom metadata record definition into the org.";
  }

  get isDeveloperNameDisabled() {
    return this.isDeploying || this.modalMode === "edit";
  }

  get selectedTypeLabel() {
    const match = this.typeOptions.find((t) => t.value === this._selectedType);
    return match ? match.label : this._selectedType;
  }

  get currentTypeDescription() {
    const match = this.typeOptions.find((t) => t.value === this._selectedType);
    return match ? match.description : "";
  }

  get recordCount() {
    return this.records ? this.records.length : 0;
  }

  get hasRecords() {
    return !this.isLoading && this.records && this.records.length > 0;
  }

  get hasNoRecords() {
    return !this.isLoading && (!this.records || this.records.length === 0);
  }

  get isLoading() {
    return this.isLoadingSchema || this.isLoadingRecords;
  }

  get datatableColumns() {
    const columns = [
      {
        label: "Label",
        fieldName: "MasterLabel",
        type: "text",
        initialWidth: 160
      },
      {
        label: "Developer Name",
        fieldName: "DeveloperName",
        type: "text",
        initialWidth: 160
      }
    ];

    this.fieldDescribes.forEach((field) => {
      const isCheckbox =
        field.dataType && field.dataType.toLowerCase() === "checkbox";
      columns.push({
        label: field.label,
        fieldName: field.apiName,
        type: isCheckbox ? "boolean" : "text"
      });
    });

    columns.push({
      type: "action",
      typeAttributes: {
        rowActions: [
          { label: "Edit Record", name: "edit", iconName: "utility:edit" }
        ]
      },
      fixedWidth: 100
    });

    return columns;
  }

  get dynamicFormFields() {
    return this.fieldDescribes.map((field) => {
      const rawType = (field.dataType || "").toLowerCase();
      const rawValue = this.formValues[field.apiName];

      return {
        apiName: field.apiName,
        label: field.label,
        isLookup: field.isLookup,
        isCheckbox: !field.isLookup && rawType === "checkbox",
        isPicklist: !field.isLookup && rawType === "picklist",
        isNumber: !field.isLookup && rawType === "number",
        isTextArea: !field.isLookup && rawType === "textarea",
        isText:
          !field.isLookup &&
          rawType !== "checkbox" &&
          rawType !== "picklist" &&
          rawType !== "number" &&
          rawType !== "textarea",
        picklistOptions: (field.picklistValues || []).map((entry) => ({
          label: entry.label,
          value: entry.value
        })),
        value: rawValue === undefined || rawValue === null ? "" : rawValue,
        checked: !!rawValue
      };
    });
  }

  handleAddNew() {
    this.modalMode = "add";
    this.developerName = "";
    this.masterLabel = "";
    this.formValues = {};
    this.showModal = true;
  }

  handleRowAction(event) {
    const row = event.detail.row;
    this.modalMode = "edit";
    this.developerName = row.DeveloperName;
    this.masterLabel = row.MasterLabel;

    const values = {};
    this.fieldDescribes.forEach((field) => {
      values[field.apiName] = row[field.apiName];
    });
    this.formValues = values;
    this.showModal = true;
  }

  handleDeveloperNameChange(event) {
    this.developerName = event.target.value;
  }

  handleMasterLabelChange(event) {
    this.masterLabel = event.target.value;
    if (this.modalMode === "add" && !this.developerName) {
      this.developerName = event.target.value
        .replace(/[^a-zA-Z0-9_]/g, "_")
        .substring(0, 40);
    }
  }

  handleFieldChange(event) {
    const fieldApiName = event.target.dataset.field;
    const field = this.fieldDescribes.find((f) => f.apiName === fieldApiName);
    let value;
    const rawType = field && field.dataType ? field.dataType.toLowerCase() : "";
    if (rawType === "checkbox") {
      value = event.target.checked;
    } else if (rawType === "number") {
      value = event.target.value === "" ? null : Number(event.target.value);
    } else {
      value = event.target.value;
    }
    this.formValues = { ...this.formValues, [fieldApiName]: value };
  }

  closeModal() {
    if (this.isDeploying) return;
    this.showModal = false;
  }

  handleSave() {
    if (!this.developerName || !this.masterLabel) {
      this.showToast(
        "Validation Error",
        "Record Label and Developer Name are required.",
        "error"
      );
      return;
    }

    const requestKey = this.generateRequestKey();
    this.pendingRequestKey = requestKey;
    this.isDeploying = true;

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.deployTimeoutId = setTimeout(() => {
      this.isDeploying = false;
      this.pendingRequestKey = null;
      this.showToast(
        "Deployment Queued",
        "Deployment is still compiling in Salesforce background. Check Setup > Deployment Status.",
        "info"
      );
    }, DEPLOY_TIMEOUT_MS);

    const fieldValues = {};
    this.fieldDescribes.forEach((field) => {
      if (!field.isLookup) {
        fieldValues[field.apiName] = this.formValues[field.apiName];
      }
    });

    requestDeploy({
      cmdtApiName: this._selectedType,
      developerName: this.developerName,
      masterLabel: this.masterLabel,
      requestKey,
      fieldValues
    }).catch((error) => {
      this.clearDeployTimeout();
      this.isDeploying = false;
      this.pendingRequestKey = null;
      this.showToast(
        "Deployment Failed to Enqueue",
        this.extractErrorMessage(error),
        "error"
      );
    });
  }

  handleDeployResult(payload) {
    this.clearDeployTimeout();
    this.isDeploying = false;
    this.pendingRequestKey = null;

    if (payload.Success__c) {
      this.showToast(
        "Deployment Succeeded",
        `Custom metadata record ${this.masterLabel} was saved and deployed successfully.`,
        "success"
      );
      this.closeModal();
      this.isLoadingRecords = true;
      refreshApex(this.wiredRecordsResult).finally(() => {
        this.isLoadingRecords = false;
      });
    } else {
      this.showToast(
        "Deployment Error",
        payload.Error_Message__c || "The metadata deployment failed.",
        "error"
      );
    }
  }

  clearDeployTimeout() {
    if (this.deployTimeoutId) {
      clearTimeout(this.deployTimeoutId);
      this.deployTimeoutId = null;
    }
  }

  generateRequestKey() {
    if (typeof crypto !== "undefined" && crypto.randomUUID) {
      return crypto.randomUUID();
    }
    return "cmdt-" + Date.now() + "-" + Math.floor(Math.random() * 1000000);
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  extractErrorMessage(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    if (error && error.message) {
      return error.message;
    }
    return "An unexpected error occurred.";
  }
}
