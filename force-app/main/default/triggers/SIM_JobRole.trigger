/**
 * @description Trigger on sirenum__Team__c (Job Role).
 *              On insert: clones the Job Role into all linked child contracts.
 *              On update: propagates field changes from parent Job Roles
 *              to all child Job Roles linked via Linked_Job_Role__c.
 *              Synced fields are controlled by the Job_Role_Sync_Fields FieldSet.
 * @author      Lakmal Rajapakse
 * @group       WFM Contracts
 * @last modified on  : 2026-07-01
**/
trigger SIM_JobRole on sirenum__Team__c (before update, after insert, after update) {
    if (Trigger.isBefore) {
        SIM_JobRole_Helper.validateSyncFields(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isInsert) {
        SIM_JobRole_Helper.cloneToLinkedContracts(Trigger.new);
    } else if (Trigger.isUpdate) {
        SIM_JobRole_Helper.syncLinkedJobRoles(Trigger.new, Trigger.oldMap);
    }
}