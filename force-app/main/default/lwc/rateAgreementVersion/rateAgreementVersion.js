import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import RATE_AGREEMENT_LINE_OBJECT from '@salesforce/schema/Rate_Agreement_Lines__c';
import getVersionWorkspace from '@salesforce/apex/RateAgreementManagerController.getVersionWorkspace';
import deleteLine from '@salesforce/apex/RateAgreementManagerController.deleteLine';

const SCALE_COLUMNS = [
    { label: 'Scale Definition', fieldName: 'scaleDefinitionName' },
    { label: 'Job Type', fieldName: 'defJobType' },
    { label: 'Region', fieldName: 'defRegion' },
    { label: 'Description', fieldName: 'defDescription' },
    { label: 'Ranking', fieldName: 'defRanking', type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Min Amount', fieldName: 'Min_Amount__c', type: 'number', editable: true, cellAttributes: { alignment: 'left' } },
    { label: 'Max Amount', fieldName: 'Max_Amount__c', type: 'number', editable: true, cellAttributes: { alignment: 'left' } }
];

export default class RateAgreementVersion extends LightningElement {
    @api versionId;
    @api rateAgreementId;
    @api isCurrent = false;

    scales = [];
    lines = [];
    originalLineById = {};
    isLoading = false;

    scaleColumns = SCALE_COLUMNS;

    showAddLineModal = false;
    showLineOnCostModal = false;
    selectedLineId;

    workerTypeOptions = [];
    calcTypeOptions = [];

    connectedCallback() {
        this.load();
    }

    @wire(getObjectInfo, { objectApiName: RATE_AGREEMENT_LINE_OBJECT })
    lineInfo;

    @wire(getPicklistValuesByRecordType, {
        objectApiName: RATE_AGREEMENT_LINE_OBJECT,
        recordTypeId: '$lineInfo.data.defaultRecordTypeId'
    })
    wiredLinePicklists({ data }) {
        if (data) {
            this.workerTypeOptions = data.picklistFieldValues.Worker_Type__c?.values || [];
            this.calcTypeOptions = data.picklistFieldValues.Calc_Type__c?.values || [];
        }
    }

    get hasScales() {
        return !this.isLoading && this.scales.length > 0;
    }

    get hasLines() {
        return !this.isLoading && this.lines.length > 0;
    }

    get trueValue() {
        return true;
    }

    get scaleTableClass() {
        return this.isCurrent ? 'table-wrapper theme-green' : 'table-wrapper theme-blue';
    }

    // Restricts the Min/Max Scale pickers to Scales that belong to this Version.
    get scaleFilter() {
        return {
            criteria: [
                { fieldPath: 'Rate_Agreement_Version__c', operator: 'eq', value: this.versionId }
            ]
        };
    }

    async load() {
        this.isLoading = true;
        try {
            const result = await getVersionWorkspace({ versionId: this.versionId });

            this.scales = (result.scales || []).map(scale => ({
                ...scale,
                scaleDefinitionName: scale.Rate_Agreement_Scale_Definition__r?.Name,
                defJobType: scale.Rate_Agreement_Scale_Definition__r?.Job_Type__c,
                defRegion: scale.Rate_Agreement_Scale_Definition__r?.Region__c,
                defDescription: scale.Rate_Agreement_Scale_Definition__r?.Description__c,
                defRanking: scale.Rate_Agreement_Scale_Definition__r?.Ranking__c
            }));

            const lines = (result.lines || []).map(l => ({ ...l, isDirty: false }));
            this.lines = lines;
            this.originalLineById = {};
            lines.forEach(l => { this.originalLineById[l.Id] = { ...l }; });
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleScaleSave(event) {
        try {
            await Promise.all(
                event.detail.draftValues.map(draft => updateRecord({ fields: { ...draft } }))
            );
            this.showToast('Success', 'Changes saved.', 'success');
            this.load();
        } catch (error) {
            this.showError(error);
        }
    }

    // lightning-combobox/lightning-input fire detail.value; lightning-record-picker fires
    // detail.recordId instead -- read whichever the event actually carries.
    handleLineCellChange(event) {
        const id = event.currentTarget.dataset.id;
        const field = event.currentTarget.dataset.field;
        const rawValue = event.detail.recordId !== undefined ? event.detail.recordId : event.detail.value;
        const value = field === 'Margin_Value__c' ? parseFloat(rawValue) : rawValue;

        this.lines = this.lines.map(line =>
            line.Id === id ? { ...line, [field]: value, isDirty: true } : line
        );
    }

    async handleSaveLineRow(event) {
        const id = event.currentTarget.dataset.id;
        const line = this.lines.find(l => l.Id === id);
        if (!line) return;

        try {
            await updateRecord({
                fields: {
                    Id: line.Id,
                    Worker_Type__c: line.Worker_Type__c,
                    Calc_Type__c: line.Calc_Type__c,
                    Margin_Value__c: line.Margin_Value__c,
                    Min_Scale__c: line.Min_Scale__c,
                    Max_Scale__c: line.Max_Scale__c
                }
            });
            this.showToast('Success', 'Changes saved.', 'success');
            this.load();
        } catch (error) {
            this.showError(error);
        }
    }

    handleCancelLineRow(event) {
        const id = event.currentTarget.dataset.id;
        const original = this.originalLineById[id];
        if (!original) return;

        this.lines = this.lines.map(line =>
            line.Id === id ? { ...original, isDirty: false } : line
        );
    }

    openAddLineModal() {
        this.showAddLineModal = true;
    }

    closeAddLineModal() {
        this.showAddLineModal = false;
    }

    handleAddLineSuccess() {
        this.closeAddLineModal();
        this.showToast('Success', 'Rate Agreement Line created.', 'success');
        this.load();
    }

    handleViewOnCostClick(event) {
        this.selectedLineId = event.currentTarget.dataset.id;
        this.showLineOnCostModal = true;
    }

    closeLineOnCostModal() {
        this.showLineOnCostModal = false;
    }

    handleDeleteLineClick(event) {
        const lineId = event.currentTarget.dataset.id;
        // eslint-disable-next-line no-alert
        if (confirm('Delete this Rate Agreement Line and its Employer On Costs?')) {
            this.deleteLineRecord(lineId);
        }
    }

    async deleteLineRecord(lineId) {
        try {
            await deleteLine({ lineId });
            this.showToast('Success', 'Rate Agreement Line deleted.', 'success');
            this.load();
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