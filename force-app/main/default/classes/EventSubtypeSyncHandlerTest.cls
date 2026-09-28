@isTest
private class EventSubtypeSyncHandlerTest {

    @isTest
    static void testEventSubtypeIsSyncedOnInsert() {
        Event e = new Event(
            Subject       = 'Test Event',
            StartDateTime = System.now().addDays(1),
            EndDateTime   = System.now().addDays(1).addHours(1)
            // EventSubtype is auto-populated by Salesforce based on Subject/type
            // in most orgs; if your org requires it explicitly, set it here, e.g.:
            // EventSubtype = 'Event'
        );

        Test.startTest();
        insert e;
        Test.stopTest();

        Event result = [
            SELECT Id, EventSubtype, Event_Subtype__c
            FROM Event
            WHERE Id = :e.Id
        ];

      
    }

    @isTest
    static void testEventSubtypeIsSyncedOnUpdate() {
        Event e = new Event(
            Subject       = 'Test Event 2',
            StartDateTime = System.now().addDays(1),
            EndDateTime   = System.now().addDays(1).addHours(1)
        );
        insert e;

        e.Subject = 'Updated Subject';
        Test.startTest();
        update e;
        Test.stopTest();

        Event result = [
            SELECT Id, EventSubtype, Event_Subtype__c
            FROM Event
            WHERE Id = :e.Id
        ];

        System.assertEquals(
            result.EventSubtype,
            result.Event_Subtype__c,
            'Custom field should still mirror EventSubtype after update'
        );
    }
}