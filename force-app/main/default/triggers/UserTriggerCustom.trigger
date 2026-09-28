/* 
@auther: Fazal Ur Rehman
@Date: 01-05-2026
@description: Class to create and delete the sharing for Sensitive Data records
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/36112755
*/
trigger UserTriggerCustom on User (After Update) {
    Set<Id> changedUsers = new Set<Id>();
    Boolean bypassAutomation = FeatureManagement.checkPermission('Bypass_System_Automation');
    if(Trigger.isAfter && !bypassAutomation){
        if(Trigger.isUpdate){
            for(User u: Trigger.new){
                if(u.ManagerId != Trigger.oldmap.get(u.id).ManagerId){
                    changedUsers.add(u.Id);
                }
            }
        }
    }

    if(!changedUsers.isEmpty()){
        Database.ExecuteBatch(new UpdateSensitiveDataSharingBatch(changedUsers));
    }

}