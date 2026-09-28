trigger rateModifierTriggerCustom on sirenum__Rate_Modifier__c (before insert, before update) {

    if(Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)){

        /// Call handler to start validation — shares the same Rate Agreement margin
        /// validation pipeline as sirenum__Rate_Line__c (see rateLineTriggerCustom.trigger).
        rateLineTriggerCustomHandler.validateRateModifier(Trigger.new);
    }
}