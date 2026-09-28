/*
@author: Gandhi Naidu Bokam
@Date: 01-09-2026
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/36248202
*/
trigger ShiftTrigger on sirenum__Shift__c (
    before insert, before update,
    after insert, after update, after delete, after undelete
) {
    // --- BEFORE context: field assignment logic only. No DML here. ---
    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            ShiftPreApprovalHandler.assignPreApprovalOnPublish(
                Trigger.new,
                Trigger.isUpdate ? Trigger.oldMap : null
            );
        }
    }

    // --- AFTER context: anything that performs DML (Placement linking,
    // Pre-Approval hours recalculation) must live here, never in before-*,
    // to avoid SELF_REFERENCE_FROM_TRIGGER when updating the triggering
    // records themselves.
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            ShiftTriggerHandler.handleAfterInsert(Trigger.new);
            PreApprovalHoursCalculator.recalculateAvailableHours(
                Trigger.new, null, true, false, false, false
            );
        }
        if (Trigger.isUpdate) {
            ShiftTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
            PreApprovalHoursCalculator.recalculateAvailableHours(
                Trigger.new, Trigger.oldMap, false, true, false, false
            );
        }
        if (Trigger.isDelete) {
            PreApprovalHoursCalculator.recalculateAvailableHours(
                null, Trigger.oldMap, false, false, true, false
            );
        }
        if (Trigger.isUndelete) {
            PreApprovalHoursCalculator.recalculateAvailableHours(
                Trigger.new, null, false, false, false, true
            );
        }
    }
}