/**
 * @description Trigger on sirenum__ProActiveContract__c.
 *              On insert: clones Job Roles from the linked contract to the new contract.
 *              On update: propagates field changes from parent contracts
 *              to all child contracts linked via Linked_Contract__c.
 *              Synced fields are controlled by the Contract_Sync_Fields FieldSet.
 *              Job Role clone fields are controlled by the Job_Role_Sync_Fields FieldSet.
 * @author      Lakmal Rajapakse
 * @group       WFM Contracts
 * @last modified on  : 2026-07-01
**/
trigger SIM_ProActiveContract on sirenum__ProActiveContract__c (before update, after insert, after update) {
    if (Trigger.isBefore) {
        SIM_ProActiveContract_Helper.validateSyncFields(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isInsert) {
        SIM_ProActiveContract_Helper.cloneJobRoles(Trigger.new);
    } else if (Trigger.isUpdate) {
        SIM_ProActiveContract_Helper.syncLinkedContracts(Trigger.new, Trigger.oldMap);
    }
}