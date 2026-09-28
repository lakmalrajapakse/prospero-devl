/**
 * @description Test class for the SIM_ProActiveContract trigger and its helper,
 *              SIM_ProActiveContract_Helper (job role cloning on insert, sync-field
 *              validation on update, and propagation to linked child contracts).
 * @author      Lakmal Rajapakse
 * @group       WFM Contracts
 * @last modified on  : 2026-08-24
**/
@isTest
private class SIM_ProActiveContractTriggerTest {

    @testSetup
    static void setup() {
        Team__c team = new Team__c(Name = 'Test Team');
        insert team;

        Account clientAccount = new Account(
            Name = 'PAC Trigger Client Account',
            Team__c = team.Id,
            BillingStreet = '1 Test St', BillingCity = 'London', BillingPostalCode = 'W1A 1AA', BillingCountry = 'United Kingdom'
        );
        insert clientAccount;

        Account childClientAccount = new Account(
            Name = 'PAC Trigger Child Client Account',
            ParentId = clientAccount.Id,
            Team__c = team.Id,
            BillingStreet = '1 Test St', BillingCity = 'London', BillingPostalCode = 'W1A 1AA', BillingCountry = 'United Kingdom'
        );
        insert childClientAccount;

        sirenum__ProActiveContract__c parentContract = new sirenum__ProActiveContract__c(
            Name = 'PAC Trigger Parent Contract',
            sirenum__Client__c = clientAccount.Id
        );
        insert parentContract;
    }

    @isTest
    static void testAfterInsert_cloneJobRoles_clonesExistingJobRolesToNewChildContract() {
        Account childClientAccount = [SELECT Id, Name FROM Account WHERE Name = 'PAC Trigger Child Client Account' LIMIT 1];
        sirenum__ProActiveContract__c parentContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'PAC Trigger Parent Contract' LIMIT 1
        ];

        sirenum__Team__c parentJobRole = new sirenum__Team__c(Name = 'Existing Parent Job Role', sirenum__Account__c = parentContract.Id);
        insert parentJobRole;

        Test.startTest();
        sirenum__ProActiveContract__c childContract = new sirenum__ProActiveContract__c(
            Name = 'New Child Contract',
            sirenum__Client__c = childClientAccount.Id,
            Linked_Contract__c = parentContract.Id
        );
        insert childContract;
        Test.stopTest();

        List<sirenum__Team__c> clones = [
            SELECT Id, Name
            FROM sirenum__Team__c
            WHERE sirenum__Account__c = :childContract.Id AND Linked_Job_Role__c = :parentJobRole.Id
        ];
        System.assertEquals(1, clones.size(), 'Existing job role on the parent contract should be cloned onto the newly linked child contract');
        System.assertEquals(childClientAccount.Name + ' - Existing Parent Job Role', clones[0].Name);
    }

    @isTest
    static void testAfterInsert_cloneJobRoles_noOpWhenParentHasNoJobRoles() {
        Account childClientAccount = [SELECT Id FROM Account WHERE Name = 'PAC Trigger Child Client Account' LIMIT 1];
        sirenum__ProActiveContract__c parentContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'PAC Trigger Parent Contract' LIMIT 1
        ];

        Test.startTest();
        sirenum__ProActiveContract__c childContract = new sirenum__ProActiveContract__c(
            Name = 'New Child Contract No Roles',
            sirenum__Client__c = childClientAccount.Id,
            Linked_Contract__c = parentContract.Id
        );
        insert childContract;
        Test.stopTest();

        Integer cloneCount = [SELECT COUNT() FROM sirenum__Team__c WHERE sirenum__Account__c = :childContract.Id];
        System.assertEquals(0, cloneCount, 'No job roles exist on the parent contract, so nothing should be cloned');
    }

    @isTest
    static void testAfterInsert_cloneJobRoles_noOpForStandaloneContract() {
        Account clientAccount = [SELECT Id FROM Account WHERE Name = 'PAC Trigger Client Account' LIMIT 1];

        Test.startTest();
        sirenum__ProActiveContract__c standaloneContract = new sirenum__ProActiveContract__c(
            Name = 'Standalone Contract',
            sirenum__Client__c = clientAccount.Id
        );
        insert standaloneContract;
        Test.stopTest();

        System.assertNotEquals(null, standaloneContract.Id, 'A contract with no Linked_Contract__c should insert without attempting to clone job roles');
    }

    @isTest
    static void testBeforeUpdate_validateSyncFields_blocksDirectEditOnLinkedChildContract() {
        Account childClientAccount = [SELECT Id FROM Account WHERE Name = 'PAC Trigger Child Client Account' LIMIT 1];
        sirenum__ProActiveContract__c parentContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'PAC Trigger Parent Contract' LIMIT 1
        ];

        sirenum__ProActiveContract__c childContract = new sirenum__ProActiveContract__c(
            Name = 'Child For Validation',
            sirenum__Client__c = childClientAccount.Id,
            Linked_Contract__c = parentContract.Id
        );
        insert childContract;

        SIM_WFMTriggerTestUtil.FieldChoice choice = SIM_WFMTriggerTestUtil.pickAlternateFieldValue(
            Schema.SObjectType.sirenum__ProActiveContract__c, 'Contract_Sync_Fields', new Set<String>{ 'id' }, childContract.id
        );
        if (choice == null) {
            System.debug('No usable Contract_Sync_Fields field found in this org - skipping validation assertions');
            return;
        }

        childContract.put(choice.fieldPath, choice.value);

        Test.startTest();
        try {
            update childContract;
            System.assert(false, 'Expected a validation error when directly editing a synced field on a linked child contract');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('managed by the parent contract'),
                'Expected the parent-managed-field error message, got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testAfterUpdate_syncLinkedContracts_propagatesFieldChangeToChildContracts() {
        Account childClientAccount = [SELECT Id FROM Account WHERE Name = 'PAC Trigger Child Client Account' LIMIT 1];
        sirenum__ProActiveContract__c parentContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'PAC Trigger Parent Contract' LIMIT 1
        ];

        sirenum__ProActiveContract__c childContract = new sirenum__ProActiveContract__c(
            Name = 'Child For Sync',
            sirenum__Client__c = childClientAccount.Id,
            Linked_Contract__c = parentContract.Id
        );
        insert childContract;
        Id childContractId = childContract.Id;

        SIM_WFMTriggerTestUtil.FieldChoice choice = SIM_WFMTriggerTestUtil.pickAlternateFieldValue(
            Schema.SObjectType.sirenum__ProActiveContract__c, 'Contract_Sync_Fields', new Set<String>{ 'id' }, childContractId
        );
        if (choice == null) {
            System.debug('No usable Contract_Sync_Fields field found in this org - skipping propagation assertions');
            return;
        }

        parentContract.put(choice.fieldPath, choice.value);

        Test.startTest();
        update parentContract;
        Test.stopTest();

        sirenum__ProActiveContract__c refreshedChild = Database.query(
            'SELECT Id, ' + choice.fieldPath + ' FROM sirenum__ProActiveContract__c WHERE Id = :childContractId'
        );
        System.assertEquals(
            choice.value, refreshedChild.get(choice.fieldPath),
            'The child contract field should be synced from the updated parent contract'
        );
    }
}