@IsTest
private class JobRoleScaleControllerTest {

    private static Map<String, Id> createTestData() {
        Team__c team = new Team__c(Name = 'Test Team'); insert team;
        Account account = new Account(Name = 'Test Account', Team__c = team.Id, BillingStreet = '123 Test Street', BillingCity = 'Test City', BillingPostalCode = '500001', BillingCountry = 'India', Health_Social_Care_Type__c = 'Local Authority');
        insert account;
        Rate_Agreements__c rateAgreement = new Rate_Agreements__c(Name = 'Test Rate Agreement');
        insert rateAgreement;
        sirenum__ProActiveContract__c contract = new sirenum__ProActiveContract__c(Name = 'Test Contract', Rate_Agreements__c = rateAgreement.Id, sirenum__Client__c = account.Id); 
        insert contract;
        sirenum__Job_Type__c jobType = new sirenum__Job_Type__c(Name = 'Test Job Type'); insert jobType;
        sirenum__Team__c jobRole = new sirenum__Team__c(Name = 'Test Job Role', sirenum__Account__c = contract.Id, sirenum__Job_Type__c = jobType.Id); 
        insert jobRole;

        return new Map<String, Id>{
            'accountId' => account.Id,
            'rateAgreementId' => rateAgreement.Id,
            'contractId' => contract.Id,
            'jobTypeId' => jobType.Id,
            'jobRoleId' => jobRole.Id
        };
    }

    // Verifies Job Roles can be searched using the available filters and pagination.
    @IsTest
    static void testSearchJobRoles() {
        Map<String, Id> data = createTestData();

        Test.startTest();
        JobRoleScaleController.JobRoleSearchPage result = JobRoleScaleController.searchJobRoles(data.get('rateAgreementId'), 'Test', data.get('jobTypeId'), data.get('accountId'), 1);
        Test.stopTest();

        System.assertEquals(1, result.records.size());
        System.assertEquals(false, result.hasNextPage);
        System.assertEquals(data.get('jobRoleId'), result.records[0].jobRoleId);
        System.assertEquals('Test Job Role', result.records[0].jobRoleName);
        System.assertEquals('Test Job Type', result.records[0].jobTypeName);
        System.assertEquals('Test Contract', result.records[0].contractName);
        System.assertEquals('Test Account', result.records[0].accountName);

        JobRoleScaleController.JobRoleSearchPage noFilters = JobRoleScaleController.searchJobRoles(data.get('rateAgreementId'), null, null, null, 1);
        System.assertEquals(0, noFilters.records.size());
        System.assertEquals(false, noFilters.hasNextPage);
    }

    // Verifies Job Roles can be assigned to and retrieved from a Scale Definition.
    @IsTest
    static void testAssignments() {
        Map<String, Id> data = createTestData();
        Rate_Agreement_Scale_Definition__c definition = new Rate_Agreement_Scale_Definition__c(Name = 'Test Definition', Rate_Agreements__c = data.get('rateAgreementId'), Region__c = 'Test Region', Description__c = 'Test Description', Ranking__c = 1); insert definition;

        Test.startTest();
        JobRoleScaleController.assignJobRoles(definition.Id, new List<Id>{data.get('jobRoleId')});
        JobRoleScaleController.assignJobRoles(definition.Id, new List<Id>{data.get('jobRoleId')});
        List<Job_Role_Scale__c> assignments = JobRoleScaleController.getAssignmentsForDefinition(definition.Id);
        Test.stopTest();

        System.assertEquals(1, assignments.size());
        System.assertEquals(data.get('jobRoleId'), assignments[0].Job_Role__c);
    }

    // Verifies an existing Job Role Scale assignment can be removed.
    @IsTest
    static void testRemoveAssignment() {
        Map<String, Id> data = createTestData();
        Rate_Agreement_Scale_Definition__c definition = new Rate_Agreement_Scale_Definition__c(Name = 'Test Definition', Rate_Agreements__c = data.get('rateAgreementId'), Region__c = 'Test Region', Description__c = 'Test Description', Ranking__c = 1); insert definition;
        Job_Role_Scale__c assignment = new Job_Role_Scale__c(Job_Role__c = data.get('jobRoleId'), Rate_Agreement_Scale_Definition__c = definition.Id); insert assignment;

        Test.startTest();
        JobRoleScaleController.removeAssignment(assignment.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Job_Role_Scale__c WHERE Id = :assignment.Id]);
    }
}