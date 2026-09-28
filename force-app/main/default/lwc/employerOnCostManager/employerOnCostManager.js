import { LightningElement, wire, api } from 'lwc';
import { createRecord, deleteRecord } from 'lightning/uiRecordApi';
import { CurrentPageReference } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getWorkspace from '@salesforce/apex/EmployerOnCostManagerController.getWorkspace';
import getRateLineUsage from '@salesforce/apex/EmployerOnCostManagerController.getRateLineUsage';
import RATE_AGREEMENT_OBJECT from '@salesforce/schema/Rate_Agreements__c';
import RATE_AGREEMENT_NAME_FIELD from '@salesforce/schema/Rate_Agreements__c.Name';
import RATE_AGREEMENT_TYPE_FIELD from '@salesforce/schema/Rate_Agreements__c.Type__c';
import RATE_AGREEMENT_VERSION_OBJECT from '@salesforce/schema/Rate_Agreement_Version__c';
import RATE_AGREEMENT_VERSION_AGREEMENT_FIELD from '@salesforce/schema/Rate_Agreement_Version__c.Rate_Agreement__c';
import RATE_AGREEMENT_VERSION_EFFECTIVE_DATE_FIELD from '@salesforce/schema/Rate_Agreement_Version__c.Effective_Date__c';
import EMPLOYER_ON_COST_OBJECT from '@salesforce/schema/Employer_On_Cost__c';
import EOC_VERSION_FIELD from '@salesforce/schema/Employer_On_Cost__c.Rate_Agreement_Version__c';
import EOC_TYPE_FIELD from '@salesforce/schema/Employer_On_Cost__c.Type__c';
import EOC_ON_COST_TYPE_FIELD from '@salesforce/schema/Employer_On_Cost__c.On_Cost_Type__c';
import EOC_CALC_TYPE_FIELD from '@salesforce/schema/Employer_On_Cost__c.Calc_Type__c';
import EOC_VALUE_FIELD from '@salesforce/schema/Employer_On_Cost__c.Value__c';
import EOC_WORKER_TYPE_FIELD from '@salesforce/schema/Employer_On_Cost__c.Worker_Type__c';

const MARGIN_CALCULATOR_TEMPLATE_TYPE = 'Margin Calculator Template';
// Every on-cost attaches to a single default version with this effective date.
const DEFAULT_EFFECTIVE_DATE = '1900-01-01';
const RECORD_AGREEMENT_TYPE = 'Record Agreement';

const COST_COLUMNS = [
    { label: 'On Cost Type', fieldName: 'On_Cost_Type__c' },
    { label: 'Calc Type', fieldName: 'Calc_Type__c' },
    { label: 'Value', fieldName: 'Value__c', type: 'number', editable: false, cellAttributes: { alignment: 'left' } },
    { label: 'Worker Type', fieldName: 'Worker_Type__c' },
    {
        type: 'action',
        typeAttributes: { rowActions: [{ label: 'Delete', name: 'delete', iconName: 'utility:delete' }] }
    }
];

export default class EmployerOnCostManager extends LightningElement {
    rateAgreementObjectApiName = RATE_AGREEMENT_OBJECT.objectApiName;
    employerOnCostObjectApiName = EMPLOYER_ON_COST_OBJECT.objectApiName;
    onCostTypeFieldName = EOC_ON_COST_TYPE_FIELD.fieldApiName;
    calcTypeFieldName = EOC_CALC_TYPE_FIELD.fieldApiName;
    valueFieldName = EOC_VALUE_FIELD.fieldApiName;
    workerTypeFieldName = EOC_WORKER_TYPE_FIELD.fieldApiName;

    agreementFilter = {
        criteria: [{ fieldPath: RATE_AGREEMENT_TYPE_FIELD.fieldApiName, operator: 'eq', value: MARGIN_CALCULATOR_TEMPLATE_TYPE }]
    };
    costColumns = COST_COLUMNS;

    @api selectedAgreementId;
    versionId;
    costs = [];
    isLoading = false;

    showNewAgreementModal = false;
    newAgreementName = '';
    isSavingAgreement = false;

    showAddCostModal = false;
    isSavingCost = false;

    wiredWorkspaceResult;

    // Reads the agreement Id from the URL when opened standalone.
    @wire(CurrentPageReference)
    setCurrentPageReference(pageReference) {
        const urlRecordId = pageReference?.state?.c__recordId;
        if (urlRecordId && !this.selectedAgreementId) {
            this.selectedAgreementId = urlRecordId;
        }
    }

    // Loads the selected agreement's default version and on-costs.
    @wire(getWorkspace, { rateAgreementId: '$selectedAgreementId' })
    wiredWorkspace(result) {
        this.wiredWorkspaceResult = result;
        const { data, error } = result;
        if (data) {
            this.versionId = data.versionId;
            this.costs = data.costs || [];
            this.isLoading = false;
        } else if (error) {
            this.versionId = undefined;
            this.costs = [];
            this.isLoading = false;
            this.showError(error);
        }
    }

    // Switches to the agreement chosen in the picker.
    handlePickerChange(event) {
        this.selectedAgreementId = event.detail.recordId;
        this.versionId = undefined;
        this.costs = [];
        this.isLoading = !!this.selectedAgreementId;
    }

    openNewAgreementModal() {
        this.newAgreementName = '';
        this.showNewAgreementModal = true;
    }

    closeNewAgreementModal() {
        this.showNewAgreementModal = false;
    }

    handleNewAgreementNameChange(event) {
        this.newAgreementName = event.target.value;
    }

    // Creates a Margin Calculator Template agreement with its default version.
    async handleCreateAgreement() {
        const name = this.newAgreementName?.trim();
        if (!name) {
            this.showToast('Error', 'Please enter an Agreement Name.', 'error');
            return;
        }

        this.isSavingAgreement = true;
        try {
            const agreement = await createRecord({
                apiName: RATE_AGREEMENT_OBJECT.objectApiName,
                fields: {
                    [RATE_AGREEMENT_NAME_FIELD.fieldApiName]: name,
                    [RATE_AGREEMENT_TYPE_FIELD.fieldApiName]: MARGIN_CALCULATOR_TEMPLATE_TYPE
                }
            });
            const version = await createRecord({
                apiName: RATE_AGREEMENT_VERSION_OBJECT.objectApiName,
                fields: {
                    [RATE_AGREEMENT_VERSION_AGREEMENT_FIELD.fieldApiName]: agreement.id,
                    [RATE_AGREEMENT_VERSION_EFFECTIVE_DATE_FIELD.fieldApiName]: DEFAULT_EFFECTIVE_DATE
                }
            });

            this.versionId = version.id;
            this.costs = [];
            this.selectedAgreementId = agreement.id;
            this.closeNewAgreementModal();
            this.showToast('Success', 'Rate Agreement created.', 'success');
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSavingAgreement = false;
        }
    }

    // Returns the default version, creating it if the agreement has none.
    async ensureVersion() {
        if (this.versionId) {
            return this.versionId;
        }
        const version = await createRecord({
            apiName: RATE_AGREEMENT_VERSION_OBJECT.objectApiName,
            fields: {
                [RATE_AGREEMENT_VERSION_AGREEMENT_FIELD.fieldApiName]: this.selectedAgreementId,
                [RATE_AGREEMENT_VERSION_EFFECTIVE_DATE_FIELD.fieldApiName]: DEFAULT_EFFECTIVE_DATE
            }
        });
        this.versionId = version.id;
        return this.versionId;
    }

    // Opens the add-cost modal once a default version exists.
    async openAddCostModal() {
        try {
            await this.ensureVersion();
            this.showAddCostModal = true;
        } catch (error) {
            this.showError(error);
        }
    }

    closeAddCostModal() {
        this.showAddCostModal = false;
    }

    // Adds the hidden version and type fields before submitting.
    handleCostFormSubmit(event) {
        event.preventDefault();
        this.isSavingCost = true;
        const fields = event.detail.fields;
        fields[EOC_VERSION_FIELD.fieldApiName] = this.versionId;
        fields[EOC_TYPE_FIELD.fieldApiName] = RECORD_AGREEMENT_TYPE;
        this.template.querySelector('lightning-record-edit-form.cost-form').submit(fields);
    }

    // Closes the modal and refreshes the on-cost list.
    async handleCostFormSuccess() {
        this.isSavingCost = false;
        this.closeAddCostModal();
        this.showToast('Success', 'Employer On Cost added.', 'success');
        await refreshApex(this.wiredWorkspaceResult);
    }

    handleCostFormError(event) {
        this.isSavingCost = false;
        this.showToast('Error', event.detail?.detail || event.detail?.message || 'Please correct the highlighted errors.', 'error');
    }

    // Deletes an on-cost unless Rate Lines use the agreement, listing up to 5 of them.
    async handleRowAction(event) {
        if (event.detail.action.name !== 'delete') {
            return;
        }
        try {
            const usage = await getRateLineUsage({ rateAgreementId: this.selectedAgreementId });
            if (usage.totalCount > 0) {
                const shown = usage.sampleNames.join(', ');
                const remaining = usage.totalCount - usage.sampleNames.length;
                const more = remaining > 0 ? `, and ${remaining} more` : '';
                this.showToast(
                    'Cannot delete Employer On Cost',
                    `This Rate Agreement is in use by Rate Line(s): ${shown}${more}. Remove those references before deleting.`,
                    'error'
                );
                return;
            }

            await deleteRecord(event.detail.row.Id);
            this.showToast('Success', 'Employer On Cost removed.', 'success');
            await refreshApex(this.wiredWorkspaceResult);
        } catch (error) {
            this.showError(error);
        }
    }

    get hasSelectedAgreement() {
        return !!this.selectedAgreementId;
    }

    get hasCosts() {
        return this.costs.length > 0;
    }

    get showEmptyState() {
        return this.hasSelectedAgreement && !this.isLoading && !this.hasCosts;
    }

    get showCostsTable() {
        return this.hasSelectedAgreement && !this.isLoading && this.hasCosts;
    }

    showError(error) {
        this.showToast('Error', this.getErrorMessage(error), 'error');
    }

    // Extracts the most specific message from a UI API or Apex error.
    getErrorMessage(error) {
        const output = error?.body?.output ?? error?.output;
        if (output?.fieldErrors && Object.keys(output.fieldErrors).length) {
            return Object.values(output.fieldErrors).flat().map((e) => e.message).join(', ');
        }
        if (output?.errors?.length) {
            return output.errors.map((e) => e.message).join(', ');
        }
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error?.body?.message) {
            return error.body.message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'An unknown error occurred.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}