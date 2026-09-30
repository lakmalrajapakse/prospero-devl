import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchJobRoles from '@salesforce/apex/JobRoleScaleController.searchJobRoles';
import getAssignmentsForDefinition from '@salesforce/apex/JobRoleScaleController.getAssignmentsForDefinition';
import assignJobRoles from '@salesforce/apex/JobRoleScaleController.assignJobRoles';
import removeAssignmentApex from '@salesforce/apex/JobRoleScaleController.removeAssignment';

export default class JobRoleScaleAssignment extends LightningElement {
    @api definitionId;
    @api rateAgreementId;

    isLoading = false;
    isSearching = false;
    hasSearched = false;
    assignments = [];

    showAssignPanel = false;
    nameSearchInput = '';
    jobTypeSearchId;
    accountSearchId;
    jobRoleOptions = [];
    showFilterPickers = true;

    jobRolePageNumber = 1;
    jobRoleHasNextPage = false;

    connectedCallback() {
        this.load();
    }

    // Loads Job Roles already assigned to this Scale Definition.
    async load() {
        this.isLoading = true;
        try {
            const data = await getAssignmentsForDefinition({ definitionId: this.definitionId });
            this.assignments = (data || []).map(a => ({
                ...a,
                pillLabel: this.buildPillLabel(a)
            }));
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // Builds a pill label combining Job Role, Contract and Account.
    buildPillLabel(assignment) {
        const jobRoleName = assignment.Job_Role__r?.Name || '';
        const contractName = assignment.Job_Role__r?.sirenum__Account__r?.Name;
        const accountName = assignment.Job_Role__r?.sirenum__Account__r?.sirenum__Client__r?.Name;
        if (contractName && accountName) {
            return `${jobRoleName} — ${contractName} — ${accountName}`;
        }
        return jobRoleName;
    }

    get hasAssignments() {
        return !this.isLoading && this.assignments.length > 0;
    }

    get showNoResults() {
        return this.hasSearched && !this.isSearching && this.jobRoleOptions.length === 0;
    }

    get disableJobRolePrevious() {
        return this.jobRolePageNumber === 1;
    }

    get disableJobRoleNext() {
        return !this.jobRoleHasNextPage;
    }

    openAssignPanel() {
        this.showAssignPanel = true;
        this.nameSearchInput = '';
        this.jobTypeSearchId = undefined;
        this.accountSearchId = undefined;
        this.jobRoleOptions = [];
        this.hasSearched = false;
        this.jobRolePageNumber = 1;
        this.jobRoleHasNextPage = false;
        this.resetFilterPickers();
    }

    closeAssignPanel() {
        this.showAssignPanel = false;
    }

    handleSearchClear() {
        this.nameSearchInput = '';
        this.jobTypeSearchId = undefined;
        this.accountSearchId = undefined;
        this.jobRoleOptions = [];
        this.hasSearched = false;
        this.jobRolePageNumber = 1;
        this.jobRoleHasNextPage = false;
        this.resetFilterPickers();
    }

    // Briefly removes and re-adds the pickers so their internal state clears.
    resetFilterPickers() {
        this.showFilterPickers = false;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            this.showFilterPickers = true;
        });
    }

    handleNameSearchChange(event) {
        this.nameSearchInput = event.detail.value;
    }

    handleJobTypeSearchChange(event) {
        this.jobTypeSearchId = event.detail.recordId;
    }

    handleAccountSearchChange(event) {
        this.accountSearchId = event.detail.recordId;
    }

    handleSearchKeyUp(event) {
        if (event.key === 'Enter') {
            this.handleSearchClick();
        }
    }

    // Runs a fresh search starting from page one.
    handleSearchClick() {
        this.jobRolePageNumber = 1;
        this.runSearch();
    }

    handleJobRolePreviousPage() {
        if (this.jobRolePageNumber > 1) {
            this.jobRolePageNumber -= 1;
            this.runSearch();
        }
    }

    handleJobRoleNextPage() {
        if (this.jobRoleHasNextPage) {
            this.jobRolePageNumber += 1;
            this.runSearch();
        }
    }

    async runSearch() {
        if (!this.nameSearchInput && !this.jobTypeSearchId && !this.accountSearchId) {
            this.showToast('Error', 'Enter a name or select a Job Type / Account to search.', 'error');
            return;
        }

        this.isSearching = true;
        this.hasSearched = true;
        try {
            const page = await searchJobRoles({
                rateAgreementId: this.rateAgreementId,
                searchText: this.nameSearchInput,
                jobTypeId: this.jobTypeSearchId,
                accountId: this.accountSearchId,
                pageNumber: this.jobRolePageNumber
            });
            const assignedIds = new Set(this.assignments.map(a => a.Job_Role__c));
            this.jobRoleOptions = (page.records || [])
                .filter(jr => !assignedIds.has(jr.jobRoleId))
                .map(jr => ({ ...jr, selected: false }));
            this.jobRoleHasNextPage = page.hasNextPage;
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSearching = false;
        }
    }

    handleJobRoleCheckbox(event) {
        const id = event.currentTarget.dataset.id;
        const checked = event.detail.checked;
        this.jobRoleOptions = this.jobRoleOptions.map(jr => jr.jobRoleId === id ? { ...jr, selected: checked } : jr);
    }

    get selectedJobRoleIds() {
        return this.jobRoleOptions.filter(jr => jr.selected).map(jr => jr.jobRoleId);
    }

    get disableAssignSave() {
        return this.selectedJobRoleIds.length === 0;
    }

    async handleAssignSave() {
        try {
            await assignJobRoles({
                definitionId: this.definitionId,
                jobRoleIds: this.selectedJobRoleIds
            });
            this.showAssignPanel = false;
            this.showToast('Success', 'Job Roles assigned.', 'success');
            await this.load();
        } catch (error) {
            this.showError(error);
        }
    }

    async removeAssignment(event) {
        const junctionId = event.target.dataset.junctionId;
        try {
            await removeAssignmentApex({ junctionId });
            this.showToast('Success', 'Assignment removed.', 'success');
            await this.load();
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