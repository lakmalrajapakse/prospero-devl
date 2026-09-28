import { LightningElement, api, wire } from 'lwc';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import { createRecord, updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import RATE_AGREEMENT_OBJECT from '@salesforce/schema/Rate_Agreements__c';
import RATE_AGREEMENT_VERSION_OBJECT from '@salesforce/schema/Rate_Agreement_Version__c';
import EMPLOYER_ON_COST_OBJECT from '@salesforce/schema/Employer_On_Cost__c';
import RATE_AGREEMENT_SCALE_DEFINITION_OBJECT from '@salesforce/schema/Rate_Agreement_Scale_Definition__c';

export default class CreateRateAgreementModal extends LightningElement {
    @api mode; 
    @api selectedAgreement; 
    @api selectedOnCost; 

    isSaving = false;

    // Create / Edit Rate Agreement
    name;
    clientId;
    type;

    effectiveDate;

    calcType;
    onCostType;
    onCostTypeValue; 
    workerType;
    value;

    // Add Scale Definition
    scaleDefName;
    jobType;
    region;
    description;

    displayInfo = { primaryField: 'Name' };

    connectedCallback() {
        if (this.mode === 'edit' && this.selectedAgreement) {
            this.name = this.selectedAgreement.Name;
            this.clientId = this.selectedAgreement.Account__c;
            this.type = this.selectedAgreement.Type__c;
        }
        if (this.mode === 'editOnCost' && this.selectedOnCost) {
            this.calcType = this.selectedOnCost.Calc_Type__c;
            this.onCostType = this.selectedOnCost.On_Cost_Type__c;
            this.onCostTypeValue = this.selectedOnCost.Type__c;
            this.workerType = this.selectedOnCost.Worker_Type__c;
            this.value = this.selectedOnCost.Value__c;
        }
    }

    get isCreateMode() {
        return this.mode === 'create' || this.mode === 'edit';
    }
    get isAddVersionMode() {
        return this.mode === 'addVersion';
    }
    get isEditOnCostMode() {
        return this.mode === 'editOnCost';
    }
    get isAddScaleDefinitionMode() {
        return this.mode === 'addScaleDefinition';
    }

    get modalTitle() {
        switch (this.mode) {
            case 'create': return 'Create Rate Agreement';
            case 'edit': return 'Edit Rate Agreement';
            case 'addVersion': return 'Add Rate Agreement Version';
            case 'editOnCost': return 'Edit Employer On-Cost';
            case 'addScaleDefinition': return 'Add Rate Agreement Scale Definition';
            default: return '';
        }
    }

    /// Rate Agreement Type__c picklist (create/edit mode)
    @wire(getObjectInfo, { objectApiName: RATE_AGREEMENT_OBJECT })
    rateAgreementInfo;

    @wire(getPicklistValuesByRecordType, {
        objectApiName: RATE_AGREEMENT_OBJECT,
        recordTypeId: '$rateAgreementInfo.data.defaultRecordTypeId'
    })
    wiredAgreementPicklists({ data }) {
        if (data) {
            this.typeOptions = data.picklistFieldValues.Type__c.values;
        }
    }

    @wire(getObjectInfo, { objectApiName: EMPLOYER_ON_COST_OBJECT })
    onCostInfo;

    @wire(getPicklistValuesByRecordType, {
        objectApiName: EMPLOYER_ON_COST_OBJECT,
        recordTypeId: '$onCostInfo.data.defaultRecordTypeId'
    })
    wiredOnCostPicklists({ data }) {
        if (data) {
            this.calcTypeOptions = data.picklistFieldValues.Calc_Type__c.values;
            this.onCostTypeOptions = data.picklistFieldValues.On_Cost_Type__c.values;
            this.onCostTypeValueOptions = data.picklistFieldValues.Type__c.values;
            this.workerTypeOptions = data.picklistFieldValues.Worker_Type__c.values;
        }
    }

    handleFieldChange(event) {
        const { name, value } = event.target;
        this[name] = value;
    }

    lookupChangeHandler(event) {
        this.clientId = event.detail.recordId;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSave() {
        this.isSaving = true;
        try {
            switch (this.mode) {
                case 'create': await this.saveCreate(); break;
                case 'edit': await this.saveEdit(); break;
                case 'addVersion': await this.saveVersion(); break;
                case 'editOnCost': await this.saveOnCost(); break;
                case 'addScaleDefinition': await this.saveScaleDefinition(); break;
                default: break;
            }
            this.dispatchEvent(new CustomEvent('success'));
        } catch (error) {
            this.showMessage('Error', error.body?.message || error.message, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async saveCreate() {
        if (!this.name || !this.clientId) {
            throw { message: 'Rate Agreement Name and Client are required.' };
        }
        await createRecord({
            apiName: RATE_AGREEMENT_OBJECT.objectApiName,
            fields: {
                Name: this.name,
                Account__c: this.clientId,
                Type__c: this.type
            }
        });
    }

    async saveEdit() {
        await updateRecord({
            fields: {
                Id: this.selectedAgreement.Id,
                Name: this.name,
                Account__c: this.clientId,
                Type__c: this.type
            }
        });
    }

    async saveVersion() {
        if (!this.effectiveDate) {
            throw { message: 'Effective Date is required.' };
        }
        const version = await createRecord({
            apiName: RATE_AGREEMENT_VERSION_OBJECT.objectApiName,
            fields: {
                Effective_Date__c: this.effectiveDate,
                Rate_Agreement__c: this.selectedAgreement.Id
            }
        });

        await createRecord({
            apiName: EMPLOYER_ON_COST_OBJECT.objectApiName,
            fields: {
                Rate_Agreement_Version__c: version.id
            }
        });
    }

    async saveOnCost() {
        await updateRecord({
            fields: {
                Id: this.selectedOnCost.Id,
                Calc_Type__c: this.calcType,
                On_Cost_Type__c: this.onCostType,
                Type__c: this.onCostTypeValue,
                Worker_Type__c: this.workerType,
                Value__c: this.value
            }
        });
    }

    async saveScaleDefinition() {
        if (!this.scaleDefName) {
            throw { message: 'Name is required.' };
        }
        await createRecord({
            apiName: RATE_AGREEMENT_SCALE_DEFINITION_OBJECT.objectApiName,
            fields: {
                Name: this.scaleDefName,
                Job_Type__c: this.jobType,
                Region__c: this.region,
                Description__c: this.description,
                Rate_Agreements__c: this.selectedAgreement.Id
            }
        });
    }

    showMessage(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}