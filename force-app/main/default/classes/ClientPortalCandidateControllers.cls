/**
 * Controller for the "My Candidates" LWC list view on the Client Portal.
 * Returns Candidates (Contacts) who had at least one Shift, in the last 1 year,
 * at a Site belonging to the same Account as the current portal user's Contact.
 *
 * NOTE: Declared WITHOUT SHARING deliberately. Candidate Contacts generally will
 * NOT be shared to the portal Account via standard Contact-to-Account sharing
 * (they belong to a staffing pool, not the client's Account), so we enforce
 * visibility explicitly via the WHERE clause below instead of relying on org
 * sharing rules. Field level security is still enforced via stripInaccessible.
 * If your org DOES share Candidate contacts to the portal account, change this
 * to "with sharing".
 */
public without sharing class ClientPortalCandidateControllers {

    // ---- Adjust these constants if your field/object API names differ ----
    private static final String CANDIDATE_RECORD_TYPE = 'Candidate';

    @AuraEnabled(cacheable=true)
    public static List<Contact> getMyCandidates(String searchTerm) {
        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) {
            return new List<Contact>();
        }

        Date oneYearAgo = Date.today().addYears(-1);
        String likeTerm = '%' + String.escapeSingleQuotes(
            String.isBlank(searchTerm) ? '' : searchTerm
        ) + '%';

        List<Contact> results = [
            SELECT Id, FirstName, sirenum__Gender__c
            FROM Contact
            WHERE RecordType.DeveloperName = :CANDIDATE_RECORD_TYPE
              AND FirstName LIKE :likeTerm
              AND Id IN (
                    SELECT sirenum__Contact__c
                    FROM sirenum__Shift__c
                    WHERE sirenum__Site__r.sirenum__Operating_Company__c = :currentAccountId
                      AND sirenum__Scheduled_Start_Time__c >= :oneYearAgo
                      AND sirenum__Contact__c != null
              )
            ORDER BY FirstName ASC
            LIMIT 200
        ];

        // Strip fields the running user isn't allowed to see (FLS safety net).
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.READABLE, results
        );
        return (List<Contact>) decision.getRecords();
    }

    /**
     * Returns the AccountId on the current user's related Contact
     * (i.e. the Account the logged-in portal user belongs to).
     * Shared by the other controllers below.
     */
    public static Id getCurrentUserAccountId() {
        List<User> users = [
            SELECT ContactId, Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (users.isEmpty() || users[0].ContactId == null) {
            return null;
        }
        return users[0].Contact.AccountId;
    }
}