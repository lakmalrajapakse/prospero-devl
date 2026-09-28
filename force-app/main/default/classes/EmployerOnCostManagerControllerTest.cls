@IsTest
private class EmployerOnCostManagerControllerTest {

    @IsTest
    static void testGetWorkspaceWithCosts() {
        Rate_Agreements__c rateAgreement = new Rate_Agreements__c(
            Name = 'Test Rate Agreement'
        );
        insert rateAgreement;

        Rate_Agreement_Version__c version = new Rate_Agreement_Version__c(
            Rate_Agreement__c = rateAgreement.Id,
            Effective_Date__c = Date.today()
        );
        insert version;

        Employer_On_Cost__c cost = new Employer_On_Cost__c(
            Rate_Agreement_Version__c = version.Id,
            On_Cost_Type__c = 'NI',
            Calc_Type__c = 'Percent',
            Value__c = 10
        );
        insert cost;

        Test.startTest();
        EmployerOnCostManagerController.Workspace result =
            EmployerOnCostManagerController.getWorkspace(rateAgreement.Id);
        Test.stopTest();

        System.assertEquals(version.Id, result.versionId);
        System.assertEquals(1, result.costs.size());
        System.assertEquals(cost.Id, result.costs[0].Id);
        System.assertEquals(version.Id, result.costs[0].Rate_Agreement_Version__c);
    }


    @IsTest
    static void testGetRateLineUsageWithRateLines() {
        Rate_Agreements__c rateAgreement = new Rate_Agreements__c(
            Name = 'Test Rate Agreement'
        );
        insert rateAgreement;

        sirenum__Rate_Card__c rateCard = new sirenum__Rate_Card__c(
            Name = 'Test Rate Card'
        );
        insert rateCard;

        sirenum__Rate_Card_Page__c page = new sirenum__Rate_Card_Page__c(
            Name = 'Test Page',
            sirenum__Rate_Card__c = rateCard.Id
        );
        insert page;

        sirenum__Rate_Line__c rateLine1 = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = page.Id,
            Employer_On_Cost__c = rateAgreement.Id,
            sirenum__Pay_Rate__c = 20,
            sirenum__Charge_Rate__c = 30,
            sirenum__SortOrder__c = 1
        );

        sirenum__Rate_Line__c rateLine2 = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = page.Id,
            Employer_On_Cost__c = rateAgreement.Id,
            sirenum__Pay_Rate__c = 25,
            sirenum__Charge_Rate__c = 35,
            sirenum__SortOrder__c = 2
        );

        insert new List<sirenum__Rate_Line__c>{ rateLine1, rateLine2 };

        Test.startTest();
        EmployerOnCostManagerController.RateLineUsage result =
            EmployerOnCostManagerController.getRateLineUsage(rateAgreement.Id);
        Test.stopTest();

        System.assertEquals(2, result.totalCount);
        System.assertEquals(2, result.sampleNames.size());
        System.assertEquals(rateLine1.Name, result.sampleNames[0]);
        System.assertEquals(rateLine2.Name, result.sampleNames[1]);
    }
}