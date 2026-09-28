import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { getRecord, createRecord, updateRecord, deleteRecord } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import { refreshApex } from '@salesforce/apex';

const COMMISSION_SPLIT = 'Commission_Split__c';
const FIELDS = [
    `${COMMISSION_SPLIT}.Consultant__c`,
    `${COMMISSION_SPLIT}.Consultant__r.Name`,
    `${COMMISSION_SPLIT}.Team__c`,
    `${COMMISSION_SPLIT}.Team__r.Name`,
    `${COMMISSION_SPLIT}.Split_Percentage__c`,
    `${COMMISSION_SPLIT}.Commission_Type__c`
];
const USER_FIELDS = ['User.Name', 'User.Commission_Type__c'];
const PLACEMENT_FIELDS = [
    'sirenum__Placement__c.Job__c',
    'sirenum__Placement__c.Job__r.Team__c',
    'sirenum__Placement__c.Job__r.Team__r.Name'
];
const CLOSING_REPORT_FIELDS = [
    'TR1__Closing_Report__c.TR1__Job__c',
    'TR1__Closing_Report__c.TR1__Job__r.Team__c',
    'TR1__Closing_Report__c.TR1__Job__r.Team__r.Name'
];

export default class ManageCommissionSplits extends LightningElement {
    @api recordId;

    rows = [];
    deletedRows = [];
    showPicker = false;
    showWarning = false;
    hasChanges = false; 
    isClosingReport = false; 
    selectedConsultantId;
    selectedConsultantName = '';
    selectedConsultantType = '';
    newPercentage;
    wiredSplitsResult;
    jobTeamId;
    jobTeamName = '';

    @wire(getObjectInfo, { objectApiName: COMMISSION_SPLIT })
    objectInfo;

    @wire(getPicklistValuesByRecordType, {
        objectApiName: COMMISSION_SPLIT,
        recordTypeId: '$objectInfo.data.defaultRecordTypeId'
    })
    picklistInfo;

    @wire(getRelatedListRecords, { parentRecordId: '$recordId', relatedListId: 'Commission_Splits__r', fields: FIELDS })
    wiredSplits(result) {
        this.wiredSplitsResult = result;
        if (result.data) {
            this.rows = result.data.records.map(rec => ({
                Id: rec.id,
                consultantId: rec.fields.Consultant__c?.value,
                consultantName: rec.fields.Consultant__r?.value?.fields?.Name?.value || '',
                teamId: rec.fields.Team__c?.value,
                teamName: rec.fields.Team__r?.value?.fields?.Name?.value || '',
                percentage: rec.fields.Split_Percentage__c?.value ?? 0,
                type: rec.fields.Commission_Type__c?.value || '',
                isNew: false
            }));
            this.deletedRows = [];
        } else if (result.error) {
            console.error('WIRE ERROR:', JSON.stringify(result.error));
            this.showToast('Error', 'Unable to load commission splits.', 'error');
        }
    }

    @wire(getRecord, { recordId: '$selectedConsultantId', fields: USER_FIELDS })
    wiredConsultant({ data }) {
        if (data) {
            this.selectedConsultantName = data.fields.Name?.value || '';
            this.selectedConsultantType = data.fields.Commission_Type__c?.value || '';
        }
    }
    // Retrieving the Team from the Placement's Job for new Commission Splits
    @wire(getRecord, { recordId: '$recordId', fields: PLACEMENT_FIELDS })
    wiredPlacement({ data, error }) {
        if (data) {
            this.jobTeamId = data.fields.Job__r?.value?.fields?.Team__c?.value;
            this.jobTeamName = data.fields.Job__r?.value?.fields?.Team__r?.value?.fields?.Name?.value || '';
            this.isClosingReport = false;
        } else if (error) {
            console.error('PLACEMENT WIRE ERROR:', JSON.stringify(error));
        }
    }
    // Retrieving the Team from the Closing Report's Job for new Commission Splits
    @wire(getRecord, { recordId: '$recordId', fields: CLOSING_REPORT_FIELDS })
    wiredClosingReport({ data, error }) {
        if (data) {
            this.jobTeamId = data.fields.TR1__Job__r?.value?.fields?.Team__c?.value;
            this.jobTeamName = data.fields.TR1__Job__r?.value?.fields?.Team__r?.value?.fields?.Name?.value || '';
            this.isClosingReport = true;
        } else if (error) {
            console.error('CLOSING REPORT WIRE ERROR:', JSON.stringify(error));
        }
    }

    handleAddRow() {
        this.showPicker = true;
    }

    handlePickerSelect(event) {
        const id = event.detail.recordId;
        /*if (this.rows.some(row => row.consultantId === id) || this.deletedRows.some(row => row.consultantId === id)) {
            this.showToast('Error', 'This consultant has already been added or marked for deletion.', 'error');
            return;
        }*/
        this.selectedConsultantId = id;
    }

    handlePercentageChange(event) {
        const id = event.target.dataset.id;
        const percentage = Number(event.target.value);
        this.rows = this.rows.map(row => row.Id === id ? { ...row, percentage } : row);
        this.showWarning = this.totalPercentage !== 100;
        this.hasChanges = true;
    }

    handleTypeChange(event) {
        const id = event.target.dataset.id;
        const type = event.detail.value;
        this.rows = this.rows.map(row => row.Id === id ? { ...row, type } : row);
        this.showWarning = this.totalPercentage !== 100;
        this.hasChanges = true;
    }

    handleDelete(event) {
        const id = event.currentTarget.dataset.id;
        const row = this.rows.find(row => row.Id === id);
        if (!row) return;

        this.rows = this.rows.filter(row => row.Id !== id);
        this.deletedRows = [...this.deletedRows, row];
        this.showWarning = true;
        this.hasChanges = true;
    }

    handleAddConsultant() {
        const percentage = Number(this.newPercentage);

        if (!this.selectedConsultantId) {
            this.showToast('Error', 'Please select a consultant.', 'error');
            return;
        }

        if (!percentage || percentage <= 0) {
            this.showToast('Error', 'Please enter a valid percentage.', 'error');
            return;
        }

        if (percentage > this.remainingPercentage) {
            this.showToast('Error', `Only ${this.remainingPercentage}% is available. Enter a smaller percentage.`, 'error');
            return;
        }

        /*if (this.rows.some(row => row.consultantId === this.selectedConsultantId) || this.deletedRows.some(row => row.consultantId === this.selectedConsultantId)) {
            this.showToast('Error', 'This consultant has already been added.', 'error');
            return;
        }*/

        this.rows = [...this.rows, {
            Id: `new-${Date.now()}`,
            consultantId: this.selectedConsultantId,
            consultantName: this.selectedConsultantName,
            teamId: this.jobTeamId,
            teamName: this.jobTeamName,
            percentage,
            type: this.selectedConsultantType,
            isNew: true
        }];

        this.showPicker = false;
        this.showWarning = this.totalPercentage !== 100;
        this.hasChanges = true;
        this.selectedConsultantId = null;
        this.selectedConsultantName = '';
        this.selectedConsultantType = '';
        this.newPercentage = null;
    }

    handleNewPercentageChange(event) {
        this.newPercentage = event.target.value;
    }

    handleCancelPicker() {
        this.showPicker = false;
        this.selectedConsultantId = null;
        this.selectedConsultantName = '';
        this.selectedConsultantType = '';
        this.newPercentage = null;
    }

    async handleSave() {
        if (this.totalPercentage !== 100) {
            this.showToast('Error', `The overall percentage is ${this.totalPercentage}%. It must be 100%.`, 'error');
            return;
        }

        try {
            const updates = this.rows.filter(row => !row.isNew).map(row =>
                updateRecord({ fields: { Id: row.Id, Split_Percentage__c: Number(row.percentage), Commission_Type__c: row.type } })
            );
            const creates = this.rows.filter(row => row.isNew).map(row =>
                createRecord({
                    apiName: COMMISSION_SPLIT,
                    fields: { 
                        // Commission Split can belong to either a Placement or a Closing Report
                        ...(this.isClosingReport
                            ? { Closing_Report__c: this.recordId }:
                            {Placement__c: this.recordId}),
                            Consultant__c: row.consultantId,
                            Team__c: row.teamId,
                            Split_Percentage__c: Number(row.percentage),
                            Commission_Type__c: row.type
                        }
                    }
                )
            );
            const deletes = this.deletedRows.filter(row => !row.isNew).map(row => deleteRecord(row.Id));

            await Promise.all([...updates, ...creates, ...deletes]);
            await refreshApex(this.wiredSplitsResult);

            this.deletedRows = [];
            this.showWarning = false;
            this.hasChanges = false;
            this.showToast('Success', 'Commission splits saved.', 'success');
        } catch (error) {
            console.error('FULL SAVE ERROR:', JSON.stringify(error));
            console.error('FIELD ERRORS:', JSON.stringify(error?.body?.output?.fieldErrors));
            console.error('ERRORS:', JSON.stringify(error?.body?.output?.errors));
            this.showToast('Error', error?.body?.message || 'Unable to save commission splits.', 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get typeOptions() {
        const values = this.picklistInfo?.data?.picklistFieldValues?.Commission_Type__c?.values;
        return values ? values.map(v => ({ label: v.label, value: v.value })) : [];
    }

    get totalPercentage() {
        return this.rows.reduce((sum, row) => sum + Number(row.percentage || 0), 0);
    }

    get remainingPercentage() {
        return Math.max(0, 100 - this.totalPercentage);
    }
    // Shows the percentage still available for a split
    get remaining() {
        return this.newPercentage === undefined || this.newPercentage === null || this.newPercentage === ''
            ? `Remaining: ${this.remainingPercentage}%`
            : `Remaining after adding: ${Math.max(0, this.remainingPercentage - Number(this.newPercentage))}%`;
    }

    get saveDisabled() {
        return this.totalPercentage !== 100;
    }

    get disableAddConsultant() {
        return !this.selectedConsultantId || !this.selectedConsultantName || !this.newPercentage;
    }
    // Only active Users can be selected as consultants
    get userFilter() {
        return { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };
    }
}