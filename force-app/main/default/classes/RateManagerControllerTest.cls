@IsTest
private class RateManagerControllerTest {

    // Verifies rate card pages and rate line count.
    @IsTest
    static void testRateCardPagesAndLineCount() {

        sirenum__Rate_Card__c rateCard = new sirenum__Rate_Card__c(
            Name = 'Test Rate Card'
        );
        insert rateCard;

        sirenum__Rate_Card_Page__c page = new sirenum__Rate_Card_Page__c(
            Name = 'Test Page',
            sirenum__Rate_Card__c = rateCard.Id,
            sirenum__SortOrder__c = 1
        );
        insert page;

        Test.startTest();

        List<sirenum__Rate_Card_Page__c> pages =
            RateManagerController.getRateCardPages(rateCard.Id);

        Integer count = RateManagerController.getRateLineCount(page.Id);

        Test.stopTest();

        System.assertEquals(1, pages.size());
        System.assertEquals(0, count);
    }


    // Verifies prefill returns the first rate line from the applicable page.
    @IsTest
    static void testGetPrefillRateLineId() {

        sirenum__Rate_Card__c rateCard = new sirenum__Rate_Card__c(
            Name = 'Test Rate Card'
        );
        insert rateCard;

        sirenum__Rate_Card_Page__c page = new sirenum__Rate_Card_Page__c(
            Name = 'Test Page',
            sirenum__Rate_Card__c = rateCard.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Valid_From_Date__c = Date.today().addDays(-10),
            sirenum__Valid_Until_Date__c = Date.today().addDays(10)
        );
        insert page;

        sirenum__Rate_Line__c rateLine = new sirenum__Rate_Line__c(
            sirenum__Rate_Card_Page__c = page.Id,
            sirenum__SortOrder__c = 1,
            sirenum__Pay_Rate__c = 20,
            sirenum__Charge_Rate__c = 30
        );
        insert rateLine;

        Test.startTest();

        Id result = RateManagerController.getPrefillRateLineId(rateCard.Id, Date.today());

        Test.stopTest();

        System.assertEquals(rateLine.Id, result);
    }


    // Verifies null inputs return empty results.
    @IsTest
    static void testNullInputs() {

        Test.startTest();

        List<sirenum__Rate_Card_Page__c> pages =
            RateManagerController.getRateCardPages(null);

        Integer count =
            RateManagerController.getRateLineCount(null);

        Id prefill =
            RateManagerController.getPrefillRateLineId(null, null);

        Test.stopTest();

        System.assertEquals(0, pages.size());
        System.assertEquals(0, count);
        System.assertEquals(null, prefill);
    }


    // Verifies invalid IDs return no results.
    @IsTest
    static void testInvalidIds() {

        Id invalidId = Account.SObjectType.newSObject().Id;

        Test.startTest();

        List<sirenum__Rate_Card_Page__c> pages =
            RateManagerController.getRateCardPages(invalidId);

        Integer count =
            RateManagerController.getRateLineCount(invalidId);

        Id prefill = RateManagerController.getPrefillRateLineId(invalidId, Date.today());

        Test.stopTest();

        System.assertEquals(0, pages.size());
        System.assertEquals(0, count);
        System.assertEquals(null, prefill);
    }
}