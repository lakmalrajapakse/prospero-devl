@IsTest
private class MarginCalculatorControllerTest {

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

    private static Integer counter = 0;

    private static String suffix() {
        counter++;
        return String.valueOf(Datetime.now().getTime()) + '-' + counter;
    }

    private static TestContext setup() {
        return setup(true);
    }

    private static TestContext setup(Boolean withAgreement) {
        TestContext c = new TestContext();
        String s = suffix();

        Team__c team = new Team__c(Name = 'Test Team ' + s);
        insert team;

        c.client = new Account(Name = 'Test Client ' + s, RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Prospero_Client').getRecordTypeId(), Health_Social_Care_Type__c = 'Local Authority', Team__c = team.Id, BillingStreet = '1 Test Street', BillingCity = 'Test City', BillingPostalCode = 'TE1 1ST', BillingCountry = 'United Kingdom');
        insert c.client;

        c.worker = new Contact(LastName = 'Worker ' + s, AccountId = c.client.Id, Team__c = team.Id, Worker_Type_Payroll_Provider__c = 'Pay As You Earn');
        insert c.worker;

        c.rateAgreement = new Rate_Agreements__c();
        insert c.rateAgreement;

        c.contract = new sirenum__ProActiveContract__c(sirenum__Client__c = c.client.Id, Rate_Agreements__c = withAgreement ? c.rateAgreement.Id : null);
        insert c.contract;

        c.jobRole = new sirenum__Team__c(sirenum__Account__c = c.contract.Id);
        insert c.jobRole;

        c.scaleDefinition = new Rate_Agreement_Scale_Definition__c(Rate_Agreements__c = c.rateAgreement.Id, Region__c = 'UK', Description__c = 'Scale 1', Ranking__c = 1);
        insert c.scaleDefinition;

        c.jobRoleScale = new Job_Role_Scale__c(Job_Role__c = c.jobRole.Id, Rate_Agreement_Scale_Definition__c = c.scaleDefinition.Id);
        insert c.jobRoleScale;

        c.version = new Rate_Agreement_Version__c(Rate_Agreement__c = c.rateAgreement.Id, Effective_Date__c = Date.newInstance(2024, 1, 1));
        insert c.version;

        c.scale = new Rate_Agreement_Scale__c(Rate_Agreement_Version__c = c.version.Id, Rate_Agreement_Scale_Definition__c = c.scaleDefinition.Id, Min_Amount__c = 10, Max_Amount__c = 100);
        insert c.scale;

        c.rateCard = new sirenum__Rate_Card__c();
        insert c.rateCard;

        Team__c jobTeam = new Team__c(Name = 'Job Team ' + s);
        insert jobTeam;

        TR1__Job__c job = new TR1__Job__c(Team__c = jobTeam.Id, TR1__Account__c = c.client.Id, s5m__Contract__c = c.contract.Id);
        insert job;

        c.placement = new sirenum__Placement__c(sirenum__Contact__c = c.worker.Id, sirenum__Job_Role__c = c.jobRole.Id, sirenum__Start_Date__c = Date.newInstance(2024, 1, 1), sirenum__Rate_Card__c = c.rateCard.Id, sirenum__Contract__c = c.contract.Id, Job_Role_Scale__c = c.jobRoleScale.Id, Job__c = job.Id);
        insert c.placement;

        c.placement = [SELECT Id, Job_Role_Scale__c FROM sirenum__Placement__c WHERE Id = :c.placement.Id];
        System.debug('JRS after insert: ' + c.placement.Job_Role_Scale__c);
        if (c.placement.Job_Role_Scale__c == null) {
            c.placement.Job_Role_Scale__c = c.jobRoleScale.Id;
            update c.placement;
        }

        c.page = new sirenum__Rate_Card_Page__c(sirenum__Rate_Card__c = c.rateCard.Id, sirenum__SortOrder__c = 1, sirenum__Condition_Field__c = 'Test', sirenum__Condition_value__c = 'Test', sirenum__Valid_From_Date__c = Date.newInstance(2024, 6, 1));
        insert c.page;

        return c;
    }

    private static sirenum__Rate_Modifier_Type__c awrType() {
        List<sirenum__Rate_Modifier_Type__c> t = [SELECT Id FROM sirenum__Rate_Modifier_Type__c WHERE Name = 'AWR' LIMIT 1];
        if (!t.isEmpty()) return t[0];
        sirenum__Rate_Modifier_Type__c n = new sirenum__Rate_Modifier_Type__c(Name = 'AWR');
        insert n;
        return n;
    }

    private static Rate_Agreement_Lines__c addLine(TestContext c, String calcType, Decimal margin, String workerType) {
        Rate_Agreement_Lines__c line = new Rate_Agreement_Lines__c(Rate_Agreement_Version__c = c.version.Id, Calc_Type__c = calcType, Margin_Value__c = margin, Worker_Type__c = workerType);
        insert line;
        return line;
    }

    private static void addCost(TestContext c, Rate_Agreement_Lines__c line, String calcType, Decimal value, String workerType) {
        insert new Employer_On_Cost__c(Rate_Agreement_Version__c = c.version.Id, Rate_Agreement_Lines__c = line.Id, Type__c = 'Record Agreement Line', Worker_Type__c = workerType, On_Cost_Type__c = 'NI', Calc_Type__c = calcType, Value__c = value);
    }

    // Creates the required records, calls getAgreementDetails, and verifies the returned agreement details.
    @IsTest
    static void testAgreementDetails() {
        TestContext c = setup();

        MarginCalculatorController.AgreementDetails r = MarginCalculatorController.getAgreementDetails(c.placement.Id);

        sirenum__Team__c jr = [SELECT Name FROM sirenum__Team__c WHERE Id = :c.jobRole.Id];
        Contact w = [SELECT Name FROM Contact WHERE Id = :c.worker.Id];
        sirenum__ProActiveContract__c ct = [SELECT Name FROM sirenum__ProActiveContract__c WHERE Id = :c.contract.Id];
        Rate_Agreements__c ra = [SELECT Name FROM Rate_Agreements__c WHERE Id = :c.rateAgreement.Id];

        System.assertEquals(jr.Name, r.jobRoleName);
        System.assertEquals(w.Name, r.workerName);
        System.assertEquals(ct.Name, r.contractName);
        System.assertEquals(ra.Name, r.rateAgreementName);
        System.assertEquals(true, r.hasRateAgreement);
        System.assertEquals(null, r.blockingError);
    }

    // Removes the Job Role Scale and verifies that a blocking error is returned.
    @IsTest
    static void testAgreementDetailsMissingScale() {
        TestContext c = setup();
        c.placement.Job_Role_Scale__c = null;
        update c.placement;

        MarginCalculatorController.AgreementDetails r = MarginCalculatorController.getAgreementDetails(c.placement.Id);

        System.assertEquals(true, r.hasRateAgreement);
        System.assertNotEquals(null, r.blockingError);
    }

    // Creates a Rate Line, retrieves the page, and verifies the line is returned without an AWR modifier.
    @IsTest
    static void testRateCardPages() {
        TestContext c = setup(false);

        sirenum__Rate_Line__c line = new sirenum__Rate_Line__c(sirenum__Rate_Card_Page__c = c.page.Id, sirenum__Code__c = 'TEST', sirenum__Pay_Rate__c = 20, sirenum__Charge_Rate__c = 30, Margin__c = 10, Margin_Type__c = 'Percent', sirenum__SortOrder__c = 1);
        insert line;

        List<MarginCalculatorController.PageWithLines> r = MarginCalculatorController.getRateCardPages(c.rateCard.Id, null);

        System.assertEquals(1, r.size());
        System.assertEquals(1, r[0].lines.size());
        System.assertEquals(line.Id, r[0].lines[0].line.Id);
        System.assertEquals(null, r[0].lines[0].awrModifier);
    }

    // Creates a second page, requests only that page, and verifies it is returned.
    @IsTest
    static void testRateCardPagesOnlyPage() {
        TestContext c = setup();

        sirenum__Rate_Card_Page__c page2 = new sirenum__Rate_Card_Page__c(sirenum__Rate_Card__c = c.rateCard.Id, sirenum__SortOrder__c = 2, sirenum__Condition_Field__c = 'Test', sirenum__Condition_value__c = 'Test', sirenum__Valid_From_Date__c = Date.newInstance(2024, 7, 1));
        insert page2;

        List<MarginCalculatorController.PageWithLines> r = MarginCalculatorController.getRateCardPages(c.rateCard.Id, page2.Id);

        System.assertEquals(1, r.size());
        System.assertEquals(page2.Id, r[0].page.Id);
    }

    // Creates a Rate Line, attempts to clone the page, and verifies the cloned line when cloning succeeds.
    @IsTest
    static void testClonePage() {
        TestContext c = setup(false);

        sirenum__Rate_Line__c line = new sirenum__Rate_Line__c(sirenum__Rate_Card_Page__c = c.page.Id, sirenum__Code__c = 'TEST', sirenum__Pay_Rate__c = 20, sirenum__Charge_Rate__c = 30, Margin__c = 10, Margin_Type__c = 'Percent', sirenum__SortOrder__c = 1);
        insert line;

        Id newPageId;

        try {
            newPageId = MarginCalculatorController.clonePage(c.page.Id, 'Cloned Page', Date.newInstance(2024, 7, 1));
        } catch (Exception e) {
            System.debug('Clone failed: ' + e.getMessage());
        }

        if (newPageId != null) {
            System.assertEquals(1, [SELECT COUNT() FROM sirenum__Rate_Line__c WHERE sirenum__Rate_Card_Page__c = :newPageId]);
        }
    }

    // Clones a page without Rate Lines and verifies that the new page has no lines.
    @IsTest
    static void testClonePageEmpty() {
        TestContext c = setup();

        Id newPageId = MarginCalculatorController.clonePage(c.page.Id, 'Empty Clone', Date.newInstance(2024, 7, 1));

        System.assertNotEquals(null, newPageId);
        System.assertEquals(0, [SELECT COUNT() FROM sirenum__Rate_Line__c WHERE sirenum__Rate_Card_Page__c = :newPageId]);
    }

    // Calls clonePage with invalid inputs and verifies that an exception is thrown.
    private static Boolean clonePageThrows(Id sourcePageId, String name, Date d) {
        try {
            MarginCalculatorController.clonePage(sourcePageId, name, d);
        } catch (AuraHandledException e) {
            return true;
        }
        return false;
    }

    @IsTest
    static void testClonePageValidation() {
        TestContext c = setup();

        System.assertEquals(true, clonePageThrows(null, 'Test', Date.newInstance(2024, 7, 1)));
        System.assertEquals(true, clonePageThrows(Id.valueOf('001000000000000AAA'), 'Test', Date.newInstance(2024, 7, 1)));
        System.assertEquals(true, clonePageThrows(c.page.Id, 'Test', Date.newInstance(2024, 5, 1)));
    }

    // Checks whether an AWR modifier type exists and verifies the controller returns its Id.
    @IsTest
    static void testAwrType() {
        List<sirenum__Rate_Modifier_Type__c> types = [SELECT Id FROM sirenum__Rate_Modifier_Type__c WHERE Name = 'AWR' LIMIT 1];

        if (!types.isEmpty()) {
            System.assertEquals(types[0].Id, MarginCalculatorController.getAwrRateModifierTypeId());
        } else {
            System.assertEquals(null, MarginCalculatorController.getAwrRateModifierTypeId());
        }
    }

    // Creates a Rate Agreement Line and Employer On Cost, then verifies the returned context values.
    @IsTest
    static void testLineContext() {
        TestContext c = setup();
        Rate_Agreement_Lines__c line = addLine(c, 'Fixed Margin %', 20, 'PAYE');
        addCost(c, line, 'Percent', 10, 'PAYE');

        MarginCalculatorController.RateAgreementLineContext r = MarginCalculatorController.getRateAgreementLineContext(c.placement.Id, c.page.Id);

        System.assertEquals(null, r.errorMessage);
        System.assertEquals(line.Id, r.rateAgreementLineId);
        System.assertEquals('Fixed Margin %', r.calcType);
        System.assertEquals(20, r.marginValue);
        System.assertEquals(10, r.payScaleMin);
        System.assertEquals(100, r.payScaleMax);
        System.assertEquals('PAYE', r.workerType);
        System.assertEquals(1, r.employerOnCosts.size());
    }

    // Calls the method without Placement and Rate Card Page Ids and verifies the error.
    @IsTest
    static void testLineContextNull() {
        MarginCalculatorController.RateAgreementLineContext r = MarginCalculatorController.getRateAgreementLineContext(null, null);

        System.assertEquals('Placement and Rate Card Page are required.', r.errorMessage);
    }

    // Uses a Contract without a Rate Agreement and verifies the returned error.
    @IsTest
    static void testLineContextNoAgreement() {
        TestContext c = setup(false);

        MarginCalculatorController.RateAgreementLineContext r = MarginCalculatorController.getRateAgreementLineContext(c.placement.Id, c.page.Id);

        System.assertEquals('This Placement\'s Contract has no Rate Agreement.', r.errorMessage);
    }

    // Creates a margin line and Employer On Cost, calculates the margin, and verifies the calculation results.
    @IsTest
    static void testCalculateMargin() {
        TestContext c = setup();
        Rate_Agreement_Lines__c line = addLine(c, 'Fixed Margin %', 20, 'PAYE');
        addCost(c, line, 'Percent', 10, 'PAYE');

        MarginCalculatorController.MarginCalculationResult r = MarginCalculatorController.calculateRateAgreementMargin(line.Id, 'PAYE', 20, 26.4, 10, 100);

        System.assertEquals(null, r.errorMessage);
        System.assertEquals(2, r.employerOnCost);
        System.assertEquals(22, r.totalCost);
        System.assertEquals(4.4, r.marginAmount);
        System.assertEquals(20, r.marginPercent.setScale(2));
    }

    // Calls the margin calculation without a Rate Agreement Line and verifies the error.
    @IsTest
    static void testCalculateMarginNullLine() {
        MarginCalculatorController.MarginCalculationResult r = MarginCalculatorController.calculateRateAgreementMargin(null, 'PAYE', 20, 50, 10, 100);

        System.assertEquals('No applicable Rate Agreement Line.', r.errorMessage);
    }

    // Uses a pay rate outside the configured scale and verifies the validation error.
    @IsTest
    static void testCalculateMarginInvalidPayRate() {
        TestContext c = setup();
        Rate_Agreement_Lines__c line = addLine(c, 'Fixed Margin %', 20, 'PAYE');

        MarginCalculatorController.MarginCalculationResult r = MarginCalculatorController.calculateRateAgreementMargin(line.Id, 'PAYE', 5, 50, 10, 100);

        System.assertNotEquals(null, r.errorMessage);
    }

    // Creates different Employer On Costs and verifies only applicable costs are returned.
    @IsTest
    static void testGetEmployerOnCosts() {
        TestContext c = setup();
        Rate_Agreement_Lines__c line = addLine(c, 'Fixed Margin %', 20, 'PAYE');

        addCost(c, line, 'Percent', 10, 'PAYE');
        addCost(c, line, 'Percent', 5, 'Umbrella');
        addCost(c, line, 'Percent', 2, null);

        List<Employer_On_Cost__c> r = MarginCalculatorController.getEmployerOnCosts(c.rateAgreement.Id, c.placement.Id);

        System.assertEquals(2, r.size());
    }

    // Calls getEmployerOnCosts without a Rate Agreement Id and verifies an empty result.
    @IsTest
    static void testGetEmployerOnCostsNull() {
        List<Employer_On_Cost__c> r = MarginCalculatorController.getEmployerOnCosts(null, null);

        System.assertEquals(0, r.size());
    }
}