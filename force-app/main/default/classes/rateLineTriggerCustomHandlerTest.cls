@isTest
private class rateLineTriggerCustomHandlerTest {

    // Bag of records shared across a scenario. buildBaseContext() wires up a fully passing
    // baseline (see its comment); individual tests mutate/extend from there.
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

    // Builds: Account -> Contact (PAYE) -> Team (Job Role) -> Rate Agreement -> Scale
    // Definition (Ranking 1) -> Job Role Scale -> Rate Agreement Version (effective
    // 2024-01-01) -> Rate Agreement Scale (10-100) -> Contract (linked to the Rate
    // Agreement) -> Placement -> Rate Card -> Rate Card Page (valid from 2024-06-01).
    // Callers add their own Rate_Agreement_Lines__c / Employer_On_Cost__c and Rate Line /
    // Rate Modifier records on top, since those vary per scenario.
    // Every call gets a fresh suffix so records inserted by different test methods (or multiple
    // times within one bulk test) never share a Name -- avoids any duplicate-rule/Flow lookup-by-
    // Name collision between otherwise-identical "Test Client"/"Test Team" style fixture records.
    private static Integer uniqueCounter = 0;
    private static String uniqueSuffix(){
        uniqueCounter++;
        return String.valueOf(Datetime.now().getTime()) + '-' + uniqueCounter;
    }

    private static TestContext buildBaseContext(){
        TestContext ctx = new TestContext();
        String suffix = uniqueSuffix();

        // A validation rule requires Account/Contact to carry a (standalone, non-namespaced)
        // Team__c lookup -- unrelated to sirenum__Team__c, which is the Job Role object below.
        Team__c team = new Team__c(Name = 'Test Team ' + suffix);
        insert team;

        // The "Prospero Client" record type validates that a Local Authority or Council lookup is
        // set, unless the Account is itself a Local Authority/Council. Mark it as a Local Authority
        // so the rule doesn't apply and no extra lookup records are needed.
        ctx.client = new Account(
            Name = 'Test Client ' + suffix,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Prospero_Client').getRecordTypeId(),
            Health_Social_Care_Type__c = 'Local Authority',
            Team__c = team.Id,
            BillingStreet = '1 Test Street',
            BillingCity = 'Test City',
            BillingPostalCode = 'TE1 1ST',
            BillingCountry = 'United Kingdom'
        );
        insert ctx.client;

        ctx.worker = new Contact(
            LastName = 'Worker ' + suffix,
            AccountId = ctx.client.Id,
            Team__c = team.Id,
            Worker_Type_Payroll_Provider__c = 'Pay As You Earn'
        );
        insert ctx.worker;

        ctx.jobRole = new sirenum__Team__c();
        insert ctx.jobRole;

        ctx.rateAgreement = new Rate_Agreements__c();
        insert ctx.rateAgreement;

        ctx.contract = new sirenum__ProActiveContract__c(
            sirenum__Client__c = ctx.client.Id,
            Rate_Agreements__c = ctx.rateAgreement.Id
        );
        insert ctx.contract;

        ctx.scaleDefinition = new Rate_Agreement_Scale_Definition__c(
            Rate_Agreements__c = ctx.rateAgreement.Id,
            Region__c = 'UK',
            Description__c = 'Scale 1',
            Ranking__c = 1
        );
        insert ctx.scaleDefinition;

        ctx.jobRoleScale = new Job_Role_Scale__c(
            Job_Role__c = ctx.jobRole.Id,
            Rate_Agreement_Scale_Definition__c = ctx.scaleDefinition.Id
        );
        insert ctx.jobRoleScale;

        ctx.version = new Rate_Agreement_Version__c(
            Rate_Agreement__c = ctx.rateAgreement.Id,
            Effective_Date__c = Date.newInstance(2024, 1, 1)
        );
        insert ctx.version;

        ctx.scale = new Rate_Agreement_Scale__c(
            Rate_Agreement_Version__c = ctx.version.Id,
            Rate_Agreement_Scale_Definition__c = ctx.scaleDefinition.Id,
            Min_Amount__c = 10,
            Max_Amount__c = 100
        );
        insert ctx.scale;

        attachPlacement(ctx, ctx.contract, ctx.jobRoleScale);

        return ctx;
    }

    // Creates a fresh Rate Card + Placement + Rate Card Page pointing at `contract`/`jobRoleScale`
    // and stores them on ctx. Always a NEW Rate Card, since a Rate Card maps to exactly one
    // Placement — reusing one across placements would silently overwrite the 1:1 lookup map
    // the handler builds.
    private static void attachPlacement(TestContext ctx, sirenum__ProActiveContract__c contract, Job_Role_Scale__c jobRoleScale){
        ctx.rateCard = new sirenum__Rate_Card__c();
        insert ctx.rateCard;

        // Placement.sirenum__Contract__c is populated from the Job's own Contract (mirrors
        // ShiftPlacementHandler: `newPlacement.sirenum__Contract__c = job.s5m__Contract__c;`) --
        // org automation derives it from Job__c rather than accepting a direct value on
        // Placement itself, so the Contract goes on the Job here, not on the Placement below.
        // Job itself is subject to the same "must add a Team" rule as Account/Contact.
        Team__c jobTeam = new Team__c(Name = 'Test Job Team ' + uniqueSuffix());
        insert jobTeam;
        // The lookup filter on s5m__Contract__c requires the Contract's Account to match the
        // Job's own Account (TR1__Account__c) -- so both need to point at the same client.
        TR1__Job__c job = new TR1__Job__c(
            Team__c = jobTeam.Id,
            TR1__Account__c = ctx.client.Id,
            s5m__Contract__c = contract.Id
        );
        insert job;

        ctx.placement = new sirenum__Placement__c(
            sirenum__Contact__c = ctx.worker.Id,
            sirenum__Job_Role__c = ctx.jobRole.Id,
            sirenum__Start_Date__c = Date.newInstance(2024, 1, 1),
            sirenum__Rate_Card__c = ctx.rateCard.Id,
            sirenum__Contract__c = contract.Id,
            Job_Role_Scale__c = jobRoleScale == null ? null : jobRoleScale.Id,
            Job__c = job.Id
        );
        insert ctx.placement;

        ctx.page = new sirenum__Rate_Card_Page__c(
            sirenum__Rate_Card__c = ctx.rateCard.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Valid_From_Date__c = Date.newInstance(2024, 6, 1)
        );
        insert ctx.page;
    }

    private static Rate_Agreement_Lines__c addLine(Rate_Agreement_Version__c version, String calcType, Decimal marginValue, String workerType){
        Rate_Agreement_Lines__c line = new Rate_Agreement_Lines__c(
            Rate_Agreement_Version__c = version.Id,
            Calc_Type__c = calcType,
            Margin_Value__c = marginValue,
            Worker_Type__c = workerType
        );
        insert line;
        return line;
    }

    private static void addEmployerOnCost(Rate_Agreement_Version__c version, Rate_Agreement_Lines__c line, String calcType, Decimal value, String workerType){
        insert new Employer_On_Cost__c(
            Rate_Agreement_Version__c = version.Id,
            Rate_Agreement_Lines__c = line.Id,
            Type__c = 'Record Agreement Line',
            On_Cost_Type__c = 'NI',
            Calc_Type__c = calcType,
            Value__c = value,
            Worker_Type__c = workerType
        );
    }

    private static sirenum__Rate_Modifier_Type__c buildModifierType(){
        sirenum__Rate_Modifier_Type__c modifierType = new sirenum__Rate_Modifier_Type__c(
            sirenum__Condition_Field__c = 'Test',
            sirenum__Condition_value__c = 'Test',
            sirenum__SortOrder__c = 1
        );
        insert modifierType;
        return modifierType;
    }

    // ---- Rate Line ----

    @isTest
    static void testRateLine_PassesWhenMarginWithinBounds(){
        TestContext ctx = buildBaseContext();
        Rate_Agreement_Lines__c line = addLine(ctx.version, 'Max Margin %', 50, null);
        addEmployerOnCost(ctx.version, line, 'Percent', 10, null); // 10% of Pay Rate

        // Pay 50, On Cost 10% = 5 -> Total Cost 55. Margin cap 50% -> max Charge = 55 * 1.5 = 82.50.
        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = ctx.page.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Pay_Rate__c = 50,
            sirenum__Charge_Rate__c = 70
        );

        Test.startTest();
        insert rateLine;
        Test.stopTest();

        System.assertNotEquals(null, rateLine.Id, 'Rate Line within margin bounds should save successfully');
    }

    @isTest
    static void testRateLine_FailsWhenMarginExceedsMax(){
        TestContext ctx = buildBaseContext();
        Rate_Agreement_Lines__c line = addLine(ctx.version, 'Max Margin %', 50, null);
        addEmployerOnCost(ctx.version, line, 'Percent', 10, null);

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = ctx.page.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Pay_Rate__c = 50,
            sirenum__Charge_Rate__c = 200 // well past the 50% margin cap
        );

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

    @isTest
    static void testRateLine_SkipsValidationWhenContractHasNoRateAgreement(){
        TestContext ctx = buildBaseContext();

        sirenum__ProActiveContract__c contractWithoutAgreement = new sirenum__ProActiveContract__c(
            sirenum__Client__c = ctx.client.Id
        );
        insert contractWithoutAgreement;

        attachPlacement(ctx, contractWithoutAgreement, ctx.jobRoleScale);

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = ctx.page.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Pay_Rate__c = 50,
            sirenum__Charge_Rate__c = 99999 // would badly fail margin if validation ran at all
        );

        Test.startTest();
        insert rateLine; // must not throw -- validation stops before the margin check
        Test.stopTest();

        System.assertNotEquals(null, rateLine.Id, 'Placement not linked to a Rate Agreement should skip validation, not block the save');
    }

    @isTest
    static void testRateLine_FailsWhenPlacementMissingScaleDefinition(){
        TestContext ctx = buildBaseContext();
        attachPlacement(ctx, ctx.contract, null); // no Job Role Scale on this placement

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = ctx.page.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Pay_Rate__c = 50,
            sirenum__Charge_Rate__c = 70
        );

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

    @isTest
    static void testRateLine_FailsWhenPayRateOutsideScale(){
        TestContext ctx = buildBaseContext(); // scale range is 10-100
        addLine(ctx.version, 'Max Margin %', 50, null);

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = ctx.page.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Pay_Rate__c = 500, // outside 10-100
            sirenum__Charge_Rate__c = 600
        );

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

    @isTest
    static void testRateLine_FailsWhenNoApplicableRateAgreementLine(){
        TestContext ctx = buildBaseContext();
        // Only an Umbrella-specific line exists; the test worker is PAYE and there is no
        // general (blank Worker Type) fallback line.
        addLine(ctx.version, 'Max Margin %', 50, 'Umbrella');

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = ctx.page.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Pay_Rate__c = 50,
            sirenum__Charge_Rate__c = 70
        );

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

    // ---- Rate Modifier: same handler pipeline, reused via validateRateModifier ----

    @isTest
    static void testRateModifier_PassesWhenMarginWithinBounds(){
        TestContext ctx = buildBaseContext();
        Rate_Agreement_Lines__c line = addLine(ctx.version, 'Max Margin %', 50, null);
        addEmployerOnCost(ctx.version, line, 'Percent', 10, null);
        sirenum__Rate_Modifier_Type__c modifierType = buildModifierType();

        // Parent Rate Line's own rate is irrelevant to the Modifier's validation -- the
        // Modifier carries its own Pay Rate / Charge Rate and is checked independently.
        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = ctx.page.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Pay_Rate__c = 50,
            sirenum__Charge_Rate__c = 70
        );
        insert rateLine;

        sirenum__Rate_Modifier__c modifier = new sirenum__Rate_Modifier__c(
            sirenum__Rate_Line__c = rateLine.Id,
            sirenum__Rate_Modifier_Type__c = modifierType.Id,
            sirenum__Pay_Rate__c = 50,
            sirenum__Charge_Rate__c = 70
        );

        Test.startTest();
        insert modifier;
        Test.stopTest();

        System.assertNotEquals(null, modifier.Id, 'Rate Modifier within margin bounds should save successfully');
    }

    @isTest
    static void testRateModifier_FailsWhenMarginExceedsMax(){
        TestContext ctx = buildBaseContext();
        Rate_Agreement_Lines__c line = addLine(ctx.version, 'Max Margin %', 50, null);
        addEmployerOnCost(ctx.version, line, 'Percent', 10, null);
        sirenum__Rate_Modifier_Type__c modifierType = buildModifierType();

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = ctx.page.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Pay_Rate__c = 50,
            sirenum__Charge_Rate__c = 70
        );
        insert rateLine;

        sirenum__Rate_Modifier__c modifier = new sirenum__Rate_Modifier__c(
            sirenum__Rate_Line__c = rateLine.Id,
            sirenum__Rate_Modifier_Type__c = modifierType.Id,
            sirenum__Pay_Rate__c = 50,
            sirenum__Charge_Rate__c = 200 // exceeds the 50% margin cap
        );

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

    // ---- Bulk safety: mixed pass/fail in one DML, across two unrelated placements ----

    @isTest
    static void testRateLine_BulkInsertHandlesMixedPassAndFailIndependently(){
        TestContext ctx = buildBaseContext();
        Rate_Agreement_Lines__c line = addLine(ctx.version, 'Max Margin %', 50, null);
        addEmployerOnCost(ctx.version, line, 'Percent', 10, null);

        // Second, independent placement under the SAME Rate Agreement/Version — its own Rate
        // Card, so the handler's 1:1 rate-card-to-placement map keeps both rows straight.
        attachPlacement(ctx, ctx.contract, ctx.jobRoleScale);
        sirenum__Rate_Card_Page__c secondPage = ctx.page;

        // Re-attach the first page for the passing record by rebuilding a distinct context slice.
        TestContext firstCtx = buildBaseContext();
        Rate_Agreement_Lines__c firstLine = addLine(firstCtx.version, 'Max Margin %', 50, null);
        addEmployerOnCost(firstCtx.version, firstLine, 'Percent', 10, null);

        sirenum__Rate_Line__c passingLine = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = firstCtx.page.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Pay_Rate__c = 50,
            sirenum__Charge_Rate__c = 70 // within bounds
        );
        sirenum__Rate_Line__c failingLine = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = secondPage.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Pay_Rate__c = 50,
            sirenum__Charge_Rate__c = 200 // over the margin cap
        );

        Test.startTest();
        Database.SaveResult[] results = Database.insert(new List<sirenum__Rate_Line__c>{ passingLine, failingLine }, false);
        Test.stopTest();

        System.assert(results[0].isSuccess(), 'First Rate Line should have saved: ' + results[0].getErrors());
        System.assert(!results[1].isSuccess(), 'Second Rate Line should have been rejected for exceeding the margin');
        System.assert(results[1].getErrors()[0].getMessage().contains('exceeds the maximum allowed margin'),
            results[1].getErrors()[0].getMessage());
    }
}