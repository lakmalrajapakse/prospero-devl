/* 
@auther: Rishikesh Kumar Suman
@Date: 09-30-2026
*/
trigger PlacementTriggerHandler on TR1__Closing_Report__c (before update) {
    if (Trigger.isBefore) {
        if (Trigger.isUpdate) {
            EvertimeSyncUtility.process(Trigger.new,Trigger.oldMap);
        }
    }
}