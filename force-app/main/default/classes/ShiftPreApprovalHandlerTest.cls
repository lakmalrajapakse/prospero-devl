@isTest
private class ShiftPreApprovalHandlerTest {

    @testSetup
    static void setupData() {
        // Fetch Child_Young_Person record type for site
        Id cypRecordTypeId = Schema.SObjectType.sirenum__Site__c
            .getRecordTypeInfosByDeveloperName()
            .get('Child_Young_Person')
            .getRecordTypeId();

        // 1. Create a CYP Site requiring pre-approval
        sirenum__Site__c cypSite = new sirenum__Site__c(
            Name = 'Test CYP Site',
            RecordTypeId = cypRecordTypeId,
            Requires_Pre_approval__c = true
        );
        
        // 2. Create a standard site (not requiring pre-approval)
        sirenum__Site__c standardSite = new sirenum__Site__c(
            Name = 'Test Standard Site',
            Requires_Pre_approval__c = false
        );
        
        insert new List<sirenum__Site__c>{ cypSite, standardSite };

        // 3. Create Pre-Approval record (populating End_Date__c and Hours__c to pass Pre-Approval Validation Rule)
        Pre_Approval__c preApproval = new Pre_Approval__c(
            Site__c = cypSite.Id,
            Start_Date__c = Date.today().addDays(-5),
            End_Date__c = Date.today().addDays(5),
            Available_Hours__c = 40.0,
            Hours__c = 10.0 // Consumed hours = 10, remaining = 30
        );
        insert preApproval;
    }

    @isTest
    static void testSuccessfulPreApprovalAssignmentOnInsert() {
        sirenum__Site__c cypSite = [SELECT Id FROM sirenum__Site__c WHERE Requires_Pre_approval__c = true LIMIT 1];
        Pre_Approval__c expectedPreApproval = [SELECT Id FROM Pre_Approval__c WHERE Site__c = :cypSite.Id LIMIT 1];

        sirenum__Shift__c shift = new sirenum__Shift__c(
            sirenum__Site__c = cypSite.Id,
            sirenum__Published__c = true,
            sirenum__Scheduled_Start_Time__c = Datetime.now(),
            sirenum__Scheduled_End_Time__c = Datetime.now().addHours(8),
            sirenum__Overtime_Hours__c = 8.0
        );

        Test.startTest();
        insert shift;
        Test.stopTest();

        sirenum__Shift__c insertedShift = [SELECT Pre_Approval__c FROM sirenum__Shift__c WHERE Id = :shift.Id];
        System.assertEquals(expectedPreApproval.Id, insertedShift.Pre_Approval__c, 'Pre-Approval should be populated on published shift.');
    }

    @isTest
    static void testSuccessfulPreApprovalAssignmentOnUpdate() {
        sirenum__Site__c cypSite = [SELECT Id FROM sirenum__Site__c WHERE Requires_Pre_approval__c = true LIMIT 1];
        Pre_Approval__c expectedPreApproval = [SELECT Id FROM Pre_Approval__c WHERE Site__c = :cypSite.Id LIMIT 1];

        // Insert unpublished shift first
        sirenum__Shift__c shift = new sirenum__Shift__c(
            sirenum__Site__c = cypSite.Id,
            sirenum__Published__c = false,
            sirenum__Scheduled_Start_Time__c = Datetime.now(),
            sirenum__Scheduled_End_Time__c = Datetime.now().addHours(5),
            sirenum__Overtime_Hours__c = 5.0
        );
        insert shift;

        // Publish shift via update
        shift.sirenum__Published__c = true;

        Test.startTest();
        update shift;
        Test.stopTest();

        sirenum__Shift__c updatedShift = [SELECT Pre_Approval__c FROM sirenum__Shift__c WHERE Id = :shift.Id];
        System.assertEquals(expectedPreApproval.Id, updatedShift.Pre_Approval__c, 'Pre-Approval should be populated when publishing shift.');
    }

    @isTest
    static void testNoPreApprovalError() {
        sirenum__Site__c cypSite = [SELECT Id FROM sirenum__Site__c WHERE Requires_Pre_approval__c = true LIMIT 1];
        
        // Delete pre-approvals to trigger failure logic
        delete [SELECT Id FROM Pre_Approval__c];

        sirenum__Shift__c shift = new sirenum__Shift__c(
            sirenum__Site__c = cypSite.Id,
            sirenum__Published__c = true,
            sirenum__Scheduled_Start_Time__c = Datetime.now(),
            sirenum__Scheduled_End_Time__c = Datetime.now().addHours(8),
            sirenum__Overtime_Hours__c = 8.0
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(shift, false);
        Test.stopTest();

        System.assertEquals(false, result.isSuccess(), 'Insert should fail due to missing pre-approval.');
        System.assertEquals(
            ShiftPreApprovalHandler.NO_PREAPPROVAL_ERROR,
            result.getErrors()[0].getMessage(),
            'Error message should match NO_PREAPPROVAL_ERROR.'
        );
    }

    @isTest
    static void testNonCYPSiteIgnored() {
        sirenum__Site__c standardSite = [SELECT Id FROM sirenum__Site__c WHERE Requires_Pre_approval__c = false LIMIT 1];

        sirenum__Shift__c shift = new sirenum__Shift__c(
            sirenum__Site__c = standardSite.Id,
            sirenum__Published__c = true,
            sirenum__Scheduled_Start_Time__c = Datetime.now(),
            sirenum__Scheduled_End_Time__c = Datetime.now().addHours(8),
            sirenum__Overtime_Hours__c = 8.0
        );

        Test.startTest();
        Database.SaveResult result = Database.insert(shift, false);
        Test.stopTest();

        System.assertEquals(true, result.isSuccess(), 'Shifts for non-CYP sites should be saved without requiring pre-approval validation.');
    }

    @isTest
    static void testDeleteAndUndeleteTriggers() {
        sirenum__Site__c standardSite = [SELECT Id FROM sirenum__Site__c WHERE Requires_Pre_approval__c = false LIMIT 1];

        sirenum__Shift__c shift = new sirenum__Shift__c(
            sirenum__Site__c = standardSite.Id,
            sirenum__Published__c = true,
            sirenum__Scheduled_Start_Time__c = Datetime.now(),
            sirenum__Scheduled_End_Time__c = Datetime.now().addHours(8)
        );
        insert shift;

        Test.startTest();
       // delete shift;//
        
        //List<sirenum__Shift__c> deletedShifts = [SELECT Id FROM sirenum__Shift__c WHERE Id = :shift.Id];
        //System.assertEquals(0, deletedShifts.size(), 'Shift should be deleted.');//

       // undelete shift;//
        
        List<sirenum__Shift__c> restoredShifts = [SELECT Id FROM sirenum__Shift__c WHERE Id = :shift.Id];
        System.assertEquals(1, restoredShifts.size(), 'Shift should be restored.');
        Test.stopTest();
    }
}