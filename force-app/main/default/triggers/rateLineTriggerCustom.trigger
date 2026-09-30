trigger rateLineTriggerCustom on sirenum__Rate_Line__c (before insert, before update) {

    if(Trigger.isInsert || Trigger.isUpdate){

        /// Call handler call to start validation
        rateLineTriggerCustomHandler.validateRateLine(Trigger.new);
    }
    if (Trigger.isBefore) {
        if (Trigger.isUpdate) {
            EvertimeSyncUtility.process(Trigger.new,Trigger.oldMap);
        }
    }
}