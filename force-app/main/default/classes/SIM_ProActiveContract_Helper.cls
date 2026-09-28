/**
 * @description Helper for SIM_ProActiveContract trigger.
 *              On insert: clones Job Roles from the linked contract to the new contract,
 *              setting Linked_Job_Role__c to the source Job Role Id.
 *              On update: propagates field changes from a parent contract to all
 *              linked child contracts (Linked_Contract__c = parentId).
 *              Contract sync fields are controlled by the "Contract_Sync_Fields" FieldSet
 *              on sirenum__ProActiveContract__c. Job Role clone/sync fields are controlled
 *              by the "Job_Role_Sync_Fields" FieldSet on sirenum__Team__c.
 * @author      Lakmal Rajapakse
 * @group       WFM Contracts
 * @last modified on  : 2026-07-01
**/
public without sharing class SIM_ProActiveContract_Helper {

    // Prevents recursive trigger execution when child contracts are updated
    private static Boolean isRunning = false;

    // ─── Before-update validation ─────────────────────────────────────────────

    public static void validateSyncFields(
        List<sirenum__ProActiveContract__c> newList,
        Map<Id, sirenum__ProActiveContract__c> oldMap
    ) {
        if (isRunning) return; // update is coming from syncLinkedContracts — allow it

        List<Schema.FieldSetMember> fsMembers = getContractSyncFieldSetMembers();
        if (fsMembers.isEmpty()) return;

        for (sirenum__ProActiveContract__c newRec : newList) {
            sirenum__ProActiveContract__c oldRec = oldMap.get(newRec.Id);
            if (oldRec.Linked_Contract__c == null) continue; // parent contract — no restriction

            List<String> changedLabels = new List<String>();
            for (Schema.FieldSetMember fsm : fsMembers) {
                if (newRec.get(fsm.getFieldPath()) != oldRec.get(fsm.getFieldPath())) {
                    changedLabels.add(fsm.getLabel());
                }
            }

            if (!changedLabels.isEmpty()) {
                newRec.addError(
                    'The following fields are managed by the parent contract and cannot be manually updated: '
                    + String.join(changedLabels, ', ')
                    + '. Make changes on the parent contract instead.'
                );
            }
        }
    }

    // ─── Update path ──────────────────────────────────────────────────────────

    public static void syncLinkedContracts(
        List<sirenum__ProActiveContract__c> newList,
        Map<Id, sirenum__ProActiveContract__c> oldMap
    ) {
        if (isRunning) return;

        List<Schema.FieldSetMember> fsMembers = getContractSyncFieldSetMembers();
        if (fsMembers.isEmpty()) return;

        // Collect IDs of parent contracts where a sync field actually changed
        Set<Id> changedParentIds = new Set<Id>();
        for (sirenum__ProActiveContract__c newRec : newList) {
            sirenum__ProActiveContract__c oldRec = oldMap.get(newRec.Id);
            for (Schema.FieldSetMember fsm : fsMembers) {
                if (newRec.get(fsm.getFieldPath()) != oldRec.get(fsm.getFieldPath())) {
                    changedParentIds.add(newRec.Id);
                    break;
                }
            }
        }

        if (changedParentIds.isEmpty()) return;

        // Build field list for dynamic SOQL
        Set<String> addedLower = new Set<String>{'id', 'linked_contract__c'};
        String fieldList = 'Id, Linked_Contract__c';
        for (Schema.FieldSetMember fsm : fsMembers) {
            if (!addedLower.contains(fsm.getFieldPath().toLowerCase())) {
                fieldList += ', ' + fsm.getFieldPath();
                addedLower.add(fsm.getFieldPath().toLowerCase());
            }
        }

        // Re-query parents to get full field values
        List<sirenum__ProActiveContract__c> parentContracts = Database.query(
            'SELECT ' + fieldList + ' FROM sirenum__ProActiveContract__c WHERE Id IN :changedParentIds'
        );
        Map<Id, sirenum__ProActiveContract__c> parentMap =
            new Map<Id, sirenum__ProActiveContract__c>(parentContracts);

        // Load all child contracts linked to any changed parent
        List<sirenum__ProActiveContract__c> childContracts = Database.query(
            'SELECT ' + fieldList + ' FROM sirenum__ProActiveContract__c WHERE Linked_Contract__c IN :changedParentIds'
        );

        if (childContracts.isEmpty()) return;

        List<sirenum__ProActiveContract__c> toUpdate = new List<sirenum__ProActiveContract__c>();
        for (sirenum__ProActiveContract__c child : childContracts) {
            sirenum__ProActiveContract__c parent = parentMap.get(child.Linked_Contract__c);
            if (parent == null) continue;

            sirenum__ProActiveContract__c updChild = new sirenum__ProActiveContract__c(Id = child.Id);
            for (Schema.FieldSetMember fsm : fsMembers) {
                updChild.put(fsm.getFieldPath(), parent.get(fsm.getFieldPath()));
            }
            toUpdate.add(updChild);
        }

        if (toUpdate.isEmpty()) return;

        isRunning = true;
        try {
            update toUpdate;
        } finally {
            isRunning = false;
        }
    }

    public static void cloneJobRoles(List<sirenum__ProActiveContract__c> newList) {
        // sourceContractToTargets: linkedContractId -> new contracts that reference it
        // New contracts are queried (not taken from Trigger.new) to get sirenum__Client__r
        Set<Id> allNewContractIds = new Set<Id>();
        for (sirenum__ProActiveContract__c newRec : newList) {
            if (newRec.Linked_Contract__c != null) {
                allNewContractIds.add(newRec.Id);
            }
        }

        if (allNewContractIds.isEmpty()) return;

        Map<Id, List<sirenum__ProActiveContract__c>> sourceContractToTargets =
            new Map<Id, List<sirenum__ProActiveContract__c>>();
        for (sirenum__ProActiveContract__c c : [
            SELECT Id, Linked_Contract__c, sirenum__Client__r.Name
            FROM sirenum__ProActiveContract__c
            WHERE Id IN :allNewContractIds
        ]) {
            if (!sourceContractToTargets.containsKey(c.Linked_Contract__c)) {
                sourceContractToTargets.put(c.Linked_Contract__c, new List<sirenum__ProActiveContract__c>());
            }
            sourceContractToTargets.get(c.Linked_Contract__c).add(c);
        }

        if (sourceContractToTargets.isEmpty()) return;

        List<Schema.FieldSetMember> fsMembers = SIM_JobRole_Helper.getCloneFieldSetMembers();
        Set<Id> linkedContractIds = sourceContractToTargets.keySet();
        List<sirenum__Team__c> sourceJobRoles = Database.query(
            'SELECT ' + SIM_JobRole_Helper.buildJobRoleFieldList(fsMembers)
            + ' FROM sirenum__Team__c WHERE sirenum__Account__c IN :linkedContractIds'
        );

        if (sourceJobRoles.isEmpty()) return;

        List<sirenum__Team__c> toInsert = SIM_JobRole_Helper.buildClones(
            sourceJobRoles, sourceContractToTargets, fsMembers
        );

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    private static List<Schema.FieldSetMember> getContractSyncFieldSetMembers() {
        Schema.FieldSet fs = Schema.SObjectType.sirenum__ProActiveContract__c
            .fieldSets.getMap().get('Contract_Sync_Fields');
        return fs != null ? fs.getFields() : new List<Schema.FieldSetMember>();
    }
}