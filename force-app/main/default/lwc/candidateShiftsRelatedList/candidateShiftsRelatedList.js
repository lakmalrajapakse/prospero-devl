import { LightningElement, api, wire } from 'lwc';
import getShiftsForCandidate from '@salesforce/apex/ClientPortalShiftController.getShiftsForCandidate';

const COLUMNS = [
    { label: 'Scheduled Start', fieldName: 'scheduledStart', type: 'date',
      typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
    { label: 'Scheduled End', fieldName: 'scheduledEnd', type: 'date',
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
            // Apex now returns a flat ShiftDTO (Id, scheduledStart, scheduledEnd, siteName)
            this.shifts = data;
        }
    }
}