import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchContracts from '@salesforce/apex/RateAgreementManagerController.searchContracts';
import getContractsForRateAgreement from '@salesforce/apex/RateAgreementManagerController.getContractsForRateAgreement';
import addContractsToRateAgreement from '@salesforce/apex/RateAgreementManagerController.addContractsToRateAgreement';
import removeContractFromRateAgreement from '@salesforce/apex/RateAgreementManagerController.removeContractFromRateAgreement';

export default class RaContractAssignment extends LightningElement {
    _rateAgreementId;

    @api
    get rateAgreementId() {
        return this._rateAgreementId;
    }
    set rateAgreementId(value) {
        const changed = value !== this._rateAgreementId;
        this._rateAgreementId = value;
        if (changed && value) {
            this.load();
        }
    }

    isLoading = false;
    isSearching = false;
    hasSearched = false;
    contracts = [];

    showAssignPanel = false;
    contractNameInput = '';
    accountId;
    contractOptions = [];
    showAccountPicker = true;

    async load() {
        this.isLoading = true;
        try {
            const data = await getContractsForRateAgreement({ rateAgreementId: this.rateAgreementId });
            this.contracts = (data || []).map(c => ({
                ...c,
                accountName: c.sirenum__Client__r?.Name
            }));
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    get hasContracts() {
        return !this.isLoading && this.contracts.length > 0;
    }

    get showNoResults() {
        return this.hasSearched && !this.isSearching && this.contractOptions.length === 0;
    }

    openAssignPanel() {
        this.showAssignPanel = true;
        this.contractNameInput = '';
        this.accountId = undefined;
        this.contractOptions = [];
        this.hasSearched = false;
        this.resetAccountPicker();
    }

    handleSearchClear() {
        this.contractNameInput = '';
        this.accountId = undefined;
        this.contractOptions = [];
        this.hasSearched = false;
        this.resetAccountPicker();
    }

    resetAccountPicker() {
        this.showAccountPicker = false;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        Promise.resolve().then(() => {
            this.showAccountPicker = true;
        });
    }

    closeAssignPanel() {
        this.showAssignPanel = false;
    }

    handleContractNameChange(event) {
        this.contractNameInput = event.detail.value;
    }

    handleAccountChange(event) {
        this.accountId = event.detail.recordId;
    }

    handleSearchKeyUp(event) {
        if (event.key === 'Enter') {
            this.handleSearchClick();
        }
    }

    handleSearchClear() {
        this.contractNameInput = '';
        this.accountId = undefined;
        this.contractOptions = [];
        this.hasSearched = false;
        this.pickerResetKey += 1;
    }

    async handleSearchClick() {
        if (!this.contractNameInput && !this.accountId) {
            this.showToast('Error', 'Enter a Contract Name or select an Account to search.', 'error');
            return;
        }

        this.isSearching = true;
        this.hasSearched = true;
        try {
            const results = await searchContracts({
                contractName: this.contractNameInput,
                accountId: this.accountId || null
            });
            const assignedIds = new Set(this.contracts.map(c => c.Id));
            this.contractOptions = (results || [])
                .filter(c => !assignedIds.has(c.Id))
                .map(c => ({
                    ...c,
                    accountName: c.sirenum__Client__r?.Name,
                    selected: false
                }));
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSearching = false;
        }
    }

    handleContractCheckbox(event) {
        const id = event.currentTarget.dataset.id;
        const checked = event.detail.checked;
        this.contractOptions = this.contractOptions.map(c => c.Id === id ? { ...c, selected: checked } : c);
    }

    get selectedContractIds() {
        return this.contractOptions.filter(c => c.selected).map(c => c.Id);
    }

    get disableAdd() {
        return this.selectedContractIds.length === 0;
    }

    async handleAddSave() {
        try {
            await addContractsToRateAgreement({
                rateAgreementId: this.rateAgreementId,
                contractIds: this.selectedContractIds
            });
            this.showAssignPanel = false;
            this.showToast('Success', 'Contracts added.', 'success');
            await this.load();
        } catch (error) {
            this.showError(error);
        }
    }

    async handleRemove(event) {
        const contractId = event.currentTarget.dataset.id;
        try {
            await removeContractFromRateAgreement({ contractId });
            this.showToast('Success', 'Contract removed.', 'success');
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