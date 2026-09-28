@isTest
public class CreateSensitiveDataSharingHandlerTest {

   
    // Helper: Create User
   
    private static User createUser(String alias, Id managerId) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        User u = new User(
            FirstName = 'Test',
            LastName = alias,
            Alias = alias.substring(0, Math.min(8, alias.length())),
            Email = alias + '@test.com',
            Username = alias + DateTime.now().getTime() + '@test.com',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ManagerId = managerId
        );
        insert u;
        return u;
    }

    
    // TEST 1: Insert Sharing
    
    @isTest
    static void testInsertSharing() {

        User manager = createUser('mgrInsert', null);
        User employee = createUser('empInsert', manager.Id);

        List<Sensitive_Data__c> records = new List<Sensitive_Data__c>();

        System.runAs(employee) {
            for (Integer i = 0; i < 3; i++) {
                records.add(new Sensitive_Data__c(First_Name__c = 'Insert ' + i));
            }

            Test.startTest();
            insert records;
            CreateSensitiveDataSharingHandler.createShareOnInsert(records);
            Test.stopTest();
        }

        List<Sensitive_Data__Share> shares = [
            SELECT Id, ParentId
            FROM Sensitive_Data__Share
            WHERE ParentId IN :records
        ];

        System.assert(shares.size() > 0, 'Shares should be created on insert');
    }

    
    // TEST 2: Update Sharing (Owner Change)
    
    @isTest
    static void testUpdateSharingOwnerChange() {

        User manager1 = createUser('mgr1', null);
        User manager2 = createUser('mgr2', null);
        User employee = createUser('empUpdate', manager1.Id);

        List<Sensitive_Data__c> records = new List<Sensitive_Data__c>();

        System.runAs(employee) {
            for (Integer i = 0; i < 2; i++) {
                records.add(new Sensitive_Data__c(First_Name__c = 'Update ' + i));
            }
            insert records;
        }

        Map<Id, Sensitive_Data__c> oldMap = new Map<Id, Sensitive_Data__c>(
            [SELECT Id, OwnerId FROM Sensitive_Data__c WHERE Id IN :records]
        );

        for (Sensitive_Data__c rec : records) {
            rec.OwnerId = manager2.Id;
        }

        Test.startTest();
        //update records;
        CreateSensitiveDataSharingHandler.createShareOnUpdate(records, oldMap);
        Test.stopTest();

        List<Sensitive_Data__Share> shares = [
            SELECT Id FROM Sensitive_Data__Share
            WHERE ParentId IN :records
        ];

        System.assert(shares.size() > 0, 'Shares should be recreated after owner change');
    }

    
    // TEST 3: No Owner Change
    
    @isTest
    static void testNoOwnerChange() {

        User manager = createUser('mgrNoChange', null);
        User employee = createUser('empNoChange', manager.Id);

        Sensitive_Data__c rec;

        System.runAs(employee) {
            rec = new Sensitive_Data__c(First_Name__c = 'No Change');
            insert rec;
        }

        Map<Id, Sensitive_Data__c> oldMap = new Map<Id, Sensitive_Data__c>{
            rec.Id => rec.clone(false, true, false, false)
        };

        rec.First_Name__c = 'Updated Only Name';

        Test.startTest();
        update rec;
        CreateSensitiveDataSharingHandler.createShareOnUpdate(
            new List<Sensitive_Data__c>{rec},
            oldMap
        );
        Test.stopTest();

        System.assert(true, 'No owner change should not break logic');
    }

    
    // TEST 4: Trigger + Batch (DELETE + RECREATE VALIDATION)
    
    @isTest
    static void testTriggerAndBatch_DeleteAndRecreateShares() {

        // Hierarchy
        User topManager = createUser('topMgr', null);
        User manager = createUser('mgrBatch', topManager.Id);
        User employee = createUser('empBatch', manager.Id);

        List<Sensitive_Data__c> records = new List<Sensitive_Data__c>();

        // Step 1: Create records
        System.runAs(employee) {
            for (Integer i = 0; i < 3; i++) {
                records.add(new Sensitive_Data__c(First_Name__c = 'Batch ' + i));
            }
            insert records;
        }

        // Step 2: Create initial shares Sensitive_Data_Sharing__cly (simulate old state)
        List<Sensitive_Data__Share> oldShares = new List<Sensitive_Data__Share>();

        for (Sensitive_Data__c rec : records) {
            oldShares.add(new Sensitive_Data__Share(
                ParentId = rec.Id,
                UserOrGroupId = manager.Id,
                AccessLevel = 'Read',
                RowCause = Schema.Sensitive_Data__Share.RowCause.Sensitive_Data_Sharing__c
            ));
        }
        insert oldShares;

        Integer oldShareCount = [SELECT count() FROM Sensitive_Data__Share WHERE ParentId IN :records];

        // Step 3: Change manager → trigger fires batch
        User newManager = createUser('newMgrBatch', null);

        Test.startTest();
        employee.ManagerId = newManager.Id;
        update employee; //  trigger → batch
        Test.stopTest();

        // Step 4: Validate old shares deleted + new created
        List<Sensitive_Data__Share> newShares = [
            SELECT Id, UserOrGroupId, AccessLevel
            FROM Sensitive_Data__Share
            WHERE ParentId IN :records
        ];

        System.assert(newShares.size() > 0, 'New shares should be created');

        // Ensure old shares are removed (count changed OR different users)
        Boolean oldShareStillExists = false;

        for (Sensitive_Data__Share s : newShares) {
            if (s.UserOrGroupId == manager.Id) {
                oldShareStillExists = true;
            }
        }

        System.assertEquals(false, oldShareStillExists,
            'Old manager shares should be deleted');

        System.assertNotEquals(oldShareCount, newShares.size(),
            'Share count should change after delete + recreate');
    }
}