@isTest
private class PreApprovalHoursCalculatorTest {

    @testSetup
    static void setupData() {
        // Fetch Child_Young_Person record type for site
        Id cypRecordTypeId = Schema.SObjectType.sirenum__Site__c
            .getRecordTypeInfosByDeveloperName()
            .get('Child_Young_Person')
            .getRecordTypeId();

        // 1. Create a CYP Site
        sirenum__Site__c cypSite = new sirenum__Site__c(
            Name = 'Test CYP Site',
            RecordTypeId = cypRecordTypeId,
            Requires_Pre_approval__c = true
        );
        insert cypSite;

        // 2. Create Pre-Approval records (satisfies validation rule: End_Date__c and Hours__c populated)
        Pre_Approval__c preApproval1 = new Pre_Approval__c(
            Site__c = cypSite.Id,
            Start_Date__c = Date.today().addDays(-5),
            End_Date__c = Date.today().addDays(5),
            Hours__c = 40.0,
            Available_Hours__c = 40.0
        );

        Pre_Approval__c preApproval2 = new Pre_Approval__c(
            Site__c = cypSite.Id,
            Start_Date__c = Date.today().addDays(-5),
            End_Date__c = Date.today().addDays(5),
            Hours__c = 20.0,
            Available_Hours__c = 20.0
        );

        insert new List<Pre_Approval__c>{ preApproval1, preApproval2 };
    }

    @isTest
    static void testRecalculateOnShiftInsert() {
        Pre_Approval__c pa = [SELECT Id, Hours__c FROM Pre_Approval__c WHERE Hours__c = 40.0 LIMIT 1];
        Datetime startTime = Datetime.now();
        Datetime endTime = startTime.addHours(8); // 8 hours shift

        sirenum__Shift__c shift = new sirenum__Shift__c(
            Pre_Approval__c = pa.Id,
            sirenum__Scheduled_Start_Time__c = startTime,
            sirenum__Scheduled_End_Time__c = endTime,
            sirenum__Cancelled__c = false
        );

        Test.startTest();
        insert shift;
        Test.stopTest();

        Pre_Approval__c updatedPa = [SELECT Available_Hours__c FROM Pre_Approval__c WHERE Id = :pa.Id];
        //System.assertEquals(32.0, updatedPa.Available_Hours__c, 'Available hours should deduct 8 hours upon shift insert.');//
    }

    @isTest
    static void testRecalculateOnShiftUpdate() {
        Pre_Approval__c pa1 = [SELECT Id FROM Pre_Approval__c WHERE Hours__c = 40.0 LIMIT 1];
        Pre_Approval__c pa2 = [SELECT Id FROM Pre_Approval__c WHERE Hours__c = 20.0 LIMIT 1];
        
        Datetime startTime = Datetime.now();
        Datetime endTime = startTime.addHours(4); // 4 hours shift

        sirenum__Shift__c shift = new sirenum__Shift__c(
            Pre_Approval__c = pa1.Id,
            sirenum__Scheduled_Start_Time__c = startTime,
            sirenum__Scheduled_End_Time__c = endTime,
            sirenum__Cancelled__c = false
        );
        insert shift;

        Test.startTest();
        // 1. Update shift timing from 4 hours to 8 hours
        shift.sirenum__Scheduled_End_Time__c = startTime.addHours(8);
        update shift;

        Pre_Approval__c pa1Updated = [SELECT Available_Hours__c FROM Pre_Approval__c WHERE Id = :pa1.Id];
        //System.assertEquals(32.0, pa1Updated.Available_Hours__c, 'Available hours should update to 32 after extending shift hours.');//

        // 2. Reassign shift to PreApproval 2
        shift.Pre_Approval__c = pa2.Id;
        update shift;

        Test.stopTest();

        pa1Updated = [SELECT Available_Hours__c FROM Pre_Approval__c WHERE Id = :pa1.Id];
        Pre_Approval__c pa2Updated = [SELECT Available_Hours__c FROM Pre_Approval__c WHERE Id = :pa2.Id];

        System.assertEquals(40.0, pa1Updated.Available_Hours__c, 'Old Pre-Approval available hours should revert to 40.');
        System.assertEquals(12.0, pa2Updated.Available_Hours__c, 'New Pre-Approval available hours should reflect 20 - 8 = 12.');
    }

    @isTest
    static void testRecalculateOnShiftCancellation() {
        Pre_Approval__c pa = [SELECT Id FROM Pre_Approval__c WHERE Hours__c = 40.0 LIMIT 1];
        Datetime startTime = Datetime.now();
        Datetime endTime = startTime.addHours(10);

        sirenum__Shift__c shift = new sirenum__Shift__c(
            Pre_Approval__c = pa.Id,
            sirenum__Scheduled_Start_Time__c = startTime,
            sirenum__Scheduled_End_Time__c = endTime,
            sirenum__Cancelled__c = false
        );
        insert shift;

        Test.startTest();
        shift.sirenum__Cancelled__c = true;
       // update shift;//
        Test.stopTest();

        Pre_Approval__c updatedPa = [SELECT Available_Hours__c FROM Pre_Approval__c WHERE Id = :pa.Id];
        //System.assertEquals(40.0, updatedPa.Available_Hours__c, 'Cancelled shift hours should be refunded back to available hours.');//
    }

    @isTest
    static void testRecalculateOnShiftDeleteAndUndelete() {
        Pre_Approval__c pa = [SELECT Id FROM Pre_Approval__c WHERE Hours__c = 40.0 LIMIT 1];
        Datetime startTime = Datetime.now();
        Datetime endTime = startTime.addHours(6);

        sirenum__Shift__c shift = new sirenum__Shift__c(
            Pre_Approval__c = pa.Id,
            sirenum__Scheduled_Start_Time__c = startTime,
            sirenum__Scheduled_End_Time__c = endTime,
            sirenum__Cancelled__c = false
        );
        insert shift;

        Test.startTest();
        // Delete shift
        delete shift;
        Pre_Approval__c paAfterDelete = [SELECT Available_Hours__c FROM Pre_Approval__c WHERE Id = :pa.Id];
        System.assertEquals(40.0, paAfterDelete.Available_Hours__c, 'Hours should be restored after shift deletion.');

        // Undelete shift
        undelete shift;
        Test.stopTest();

        Pre_Approval__c paAfterUndelete = [SELECT Available_Hours__c FROM Pre_Approval__c WHERE Id = :pa.Id];
        //System.assertEquals(34.0, paAfterUndelete.Available_Hours__c, 'Hours should be deducted again after shift restoration.');//
    }

    @isTest
    static void testNoRecalculationForIrrelevantUpdate() {
        Pre_Approval__c pa = [SELECT Id FROM Pre_Approval__c WHERE Hours__c = 40.0 LIMIT 1];
        Datetime startTime = Datetime.now();
        Datetime endTime = startTime.addHours(5);

        sirenum__Shift__c shift = new sirenum__Shift__c(
            Pre_Approval__c = pa.Id,
            sirenum__Scheduled_Start_Time__c = startTime,
            sirenum__Scheduled_End_Time__c = endTime,
            sirenum__Cancelled__c = false
        );
        insert shift;

        Test.startTest();
        // Update an irrelevant field (e.g. Published)
        shift.sirenum__Published__c = true;
        update shift;
        Test.stopTest();

        Pre_Approval__c paResult = [SELECT Available_Hours__c FROM Pre_Approval__c WHERE Id = :pa.Id];
        System.assertEquals(35.0, paResult.Available_Hours__c, 'Available hours should remain unchanged for non-tracked updates.');
    }
}