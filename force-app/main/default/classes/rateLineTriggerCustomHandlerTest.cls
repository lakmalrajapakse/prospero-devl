@isTest
private class rateLineTriggerCustomHandlerTest {

    private class TestContext {
        Account client;
        Contact worker;
        sirenum__Team__c jobRole;
        Rate_Agreements__c rateAgreement;
        sirenum__ProActiveContract__c contract;
        Rate_Agreement_Scale_Definition__c scaleDefinition;
        Job_Role_Scale__c jobRoleScale;
        Rate_Agreement_Version__c version;
        Rate_Agreement_Scale__c scale;
        sirenum__Rate_Card__c rateCard;
        sirenum__Placement__c placement;
        sirenum__Rate_Card_Page__c page;
    }

    private static Integer uniqueCounter = 0;

    private static String uniqueSuffix(){
        uniqueCounter++;
        return String.valueOf(Datetime.now().getTime()) + '-' + uniqueCounter;
    }

    private static TestContext buildBaseContext(){
        return buildBaseContext(true);
    }

    private static TestContext buildBaseContext(Boolean withScale){
        TestContext ctx = new TestContext();
        String suffix = uniqueSuffix();

        Team__c team = new Team__c(Name = 'Test Team ' + suffix);
        insert team;

        ctx.client = new Account(Name = 'Test Client ' + suffix, RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Prospero_Client').getRecordTypeId(), Health_Social_Care_Type__c = 'Local Authority', Team__c = team.Id, BillingStreet = '1 Test Street', BillingCity = 'Test City', BillingPostalCode = 'TE1 1ST', BillingCountry = 'United Kingdom');
        insert ctx.client;

        ctx.worker = new Contact(LastName = 'Worker ' + suffix, AccountId = ctx.client.Id, Team__c = team.Id, Worker_Type_Payroll_Provider__c = 'Pay As You Earn');
        insert ctx.worker;

        ctx.rateAgreement = new Rate_Agreements__c();
        insert ctx.rateAgreement;

        ctx.contract = new sirenum__ProActiveContract__c(sirenum__Client__c = ctx.client.Id, Rate_Agreements__c = ctx.rateAgreement.Id);
        insert ctx.contract;

        ctx.jobRole = new sirenum__Team__c(sirenum__Account__c = ctx.contract.Id);
        insert ctx.jobRole;

        ctx.scaleDefinition = new Rate_Agreement_Scale_Definition__c(Rate_Agreements__c = ctx.rateAgreement.Id, Region__c = 'UK', Description__c = 'Scale 1', Ranking__c = 1);
        insert ctx.scaleDefinition;

        ctx.jobRoleScale = new Job_Role_Scale__c(Job_Role__c = ctx.jobRole.Id, Rate_Agreement_Scale_Definition__c = ctx.scaleDefinition.Id);
        insert ctx.jobRoleScale;

        ctx.version = new Rate_Agreement_Version__c(Rate_Agreement__c = ctx.rateAgreement.Id, Effective_Date__c = Date.newInstance(2024, 1, 1));
        insert ctx.version;

        ctx.scale = new Rate_Agreement_Scale__c(Rate_Agreement_Version__c = ctx.version.Id, Rate_Agreement_Scale_Definition__c = ctx.scaleDefinition.Id, Min_Amount__c = 10, Max_Amount__c = 100);
        insert ctx.scale;

        attachPlacement(ctx, ctx.contract, withScale ? ctx.jobRoleScale : null);

        return ctx;
    }

    private static void attachPlacement(TestContext ctx, sirenum__ProActiveContract__c contract, Job_Role_Scale__c jobRoleScale){
        ctx.rateCard = new sirenum__Rate_Card__c();
        insert ctx.rateCard;

        Team__c jobTeam = new Team__c(Name = 'Test Job Team ' + uniqueSuffix());
        insert jobTeam;

        TR1__Job__c job = new TR1__Job__c(Team__c = jobTeam.Id, TR1__Account__c = ctx.client.Id, s5m__Contract__c = contract.Id, Job_Role_Scale__c = jobRoleScale == null ? null : jobRoleScale.Id);
        insert job;

        ctx.placement = new sirenum__Placement__c(sirenum__Contact__c = ctx.worker.Id, sirenum__Job_Role__c = ctx.jobRole.Id, sirenum__Start_Date__c = Date.newInstance(2024, 1, 1), sirenum__Rate_Card__c = ctx.rateCard.Id, sirenum__Contract__c = contract.Id, Job_Role_Scale__c = jobRoleScale == null ? null : jobRoleScale.Id, Job__c = job.Id);
        insert ctx.placement;

        if(jobRoleScale != null){
            ctx.placement = [SELECT Id, Job_Role_Scale__c FROM sirenum__Placement__c WHERE Id = :ctx.placement.Id];
            if(ctx.placement.Job_Role_Scale__c == null){
                ctx.placement.Job_Role_Scale__c = jobRoleScale.Id;
                update ctx.placement;
            }
        }

        ctx.page = new sirenum__Rate_Card_Page__c(sirenum__Rate_Card__c = ctx.rateCard.Id, sirenum__SortOrder__c = 1, sirenum__Condition_Field__c = 'Test', sirenum__Condition_value__c = 'Test', sirenum__Valid_From_Date__c = Date.newInstance(2024, 6, 1));
        insert ctx.page;
    }

    private static Rate_Agreement_Lines__c addLine(Rate_Agreement_Version__c version, String calcType, Decimal marginValue, String workerType){
        Rate_Agreement_Lines__c line = new Rate_Agreement_Lines__c(Rate_Agreement_Version__c = version.Id, Calc_Type__c = calcType, Margin_Value__c = marginValue, Worker_Type__c = workerType);
        insert line;
        return line;
    }

    private static void addEmployerOnCost(Rate_Agreement_Version__c version, Rate_Agreement_Lines__c line, String calcType, Decimal value, String workerType){
        insert new Employer_On_Cost__c(Rate_Agreement_Version__c = version.Id, Rate_Agreement_Lines__c = line.Id, Type__c = 'Record Agreement Line', On_Cost_Type__c = 'NI', Calc_Type__c = calcType, Value__c = value, Worker_Type__c = workerType);
    }

    private static sirenum__Rate_Modifier_Type__c buildModifierType(){
        sirenum__Rate_Modifier_Type__c modifierType = new sirenum__Rate_Modifier_Type__c(sirenum__Condition_Field__c = 'Test', sirenum__Condition_value__c = 'Test', sirenum__SortOrder__c = 1);
        insert modifierType;
        return modifierType;
    }

    // Verifies a Rate Line saves when the margin is within the allowed limit.
    @isTest
    static void testRateLine_PassesWhenMarginWithinBounds(){
        TestContext ctx = buildBaseContext();
        Rate_Agreement_Lines__c line = addLine(ctx.version, 'Max Margin %', 50, null);
        addEmployerOnCost(ctx.version, line, 'Percent', 10, null);

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(sirenum__Rate_Card_Page__c = ctx.page.Id, sirenum__SortOrder__c = 1, sirenum__Pay_Rate__c = 50, sirenum__Charge_Rate__c = 70);

        Test.startTest();
        insert rateLine;
        Test.stopTest();

        System.assertNotEquals(null, rateLine.Id, 'Rate Line within margin bounds should save successfully');
    }

    // Verifies a Rate Line is rejected when the margin exceeds the maximum.
    @isTest
    static void testRateLine_FailsWhenMarginExceedsMax(){
        TestContext ctx = buildBaseContext();
        Rate_Agreement_Lines__c line = addLine(ctx.version, 'Max Margin %', 50, null);
        addEmployerOnCost(ctx.version, line, 'Percent', 10, null);

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(sirenum__Rate_Card_Page__c = ctx.page.Id, sirenum__SortOrder__c = 1, sirenum__Pay_Rate__c = 50, sirenum__Charge_Rate__c = 200);

        Test.startTest();
        DmlException caught;
        try {
            insert rateLine;
        } catch(DmlException e){
            caught = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, 'Expected the insert to be blocked by the margin validation');
        System.assert(caught.getMessage().contains('exceeds the maximum allowed margin'), caught.getMessage());
    }

    // Verifies validation is skipped when the Contract has no Rate Agreement.
    @isTest
    static void testRateLine_SkipsValidationWhenContractHasNoRateAgreement(){
        TestContext ctx = buildBaseContext();

        sirenum__ProActiveContract__c contractWithoutAgreement = new sirenum__ProActiveContract__c(sirenum__Client__c = ctx.client.Id);
        insert contractWithoutAgreement;

        addLine(ctx.version, 'Max Margin %', 50, null);
        attachPlacement(ctx, contractWithoutAgreement, ctx.jobRoleScale);

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(sirenum__Rate_Card_Page__c = ctx.page.Id, sirenum__SortOrder__c = 1, sirenum__Pay_Rate__c = 50, sirenum__Charge_Rate__c = 70);

        Test.startTest();
        insert rateLine;
        Test.stopTest();

        System.assertNotEquals(null, rateLine.Id, 'Placement not linked to a Rate Agreement should skip validation, not block the save');
    }

    // Verifies a Rate Line is rejected when the Placement has no Rate Agreement Scale Definition.
    @isTest
    static void testRateLine_FailsWhenPlacementMissingScaleDefinition(){
        TestContext ctx = buildBaseContext(false);

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(sirenum__Rate_Card_Page__c = ctx.page.Id, sirenum__SortOrder__c = 1, sirenum__Pay_Rate__c = 50, sirenum__Charge_Rate__c = 70);

        Test.startTest();
        DmlException caught;
        try {
            insert rateLine;
        } catch(DmlException e){
            caught = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, 'Expected the insert to be blocked');
        System.assert(caught.getMessage().contains('missing Rate Agreement Scale Definition'), caught.getMessage());
    }

    // Verifies a Rate Line is rejected when the Pay Rate is outside the Scale range.
    @isTest
    static void testRateLine_FailsWhenPayRateOutsideScale(){
        TestContext ctx = buildBaseContext();
        addLine(ctx.version, 'Max Margin %', 50, null);

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(sirenum__Rate_Card_Page__c = ctx.page.Id, sirenum__SortOrder__c = 1, sirenum__Pay_Rate__c = 500, sirenum__Charge_Rate__c = 600);

        Test.startTest();
        DmlException caught;
        try {
            insert rateLine;
        } catch(DmlException e){
            caught = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, 'Expected the insert to be blocked');
        System.assert(caught.getMessage().contains('is outside the allowed range'), caught.getMessage());
    }

    // Verifies a Rate Line is rejected when no applicable Rate Agreement Line exists.
    @isTest
    static void testRateLine_FailsWhenNoApplicableRateAgreementLine(){
        TestContext ctx = buildBaseContext();
        addLine(ctx.version, 'Max Margin %', 50, 'Umbrella');

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(sirenum__Rate_Card_Page__c = ctx.page.Id, sirenum__SortOrder__c = 1, sirenum__Pay_Rate__c = 50, sirenum__Charge_Rate__c = 70);

        Test.startTest();
        DmlException caught;
        try {
            insert rateLine;
        } catch(DmlException e){
            caught = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, 'Expected the insert to be blocked');
        System.assert(caught.getMessage().contains('No applicable Rate Agreement Line was found'), caught.getMessage());
    }

    // Verifies a Rate Modifier saves when the margin is within the allowed limit.
    @isTest
    static void testRateModifier_PassesWhenMarginWithinBounds(){
        TestContext ctx = buildBaseContext();
        Rate_Agreement_Lines__c line = addLine(ctx.version, 'Max Margin %', 50, null);
        addEmployerOnCost(ctx.version, line, 'Percent', 10, null);
        sirenum__Rate_Modifier_Type__c modifierType = buildModifierType();

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(sirenum__Rate_Card_Page__c = ctx.page.Id, sirenum__SortOrder__c = 1, sirenum__Pay_Rate__c = 50, sirenum__Charge_Rate__c = 70);
        insert rateLine;

        sirenum__Rate_Modifier__c modifier = new sirenum__Rate_Modifier__c(sirenum__Rate_Line__c = rateLine.Id, sirenum__Rate_Modifier_Type__c = modifierType.Id, sirenum__Pay_Rate__c = 50, sirenum__Charge_Rate__c = 70);

        Test.startTest();
        insert modifier;
        Test.stopTest();

        System.assertNotEquals(null, modifier.Id, 'Rate Modifier within margin bounds should save successfully');
    }

    // Verifies a Rate Modifier is rejected when the margin exceeds the maximum.
    @isTest
    static void testRateModifier_FailsWhenMarginExceedsMax(){
        TestContext ctx = buildBaseContext();
        Rate_Agreement_Lines__c line = addLine(ctx.version, 'Max Margin %', 50, null);
        addEmployerOnCost(ctx.version, line, 'Percent', 10, null);
        sirenum__Rate_Modifier_Type__c modifierType = buildModifierType();

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(sirenum__Rate_Card_Page__c = ctx.page.Id, sirenum__SortOrder__c = 1, sirenum__Pay_Rate__c = 50, sirenum__Charge_Rate__c = 70);
        insert rateLine;

        sirenum__Rate_Modifier__c modifier = new sirenum__Rate_Modifier__c(sirenum__Rate_Line__c = rateLine.Id, sirenum__Rate_Modifier_Type__c = modifierType.Id, sirenum__Pay_Rate__c = 50, sirenum__Charge_Rate__c = 200);

        Test.startTest();
        DmlException caught;
        try {
            insert modifier;
        } catch(DmlException e){
            caught = e;
        }
        Test.stopTest();

        System.assertNotEquals(null, caught, 'Expected the insert to be blocked by the margin validation');
        System.assert(caught.getMessage().contains('exceeds the maximum allowed margin'), caught.getMessage());
    }

    // Verifies bulk insert handles passing and failing Rate Lines independently.
    @isTest
    static void testRateLine_BulkInsertHandlesMixedPassAndFailIndependently(){
        TestContext ctx = buildBaseContext();
        Rate_Agreement_Lines__c line = addLine(ctx.version, 'Max Margin %', 50, null);
        addEmployerOnCost(ctx.version, line, 'Percent', 10, null);

        sirenum__Rate_Card_Page__c firstPage = ctx.page;
        attachPlacement(ctx, ctx.contract, ctx.jobRoleScale);
        sirenum__Rate_Card_Page__c secondPage = ctx.page;

        sirenum__Rate_Line__c passingLine = new sirenum__Rate_Line__c(sirenum__Rate_Card_Page__c = firstPage.Id, sirenum__SortOrder__c = 1, sirenum__Pay_Rate__c = 50, sirenum__Charge_Rate__c = 70);
        sirenum__Rate_Line__c failingLine = new sirenum__Rate_Line__c(sirenum__Rate_Card_Page__c = secondPage.Id, sirenum__SortOrder__c = 1, sirenum__Pay_Rate__c = 50, sirenum__Charge_Rate__c = 200);

        Test.startTest();
        Database.SaveResult[] results = Database.insert(new List<sirenum__Rate_Line__c>{ passingLine, failingLine }, false);
        Test.stopTest();

        System.assert(results[0].isSuccess(), 'First Rate Line should have saved: ' + results[0].getErrors());
        System.assert(!results[1].isSuccess(), 'Second Rate Line should have been rejected for exceeding the margin');
        System.assert(results[1].getErrors()[0].getMessage().contains('exceeds the maximum allowed margin'), results[1].getErrors()[0].getMessage());
    }
}