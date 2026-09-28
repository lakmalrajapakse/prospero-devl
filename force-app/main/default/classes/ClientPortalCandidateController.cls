public with sharing class ClientPortalCandidateController {

    // Fetch Candidates who had a Shift at the logged-in user's Account in the last 1 year
    @AuraEnabled(cacheable=true)
    public static List<Contact> getMyCandidates(String searchKey) {
        Id userAccountId = getUserAccountId();
        if (userAccountId == null) {
            return new List<Contact>();
        }

        DateTime oneYearAgo = System.now().addYears(-1);
        
        String query = 'SELECT Id, FirstName, sirenum__Gender__c ' +
                       'FROM Contact ' +
                       'WHERE Id IN (SELECT sirenum__Contact__c FROM sirenum__Shift__c ' +
                                   'WHERE sirenum__Site__r.sirenum__Account__c = :userAccountId ' +
                                   'AND sirenum__Scheduled_Start_Time__c >= :oneYearAgo)';

        if (String.isNotBlank(searchKey)) {
            String key = '%' + String.escapeSingleQuotes(searchKey) + '%';
            query += ' AND FirstName LIKE :key';
        }

        query += ' ORDER BY FirstName ASC';
        return Database.query(query);
    }

    // Related List: Ratings filtered by current user's Account
    // Replace sirenum__Placement_Rating__c with sirenum__Rating__c if your package uses Rating directly
    @AuraEnabled(cacheable=true)
    public static List<sirenum__Ranking__c> getCandidateRatings(Id candidateId) {
        Id userAccountId = getUserAccountId();
        return [
            SELECT Id,	sirenum__Rank__c, CreatedDate 
            FROM sirenum__Ranking__c 
            WHERE sirenum__Contact__c = :candidateId 
            AND sirenum__Account__c = :userAccountId
            ORDER BY CreatedDate DESC
        ];
    }

    // Related List: Confirmed Tickets (Read-Only)
    // Adjust sirenum__Placement__c if your Ticket object uses sirenum__Owner__c or sirenum__Contact__c
    @AuraEnabled(cacheable=true)
    public static List<sirenum__Ticket__c> getConfirmedTickets(Id candidateId) {
        return [
            SELECT Id, sirenum__Valid_From__c, sirenum__Valid_Until__c 
            FROM sirenum__Ticket__c 
            WHERE 	sirenum__Owner__c = :candidateId 
            AND sirenum__Status__c = 'Confirmed'
            ORDER BY sirenum__Valid_Until__c DESC
        ];
    }

    // Related List: Shifts at the user's Account (Read-Only)
    @AuraEnabled(cacheable=true)
    public static List<sirenum__Shift__c> getCandidateShifts(Id candidateId) {
        Id userAccountId = getUserAccountId();
        return [
            SELECT Id, sirenum__Scheduled_Start_Time__c, sirenum__Scheduled_End_Time__c, sirenum__Site__r.Name 
            FROM sirenum__Shift__c 
            WHERE sirenum__Contact__c = :candidateId 
            AND sirenum__Site__r.sirenum__Operating_Company__c = :userAccountId
            ORDER BY sirenum__Scheduled_Start_Time__c DESC
        ];
    }

    private static Id getUserAccountId() {
        User u = [SELECT Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return u.Contact != null ? u.Contact.AccountId : null;
    }
}