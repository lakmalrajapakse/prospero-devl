/**
 * @description Test class for the SIM_JobRole trigger and its helper,
 *              SIM_JobRole_Helper (cloning a new Job Role onto linked child
 *              contracts on insert, sync-field validation on update, and
 *              propagation to linked child Job Roles).
 * @author      Lakmal Rajapakse
 * @group       WFM Contracts
 * @last modified on  : 2026-08-24
**/
@isTest
private class SIM_JobRoleTriggerTest {

    private static final Set<String> SYNC_FIELD_EXCLUSIONS = new Set<String>{
        'id', 'linked_job_role__c', 'sirenum__account__c'
    };

    @testSetup
    static void setup() {
        Team__c team = new Team__c(Name = 'Test Team');
        insert team;

        Account clientAccount = new Account(
            Name = 'JR Trigger Client Account',
            Team__c = team.Id,
            BillingStreet = '1 Test St', BillingCity = 'London', BillingPostalCode = 'W1A 1AA', BillingCountry = 'United Kingdom'
        );
        insert clientAccount;

        Account childClientAccount = new Account(
            Name = 'JR Trigger Child Client Account',
            ParentId = clientAccount.Id,
            Team__c = team.Id,
            BillingStreet = '1 Test St', BillingCity = 'London', BillingPostalCode = 'W1A 1AA', BillingCountry = 'United Kingdom'
        );
        insert childClientAccount;

        sirenum__ProActiveContract__c parentContract = new sirenum__ProActiveContract__c(
            Name = 'JR Trigger Parent Contract',
            sirenum__Client__c = clientAccount.Id
        );
        insert parentContract;

        sirenum__ProActiveContract__c childContract = new sirenum__ProActiveContract__c(
            Name = 'JR Trigger Child Contract',
            sirenum__Client__c = childClientAccount.Id,
            Linked_Contract__c = parentContract.Id
        );
        insert childContract;
    }

    @isTest
    static void testAfterInsert_cloneToLinkedContracts_clonesNewJobRoleToExistingLinkedChildContract() {
        Account childClientAccount = [SELECT Id, Name FROM Account WHERE Name = 'JR Trigger Child Client Account' LIMIT 1];
        sirenum__ProActiveContract__c parentContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'JR Trigger Parent Contract' LIMIT 1
        ];
        sirenum__ProActiveContract__c childContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'JR Trigger Child Contract' LIMIT 1
        ];

        Test.startTest();
        sirenum__Team__c parentJobRole = new sirenum__Team__c(Name = 'New Parent Job Role', sirenum__Account__c = parentContract.Id);
        insert parentJobRole;
        Test.stopTest();

        List<sirenum__Team__c> clones = [
            SELECT Id, Name
            FROM sirenum__Team__c
            WHERE sirenum__Account__c = :childContract.Id AND Linked_Job_Role__c = :parentJobRole.Id
        ];
        System.assertEquals(1, clones.size(), 'A new Job Role on the parent contract should be cloned onto its already-linked child contract');
        System.assertEquals(childClientAccount.Name + ' - New Parent Job Role', clones[0].Name);
    }

    @isTest
    static void testAfterInsert_cloneToLinkedContracts_noOpWhenNoLinkedChildContracts() {
        sirenum__ProActiveContract__c childContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'JR Trigger Child Contract' LIMIT 1
        ];

        Test.startTest();
        sirenum__Team__c leafJobRole = new sirenum__Team__c(Name = 'Leaf Job Role', sirenum__Account__c = childContract.Id);
        insert leafJobRole;
        Test.stopTest();

        Integer cloneCount = [SELECT COUNT() FROM sirenum__Team__c WHERE Linked_Job_Role__c = :leafJobRole.Id];
        System.assertEquals(0, cloneCount, 'The child contract has no linked contracts of its own, so nothing should be cloned');
    }

    @isTest
    static void testAfterInsert_cloneToLinkedContracts_skipsAlreadyLinkedJobRoles() {
        sirenum__ProActiveContract__c parentContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'JR Trigger Parent Contract' LIMIT 1
        ];

        sirenum__Team__c sourceJobRole = new sirenum__Team__c(Name = 'Source For Skip Test', sirenum__Account__c = parentContract.Id);
        insert sourceJobRole;

        Test.startTest();
        sirenum__Team__c alreadyLinkedJobRole = new sirenum__Team__c(
            Name = 'Already Linked Job Role',
            sirenum__Account__c = parentContract.Id,
            Linked_Job_Role__c = sourceJobRole.Id
        );
        insert alreadyLinkedJobRole;
        Test.stopTest();

        Integer secondaryCloneCount = [SELECT COUNT() FROM sirenum__Team__c WHERE Linked_Job_Role__c = :alreadyLinkedJobRole.Id];
        System.assertEquals(0, secondaryCloneCount, 'A Job Role that is itself already a clone should not be re-cloned to linked contracts');
    }

    @isTest
    static void testBeforeUpdate_validateSyncFields_blocksDirectEditOnLinkedChildJobRole() {
        sirenum__ProActiveContract__c parentContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'JR Trigger Parent Contract' LIMIT 1
        ];

        sirenum__Team__c parentJobRole = new sirenum__Team__c(Name = 'Sync Validation Parent Role', sirenum__Account__c = parentContract.Id);
        insert parentJobRole;

        sirenum__Team__c childJobRole = [
            SELECT Id FROM sirenum__Team__c WHERE Linked_Job_Role__c = :parentJobRole.Id LIMIT 1
        ];

        SIM_WFMTriggerTestUtil.FieldChoice choice = SIM_WFMTriggerTestUtil.pickAlternateFieldValue(
            Schema.SObjectType.sirenum__Team__c, 'Job_Role_Sync_Fields', SYNC_FIELD_EXCLUSIONS, childJobRole.Id
        );
        if (choice == null) {
            System.debug('No usable Job_Role_Sync_Fields field found in this org - skipping validation assertions');
            return;
        }

        childJobRole.put(choice.fieldPath, choice.value);

        Test.startTest();
        try {
            update childJobRole;
            System.assert(false, 'Expected a validation error when directly editing a synced field on a linked child Job Role');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('managed by the parent Job Role'),
                'Expected the parent-managed-field error message, got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testAfterUpdate_syncLinkedJobRoles_propagatesFieldChangeToLinkedJobRoles() {
        sirenum__ProActiveContract__c parentContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'JR Trigger Parent Contract' LIMIT 1
        ];

        sirenum__Team__c parentJobRole = new sirenum__Team__c(Name = 'Sync Propagation Parent Role', sirenum__Account__c = parentContract.Id);
        insert parentJobRole;

        sirenum__Team__c childJobRole = [
            SELECT Id FROM sirenum__Team__c WHERE Linked_Job_Role__c = :parentJobRole.Id LIMIT 1
        ];
        Id childJobRoleId = childJobRole.Id;

        SIM_WFMTriggerTestUtil.FieldChoice choice = SIM_WFMTriggerTestUtil.pickAlternateFieldValue(
            Schema.SObjectType.sirenum__Team__c, 'Job_Role_Sync_Fields', SYNC_FIELD_EXCLUSIONS, childJobRole.Id
        );
        if (choice == null) {
            System.debug('No usable Job_Role_Sync_Fields field found in this org - skipping propagation assertions');
            return;
        }

        parentJobRole.put(choice.fieldPath, choice.value);

        Test.startTest();
        update parentJobRole;
        Test.stopTest();

        
        sirenum__Team__c refreshedChild = Database.query(
            'SELECT Id, ' + choice.fieldPath + ' FROM sirenum__Team__c WHERE Id = :childJobRoleId'
        );
        System.assertEquals(
            choice.value, refreshedChild.get(choice.fieldPath),
            'The linked child Job Role field should be synced from the updated parent Job Role'
        );
    }
}