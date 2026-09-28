/* 
@auther: Fazal Ur Rehman
@Date: 01-05-2026
@description: Class to create and delete the sharing for Sensitive Data records
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/36112755
*/
public class UpdateSensitiveDataSharingBatch implements Database.Batchable<Sobject>, Database.Stateful {
    private set<Id> userIds;
    // constructor
    public UpdateSensitiveDataSharingBatch(set<Id> userIds) {
        this.userIds = userIds;
    }

    public Database.Querylocator Start(Database.BatchableContext BC){
        
        // Get full impacted hierarchy
        Set<Id> impactedUsers =  SensitiveDataSharingUtility.getAllSubordinateUsers(userIds);
        return Database.getQueryLocator([
                                        SELECT Id, OwnerId
                                            FROM Sensitive_Data__c
                                            WHERE ownerId IN: impactedUsers]);
    }

    public void Execute(Database.BatchableContext BC, List<Sensitive_Data__c> records){
       SensitiveDataSharingUtility.syncManagerShares(records);
    }

    public void Finish(Database.BatchableContext BC){
        
    }
}