/* 
@auther: Fazal Ur Rehman
@Date: 01-05-2026
@description: Class to create and delete the sharing for Sensitive Data records
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/36112755
*/
public without sharing class CreateSensitiveDataSharingHandler {

    public static void createShareOnInsert(List<Sensitive_Data__c> dataList){
        // call Utility Method
        SensitiveDataSharingUtility.syncManagerShares(dataList);
      
    }

    public static void createShareOnUpdate(List<Sensitive_Data__c> dataList, Map<Id, Sensitive_Data__c> oldDataList){

        List<Sensitive_Data__c> recordsToProcess = new List<Sensitive_Data__c>();

        for(Sensitive_Data__c rec: dataList){
            if(rec.OwnerId != oldDataList.get(rec.Id).OwnerId){
                recordsToProcess.add(rec);
            }
        }

        if(recordsToProcess.isEmpty()) return;
        // call Utility Method
        SensitiveDataSharingUtility.syncManagerShares(recordsToProcess);

    }
}