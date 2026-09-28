/**
 * @description Helper for SIM_JobRole trigger.
 *              On insert: clones the Job Role into all linked child contracts.
 *              On update: propagates field changes from a parent Job Role to all
 *              linked child Job Roles (Linked_Job_Role__c = parentId).
 *              Which fields are cloned/synced is controlled by the
 *              "Job_Role_Sync_Fields" FieldSet on sirenum__Team__c.
 *
 *              buildClones() and buildJobRoleFieldList() are also called by
 *              SIM_ProActiveContract_Helper to avoid duplicating the clone logic.
 * @author      Lakmal Rajapakse
 * @group       WFM Contracts
 * @last modified on  : 2026-07-01
**/
public without sharing class SIM_JobRole_Helper {

    // Prevents recursive trigger execution when child Job Roles are updated
    private static Boolean isRunning = false;
    // Prevents the inserted clones from re-triggering another clone pass
    private static Boolean isCloning = false;

    // Fields never synced from parent to child — they define the relationship itself
    private static final Set<String> EXCLUDED_FIELDS = new Set<String>{
        'id', 'linked_job_role__c', 'sirenum__account__c'
    };
    // Fields set explicitly on every clone and must not be overwritten by the fieldset loop
    private static final Set<String> CLONE_SKIP_FIELDS = new Set<String>{
        'id', 'name', 'sirenum__account__c', 'linked_job_role__c'
    };

    // ─── Before-update validation ─────────────────────────────────────────────

    public static void validateSyncFields(
        List<sirenum__Team__c> newList,
        Map<Id, sirenum__Team__c> oldMap
    ) {
        if (isRunning) return; // update is coming from syncLinkedJobRoles — allow it

        List<Schema.FieldSetMember> fsMembers = getSyncFieldSetMembers();
        if (fsMembers.isEmpty()) return;

        for (sirenum__Team__c newRec : newList) {
            sirenum__Team__c oldRec = oldMap.get(newRec.Id);
            if (oldRec.Linked_Job_Role__c == null) continue; // parent record — no restriction

            List<String> changedLabels = new List<String>();
            for (Schema.FieldSetMember fsm : fsMembers) {
                String fp = fsm.getFieldPath();
                if (EXCLUDED_FIELDS.contains(fp.toLowerCase())) continue;
                if (newRec.get(fp) != oldRec.get(fp)) {
                    changedLabels.add(fsm.getLabel());
                }
            }

            if (!changedLabels.isEmpty()) {
                newRec.addError(
                    'The following fields are managed by the parent Job Role and cannot be manually updated: '
                    + String.join(changedLabels, ', ')
                    + '. Make changes on the parent Job Role instead.'
                );
            }
        }
    }

    // ─── Insert path ──────────────────────────────────────────────────────────

    public static void cloneToLinkedContracts(List<sirenum__Team__c> newList) {
        if (isCloning) return;

        // Only process job roles added directly to a contract (not already-cloned children)
        Set<Id> parentContractIds = new Set<Id>();
        Set<Id> eligibleIds = new Set<Id>();
        for (sirenum__Team__c jr : newList) {
            if (jr.sirenum__Account__c != null && jr.Linked_Job_Role__c == null) {
                parentContractIds.add(jr.sirenum__Account__c);
                eligibleIds.add(jr.Id);
            }
        }

        if (parentContractIds.isEmpty()) return;

        // sourceContractToTargets: parentContractId -> linked child contracts
        Map<Id, List<sirenum__ProActiveContract__c>> sourceContractToTargets =
            new Map<Id, List<sirenum__ProActiveContract__c>>();
        for (sirenum__ProActiveContract__c lc : [
            SELECT Id, Linked_Contract__c, sirenum__Client__r.Name
            FROM sirenum__ProActiveContract__c
            WHERE Linked_Contract__c IN :parentContractIds
        ]) {
            if (!sourceContractToTargets.containsKey(lc.Linked_Contract__c)) {
                sourceContractToTargets.put(lc.Linked_Contract__c, new List<sirenum__ProActiveContract__c>());
            }
            sourceContractToTargets.get(lc.Linked_Contract__c).add(lc);
        }

        if (sourceContractToTargets.isEmpty()) return;

        List<Schema.FieldSetMember> fsMembers = getCloneFieldSetMembers();
        List<sirenum__Team__c> sourceJobRoles = Database.query(
            'SELECT ' + buildJobRoleFieldList(fsMembers) + ' FROM sirenum__Team__c WHERE Id IN :eligibleIds'
        );

        if (sourceJobRoles.isEmpty()) return;

        List<sirenum__Team__c> toInsert = buildClones(sourceJobRoles, sourceContractToTargets, fsMembers);
        if (toInsert.isEmpty()) return;

        isCloning = true;
        try {
            insert toInsert;
        } finally {
            isCloning = false;
        }
    }

    // ─── Update path ──────────────────────────────────────────────────────────

    public static void syncLinkedJobRoles(
        List<sirenum__Team__c> newList,
        Map<Id, sirenum__Team__c> oldMap
    ) {
        if (isRunning) return;

        List<Schema.FieldSetMember> fsMembers = getSyncFieldSetMembers();
        if (fsMembers.isEmpty()) return;

        // Collect IDs of parent Job Roles where a sync field actually changed
        Set<Id> changedParentIds = new Set<Id>();
        for (sirenum__Team__c newRec : newList) {
            sirenum__Team__c oldRec = oldMap.get(newRec.Id);
            for (Schema.FieldSetMember fsm : fsMembers) {
                String fp = fsm.getFieldPath();
                if (EXCLUDED_FIELDS.contains(fp.toLowerCase())) continue;
                if (newRec.get(fp) != oldRec.get(fp)) {
                    changedParentIds.add(newRec.Id);
                    break;
                }
            }
        }

        if (changedParentIds.isEmpty()) return;

        // Build field list for dynamic SOQL, excluding structural fields
        Set<String> addedLower = new Set<String>{'id', 'linked_job_role__c'};
        String fieldList = 'Id, Linked_Job_Role__c';
        for (Schema.FieldSetMember fsm : fsMembers) {
            String fpLower = fsm.getFieldPath().toLowerCase();
            if (!addedLower.contains(fpLower) && !EXCLUDED_FIELDS.contains(fpLower)) {
                fieldList += ', ' + fsm.getFieldPath();
                addedLower.add(fpLower);
            }
        }

        List<sirenum__Team__c> parentJobRoles = Database.query(
            'SELECT ' + fieldList + ' FROM sirenum__Team__c WHERE Id IN :changedParentIds'
        );
        Map<Id, sirenum__Team__c> parentMap = new Map<Id, sirenum__Team__c>(parentJobRoles);

        List<sirenum__Team__c> linkedJobRoles = Database.query(
            'SELECT ' + fieldList + ' FROM sirenum__Team__c WHERE Linked_Job_Role__c IN :changedParentIds'
        );

        if (linkedJobRoles.isEmpty()) return;

        List<sirenum__Team__c> toUpdate = new List<sirenum__Team__c>();
        for (sirenum__Team__c linked : linkedJobRoles) {
            sirenum__Team__c parent = parentMap.get(linked.Linked_Job_Role__c);
            if (parent == null) continue;

            sirenum__Team__c updLinked = new sirenum__Team__c(Id = linked.Id);
            for (Schema.FieldSetMember fsm : fsMembers) {
                String fp = fsm.getFieldPath();
                if (!EXCLUDED_FIELDS.contains(fp.toLowerCase())) {
                    updLinked.put(fp, parent.get(fp));
                }
            }
            toUpdate.add(updLinked);
        }

        if (toUpdate.isEmpty()) return;

        isRunning = true;
        try {
            update toUpdate;
        } finally {
            isRunning = false;
        }
    }

    // ─── Shared utilities (also called by SIM_ProActiveContract_Helper) ───────

    /**
     * Builds one clone of each source Job Role for each target contract.
     * sourceContractToTargets maps each source job role's sirenum__Account__c
     * to the list of target contracts; each target must have
     * sirenum__Client__r.Name queried.
     * Clone name: "<Client Name> - <source Name>".
     */
    public static List<sirenum__Team__c> buildClones(
        List<sirenum__Team__c> sourceJobRoles,
        Map<Id, List<sirenum__ProActiveContract__c>> sourceContractToTargets,
        List<Schema.FieldSetMember> fsMembers
    ) {
        List<sirenum__Team__c> clones = new List<sirenum__Team__c>();
        for (sirenum__Team__c source : sourceJobRoles) {
            List<sirenum__ProActiveContract__c> targets = sourceContractToTargets.get(source.sirenum__Account__c);
            if (targets == null) continue;
            for (sirenum__ProActiveContract__c target : targets) {
                String cloneName = target.sirenum__Client__r.Name.left(80 - source.Name.length() - 3) + ' - ' + source.Name;                    
                sirenum__Team__c clone = new sirenum__Team__c(
                    Name                = cloneName,
                    sirenum__Account__c = target.Id,
                    Linked_Job_Role__c  = source.Id
                );
                for (Schema.FieldSetMember fsm : fsMembers) {
                    if (!CLONE_SKIP_FIELDS.contains(fsm.getFieldPath().toLowerCase())) {
                        clone.put(fsm.getFieldPath(), source.get(fsm.getFieldPath()));
                    }
                }
                clones.add(clone);
            }
        }
        return clones;
    }

    /** Builds the SOQL field list for querying Job Roles with all fieldset fields. */
    public static String buildJobRoleFieldList(List<Schema.FieldSetMember> fsMembers) {
        Set<String> addedLower = new Set<String>{'id', 'name', 'sirenum__account__c'};
        String fieldList = 'Id, Name, sirenum__Account__c';
        for (Schema.FieldSetMember fsm : fsMembers) {
            if (!addedLower.contains(fsm.getFieldPath().toLowerCase())) {
                fieldList += ', ' + fsm.getFieldPath();
                addedLower.add(fsm.getFieldPath().toLowerCase());
            }
        }
        return fieldList;
    }

    public static List<Schema.FieldSetMember> getCloneFieldSetMembers() {
        Schema.FieldSet fs = Schema.SObjectType.sirenum__Team__c
            .fieldSets.getMap().get('Job_Role_Clone_Fields');
        return fs != null ? fs.getFields() : new List<Schema.FieldSetMember>();
    }

    public static List<Schema.FieldSetMember> getSyncFieldSetMembers() {
        Schema.FieldSet fs = Schema.SObjectType.sirenum__Team__c
            .fieldSets.getMap().get('Job_Role_Sync_Fields');
        return fs != null ? fs.getFields() : new List<Schema.FieldSetMember>();
    }
}