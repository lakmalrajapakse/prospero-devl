@isTest
private class ClientPortalCandidateControllersTest {

    // NOTE: adjust the Profile filter below if your org's portal license/profile
    // is named differently (e.g. 'Customer Community Plus Login', 'Partner Community Login').
    private static User createPortalUser(Contact portalContact) {
        Profile p = [
            SELECT Id FROM Profile
            WHERE UserLicense.Name LIKE 'Customer Community%'
            LIMIT 1
        ];

        String uniqueName = 'candportal' + DateTime.now().getTime() + '@testorg.com';
        User u = new User(
            FirstName = 'Portal',
            LastName = 'User',
            Email = uniqueName,
            Username = uniqueName,
            Alias = 'candpu',
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

        Contact matchingCandidate = new Contact(
            FirstName = 'Alice',
            LastName = 'Match',
            RecordTypeId = candidateRtId
        );
        Contact nonMatchingCandidate = new Contact(
            FirstName = 'Bob',
            LastName = 'NoMatch',
            RecordTypeId = candidateRtId
        );
        insert new List<Contact>{ matchingCandidate, nonMatchingCandidate };

        sirenum__Site__c clientSite = new sirenum__Site__c(
            Name = 'Client Site',
            sirenum__Operating_Company__c = clientAccount.Id
        );
        sirenum__Site__c otherSite = new sirenum__Site__c(
            Name = 'Other Site',
            sirenum__Operating_Company__c = otherAccount.Id
        );
        insert new List<sirenum__Site__c>{ clientSite, otherSite };

        // Recent shift for the candidate that SHOULD show up (client site, within last year)
        sirenum__Shift__c recentShiftAtClientSite = new sirenum__Shift__c(
            sirenum__Contact__c = matchingCandidate.Id,
            sirenum__Site__c = clientSite.Id,
            sirenum__Scheduled_Start_Time__c = DateTime.now().addMonths(-1),
            sirenum__Scheduled_End_Time__c = DateTime.now().addMonths(-1).addHours(8)
        );

        // Old shift (outside 1 year window) for the candidate that should NOT show up
        sirenum__Shift__c oldShiftAtClientSite = new sirenum__Shift__c(
            sirenum__Contact__c = nonMatchingCandidate.Id,
            sirenum__Site__c = clientSite.Id,
            sirenum__Scheduled_Start_Time__c = DateTime.now().addYears(-2),
            sirenum__Scheduled_End_Time__c = DateTime.now().addYears(-2).addHours(8)
        );

        insert new List<sirenum__Shift__c>{ recentShiftAtClientSite, oldShiftAtClientSite };
    }

    @isTest
    static void testGetMyCandidates_returnsMatchingCandidateOnly() {
        Contact portalContact = [SELECT Id FROM Contact WHERE FirstName = 'Portal' LIMIT 1];
        User portalUser = createPortalUser(portalContact);

        List<Contact> results;
        System.runAs(portalUser) {
            Test.startTest();
            results = ClientPortalCandidateControllers.getMyCandidates('');
            Test.stopTest();
        }

        System.assertEquals(1, results.size(),
            'Only the candidate with a recent shift at the client account site should return');
        System.assertEquals('Alice', results[0].FirstName);
    }

    @isTest
    static void testGetMyCandidates_searchTermFiltersResults() {
        Contact portalContact = [SELECT Id FROM Contact WHERE FirstName = 'Portal' LIMIT 1];
        User portalUser = createPortalUser(portalContact);

        List<Contact> results;
        System.runAs(portalUser) {
            Test.startTest();
            results = ClientPortalCandidateControllers.getMyCandidates('Zzz-no-match');
            Test.stopTest();
        }

        System.assertEquals(0, results.size(), 'A non-matching search term should return no rows');
    }

    @isTest
    static void testGetMyCandidates_userWithNoAccount_returnsEmpty() {
        // The default test running user has no related Contact/Account,
        // exercising the "currentAccountId == null" early return.
        Test.startTest();
        List<Contact> results = ClientPortalCandidateControllers.getMyCandidates('');
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @isTest
    static void testGetCurrentUserAccountId_returnsAccountForPortalUser() {
        Account clientAccount = [SELECT Id FROM Account WHERE Name = 'Client Account' LIMIT 1];
        Contact portalContact = [SELECT Id FROM Contact WHERE FirstName = 'Portal' LIMIT 1];
        User portalUser = createPortalUser(portalContact);

        Id resolvedAccountId;
        System.runAs(portalUser) {
            resolvedAccountId = ClientPortalCandidateControllers.getCurrentUserAccountId();
        }

        System.assertEquals(clientAccount.Id, resolvedAccountId);
    }
}