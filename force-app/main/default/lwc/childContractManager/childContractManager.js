/**
 * @description LWC for managing WFM Contracts on child accounts.
 *              Launched as a Quick Action (ScreenAction) from sirenum__ProActiveContract__c.
 *              Shows all child accounts of the contract's account, indicates which already
 *              have a linked contract, and allows creating or updating them in bulk.
 * @author      Lakmal Rajapakse
 * @group       WFM Contracts
 * @last modified on  : 2026-06-30
**/
import { LightningElement, api, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getChildAccountData from '@salesforce/apex/SIM_ChildContractManagerCtrl.getChildAccountData';
import saveChildContracts from '@salesforce/apex/SIM_ChildContractManagerCtrl.saveChildContracts';

export default class ChildContractManager extends LightningElement {
    @api recordId;

    @track isLoading = false;
    @track contractName = '';
    @track parentAccountName = '';
    @track childRows = [];
    @track errorMessages = [];

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.recordId = currentPageReference.state.recordId;
            this.loadData();
        }
    }

    loadData() {
        this.isLoading = true;
        this.errorMessages = [];

        getChildAccountData({ contractId: this.recordId })
            .then(result => {
                const data = JSON.parse(result);
                this.contractName      = data.contractName;
                this.parentAccountName = data.parentAccountName;
                this.childRows = (data.childAccountRows || []).map(row => ({
                    ...row,
                    isSelected: false,
                    rowKey: row.accountId,
                    linkedContractUrl: row.linkedContractId
                        ? `/lightning/r/sirenum__ProActiveContract__c/${row.linkedContractId}/view`
                        : null
                }));
            })
            .catch(err => {
                this.errorMessages = [this.extractError(err)];
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRowSelect(event) {
        const accountId = event.target.dataset.id;
        const checked   = event.target.checked;
        this.childRows  = this.childRows.map(row =>
            row.accountId === accountId ? { ...row, isSelected: checked } : row
        );
    }

    handleSelectAll(event) {
        const checked  = event.target.checked;
        this.childRows = this.childRows.map(row => ({ ...row, isSelected: checked }));
    }

    handleSubmit() {
        this.errorMessages = [];

        const selectedRows = this.childRows.filter(r => r.isSelected);
        if (selectedRows.length === 0) {
            this.errorMessages = ['Please select at least one row before submitting.'];
            return;
        }

        this.isLoading = true;
        saveChildContracts({
            contractId:       this.recordId,
            selectedRowsJSON: JSON.stringify(selectedRows)
        })
        .then(result => {
            const data = JSON.parse(result);
            const msg  = `Done — ${data.insertedCount} contract(s) created.`;
            this.dispatchEvent(new ShowToastEvent({ title: 'Success', message: msg, variant: 'success' }));
            this.dispatchEvent(new CloseActionScreenEvent());
        })
        .catch(err => {
            this.errorMessages = [this.extractError(err)];
            this.isLoading = false;
        });
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // ── Getters ────────────────────────────────────────────────────────────────

    get hasErrors() {
        return this.errorMessages && this.errorMessages.length > 0;
    }

    get hasChildAccounts() {
        return this.childRows && this.childRows.length > 0;
    }

    get hasNoChildAccounts() {
        return !this.isLoading && (!this.childRows || this.childRows.length === 0);
    }

    get selectedCount() {
        return this.childRows.filter(r => r.isSelected).length;
    }

    get totalCount() {
        return this.childRows.length;
    }

    get noRowsSelected() {
        return this.selectedCount === 0;
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    extractError(err) {
        if (err && err.body && err.body.message) return err.body.message;
        if (err && err.message) return err.message;
        return 'An unexpected error occurred.';
    }
}