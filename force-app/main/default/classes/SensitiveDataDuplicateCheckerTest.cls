@isTest
private class SensitiveDataDuplicateCheckerTest {

    @TestSetup
    static void setup() {
        General_Settings__c setting = new General_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Fuzzy_Match_Threshold__c = 80
        );
        insert setting;

        insert new Sensitive_Data__c(
            First_Name__c = 'Jonathan',
            Last_Name__c = 'Smith',
            Date_of_Birth__c = Date.newInstance(1990, 5, 15),
            Reference_ID__c = 'REF-001'
        );
    }

    @isTest
    static void testDuplicateFound() {
        SensitiveDataDuplicateChecker.InputWrapper input = new SensitiveDataDuplicateChecker.InputWrapper();
        input.firstName = 'Jonathon'; // close enough to clear fuzzy threshold
        input.lastName = 'Smith';
        input.dateOfBirth = Date.newInstance(1990, 5, 15);

        Test.startTest();
        List<SensitiveDataDuplicateChecker.OutputWrapper> results =
            SensitiveDataDuplicateChecker.checkDuplicate(new List<SensitiveDataDuplicateChecker.InputWrapper>{ input });
        Test.stopTest();

        SensitiveDataDuplicateChecker.OutputWrapper output = results[0];
        System.assertEquals(false, output.noDuplicateFound);
        System.assertEquals(true, output.duplicateWithAccess);
        System.assertEquals('REF-001', output.referenceId);
    }

    @isTest
    static void testNoDuplicateFound() {
        SensitiveDataDuplicateChecker.InputWrapper input = new SensitiveDataDuplicateChecker.InputWrapper();
        input.firstName = 'Zed';
        input.lastName = 'Nowhere';
        input.dateOfBirth = Date.newInstance(1975, 3, 3);

        Test.startTest();
        List<SensitiveDataDuplicateChecker.OutputWrapper> results =
            SensitiveDataDuplicateChecker.checkDuplicate(new List<SensitiveDataDuplicateChecker.InputWrapper>{ input });
        Test.stopTest();

        System.assertEquals(true, results[0].noDuplicateFound);
    }
}