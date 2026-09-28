import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import cloneVersion from '@salesforce/apex/RateAgreementManagerController.cloneVersion';

export default class ManageRateAgreementVersion extends LightningElement {
    @api mode; // 'edit' or 'clone'
    @api versionId;

    newEffectiveDate;
    isSaving = false;

    get isEditMode() {
        return this.mode === 'edit';
    }

    get isCloneMode() {
        return this.mode === 'clone';
    }

    get modalTitle() {
        return this.isEditMode ? 'Edit Rate Agreement Version' : 'Clone Rate Agreement Version';
    }

    get disableClone() {
        return !this.newEffectiveDate || this.isSaving;
    }

    handleDateChange(event) {
        this.newEffectiveDate = event.detail.value;
    }

    handleEditSubmit() {
        this.isSaving = true;
    }

    handleEditSuccess() {
        this.isSaving = false;
        this.dispatchEvent(new CustomEvent('success'));
    }

    async handleClone() {
        this.isSaving = true;
        try {
            await cloneVersion({
                sourceVersionId: this.versionId,
                newEffectiveDate: this.newEffectiveDate
            });
            this.dispatchEvent(new CustomEvent('success'));
        } catch (error) {
            this.handleError(error);
        } finally {
            this.isSaving = false;
        }
    }

    handleError(error) {
        this.isSaving = false;
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message: error?.body?.message || error?.message || 'Something went wrong.',
            variant: 'error'
        }));
    }

    close() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}