import { LightningElement, api, wire } from 'lwc';
import getConfirmedTickets from '@salesforce/apex/ClientPortalTicketController.getConfirmedTickets';

const COLUMNS = [
    { label: 'Valid From', fieldName: 'sirenum__Valid_From__c', type: 'date-local' },
    { label: 'Valid Until', fieldName: 'sirenum__Valid_Until__c', type: 'date-local' }
];

export default class CandidateTicketsRelatedList extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    tickets = [];

    @wire(getConfirmedTickets, { contactId: '$recordId' })
    wiredTickets({ data, error }) {
        if (data) {
            this.tickets = data;
        } else if (error) {
            this.tickets = [];
            console.error('Error loading tickets', error);
        }
    }

    get hasTickets() {
        return this.tickets.length > 0;
    }
}