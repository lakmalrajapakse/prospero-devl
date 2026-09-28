import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getMyCandidates from '@salesforce/apex/ClientPortalCandidateControllers.getMyCandidates';

const COLUMNS = [
    { label: 'First Name', fieldName: 'FirstName' },
    { label: 'Gender', fieldName: 'sirenum__Gender__c' },
    {
        type: 'button',
        typeAttributes: {
            label: 'View',
            name: 'view',
            variant: 'brand',
            iconName: 'utility:preview'
        }
    }
];

export default class MyCandidatesList extends NavigationMixin(LightningElement) {
    columns = COLUMNS;
    candidates = [];
    searchTerm = '';
    isLoading = false;
    wiredResult;

    @wire(getMyCandidates, { searchTerm: '$searchTerm' })
    wiredCandidates(result) {
        this.wiredResult = result;
        this.isLoading = false;
        if (result.data) {
            this.candidates = result.data;
        } else if (result.error) {
            this.candidates = [];
            // eslint-disable-next-line no-console
            console.error('Error loading candidates', result.error);
        }
    }

    handleSearchChange(event) {
        this.isLoading = true;
        this.searchTerm = event.target.value;
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this.wiredResult).finally(() => {
            this.isLoading = false;
        });
    }

    handleRowAction(event) {
        const row = event.detail.row;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: row.Id,
                objectApiName: 'Contact',
                actionName: 'view'
            }
        });
    }

    get hasNoResults() {
        return !this.isLoading && this.candidates.length === 0;
    }
}