import { LightningElement, api, wire } from 'lwc';
import getShiftsForCandidate from '@salesforce/apex/ClientPortalShiftController.getShiftsForCandidate';

const COLUMNS = [
    { label: 'Scheduled Start', fieldName: 'sirenum__Scheduled_Start_Time__c', type: 'date',
      typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
    { label: 'Scheduled End', fieldName: 'sirenum__Scheduled_End_Time__c', type: 'date',
      typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
    { label: 'Site', fieldName: 'siteName' }
];

export default class CandidateShiftsRelatedList extends LightningElement {
    @api recordId;
    columns = COLUMNS;
    shifts = [];

    @wire(getShiftsForCandidate, { contactId: '$recordId' })
    wiredShifts({ data }) {
        if (data) {
            this.shifts = data.map((s) => ({
                ...s,
                siteName: s.sirenum__Site__r ? s.sirenum__Site__r.Name : ''
            }));
        }
    }
}