import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import copyDefaultOnCostsToLine from '@salesforce/apex/RateAgreementManagerController.copyDefaultOnCostsToLine';

export default class AddRateAgreementLine extends LightningElement {
    @api versionId;
    isSaving = false;

    handleSubmit() {
        this.isSaving = true;
    }

    async handleSuccess(event) {
        const newLineId = event.detail.id;
        try {
            await copyDefaultOnCostsToLine({ versionId: this.versionId, lineId: newLineId });
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Line created, but copying default on-costs failed: ' + (error.body?.message || error.message),
                variant: 'error'
            }));
        } finally {
            this.isSaving = false;
            this.dispatchEvent(new CustomEvent('success'));
        }
    }

    handleError() {
        this.isSaving = false;
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}