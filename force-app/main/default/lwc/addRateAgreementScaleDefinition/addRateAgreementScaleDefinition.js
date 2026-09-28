import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import createScaleDefinition from '@salesforce/apex/RateAgreementManagerController.createScaleDefinition';

export default class AddRateAgreementScaleDefinition extends LightningElement {
    @api rateAgreementId;
    isSaving = false;
    name;
    jobType;
    region;
    description;

    handleFieldChange(event) {
        this[event.target.dataset.field] = event.detail.value;
    }

    async handleSave() {
        if (!this.name) {
            this.showToast('Error', 'Name is required.', 'error');
            return;
        }
        this.isSaving = true;
        try {
            await createScaleDefinition({
                rateAgreementId: this.rateAgreementId,
                name: this.name,
                jobType: this.jobType,
                region: this.region,
                description: this.description
            });
            this.isSaving = false;
            this.dispatchEvent(new CustomEvent('success'));
        } catch (error) {
            this.isSaving = false;
            this.showToast('Error', error.body?.message || error.message, 'error');
        }
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}