/* 
@auther: Fazal Ur Rehman
@Date: 01-05-2026
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/36112755
*/
trigger SensitiveDataTrigger on Sensitive_Data__c (After Insert, After Update) {
    
    Boolean bypassAutomation = FeatureManagement.checkPermission('Bypass_System_Automation');
     
    if(trigger.isAfter && !bypassAutomation){
        if(trigger.isInsert){
            CreateSensitiveDataSharingHandler.createShareOnInsert(trigger.new);
        }
        if(trigger.isUpdate){
            CreateSensitiveDataSharingHandler.createShareOnUpdate(trigger.new, trigger.oldMap);
        }
    }
}