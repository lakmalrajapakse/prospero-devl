/**
 * Controller for the read-only "Shifts" related list on the Candidate detail page.
 * Only returns Shifts at a Site belonging to the current portal user's Account.
 */
public without sharing class ClientPortalShiftController {

    @AuraEnabled(cacheable=true)
    public static List<sirenum__Shift__c> getShiftsForCandidate(Id contactId) {
        Id currentAccountId = ClientPortalCandidateControllers.getCurrentUserAccountId();
        if (contactId == null || currentAccountId == null) {
            return new List<sirenum__Shift__c>();
        }

        List<sirenum__Shift__c> results = [
            SELECT Id, sirenum__Scheduled_Start_Time__c, sirenum__Scheduled_End_Time__c,
                   sirenum__Site__r.Name
            FROM sirenum__Shift__c
            WHERE sirenum__Contact__c = :contactId
              AND sirenum__Site__r.sirenum__Operating_Company__c = :currentAccountId
            ORDER BY sirenum__Scheduled_Start_Time__c DESC
            LIMIT 200
        ];

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.READABLE, results
        );
        return (List<sirenum__Shift__c>) decision.getRecords();
    }
}