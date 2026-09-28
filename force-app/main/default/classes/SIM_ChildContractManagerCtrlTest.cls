/**
 * @description Test class for SIM_ChildContractManagerCtrl.
 * @author      Lakmal Rajapakse
 * @group       WFM Contracts
 * @last modified on  : 2026-08-24
**/
@isTest
private class SIM_ChildContractManagerCtrlTest {

    @testSetup
    static void setup() {
        Team__c team = new Team__c(Name = 'Test Team');
        insert team;
        
        Account parentAccount = new Account(Name = 'Test Parent Account', Team__c = team.Id, BillingStreet='123 Main St', BillingCity='London', BillingPostalCode='W1A 1AA', BillingCountry='United Kingdom');
        insert parentAccount;

        // Named out of alphabetical order so sorting behaviour is actually exercised
        Account childAccountA = new Account(Name = 'Zephyr Child Account', ParentId = parentAccount.Id, Team__c = team.Id, BillingStreet='123 Main St', BillingCity='London', BillingPostalCode='W1A 1AA', BillingCountry='United Kingdom');
        Account childAccountB = new Account(Name = 'Alpha Child Account', ParentId = parentAccount.Id, Team__c = team.Id, BillingStreet='123 Main St', BillingCity='London', BillingPostalCode='W1A 1AA', BillingCountry='United Kingdom');
        insert new List<Account>{ childAccountA, childAccountB };

        Account grandchildAccount = new Account(Name = 'Middle Grandchild Account', ParentId = childAccountB.Id, Team__c = team.Id, BillingStreet='123 Main St', BillingCity='London', BillingPostalCode='W1A 1AA', BillingCountry='United Kingdom');
        insert grandchildAccount;

        Account greatGrandchildAccount = new Account(Name = 'Omega Great-Grandchild Account', ParentId = grandchildAccount.Id, Team__c = team.Id, BillingStreet='123 Main St', BillingCity='London', BillingPostalCode='W1A 1AA', BillingCountry='United Kingdom');
        insert greatGrandchildAccount;

        // Sibling of the parent account - must never show up as a descendant
        insert new Account(Name = 'Unrelated Sibling Account', Team__c = team.Id, BillingStreet='123 Main St', BillingCity='London', BillingPostalCode='W1A 1AA', BillingCountry='United Kingdom');

        Account noChildAccount = new Account(Name = 'Lonely Account With No Children', Team__c = team.Id, BillingStreet='123 Main St', BillingCity='London', BillingPostalCode='W1A 1AA', BillingCountry='United Kingdom');
        insert noChildAccount;

        sirenum__ProActiveContract__c parentContract = new sirenum__ProActiveContract__c(
            Name = 'Parent Contract',
            sirenum__Client__c = parentAccount.Id
        );
        insert parentContract;

        sirenum__ProActiveContract__c childlessContract = new sirenum__ProActiveContract__c(
            Name = 'Childless Contract',
            sirenum__Client__c = noChildAccount.Id
        );
        insert childlessContract;

        sirenum__ProActiveContract__c existingLinkedContract = new sirenum__ProActiveContract__c(
            Name = 'Existing Child Contract',
            sirenum__Client__c = childAccountA.Id,
            Linked_Contract__c = parentContract.Id
        );
        insert existingLinkedContract;

        // Separate branch used to prove that a contract which is ITSELF already a child
        // (Linked_Contract__c != null) does not expand its own account's descendants,
        // even though those descendants exist.
        Account branchParentAccount = new Account(
            Name = 'Branch Parent Account',
            Team__c = team.Id,
            BillingStreet = '123 Main St', BillingCity = 'London', BillingPostalCode = 'W1A 1AA', BillingCountry = 'United Kingdom'
        );
        insert branchParentAccount;

        Account branchChildAccount = new Account(
            Name = 'Branch Child Account',
            ParentId = branchParentAccount.Id,
            Team__c = team.Id,
            BillingStreet = '123 Main St', BillingCity = 'London', BillingPostalCode = 'W1A 1AA', BillingCountry = 'United Kingdom'
        );
        insert branchChildAccount;

        Account branchGrandchildAccount = new Account(
            Name = 'Branch Grandchild Account',
            ParentId = branchChildAccount.Id,
            Team__c = team.Id,
            BillingStreet = '123 Main St', BillingCity = 'London', BillingPostalCode = 'W1A 1AA', BillingCountry = 'United Kingdom'
        );
        insert branchGrandchildAccount;

        sirenum__ProActiveContract__c branchParentContract = new sirenum__ProActiveContract__c(
            Name = 'Branch Parent Contract',
            sirenum__Client__c = branchParentAccount.Id
        );
        insert branchParentContract;

        sirenum__ProActiveContract__c branchChildContract = new sirenum__ProActiveContract__c(
            Name = 'Branch Child Contract',
            sirenum__Client__c = branchChildAccount.Id,
            Linked_Contract__c = branchParentContract.Id
        );
        insert branchChildContract;
    }

    @isTest
    static void testGetChildAccountData_returnsAllDescendantLevelsSortedByName() {
        sirenum__ProActiveContract__c parentContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'Parent Contract' LIMIT 1
        ];
        Account childA = [SELECT Id FROM Account WHERE Name = 'Zephyr Child Account' LIMIT 1];
        Account childB = [SELECT Id FROM Account WHERE Name = 'Alpha Child Account' LIMIT 1];
        Account grandchild = [SELECT Id FROM Account WHERE Name = 'Middle Grandchild Account' LIMIT 1];
        Account greatGrandchild = [SELECT Id FROM Account WHERE Name = 'Omega Great-Grandchild Account' LIMIT 1];
        sirenum__ProActiveContract__c existingLinkedContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'Existing Child Contract' LIMIT 1
        ];

        Test.startTest();
        String resultJson = SIM_ChildContractManagerCtrl.getChildAccountData(parentContract.Id);
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(resultJson);
        System.assertEquals('Parent Contract', result.get('contractName'));
        System.assertEquals('Test Parent Account', result.get('parentAccountName'));

        List<Object> rows = (List<Object>) result.get('childAccountRows');
        System.assertEquals(4, rows.size(), 'Children, grandchildren and great-grandchildren should all be included');

        List<String> expectedOrder = new List<String>{
            'Alpha Child Account', 'Middle Grandchild Account', 'Omega Great-Grandchild Account', 'Zephyr Child Account'
        };
        for (Integer i = 0; i < rows.size(); i++) {
            Map<String, Object> row = (Map<String, Object>) rows.get(i);
            System.assertEquals(expectedOrder[i], row.get('accountName'), 'Rows should be sorted alphabetically by account name');
        }

        Map<Id, Map<String, Object>> rowsByAccountId = new Map<Id, Map<String, Object>>();
        for (Object rowObj : rows) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            rowsByAccountId.put((Id) row.get('accountId'), row);
        }

        System.assertEquals(true, rowsByAccountId.get(childA.Id).get('hasLinkedContract'));
        System.assertEquals(existingLinkedContract.Id, (Id) rowsByAccountId.get(childA.Id).get('linkedContractId'));
        System.assertEquals(false, rowsByAccountId.get(childB.Id).get('hasLinkedContract'));
        System.assertEquals(false, rowsByAccountId.get(grandchild.Id).get('hasLinkedContract'));
        System.assertEquals(false, rowsByAccountId.get(greatGrandchild.Id).get('hasLinkedContract'));
    }

    @isTest
    static void testGetChildAccountData_accountWithNoChildrenReturnsEmptyRows() {
        sirenum__ProActiveContract__c childlessContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'Childless Contract' LIMIT 1
        ];

        Test.startTest();
        String resultJson = SIM_ChildContractManagerCtrl.getChildAccountData(childlessContract.Id);
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(resultJson);
        List<Object> rows = (List<Object>) result.get('childAccountRows');
        System.assertEquals(0, rows.size());
    }

    @isTest
    static void testGetChildAccountData_missingContractThrowsAuraHandledException() {
        Test.startTest();
        try {
            SIM_ChildContractManagerCtrl.getChildAccountData(null);
            System.assert(false, 'Expected an AuraHandledException when the contract cannot be found');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGetChildAccountData_topLevelContractStillReturnsAllDescendantsEvenWhenAChildIsAlreadyLinked() {
        sirenum__ProActiveContract__c branchParentContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'Branch Parent Contract' LIMIT 1
        ];
        Account branchChildAccount = [SELECT Id FROM Account WHERE Name = 'Branch Child Account' LIMIT 1];
        Account branchGrandchildAccount = [SELECT Id FROM Account WHERE Name = 'Branch Grandchild Account' LIMIT 1];
        sirenum__ProActiveContract__c branchChildContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'Branch Child Contract' LIMIT 1
        ];

        Test.startTest();
        String resultJson = SIM_ChildContractManagerCtrl.getChildAccountData(branchParentContract.Id);
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(resultJson);
        List<Object> rows = (List<Object>) result.get('childAccountRows');
        System.assertEquals(2, rows.size(), 'A top-level contract should still expand every descendant of its account');

        Map<Id, Map<String, Object>> rowsByAccountId = new Map<Id, Map<String, Object>>();
        for (Object rowObj : rows) {
            Map<String, Object> row = (Map<String, Object>) rowObj;
            rowsByAccountId.put((Id) row.get('accountId'), row);
        }

        System.assertEquals(true, rowsByAccountId.get(branchChildAccount.Id).get('hasLinkedContract'));
        System.assertEquals(branchChildContract.Id, (Id) rowsByAccountId.get(branchChildAccount.Id).get('linkedContractId'));
        System.assertEquals(false, rowsByAccountId.get(branchGrandchildAccount.Id).get('hasLinkedContract'));
    }

    @isTest
    static void testGetChildAccountData_childContractDoesNotExpandItsOwnDescendants() {
        sirenum__ProActiveContract__c branchChildContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'Branch Child Contract' LIMIT 1
        ];

        Test.startTest();
        String resultJson = SIM_ChildContractManagerCtrl.getChildAccountData(branchChildContract.Id);
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(resultJson);
        System.assertEquals('Branch Child Contract', result.get('contractName'));
        System.assertEquals('Branch Child Account', result.get('parentAccountName'));

        List<Object> rows = (List<Object>) result.get('childAccountRows');
        System.assertEquals(
            0, rows.size(),
            'A contract that is itself already linked (Linked_Contract__c != null) should not expand its own account\'s descendants'
        );
    }

    @isTest
    static void testSaveChildContracts_createsUnlinkedRowsAndSkipsAlreadyLinkedRows() {
        sirenum__ProActiveContract__c parentContract = [
            SELECT Id, Name FROM sirenum__ProActiveContract__c WHERE Name = 'Parent Contract' LIMIT 1
        ];
        Account childA = [SELECT Id, Name FROM Account WHERE Name = 'Zephyr Child Account' LIMIT 1];
        Account childB = [SELECT Id, Name FROM Account WHERE Name = 'Alpha Child Account' LIMIT 1];
        Account grandchild = [SELECT Id, Name FROM Account WHERE Name = 'Middle Grandchild Account' LIMIT 1];
        sirenum__ProActiveContract__c existingLinkedContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'Existing Child Contract' LIMIT 1
        ];

        List<Map<String, Object>> selectedRows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'accountId' => childA.Id, 'accountName' => childA.Name, 'linkedContractId' => existingLinkedContract.Id },
            new Map<String, Object>{ 'accountId' => childB.Id, 'accountName' => childB.Name, 'linkedContractId' => null },
            new Map<String, Object>{ 'accountId' => grandchild.Id, 'accountName' => grandchild.Name, 'linkedContractId' => null }
        };

        Test.startTest();
        String resultJson = SIM_ChildContractManagerCtrl.saveChildContracts(parentContract.Id, JSON.serialize(selectedRows));
        Test.stopTest();

        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(resultJson);
        System.assertEquals(true, result.get('success'));
        System.assertEquals(2, (Integer) result.get('insertedCount'), 'Only rows without an existing linked contract should be inserted');

        Set<Id> newlyLinkedAccountIds = new Set<Id>{ childB.Id, grandchild.Id };
        List<sirenum__ProActiveContract__c> created = [
            SELECT Id, Name, sirenum__Client__c
            FROM sirenum__ProActiveContract__c
            WHERE Linked_Contract__c = :parentContract.Id AND sirenum__Client__c IN :newlyLinkedAccountIds
        ];
        System.assertEquals(2, created.size());

        for (sirenum__ProActiveContract__c c : created) {
            if (c.sirenum__Client__c == childB.Id) {
                System.assertEquals('Alpha Child Account - Parent Contract', c.Name);
            }
        }

        Integer stillOnlyOriginalContractForChildA = [
            SELECT COUNT()
            FROM sirenum__ProActiveContract__c
            WHERE Linked_Contract__c = :parentContract.Id AND sirenum__Client__c = :childA.Id
        ];
        System.assertEquals(1, stillOnlyOriginalContractForChildA, 'The already-linked account should not receive a duplicate contract');
    }

    @isTest
    static void testSaveChildContracts_noSelectedRowsThrowsAuraHandledException() {
        sirenum__ProActiveContract__c parentContract = [
            SELECT Id FROM sirenum__ProActiveContract__c WHERE Name = 'Parent Contract' LIMIT 1
        ];

        Test.startTest();
        try {
            SIM_ChildContractManagerCtrl.saveChildContracts(parentContract.Id, '[]');
            System.assert(false, 'Expected an AuraHandledException when no rows are provided');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
}