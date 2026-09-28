/**
 * Controller for the read-only "Tickets" related list on the Candidate detail page.
 * Only returns the Candidate's Tickets whose related Ticket status is 'Confirmed'.
 * Adjust sirenum__Contact_Ticket__c / sirenum__Ticket__r to your actual junction object.
 */
public without sharing class ClientPortalTicketController {

    @AuraEnabled(cacheable=true)
    public static List<sirenum__Ticket__c> getConfirmedTickets(Id contactId) {
        if (contactId == null) {
            return new List<sirenum__Ticket__c>();
        }

        List<sirenum__Ticket__c> results = [
            SELECT Id,sirenum__Valid_From__c, sirenum__Valid_Until__c
                   
            FROM sirenum__Ticket__c
            WHERE sirenum__Owner__c = :contactId
              AND sirenum__Status__c = 'Confirmed'
            ORDER BY sirenum__Valid_From__c DESC
            LIMIT 100
        ];

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.READABLE, results
        );
        return (List<sirenum__Ticket__c>) decision.getRecords();
    }
}