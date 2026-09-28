@IsTest
private class JobRoleScaleControllerTest {

    // Verifies Job Roles can be searched using the available filters.
    @IsTest
    static void testSearchJobRoles() {

        Team__c team = new Team__c(Name = 'Test Team');
        insert team;

        Account account = new Account(Name = 'Test Account', Team__c = team.Id, BillingStreet = '123 Test Street', BillingCity = 'Test City', BillingPostalCode = '500001', BillingCountry = 'India', Health_Social_Care_Type__c = 'Local Authority');
        insert account;

        Rate_Agreements__c rateAgreement = new Rate_Agreements__c(Name = 'Test Rate Agreement');
        insert rateAgreement;

        sirenum__ProActiveContract__c contract = new sirenum__ProActiveContract__c(Name = 'Test Contract', Rate_Agreements__c = rateAgreement.Id, sirenum__Client__c = account.Id);
        insert contract;

        sirenum__Job_Type__c jobType = new sirenum__Job_Type__c(Name = 'Test Job Type');
        insert jobType;

        sirenum__Team__c jobRole = new sirenum__Team__c(Name = 'Test Job Role', sirenum__Account__c = contract.Id, sirenum__Job_Type__c = jobType.Id);
        insert jobRole;

        Test.startTest();
        List<JobRoleScaleController.JobRoleSearchResult> results =
            JobRoleScaleController.searchJobRoles(rateAgreement.Id, 'Test', jobType.Id, account.Id);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(jobRole.Id, results[0].jobRoleId);
        System.assertEquals('Test Job Role', results[0].jobRoleName);
        System.assertEquals('Test Job Type', results[0].jobTypeName);
        System.assertEquals('Test Contract', results[0].contractName);
        System.assertEquals('Test Account', results[0].accountName);
    }

    // Verifies no results are returned when no filters are provided.
    @IsTest
    static void testSearchJobRolesNoFilters() {

        Rate_Agreements__c rateAgreement = new Rate_Agreements__c(Name = 'Test Rate Agreement');
        insert rateAgreement;

        Test.startTest();
        List<JobRoleScaleController.JobRoleSearchResult> results =
            JobRoleScaleController.searchJobRoles(rateAgreement.Id, null, null, null);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }

    // Verifies Job Roles can be assigned to and retrieved from a Scale Definition.
    @IsTest
    static void testGetAssignmentsAndAssignJobRoles() {

        Team__c team = new Team__c(Name = 'Test Team');
        insert team;

        Account account = new Account(Name = 'Test Account', Team__c = team.Id, BillingStreet = '123 Test Street', BillingCity = 'Test City', BillingPostalCode = '500001', BillingCountry = 'India', Health_Social_Care_Type__c = 'Local Authority');
        insert account;

        Rate_Agreements__c rateAgreement = new Rate_Agreements__c(Name = 'Test Rate Agreement');
        insert rateAgreement;

        sirenum__ProActiveContract__c contract = new sirenum__ProActiveContract__c(Name = 'Test Contract', Rate_Agreements__c = rateAgreement.Id, sirenum__Client__c = account.Id);
        insert contract;

        sirenum__Team__c jobRole = new sirenum__Team__c(Name = 'Test Job Role', sirenum__Account__c = contract.Id);
        insert jobRole;

        Rate_Agreement_Scale_Definition__c definition = new Rate_Agreement_Scale_Definition__c(Name = 'Test Definition', Rate_Agreements__c = rateAgreement.Id, Region__c = 'Test Region', Description__c = 'Test Description', Ranking__c = 1);
        insert definition;

        Test.startTest();
        JobRoleScaleController.assignJobRoles(definition.Id, new List<Id>{ jobRole.Id });

        List<Job_Role_Scale__c> assignments =
            JobRoleScaleController.getAssignmentsForDefinition(definition.Id);
        Test.stopTest();

        System.assertEquals(1, assignments.size());
        System.assertEquals(jobRole.Id, assignments[0].Job_Role__c);
    }

    // Verifies an existing Job Role Scale assignment can be removed.
    @IsTest
    static void testRemoveAssignment() {

        Team__c team = new Team__c(Name = 'Test Team');
        insert team;

        Account account = new Account(Name = 'Test Account', Team__c = team.Id, BillingStreet = '123 Test Street', BillingCity = 'Test City', BillingPostalCode = '500001', BillingCountry = 'India', Health_Social_Care_Type__c = 'Local Authority');
        insert account;

        Rate_Agreements__c rateAgreement = new Rate_Agreements__c(Name = 'Test Rate Agreement');
        insert rateAgreement;

        Rate_Agreement_Scale_Definition__c definition = new Rate_Agreement_Scale_Definition__c(Name = 'Test Definition', Rate_Agreements__c = rateAgreement.Id, Region__c = 'Test Region', Description__c = 'Test Description', Ranking__c = 1);
        insert definition;

        sirenum__ProActiveContract__c contract = new sirenum__ProActiveContract__c(Name = 'Test Contract', Rate_Agreements__c = rateAgreement.Id, sirenum__Client__c = account.Id);
        insert contract;

        sirenum__Team__c jobRole = new sirenum__Team__c(Name = 'Test Job Role', sirenum__Account__c = contract.Id);
        insert jobRole;

        Job_Role_Scale__c assignment = new Job_Role_Scale__c(Job_Role__c = jobRole.Id, Rate_Agreement_Scale_Definition__c = definition.Id);
        insert assignment;

        Test.startTest();
        JobRoleScaleController.removeAssignment(assignment.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Job_Role_Scale__c WHERE Id = :assignment.Id]);
    }
}