@isTest
private class ClientPortalShiftControllerTest {

    private static User createPortalUser(Contact portalContact) {
        Profile p = [
            SELECT Id FROM Profile
            WHERE UserLicense.Name LIKE 'Customer Community%'
            LIMIT 1
        ];

        String uniqueName = 'shiftportal' + DateTime.now().getTime() + '@testorg.com';
        User u = new User(
            FirstName = 'Portal',
            LastName = 'User',
            Email = uniqueName,
            Username = uniqueName,
            Alias = 'shftpu',
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

        sirenum__Site__c clientSite = new sirenum__Site__c(
            Name = 'Client Site',
            sirenum__Operating_Company__c = clientAccount.Id
        );
        sirenum__Site__c otherSite = new sirenum__Site__c(
            Name = 'Other Site',
            sirenum__Operating_Company__c = otherAccount.Id
        );
        insert new List<sirenum__Site__c>{ clientSite, otherSite };

        // Shift at the client's own site - SHOULD be returned
        sirenum__Shift__c matchingShift = new sirenum__Shift__c(
            sirenum__Contact__c = candidate.Id,
            sirenum__Site__c = clientSite.Id,
            sirenum__Scheduled_Start_Time__c = DateTime.now(),
            sirenum__Scheduled_End_Time__c = DateTime.now().addHours(8)
        );

        // Shift at a different account's site - should NOT be returned
        sirenum__Shift__c otherShift = new sirenum__Shift__c(
            sirenum__Contact__c = candidate.Id,
            sirenum__Site__c = otherSite.Id,
            sirenum__Scheduled_Start_Time__c = DateTime.now(),
            sirenum__Scheduled_End_Time__c = DateTime.now().addHours(8)
        );

        insert new List<sirenum__Shift__c>{ matchingShift, otherShift };
    }

    @isTest
    static void testGetShiftsForCandidate_returnsOnlyClientSiteShifts() {
        Contact portalContact = [SELECT Id FROM Contact WHERE FirstName = 'Portal' LIMIT 1];
        Contact candidate = [SELECT Id FROM Contact WHERE FirstName = 'Alice' LIMIT 1];
        User portalUser = createPortalUser(portalContact);

        List<sirenum__Shift__c> results;
        System.runAs(portalUser) {
            Test.startTest();
            results = ClientPortalShiftController.getShiftsForCandidate(candidate.Id);
            Test.stopTest();
        }

        System.assertEquals(1, results.size(),
            'Only the shift at the portal account\'s own site should return');
    }

    @isTest
    static void testGetShiftsForCandidate_nullContactId_returnsEmpty() {
        Contact portalContact = [SELECT Id FROM Contact WHERE FirstName = 'Portal' LIMIT 1];
        User portalUser = createPortalUser(portalContact);

        List<sirenum__Shift__c> results;
        System.runAs(portalUser) {
            Test.startTest();
            results = ClientPortalShiftController.getShiftsForCandidate(null);
            Test.stopTest();
        }

        System.assertEquals(0, results.size());
    }

    @isTest
    static void testGetShiftsForCandidate_userWithNoAccount_returnsEmpty() {
        Contact candidate = [SELECT Id FROM Contact WHERE FirstName = 'Alice' LIMIT 1];

        Test.startTest();
        List<sirenum__Shift__c> results = ClientPortalShiftController.getShiftsForCandidate(candidate.Id);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }
}