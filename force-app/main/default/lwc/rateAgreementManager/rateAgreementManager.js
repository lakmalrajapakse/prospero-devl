import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
// import { wire } from 'lwc';
// import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
// import RATE_AGREEMENT_OBJECT from '@salesforce/schema/Rate_Agreements__c';
import getRateAgreementsPage from '@salesforce/apex/RateAgreementManagerController.getRateAgreementsPage';
import getRateAgreementWorkspace from '@salesforce/apex/RateAgreementManagerController.getRateAgreementWorkspace';
import getScaleDefinitionsWithLock from '@salesforce/apex/RateAgreementManagerController.getScaleDefinitionsWithLock';
import reorderScaleDefinitions from '@salesforce/apex/RateAgreementManagerController.reorderScaleDefinitions';
import deleteScaleDefinition from '@salesforce/apex/RateAgreementManagerController.deleteScaleDefinition';

const COLUMNS = [
    { label: 'Rate Agreement Name', fieldName: 'Name', sortable: true },
    { label: 'Client', fieldName: 'accountName', sortable: true }
    // { label: 'Type', fieldName: 'Type__c', sortable: true }
];

export default class RateAgreementManager extends LightningElement {
    columns = COLUMNS;

    // rateAgreementFields = ['Name', 'Account__c', 'Type__c'];

    agreements = [];
    versions = [];
    scaleDefinitions = [];

    agreementName;
    clientId;
    // agreementType;
    // typeOptions = [];

    pageNumber = 1;
    hasNextPage = false;
    isLoading = false;
    isWorkspaceLoading = false;
    isDefinitionsLoading = false;
    isReordering = false;
    isSavingDetails = false;
    isDetailsDirty = false;

    sortedBy = 'Name';
    sortDirection = 'asc';

    selectedRateAgreementId;

    showCreateModal = false;
    showScaleDefinitionModal = false;
    showAddVersionModal = false;
    isCreatingAgreement = false;

    showManageVersionModal = false;
    manageVersionMode;
    manageVersionId;

    showJobRoleModal = false;
    jobRoleModalDefinitionId;
    jobRoleModalDefinitionName;

    draggedDefId;

    showDetailsForm = true;

    connectedCallback() {
        this.loadPage();
    }

    // @wire(getObjectInfo, { objectApiName: RATE_AGREEMENT_OBJECT })
    // agreementInfo;

    // @wire(getPicklistValuesByRecordType, {
    //     objectApiName: RATE_AGREEMENT_OBJECT,
    //     recordTypeId: '$agreementInfo.data.defaultRecordTypeId'
    // })
    // loadPicklists({ data }) {
    //     if (data) {
    //         this.typeOptions = data.picklistFieldValues.Type__c.values;
    //     }
    // }

    // Loads the current page of Rate Agreements using the active filters.
    async loadPage() {
        this.isLoading = true;

        try {
            const result = await getRateAgreementsPage({
                agreementName: this.agreementName || null,
                accountId: this.clientId || null,
                // agreementType: this.agreementType || null,
                pageNumber: this.pageNumber
            });

            this.agreements = (result.records || []).map(row => ({
                ...row,
                accountName: row.Account__r?.Name
            }));

            this.hasNextPage = result.hasNextPage;
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // Loads the selected Rate Agreement's versions, then its definitions.
    async loadWorkspace() {
        if (!this.selectedRateAgreementId) {
            return;
        }

        this.isWorkspaceLoading = true;

        try {
            const workspace = await getRateAgreementWorkspace({
                rateAgreementId: this.selectedRateAgreementId
            });

            this.versions = this.buildVersionLabels(workspace.versions || []);
        } catch (error) {
            this.showError(error);
        } finally {
            this.isWorkspaceLoading = false;
        }

        this.loadDefinitions();
    }

    // Loads Scale Definitions with their drag/delete flags.
    async loadDefinitions() {
        if (!this.selectedRateAgreementId) return;

        this.isDefinitionsLoading = true;
        try {
            const data = await getScaleDefinitionsWithLock({
                rateAgreementId: this.selectedRateAgreementId
            });

            this.scaleDefinitions = (data || []).map(item => ({
                definition: item.definition,
                isLocked: item.isLocked,
                draggable: !item.isLocked,
                canDelete: !item.isLocked,
                rowClass: item.isLocked ? 'slds-hint-parent' : 'slds-hint-parent draggable-row'
            }));
        } catch (error) {
            this.showError(error);
        } finally {
            this.isDefinitionsLoading = false;
        }
    }

    // Labels each version with its date range; the newest is current.
    buildVersionLabels(versions) {
        return versions.map((version, index) => {
            const start = version.Effective_Date__c;
            const isCurrent = index === 0;
            const end = isCurrent
                ? 'Present'
                : this.dayBefore(versions[index - 1].Effective_Date__c);

            return {
                ...version,
                label: start ? `${start} – ${end}` : version.Name,
                isCurrent,
                accordionClass: isCurrent
                    ? 'version-accordion version-current'
                    : 'version-accordion version-past'
            };
        });
    }

    // Returns the day before an ISO date string.
    dayBefore(dateString) {
        if (!dateString) return dateString;
        const date = new Date(`${dateString}T00:00:00Z`);
        date.setUTCDate(date.getUTCDate() - 1);
        return date.toISOString().slice(0, 10);
    }

    // Stores a filter input's value by its name.
    filterChangeHandler(event) {
        this[event.target.name] = event.target.value;
    }

    // Stores the selected client filter.
    lookupChangeHandler(event) {
        this.clientId = event.detail.recordId;
    }

    // Reloads the list from page one.
    handleSearchClick() {
        this.pageNumber = 1;
        this.loadPage();
    }

    // Goes to the previous page.
    handlePreviousPage() {
        if (this.pageNumber > 1) {
            this.pageNumber -= 1;
            this.loadPage();
        }
    }

    // Goes to the next page.
    handleNextPage() {
        if (this.hasNextPage) {
            this.pageNumber += 1;
            this.loadPage();
        }
    }

    // Sorts the loaded Rate Agreements by the clicked column.
    handleSort(event) {
        this.sortedBy = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;

        this.agreements = [...this.agreements].sort((first, second) => {
            const firstValue = `${first[this.sortedBy] || ''}`;
            const secondValue = `${second[this.sortedBy] || ''}`;

            const comparison = firstValue.localeCompare(secondValue);

            return this.sortDirection === 'asc' ? comparison : comparison * -1;
        });
    }

    // Selects a Rate Agreement and loads its workspace.
    handleRowSelection(event) {
        const selected = event.detail.selectedRows[0];

        this.selectedRateAgreementId = selected?.Id;
        this.versions = [];
        this.scaleDefinitions = [];
        this.isDetailsDirty = false;

        this.showDetailsForm = false;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            this.showDetailsForm = true;
        });

        this.loadWorkspace();
    }

    handleDetailsCancel() {
        this.isDetailsDirty = false;
        this.showDetailsForm = false;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            this.showDetailsForm = true;
        });
    }

    openCreateModal() {
        this.showCreateModal = true;
    }

    closeCreateModal() {
        this.showCreateModal = false;
    }

    handleCreateSubmit() {
        this.isCreatingAgreement = true;
    }

    // Closes the create modal and refreshes the list.
    handleCreateSuccess() {
        this.isCreatingAgreement = false;
        this.closeCreateModal();
        this.showToast('Success', 'Rate Agreement created.', 'success');
        this.loadPage();
    }

    // Shows the Save button once a Details field is edited.
    handleDetailsFieldChange() {
        this.isDetailsDirty = true;
    }

    handleDetailsSubmit() {
        this.isSavingDetails = true;
    }

    // Hides Save and refreshes the list after Details are saved.
    handleDetailsSuccess() {
        this.isSavingDetails = false;
        this.isDetailsDirty = false;
        this.showToast('Success', 'Rate Agreement updated.', 'success');
        this.loadPage();
    }

    handleDetailsError(event) {
        this.isSavingDetails = false;
        this.showToast('Error', event.detail.detail || 'Please correct the highlighted errors.', 'error');
    }

    openAddVersionModal() {
        this.showAddVersionModal = true;
    }

    closeAddVersionModal() {
        this.showAddVersionModal = false;
    }

    // Closes the version modal and reloads versions.
    handleVersionSuccess() {
        this.closeAddVersionModal();
        this.showToast('Success', 'Rate Agreement Version created.', 'success');
        this.loadWorkspace();
    }

    openScaleDefinitionModal() {
        this.showScaleDefinitionModal = true;
    }

    closeScaleDefinitionModal() {
        this.showScaleDefinitionModal = false;
    }

    // Closes the definition modal and reloads definitions.
    handleScaleDefinitionSuccess() {
        this.closeScaleDefinitionModal();
        this.showToast('Success', 'Scale Definition created.', 'success');
        this.loadDefinitions();
    }

    handleDragStart(event) {
        if (this.isReordering) return;
        this.draggedDefId = event.currentTarget.dataset.id;
        event.dataTransfer.effectAllowed = 'move';
    }

    handleDragOver(event) {
        event.preventDefault();
    }

    // Moves the dragged definition to the drop position and saves the order.
    handleDrop(event) {
        event.preventDefault();
        if (this.isReordering) return;

        const targetId = event.currentTarget.dataset.id;
        if (!this.draggedDefId || targetId === this.draggedDefId) return;

        const currentOrder = [...this.scaleDefinitions];
        const fromIndex = currentOrder.findIndex(d => d.definition.Id === this.draggedDefId);
        const toIndex = currentOrder.findIndex(d => d.definition.Id === targetId);
        if (fromIndex === -1 || toIndex === -1) return;

        if (currentOrder[fromIndex].isLocked || currentOrder[toIndex].isLocked) {
            this.showToast('Error', 'Locked Scale Definitions cannot be reordered.', 'error');
            return;
        }

        const [moved] = currentOrder.splice(fromIndex, 1);
        currentOrder.splice(toIndex, 0, moved);

        this.scaleDefinitions = currentOrder;
        this.saveNewOrder(currentOrder);
    }

    handleDragEnd() {
        this.draggedDefId = undefined;
    }

    // Saves the new ranking sequence, then reloads definitions.
    async saveNewOrder(orderedList) {
        this.isReordering = true;

        const payload = orderedList.map((item, index) => ({
            definitionId: item.definition.Id,
            ranking: index + 1
        }));

        try {
            await reorderScaleDefinitions({ orderedDefinitions: payload });
            this.showToast('Success', 'Ranking updated.', 'success');
        } catch (error) {
            this.showError(error);
        } finally {
            this.isReordering = false;
            this.loadDefinitions();
        }
    }

    // Deletes a definition and renumbers the remaining unlocked ones.
    async handleDeleteDefinition(event) {
        const defId = event.currentTarget.dataset.id;
        // eslint-disable-next-line no-alert
        if (!confirm('Delete this Scale Definition?')) return;

        this.isDefinitionsLoading = true;
        try {
            await deleteScaleDefinition({ definitionId: defId });

            const remainingUnlocked = this.scaleDefinitions
                .filter(d => d.definition.Id !== defId && !d.isLocked)
                .map((d, idx) => ({ definitionId: d.definition.Id, ranking: idx + 1 }));

            if (remainingUnlocked.length > 0) {
                await reorderScaleDefinitions({ orderedDefinitions: remainingUnlocked });
            }

            this.showToast('Success', 'Scale Definition deleted.', 'success');
        } catch (error) {
            this.showError(error);
        } finally {
            this.loadDefinitions();
        }
    }

    // Opens the Job Role assignment modal for a definition.
    handleManageJobRolesClick(event) {
        const defId = event.currentTarget.dataset.id;
        const def = this.scaleDefinitions.find(d => d.definition.Id === defId);
        this.jobRoleModalDefinitionId = defId;
        this.jobRoleModalDefinitionName = def ? def.definition.Name : '';
        this.showJobRoleModal = true;
    }

    closeJobRoleModal() {
        this.showJobRoleModal = false;
        this.jobRoleModalDefinitionId = undefined;
    }

    handleEditIconClick(event) {
        this.manageVersionMode = 'edit';
        this.manageVersionId = event.currentTarget.dataset.id;
        this.showManageVersionModal = true;
    }

    handleCloneIconClick(event) {
        this.manageVersionMode = 'clone';
        this.manageVersionId = event.currentTarget.dataset.id;
        this.showManageVersionModal = true;
    }

    closeManageVersionModal() {
        this.showManageVersionModal = false;
        this.manageVersionMode = undefined;
        this.manageVersionId = undefined;
    }

    // Closes the edit/clone modal and reloads versions.
    handleManageVersionSuccess() {
        const message = this.manageVersionMode === 'clone'
            ? 'Rate Agreement Version cloned.'
            : 'Rate Agreement Version updated.';
        this.closeManageVersionModal();
        this.showToast('Success', message, 'success');
        this.loadWorkspace();
    }

    handleFormError(event) {
        this.isCreatingAgreement = false;
        this.showToast('Error', event.detail.detail || 'Please correct the highlighted errors.', 'error');
    }

    showError(error) {
        this.showToast('Error', error.body?.message || error.message, 'error');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get hasSelectedRateAgreement() {
        return Boolean(this.selectedRateAgreementId);
    }

    get hasNoVersions() {
        return !this.isWorkspaceLoading && this.versions.length === 0;
    }

    get hasScaleDefinitions() {
        return !this.isDefinitionsLoading && this.scaleDefinitions.length > 0;
    }

    get disablePreviousPage() {
        return this.pageNumber === 1;
    }

    get disableNextPage() {
        return !this.hasNextPage;
    }
}