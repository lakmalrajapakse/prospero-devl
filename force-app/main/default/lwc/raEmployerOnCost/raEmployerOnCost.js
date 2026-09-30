import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import EMPLOYER_ON_COST_OBJECT from '@salesforce/schema/Employer_On_Cost__c';
import getOnCosts from '@salesforce/apex/RateAgreementManagerController.getOnCosts';
import upsertOnCost from '@salesforce/apex/RateAgreementManagerController.upsertOnCost';
import deleteOnCost from '@salesforce/apex/RateAgreementManagerController.deleteOnCost';

export default class RaEmployerOnCost extends LightningElement {
    @api versionId;
    @api lineId;
    @api isDefault = false;

    onCosts = [];
    originalById = {};
    isLoading = false;
    isSaving = false;

    showAddModal = false;
    newWorkerType;
    newOnCostType;
    newCalcType;
    newType;
    newValue;

    workerTypeOptions = [];
    onCostTypeOptions = [];
    calcTypeOptions = [];
    typeOptions = [];

    connectedCallback() {
        this.load();
    }

    get hasOnCosts() {
        return !this.isLoading && this.onCosts.length > 0;
    }

    @wire(getObjectInfo, { objectApiName: EMPLOYER_ON_COST_OBJECT })
    onCostInfo;

    @wire(getPicklistValuesByRecordType, {
        objectApiName: EMPLOYER_ON_COST_OBJECT,
        recordTypeId: '$onCostInfo.data.defaultRecordTypeId'
    })
    wiredPicklists({ data }) {
        if (data) {
            this.workerTypeOptions = data.picklistFieldValues.Worker_Type__c?.values || [];
            this.onCostTypeOptions = data.picklistFieldValues.On_Cost_Type__c?.values || [];
            this.calcTypeOptions = data.picklistFieldValues.Calc_Type__c?.values || [];
            this.typeOptions = data.picklistFieldValues.Type__c?.values || [];
        }
    }

    async load() {
        this.isLoading = true;
        try {
            const data = await getOnCosts({
                versionId: this.versionId,
                lineId: this.lineId || null
            });
            this.onCosts = data.map(r => ({ ...r, isDirty: false }));
            this.originalById = {};
            data.forEach(r => { this.originalById[r.Id] = { ...r }; });
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleCellChange(event) {
        const id = event.currentTarget.dataset.id;
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;

        this.onCosts = this.onCosts.map(row =>
            row.Id === id
                ? { ...row, [field]: field === 'Value__c' ? parseFloat(value) : value, isDirty: true }
                : row
        );
    }

    async handleSaveRow(event) {
        const id = event.currentTarget.dataset.id;
        const row = this.onCosts.find(r => r.Id === id);
        if (!row) return;

        try {
            await upsertOnCost({
                versionId: this.versionId,
                lineId: this.lineId || null,
                input: {
                    id: row.Id,
                    workerType: row.Worker_Type__c,
                    onCostType: row.On_Cost_Type__c,
                    calcType: row.Calc_Type__c,
                    type: row.Type__c,
                    value: row.Value__c
                }
            });
            this.showToast('Success', 'Changes saved.', 'success');
            await this.load();
            this.dispatchEvent(new CustomEvent('change'));
        } catch (error) {
            this.showError(error);
        }
    }

    handleCancelRow(event) {
        const id = event.currentTarget.dataset.id;
        const original = this.originalById[id];
        if (!original) return;

        this.onCosts = this.onCosts.map(row =>
            row.Id === id ? { ...original, isDirty: false } : row
        );
    }

    openAddModal() {
        this.newWorkerType = undefined;
        this.newOnCostType = undefined;
        this.newCalcType = undefined;
        this.newType = undefined;
        this.newValue = undefined;
        this.showAddModal = true;
    }

    closeAddModal() {
        this.showAddModal = false;
    }

    handleNewFieldChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.detail.value;
        if (field === 'workerType') this.newWorkerType = value;
        if (field === 'onCostType') this.newOnCostType = value;
        if (field === 'calcType') this.newCalcType = value;
        if (field === 'type') this.newType = value;
        if (field === 'value') this.newValue = value;
    }

    async handleAddSave() {
        this.isSaving = true;
        try {
            await upsertOnCost({
                versionId: this.versionId,
                lineId: this.lineId || null,
                input: {
                    id: null,
                    workerType: this.newWorkerType,
                    onCostType: this.newOnCostType,
                    calcType: this.newCalcType,
                    type: this.newType,
                    value: this.newValue !== undefined && this.newValue !== '' ? parseFloat(this.newValue) : null
                }
            });
            this.showAddModal = false;
            this.showToast('Success', 'Employer On Cost added.', 'success');
            await this.load();
            this.dispatchEvent(new CustomEvent('change'));
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSaving = false;
        }
    }

    async handleDelete(event) {
        const id = event.currentTarget.dataset.id;
        try {
            await deleteOnCost({ onCostId: id });
            this.showToast('Success', 'Employer On Cost deleted.', 'success');
            await this.load();
            this.dispatchEvent(new CustomEvent('change'));
        } catch (error) {
            this.showError(error);
        }
    }

    showError(error) {
        this.showToast('Error', error.body?.message || error.message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}