import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { refreshApex } from '@salesforce/apex';
import getRatings from '@salesforce/apex/ClientPortalRatingController.getRatings';

const COLUMNS = [
    { label: 'Rating', fieldName: 'sirenum__Rating__c' },
    { label: 'Ranked By', fieldName: 'rankedByName' },
    { label: 'Date', fieldName: 'CreatedDate', type: 'date' },
    {
        type: 'button',
        typeAttributes: { label: 'View', name: 'view', variant: 'base' }
    }
];

export default class CandidateRatingsRelatedList extends NavigationMixin(LightningElement) {
    @api recordId; // automatically populated when placed on the Contact record page
    columns = COLUMNS;
    ratings = [];
    wiredResult;

    @wire(getRatings, { contactId: '$recordId' })
    wiredRatings(result) {
        this.wiredResult = result;
        if (result.data) {
            this.ratings = result.data.map((r) => ({
                ...r,
                rankedByName: r.sirenum__Ranked_By__r
                    ? r.sirenum__Ranked_By__r.Name
                    : ''
            }));
        }
    }

    handleRefresh() {
        return refreshApex(this.wiredResult);
    }

    handleRowAction(event) {
        const row = event.detail.row;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: row.Id,
                objectApiName: 'sirenum__Ranking__c',
                actionName: 'view'
            }
        });
    }

    handleNew() {
        // Pre-fill the Contact lookup; Ranked By + Account are set by the
        // Record-Triggered Flow on sirenum__Rating__c (before-save).
        const defaultValues = encodeDefaultFieldValues({
            sirenum__Contact__c: this.recordId
        });
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'sirenum__Ranking__c',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: defaultValues,
                nooverride: '1'
            }
        });
    }
}