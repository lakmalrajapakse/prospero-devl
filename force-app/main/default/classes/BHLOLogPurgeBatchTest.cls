@isTest
private class BHLOLogPurgeBatchTest {

    @TestSetup
    static void setup() {
        List<TR1__BHLO_Log__c> logs = new List<TR1__BHLO_Log__c>();

        for (Integer i = 0; i < 7; i++) {
            logs.add(new TR1__BHLO_Log__c(
                TR1__Module__c = 'TEST',
                TR1__Type__c = 'Indexing Status'
            ));
        }
        insert logs;
    }

    @isTest
    static void testPurgeDeletesAllRecords() {
        System.assertEquals(7, [SELECT COUNT() FROM TR1__BHLO_Log__c]);

        Test.startTest();
        Database.executeBatch(new BHLOLogPurgeBatch());
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM TR1__BHLO_Log__c],
            'All TR1__BHLO_Log__c records should be purged');
    }

    @isTest
    static void testScheduleDaily() {
        Test.startTest();
        Id jobId = BHLOLogPurgeBatch.scheduleDaily();
        Test.stopTest();

        CronTrigger ct = [SELECT Id, CronExpression, TimesTriggered, State FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('0 0 2 * * ?', ct.CronExpression);
    }

    @isTest
    static void testRunNow() {
        Test.startTest();
        Id jobId = BHLOLogPurgeBatch.runNow();
        Test.stopTest();

        System.assertNotEquals(null, jobId);
    }
}