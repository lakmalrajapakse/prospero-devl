public without sharing class ClientPortalCandidateControllers {

    private static final String CANDIDATE_RECORD_TYPE = 'Candidate';

    @AuraEnabled(cacheable=true)
    public static List<Contact> getMyCandidates(String searchTerm) {
        Id currentAccountId = getCurrentUserAccountId();
        if (currentAccountId == null) {
            return new List<Contact>();
        }

        Id candidateRtId = getCandidateRecordTypeId();
        if (candidateRtId == null) {
            return new List<Contact>();
        }

        Date oneYearAgo = Date.today().addYears(-1);
        String likeTerm = '%' + String.escapeSingleQuotes(
            String.isBlank(searchTerm) ? '' : searchTerm
        ) + '%';

        
        Set<Id> siteIds = new Map<Id, sirenum__Site__c>([
            SELECT Id
            FROM sirenum__Site__c
            WHERE sirenum__Operating_Company__c = :currentAccountId
        ]).keySet();

        if (siteIds.isEmpty()) {
            return new List<Contact>();
        }

        List<Contact> results = [SELECT Id, FirstName, Gender__c
                                 FROM Contact
                                 WHERE RecordTypeId = :candidateRtId
                                AND FirstName LIKE :likeTerm
                                AND Id IN (
                                SELECT sirenum__Contact__c
                                FROM sirenum__Shift__c
                                WHERE sirenum__Site__c IN :siteIds
                                AND sirenum__Date__c >= :oneYearAgo
                                AND sirenum__Contact__c != null
                                )
                               ORDER BY FirstName ASC
                               LIMIT 200
                               ];

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.READABLE, results
        );
        return (List<Contact>) decision.getRecords();
    }

    private static Id getCandidateRecordTypeId() {
        Schema.RecordTypeInfo info = Schema.SObjectType.Contact
            .getRecordTypeInfosByDeveloperName()
            .get(CANDIDATE_RECORD_TYPE);
        return info == null ? null : info.getRecordTypeId();
    }

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