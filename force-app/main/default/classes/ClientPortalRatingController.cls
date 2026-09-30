public without sharing class ClientPortalRatingController {

    @AuraEnabled(cacheable=true)
    public static List<sirenum__Ranking__c> getRatings(Id contactId) {
        Id currentAccountId = ClientPortalCandidateControllers.getCurrentUserAccountId();
        if (contactId == null || currentAccountId == null) {
            return new List<sirenum__Ranking__c>();
        }

        List<sirenum__Ranking__c> results = [
            SELECT Id, Name,  sirenum__Ranked_By__c,
                   sirenum__Ranked_By__r.Name, CreatedDate
            FROM sirenum__Ranking__c
            WHERE sirenum__Contact__c = :contactId
              AND sirenum__Account__c = :currentAccountId
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.READABLE, results
        );
        return (List<sirenum__Ranking__c>) decision.getRecords();
    }
}