/* 
@auther: Rishikesh Kumar Suman
@Date: 09-30-2026
*/
trigger AccountTriggerHandler on Account (before update) {
    if (Trigger.isBefore) {
        if (Trigger.isUpdate) {
            EvertimeSyncUtility.process(Trigger.new,Trigger.oldMap);
        }
    }
}