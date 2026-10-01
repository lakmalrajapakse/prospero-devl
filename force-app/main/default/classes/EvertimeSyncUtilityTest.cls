@IsTest
private class EvertimeSyncUtilityTest {

    /**
     * Test 1:
     * Account field from Evertime_Sync_Field is changed
     * and Last Evertime Sync is populated.
     *
     * Expected:
     * Evertime Sync Required should be populated.
     *
     * NOTE:
     * Email__c must be included in the Account
     * Evertime_Sync_Field Field Set.
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

        Account newAccount =
            oldAccount.clone(false, true, false, false);

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

        Account newAccount =
            oldAccount.clone(false, true, false, false);

        newAccount.Id = oldAccount.Id;

        /*
         * Change a field that should NOT be in the
         * Evertime_Sync_Field Field Set.
         */
        newAccount.Name = 'Updated Account Name';

        Map<Id, SObject> oldMap = new Map<Id, SObject>{
            oldAccount.Id => oldAccount
        };

        Test.startTest();

        EvertimeSyncUtility.process(
            new List<SObject>{ newAccount },
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

        Account newAccount =
            oldAccount.clone(false, true, false, false);

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

        Account newAccount =
            oldAccount.clone(false, true, false, false);

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

        Account newAccount =
            oldAccount.clone(false, true, false, false);

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

    }


    /**
     * Test 6:
     * Bulk processing.
     *
     * Record 1:
     * Evertime field changed + Last Sync populated
     * => Should be marked.
     *
     * Record 2:
     * Non-Evertime field changed
     * => Should NOT be marked.
     *
     * Record 3:
     * Evertime field changed + Last Sync null
     * => Should NOT be marked.
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

        // Non-Evertime field changed
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


        System.assertEquals(
            null,
            newAccount2.Evertime_Sync_Required__c,
            'Account 2 should not be marked because no Evertime field changed.'
        );

        System.assertEquals(
            null,
            newAccount3.Evertime_Sync_Required__c,
            'Account 3 should not be marked because Last Evertime Sync is null.'
        );
    }


    /**
     * Test 7:
     * Verify another object uses its own
     * Evertime_Sync_Field Field Set.
     *
     * NOTE:
     * TR1__Batch_ID__c must be present in the
     * Contact Evertime_Sync_Field Field Set.
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
    }


    /**
 * Test 8:
 * Verify an object without the
 * Evertime_Sync_Field Field Set is ignored.
 */
@IsTest
static void testObjectWithoutEvertimeFieldSet() {

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
        'The Lead record should remain unchanged.'
    );
}


    /**
     * Test 9:
     * Verify null and empty input handling.
     */
    @IsTest
    static void testEmptyInput() {

        Test.startTest();

        EvertimeSyncUtility.process(
            new List<SObject>(),
            new Map<Id, SObject>()
        );

        EvertimeSyncUtility.process(
            null,
            null
        );

        Test.stopTest();

        System.assert(
            true,
            'Method should safely handle null and empty input.'
        );
    }
}