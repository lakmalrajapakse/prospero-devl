import { LightningElement, api, wire } from 'lwc';
import getConfirmedTickets from '@salesforce/apex/ClientPortalTicketController.getConfirmedTickets';

const COLUMNS = [
    { label: 'Ticket', fieldName: 'ticketName' },
    { label: 'Valid From', fieldName: 'sirenum__Valid_From__c', type: 'date' },
    { label: 'Valid Until', fieldName: 'sirenum__Valid_Until__c', type: 'date' }
];

export default class CandidateTicketsRelatedList extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    tickets = [];

    @wire(getConfirmedTickets, { contactId: '$recordId' })
    wiredTickets({ data }) {
        if (data) {
            this.tickets = data.map((t) => ({
                ...t,
                ticketName: t.sirenum__Ticket__r ? t.sirenum__Ticket__r.Name : ''
            }));
        }
    }
}