public class BHLOLogPurgeBatch implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    private static final Integer BATCH_SIZE = 2000;

    public Integer totalDeleted = 0;

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id
            FROM TR1__BHLO_Log__c
        ]);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Database.DeleteResult[] results = Database.delete(scope, false);

        List<Id> deletedIds = new List<Id>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                deletedIds.add(scope[i].Id);
            } else {
                for (Database.Error err : results[i].getErrors()) {
                    System.debug(LoggingLevel.ERROR, 'BHLOLogPurgeBatch: failed to delete ' + scope[i].Id + ' - ' + err.getMessage());
                }
            }
        }

        totalDeleted += deletedIds.size();

        if (!deletedIds.isEmpty()) {
            Database.emptyRecycleBin(deletedIds);
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'BHLOLogPurgeBatch: purge complete, ' + totalDeleted + ' TR1__BHLO_Log__c records deleted.');
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new BHLOLogPurgeBatch(), BATCH_SIZE);
    }

    public static Id runNow() {
        return Database.executeBatch(new BHLOLogPurgeBatch(), BATCH_SIZE);
    }

    public static Id scheduleDaily() {
        String cronExpr = '0 0 2 * * ?';
        return System.schedule('BHLO Log Purge - Daily', cronExpr, new BHLOLogPurgeBatch());
    }
}