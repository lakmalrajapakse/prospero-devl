@isTest
private class ClientPortalTicketControllerTest {

    @TestSetup
    static void setupData() {
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

        // Confirmed ticket - SHOULD be returned
        sirenum__Ticket__c confirmedTicket = new sirenum__Ticket__c(
            sirenum__Owner__c = candidate.Id,
            sirenum__Status__c = 'Confirmed',
            sirenum__Valid_From__c = Date.today(),
            sirenum__Valid_Until__c = Date.today().addYears(1)
        );

        // Pending ticket - should NOT be returned
        sirenum__Ticket__c pendingTicket = new sirenum__Ticket__c(
            sirenum__Owner__c = candidate.Id,
            sirenum__Status__c = 'Pending',
            sirenum__Valid_From__c = Date.today(),
            sirenum__Valid_Until__c = Date.today().addYears(1)
        );

        insert new List<sirenum__Ticket__c>{ confirmedTicket, pendingTicket };
    }

    @isTest
    static void testGetConfirmedTickets_returnsOnlyConfirmedStatus() {
        Contact candidate = [SELECT Id FROM Contact WHERE FirstName = 'Alice' LIMIT 1];

        Test.startTest();
        List<sirenum__Ticket__c> results = ClientPortalTicketController.getConfirmedTickets(candidate.Id);
        Test.stopTest();

        System.assertEquals(1, results.size(),
            'Only the ticket with status Confirmed should be returned');
    }

    @isTest
    static void testGetConfirmedTickets_nullContactId_returnsEmpty() {
        Test.startTest();
        List<sirenum__Ticket__c> results = ClientPortalTicketController.getConfirmedTickets(null);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    @isTest
    static void testGetConfirmedTickets_candidateWithNoTickets_returnsEmpty() {
        Id candidateRtId = Schema.SObjectType.Contact
            .getRecordTypeInfosByDeveloperName()
            .get('Candidate')
            .getRecordTypeId();
        Contact otherCandidate = new Contact(
            FirstName = 'Zoe',
            LastName = 'NoTickets',
            RecordTypeId = candidateRtId
        );
        insert otherCandidate;

        Test.startTest();
        List<sirenum__Ticket__c> results = ClientPortalTicketController.getConfirmedTickets(otherCandidate.Id);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }
}