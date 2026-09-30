/* 
@auther: Rishikesh Kumar Suman
@Date: 09-30-2026
*/
trigger RateCardPageTriggerHandler on sirenum__Rate_Card_Page__c (before update) {
    if (Trigger.isBefore) {
        if (Trigger.isUpdate) {
            EvertimeSyncUtility.process(Trigger.new,Trigger.oldMap);
        }
    }
}