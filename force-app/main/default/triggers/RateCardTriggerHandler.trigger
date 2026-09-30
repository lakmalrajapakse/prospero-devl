/* 
@auther: Rishikesh Kumar Suman
@Date: 09-30-2026
*/
trigger RateCardTriggerHandler on sirenum__Rate_Card__c (before update) {
    if (Trigger.isBefore) {
        if (Trigger.isUpdate) {
            EvertimeSyncUtility.process(Trigger.new,Trigger.oldMap);
        }
    }
}