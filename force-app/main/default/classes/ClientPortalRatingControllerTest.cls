@isTest
private class ClientPortalRatingControllerTest {

    private static User createPortalUser(Contact portalContact) {
        Profile p = [
            SELECT Id FROM Profile
            WHERE UserLicense.Name LIKE 'Customer Community%'
            LIMIT 1
        ];

        String uniqueName = 'ratingportal' + DateTime.now().getTime() + '@testorg.com';
        User u = new User(
            FirstName = 'Portal',
            LastName = 'User',
            Email = uniqueName,
            Username = uniqueName,
            Alias = 'ratpu',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id,
            ContactId = portalContact.Id
        );
        insert u;
        return u;
    }

    @TestSetup
    static void setupData() {
        Account clientAccount = new Account(Name = 'Client Account');
        Account otherAccount = new Account(Name = 'Other Account');
        insert new List<Account>{ clientAccount, otherAccount };

        Contact portalContact = new Contact(
            FirstName = 'Portal',
            LastName = 'User',
            AccountId = clientAccount.Id
        );
        insert portalContact;

        Id candidateRtId = Schema.SObjectType.Contact
            .getRecordTypeInfosByDeveloperName()
            .get('Candidate')
            .getRecordTypeId();
        Contact candidate = new Contact(
            FirstName = 'Alice',
            LastName = 'Candidate',
            RecordTypeId = candidateRtId
        );
        insert candidate;

        // Ranking tied to the client account - SHOULD be returned
        sirenum__Ranking__c matchingRanking = new sirenum__Ranking__c(
            sirenum__Contact__c = candidate.Id,
            sirenum__Account__c = clientAccount.Id,
            sirenum__Ranked_By__c = portalContact.Id
        );

        // Ranking tied to a different account - should NOT be returned
        sirenum__Ranking__c otherAccountRanking = new sirenum__Ranking__c(
            sirenum__Contact__c = candidate.Id,
            sirenum__Account__c = otherAccount.Id,
            sirenum__Ranked_By__c = portalContact.Id
        );

        insert new List<sirenum__Ranking__c>{ matchingRanking, otherAccountRanking };
    }

    @isTest
    static void testGetRatings_returnsOnlyMatchingAccountRatings() {
        Account clientAccount = [SELECT Id FROM Account WHERE Name = 'Client Account' LIMIT 1];
        Contact portalContact = [SELECT Id FROM Contact WHERE FirstName = 'Portal' LIMIT 1];
        Contact candidate = [SELECT Id FROM Contact WHERE FirstName = 'Alice' LIMIT 1];
        User portalUser = createPortalUser(portalContact);

        List<sirenum__Ranking__c> results;
        System.runAs(portalUser) {
            Test.startTest();
            results = ClientPortalRatingController.getRatings(candidate.Id);
            Test.stopTest();
        }

        System.assertEquals(1, results.size(),
            'Only the ranking that belongs to the portal user\'s account should return');
        System.assertEquals(clientAccount.Id, results[0].sirenum__Account__c);
    }

    @isTest
    static void testGetRatings_nullContactId_returnsEmpty() {
        Contact portalContact = [SELECT Id FROM Contact WHERE FirstName = 'Portal' LIMIT 1];
        User portalUser = createPortalUser(portalContact);

        List<sirenum__Ranking__c> results;
        System.runAs(portalUser) {
            Test.startTest();
            results = ClientPortalRatingController.getRatings(null);
            Test.stopTest();
        }

        System.assertEquals(0, results.size());
    }

    @isTest
    static void testGetRatings_userWithNoAccount_returnsEmpty() {
        Contact candidate = [SELECT Id FROM Contact WHERE FirstName = 'Alice' LIMIT 1];

        // Default test running user has no Account, exercising the null-account branch.
        Test.startTest();
        List<sirenum__Ranking__c> results = ClientPortalRatingController.getRatings(candidate.Id);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }
}