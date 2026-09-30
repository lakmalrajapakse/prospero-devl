@IsTest
private class EvertimeSyncUtilityTest {

    /**
     * Test 1:
     * Account Evertime field is changed and Last Evertime Sync
     * is populated.
     *
     * Expected:
     * Evertime Sync Required should be populated.
     */
    @IsTest
    static void testEvertimeFieldChanged() {

        Account oldAccount = new Account(
            Id = '001000000000001AAA',
            Name = 'Test Account',
            Email__c = 'old@test.com',
            Description = 'Old Description',
            Diocese__c = 'Old Diocese',
            Last_Evertime_Sync__c = System.now().addDays(-1)
        );

        Account newAccount = oldAccount.clone(false, true, false, false);

        newAccount.Id = oldAccount.Id;
        newAccount.Email__c = 'new@test.com';

        Map<Id, SObject> oldMap = new Map<Id, SObject>{
            oldAccount.Id => oldAccount
        };

        List<SObject> newRecords = new List<SObject>{
            newAccount
        };

        Test.startTest();

        EvertimeSyncUtility.process(
            newRecords,
            oldMap
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            newAccount.Evertime_Sync_Required__c,
            'Evertime Sync Required should be populated when an Evertime field changes.'
        );
    }


    /**
     * Test 2:
     * No Evertime field is changed.
     *
     * Expected:
     * Evertime Sync Required should remain null.
     */
    @IsTest
    static void testNoEvertimeFieldChanged() {

        Account oldAccount = new Account(
            Id = '001000000000002AAA',
            Name = 'Test Account',
            Email__c = 'test@test.com',
            Description = 'Description',
            Diocese__c = 'Diocese',
            Last_Evertime_Sync__c = System.now().addDays(-1)
        );

        Account newAccount = oldAccount.clone(false, true, false, false);

        newAccount.Id = oldAccount.Id;

        Map<Id, SObject> oldMap = new Map<Id, SObject>{
            oldAccount.Id => oldAccount
        };

        List<SObject> newRecords = new List<SObject>{
            newAccount
        };

        Test.startTest();

        EvertimeSyncUtility.process(
            newRecords,
            oldMap
        );

        Test.stopTest();

        System.assertEquals(
            null,
            newAccount.Evertime_Sync_Required__c,
            'Evertime Sync Required should remain null when no Evertime field changes.'
        );
    }


    /**
     * Test 3:
     * Evertime field is changed but Last Evertime Sync is null.
     *
     * Expected:
     * Evertime Sync Required should remain null.
     */
    @IsTest
    static void testLastEvertimeSyncIsNull() {

        Account oldAccount = new Account(
            Id = '001000000000003AAA',
            Name = 'Test Account',
            Email__c = 'old@test.com',
            Description = 'Description',
            Diocese__c = 'Diocese'
        );

        Account newAccount = oldAccount.clone(false, true, false, false);

        newAccount.Id = oldAccount.Id;
        newAccount.Email__c = 'new@test.com';

        Map<Id, SObject> oldMap = new Map<Id, SObject>{
            oldAccount.Id => oldAccount
        };

        List<SObject> newRecords = new List<SObject>{
            newAccount
        };

        Test.startTest();

        EvertimeSyncUtility.process(
            newRecords,
            oldMap
        );

        Test.stopTest();

        System.assertEquals(
            null,
            newAccount.Evertime_Sync_Required__c,
            'Evertime Sync Required should remain null when Last Evertime Sync is null.'
        );
    }


    /**
     * Test 4:
     * Evertime field changes from null to a value.
     *
     * Expected:
     * Evertime Sync Required should be populated.
     */
    @IsTest
    static void testNullToValueChange() {

        Account oldAccount = new Account(
            Id = '001000000000004AAA',
            Name = 'Test Account',
            Email__c = null,
            Description = 'Description',
            Diocese__c = 'Diocese',
            Last_Evertime_Sync__c = System.now().addDays(-1)
        );

        Account newAccount = oldAccount.clone(false, true, false, false);

        newAccount.Id = oldAccount.Id;
        newAccount.Email__c = 'new@test.com';

        Map<Id, SObject> oldMap = new Map<Id, SObject>{
            oldAccount.Id => oldAccount
        };

        Test.startTest();

        EvertimeSyncUtility.process(
            new List<SObject>{ newAccount },
            oldMap
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            newAccount.Evertime_Sync_Required__c,
            'Evertime Sync Required should be populated for a null-to-value change.'
        );
    }


    /**
     * Test 5:
     * Evertime field changes from a value to null.
     *
     * Expected:
     * Evertime Sync Required should be populated.
     */
    @IsTest
    static void testValueToNullChange() {

        Account oldAccount = new Account(
            Id = '001000000000005AAA',
            Name = 'Test Account',
            Email__c = 'old@test.com',
            Description = 'Description',
            Diocese__c = 'Diocese',
            Last_Evertime_Sync__c = System.now().addDays(-1)
        );

        Account newAccount = oldAccount.clone(false, true, false, false);

        newAccount.Id = oldAccount.Id;
        newAccount.Email__c = null;

        Map<Id, SObject> oldMap = new Map<Id, SObject>{
            oldAccount.Id => oldAccount
        };

        Test.startTest();

        EvertimeSyncUtility.process(
            new List<SObject>{ newAccount },
            oldMap
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            newAccount.Evertime_Sync_Required__c,
            'Evertime Sync Required should be populated for a value-to-null change.'
        );
    }


    /**
     * Test 6:
     * Bulk processing.
     *
     * Expected:
     * Only records where an Evertime field changed should be updated.
     */
    @IsTest
    static void testBulkProcessing() {

        Datetime lastSync = System.now().addDays(-1);

        Account oldAccount1 = new Account(
            Id = '001000000000006AAA',
            Name = 'Account 1',
            Email__c = 'old1@test.com',
            Description = 'Description 1',
            Diocese__c = 'Diocese 1',
            Last_Evertime_Sync__c = lastSync
        );

        Account oldAccount2 = new Account(
            Id = '001000000000007AAA',
            Name = 'Account 2',
            Email__c = 'old2@test.com',
            Description = 'Description 2',
            Diocese__c = 'Diocese 2',
            Last_Evertime_Sync__c = lastSync
        );

        Account oldAccount3 = new Account(
            Id = '001000000000008AAA',
            Name = 'Account 3',
            Email__c = 'old3@test.com',
            Description = 'Description 3',
            Diocese__c = 'Diocese 3'
        );

        Account newAccount1 =
            oldAccount1.clone(false, true, false, false);

        Account newAccount2 =
            oldAccount2.clone(false, true, false, false);

        Account newAccount3 =
            oldAccount3.clone(false, true, false, false);

        newAccount1.Id = oldAccount1.Id;
        newAccount2.Id = oldAccount2.Id;
        newAccount3.Id = oldAccount3.Id;

        // Evertime field changed
        newAccount1.Email__c = 'new1@test.com';

        // No Evertime field changed
        newAccount2.Name = 'Updated Account 2';

        // Evertime field changed but Last Sync is null
        newAccount3.Email__c = 'new3@test.com';

        Map<Id, SObject> oldMap = new Map<Id, SObject>{
            oldAccount1.Id => oldAccount1,
            oldAccount2.Id => oldAccount2,
            oldAccount3.Id => oldAccount3
        };

        List<SObject> newRecords = new List<SObject>{
            newAccount1,
            newAccount2,
            newAccount3
        };

        Test.startTest();

        EvertimeSyncUtility.process(
            newRecords,
            oldMap
        );

        Test.stopTest();

        // Record 1 should be marked
        System.assertNotEquals(
            null,
            newAccount1.Evertime_Sync_Required__c,
            'Account 1 should be marked for Evertime sync.'
        );

        // Record 2 should NOT be marked
        System.assertEquals(
            null,
            newAccount2.Evertime_Sync_Required__c,
            'Account 2 should not be marked because no Evertime field changed.'
        );

        // Record 3 should NOT be marked
        System.assertEquals(
            null,
            newAccount3.Evertime_Sync_Required__c,
            'Account 3 should not be marked because Last Evertime Sync is null.'
        );
    }


    /**
     * Test 7:
     * Verify another object mapping.
     *
     * Contact uses:
     * TR1__Batch_ID__c
     * Birthdate
     * Brand_Single_Pick__c
     */
    @IsTest
    static void testContactEvertimeFieldChanged() {

        Contact oldContact = new Contact(
            Id = '003000000000001AAA',
            LastName = 'Test Contact',
            TR1__Batch_ID__c = 'OLD_BATCH',
            Last_Evertime_Sync__c = System.now().addDays(-1)
        );

        Contact newContact =
            oldContact.clone(false, true, false, false);

        newContact.Id = oldContact.Id;
        newContact.TR1__Batch_ID__c = 'NEW_BATCH';

        Map<Id, SObject> oldMap = new Map<Id, SObject>{
            oldContact.Id => oldContact
        };

        Test.startTest();

        EvertimeSyncUtility.process(
            new List<SObject>{ newContact },
            oldMap
        );

        Test.stopTest();

        System.assertNotEquals(
            null,
            newContact.Evertime_Sync_Required__c,
            'Contact should be marked when an Evertime field changes.'
        );
    }


    /**
     * Test 8:
     * Verify that an object which is not configured
     * does not cause an exception or update.
     */
    @IsTest
    static void testUnsupportedObject() {

        Lead oldLead = new Lead(
            Id = '00Q000000000001AAA',
            LastName = 'Test Lead',
            Company = 'Test Company'
        );

        Lead newLead =
            oldLead.clone(false, true, false, false);

        newLead.Id = oldLead.Id;
        newLead.LastName = 'Updated Lead';

        Map<Id, SObject> oldMap = new Map<Id, SObject>{
            oldLead.Id => oldLead
        };

        Test.startTest();

        EvertimeSyncUtility.process(
            new List<SObject>{ newLead },
            oldMap
        );

        Test.stopTest();

        System.assertEquals(
            'Updated Lead',
            newLead.LastName,
            'Unsupported objects should be ignored by the utility.'
        );
    }
}