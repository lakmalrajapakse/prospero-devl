import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getScaleDefinitionsForRateAgreement from '@salesforce/apex/RateAgreementManagerController.getScaleDefinitionsForRateAgreement';
import createVersionWithScales from '@salesforce/apex/RateAgreementManagerController.createVersionWithScales';

export default class AddRateAgreementVersion extends LightningElement {
    @api rateAgreementId;

    step = 1;
    effectiveDate;
    scaleRows = [];
    isSaving = false;
    isLoadingDefinitions = false;

    connectedCallback() {
        this.loadDefinitions();
    }

    async loadDefinitions() {
        this.isLoadingDefinitions = true;
        try {
            const data = await getScaleDefinitionsForRateAgreement({
                rateAgreementId: this.rateAgreementId
            });

            this.scaleRows = (data || []).map(def => ({
                scaleDefinitionId: def.Id,
                name: def.Name,
                jobType: def.Job_Type__c,
                region: def.Region__c,
                description: def.Description__c,
                minAmount: null,
                maxAmount: null
            }));
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoadingDefinitions = false;
        }
    }

    get isStepOne() {
        return this.step === 1;
    }

    get isStepTwo() {
        return this.step === 2;
    }

    get modalClass() {
        return this.isStepTwo
            ? 'slds-modal slds-fade-in-open slds-modal_large'
            : 'slds-modal slds-fade-in-open slds-modal_small';
    }

    get hasDefinitions() {
        return this.scaleRows.length > 0;
    }

    get disableNext() {
        return !this.effectiveDate;
    }

    handleDateChange(event) {
        this.effectiveDate = event.detail.value;
    }

    handleAmountChange(event) {
        const definitionId = event.target.dataset.id;
        const field = event.target.name;
        const value = event.detail.value;

        this.scaleRows = this.scaleRows.map(row =>
            row.scaleDefinitionId === definitionId
                ? { ...row, [field]: value === '' ? null : parseFloat(value) }
                : row
        );
    }

    goNext() {
        this.step = 2;
    }

    goBack() {
        this.step = 1;
    }

    async handleSave() {
        const incomplete = this.scaleRows.some(
            row => row.minAmount === null || row.maxAmount === null
        );

        if (incomplete) {
            this.showToast('Error', 'Enter a Min and Max Amount for every definition.', 'error');
            return;
        }

        this.isSaving = true;

        try {
            await createVersionWithScales({
                rateAgreementId: this.rateAgreementId,
                effectiveDate: this.effectiveDate,
                scales: this.scaleRows.map(row => ({
                    scaleDefinitionId: row.scaleDefinitionId,
                    minAmount: row.minAmount,
                    maxAmount: row.maxAmount
                }))
            });

            this.dispatchEvent(new CustomEvent('success'));
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSaving = false;
        }
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    showError(error) {
        this.showToast('Error', error.body?.message || error.message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}