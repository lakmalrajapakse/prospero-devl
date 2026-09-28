@IsTest
private class RateAgreementManagerControllerTest {

    @TestSetup
    static void setup() {
        Team__c team = new Team__c(Name = 'Test Team');
        insert team;

        Account account = new Account(Name = 'Test Account', Team__c = team.Id, BillingStreet = '123 Test Street', BillingCity = 'Test City', BillingPostalCode = '500001', BillingCountry = 'India', Health_Social_Care_Type__c = 'Local Authority');
        insert account;

        Rate_Agreements__c ra = new Rate_Agreements__c(Name = 'Test Rate Agreement', Account__c = account.Id, Type__c = 'Pay Based');
        insert ra;

        // defLocked gets a Scale, the other two are free
        Rate_Agreement_Scale_Definition__c defLocked = new Rate_Agreement_Scale_Definition__c(Name = 'Locked Def', Rate_Agreements__c = ra.Id, Region__c = 'Region', Description__c = 'Desc', Ranking__c = 1);
        Rate_Agreement_Scale_Definition__c defFree1 = new Rate_Agreement_Scale_Definition__c(Name = 'Free Def 1', Rate_Agreements__c = ra.Id, Region__c = 'Region', Description__c = 'Desc', Ranking__c = 2);
        Rate_Agreement_Scale_Definition__c defFree2 = new Rate_Agreement_Scale_Definition__c(Name = 'Free Def 2', Rate_Agreements__c = ra.Id, Region__c = 'Region', Description__c = 'Desc', Ranking__c = 3);
        insert new List<Rate_Agreement_Scale_Definition__c>{defLocked, defFree1, defFree2};

        Rate_Agreement_Version__c version = new Rate_Agreement_Version__c(Rate_Agreement__c = ra.Id, Effective_Date__c = Date.today());
        insert version;

        Rate_Agreement_Scale__c scale = new Rate_Agreement_Scale__c(Rate_Agreement_Version__c = version.Id, Rate_Agreement_Scale_Definition__c = defLocked.Id, Min_Amount__c = 10, Max_Amount__c = 100);
        insert scale;

        Rate_Agreement_Lines__c line = new Rate_Agreement_Lines__c(Rate_Agreement_Version__c = version.Id, Worker_Type__c = 'PAYE', Calc_Type__c = 'Fixed Margin Amount', Margin_Value__c = 10, Min_Scale__c = scale.Id, Max_Scale__c = scale.Id);
        insert line;

        // One default on-cost (no line) and one line-level on-cost
        insert new List<Employer_On_Cost__c>{
            new Employer_On_Cost__c(Rate_Agreement_Version__c = version.Id, Worker_Type__c = 'PAYE', On_Cost_Type__c = 'NI', Calc_Type__c = 'Fixed', Value__c = 10),
            new Employer_On_Cost__c(Rate_Agreement_Version__c = version.Id, Rate_Agreement_Lines__c = line.Id, Worker_Type__c = 'PAYE', On_Cost_Type__c = 'NI', Calc_Type__c = 'Percent', Value__c = 5)
        };

        // Contract not yet assigned to any Rate Agreement
        insert new sirenum__ProActiveContract__c(Name = 'Test Contract', sirenum__Client__c = account.Id);
    }

    // Read/query methods: list, workspace, version workspace, definitions, on-costs
    @IsTest
    static void testReadMethods() {
        Rate_Agreements__c ra = [SELECT Id, Account__c FROM Rate_Agreements__c LIMIT 1];
        Rate_Agreement_Version__c version = [SELECT Id FROM Rate_Agreement_Version__c LIMIT 1];
        Rate_Agreement_Lines__c line = [SELECT Id FROM Rate_Agreement_Lines__c LIMIT 1];

        Test.startTest();
        RateAgreementManagerController.PageResult filtered = RateAgreementManagerController.getRateAgreementsPage('Test', ra.Account__c, 1);
        RateAgreementManagerController.PageResult unfiltered = RateAgreementManagerController.getRateAgreementsPage(null, null, null);
        RateAgreementManagerController.WorkspaceResult workspace = RateAgreementManagerController.getRateAgreementWorkspace(ra.Id);
        RateAgreementManagerController.VersionWorkspaceResult versionWs = RateAgreementManagerController.getVersionWorkspace(version.Id);
        List<Rate_Agreement_Scale_Definition__c> defs = RateAgreementManagerController.getScaleDefinitionsForRateAgreement(ra.Id);
        List<Employer_On_Cost__c> defaultCosts = RateAgreementManagerController.getOnCosts(version.Id, null);
        List<Employer_On_Cost__c> lineCosts = RateAgreementManagerController.getOnCosts(version.Id, line.Id);
        Test.stopTest();

        System.assertEquals(1, filtered.records.size());
        System.assertEquals(false, filtered.hasNextPage);
        System.assertEquals(1, unfiltered.records.size());
        System.assertEquals(1, workspace.versions.size());
        System.assertEquals(1, versionWs.scales.size());
        System.assertEquals(1, versionWs.lines.size());
        System.assertEquals(3, defs.size());
        System.assertEquals(1, defaultCosts.size());
        System.assertEquals(1, lineCosts.size());
    }

    // Scale Definitions: lock status, create, reorder, delete, and the locked-row errors
    @IsTest
    static void testScaleDefinitions() {
        Rate_Agreements__c ra = [SELECT Id FROM Rate_Agreements__c LIMIT 1];
        Map<String, Rate_Agreement_Scale_Definition__c> defs = new Map<String, Rate_Agreement_Scale_Definition__c>();
        for (Rate_Agreement_Scale_Definition__c d : [SELECT Id, Name FROM Rate_Agreement_Scale_Definition__c]) {
            defs.put(d.Name, d);
        }

        Test.startTest();

        // Lock status
        List<RateAgreementManagerController.DefinitionWithLock> withLock = RateAgreementManagerController.getScaleDefinitionsWithLock(ra.Id);
        Integer lockedCount = 0;
        for (RateAgreementManagerController.DefinitionWithLock w : withLock) {
            if (w.isLocked) lockedCount++;
        }
        System.assertEquals(3, withLock.size());
        System.assertEquals(1, lockedCount);

        // Create: ranking is max + 1
        Id newDefId = RateAgreementManagerController.createScaleDefinition(ra.Id, 'New Def', null, 'Region', 'Desc');
        System.assertEquals(4, [SELECT Ranking__c FROM Rate_Agreement_Scale_Definition__c WHERE Id = :newDefId].Ranking__c);

        // Reorder two unlocked definitions
        RateAgreementManagerController.DefinitionRankingInput in1 = new RateAgreementManagerController.DefinitionRankingInput();
        in1.definitionId = defs.get('Free Def 1').Id;
        in1.ranking = 3;
        RateAgreementManagerController.DefinitionRankingInput in2 = new RateAgreementManagerController.DefinitionRankingInput();
        in2.definitionId = defs.get('Free Def 2').Id;
        in2.ranking = 2;
        RateAgreementManagerController.reorderScaleDefinitions(new List<RateAgreementManagerController.DefinitionRankingInput>{in1, in2});
        System.assertEquals(3, [SELECT Ranking__c FROM Rate_Agreement_Scale_Definition__c WHERE Id = :in1.definitionId].Ranking__c);
        System.assertEquals(2, [SELECT Ranking__c FROM Rate_Agreement_Scale_Definition__c WHERE Id = :in2.definitionId].Ranking__c);

        // Reordering a locked definition is rejected
        RateAgreementManagerController.DefinitionRankingInput lockedIn = new RateAgreementManagerController.DefinitionRankingInput();
        lockedIn.definitionId = defs.get('Locked Def').Id;
        lockedIn.ranking = 9;
        Boolean reorderBlocked = false;
        try {
            RateAgreementManagerController.reorderScaleDefinitions(new List<RateAgreementManagerController.DefinitionRankingInput>{lockedIn});
        } catch (AuraHandledException e) {
            reorderBlocked = true;
        }
        System.assert(reorderBlocked, 'Locked definition should not be reorderable');

        // Deleting a locked definition is rejected
        Boolean deleteBlocked = false;
        try {
            RateAgreementManagerController.deleteScaleDefinition(defs.get('Locked Def').Id);
        } catch (AuraHandledException e) {
            deleteBlocked = true;
        }
        System.assert(deleteBlocked, 'Locked definition should not be deletable');

        // Deleting an unlocked definition works
        RateAgreementManagerController.deleteScaleDefinition(defs.get('Free Def 1').Id);
        System.assertEquals(0, [SELECT COUNT() FROM Rate_Agreement_Scale_Definition__c WHERE Id = :defs.get('Free Def 1').Id]);

        Test.stopTest();
    }

    // Versions: create with scales, clone (with remapped lookups), duplicate-date validation
    @IsTest
    static void testVersionCreateAndClone() {
        Rate_Agreements__c ra = [SELECT Id FROM Rate_Agreements__c LIMIT 1];
        Rate_Agreement_Version__c version = [SELECT Id FROM Rate_Agreement_Version__c LIMIT 1];
        Rate_Agreement_Scale__c originalScale = [SELECT Id FROM Rate_Agreement_Scale__c LIMIT 1];
        Rate_Agreement_Scale_Definition__c freeDef = [SELECT Id FROM Rate_Agreement_Scale_Definition__c WHERE Name = 'Free Def 1' LIMIT 1];

        Test.startTest();

        // Create a version with one scale
        RateAgreementManagerController.ScaleInput scaleIn = new RateAgreementManagerController.ScaleInput();
        scaleIn.scaleDefinitionId = freeDef.Id;
        scaleIn.minAmount = 10;
        scaleIn.maxAmount = 50;
        Id createdId = RateAgreementManagerController.createVersionWithScales(ra.Id, Date.today().addDays(10), new List<RateAgreementManagerController.ScaleInput>{scaleIn});
        System.assertEquals(1, [SELECT COUNT() FROM Rate_Agreement_Scale__c WHERE Rate_Agreement_Version__c = :createdId]);

        // Duplicate effective date is rejected (create)
        Boolean createBlocked = false;
        try {
            RateAgreementManagerController.createVersionWithScales(ra.Id, Date.today(), null);
        } catch (AuraHandledException e) {
            createBlocked = true;
        }
        System.assert(createBlocked, 'Duplicate date should be rejected on create');

        // Clone copies scales, lines and both levels of on-costs
        Id clonedId = RateAgreementManagerController.cloneVersion(version.Id, Date.today().addDays(1));
        System.assertEquals(1, [SELECT COUNT() FROM Rate_Agreement_Scale__c WHERE Rate_Agreement_Version__c = :clonedId]);
        System.assertEquals(1, [SELECT COUNT() FROM Rate_Agreement_Lines__c WHERE Rate_Agreement_Version__c = :clonedId]);
        System.assertEquals(2, [SELECT COUNT() FROM Employer_On_Cost__c WHERE Rate_Agreement_Version__c = :clonedId]);

        // Cloned line points at the cloned scale, not the original
        Rate_Agreement_Lines__c clonedLine = [SELECT Min_Scale__c FROM Rate_Agreement_Lines__c WHERE Rate_Agreement_Version__c = :clonedId LIMIT 1];
        System.assertNotEquals(originalScale.Id, clonedLine.Min_Scale__c);
        System.assertNotEquals(null, clonedLine.Min_Scale__c);

        // Duplicate effective date is rejected (clone)
        Boolean cloneBlocked = false;
        try {
            RateAgreementManagerController.cloneVersion(version.Id, Date.today());
        } catch (AuraHandledException e) {
            cloneBlocked = true;
        }
        System.assert(cloneBlocked, 'Duplicate date should be rejected on clone');

        Test.stopTest();
    }

    // Employer On Cost and Line: insert, update, delete, copy defaults, delete line
    @IsTest
    static void testOnCostAndLineOperations() {
        Rate_Agreement_Version__c version = [SELECT Id FROM Rate_Agreement_Version__c LIMIT 1];
        Rate_Agreement_Lines__c line = [SELECT Id FROM Rate_Agreement_Lines__c LIMIT 1];

        Test.startTest();

        // Insert
        RateAgreementManagerController.OnCostInput input = new RateAgreementManagerController.OnCostInput();
        input.workerType = 'Umbrella';
        input.onCostType = 'NI';
        input.calcType = 'Percent';
        input.value = 12;
        Id onCostId = RateAgreementManagerController.upsertOnCost(version.Id, null, input);
        System.assertEquals(12, [SELECT Value__c FROM Employer_On_Cost__c WHERE Id = :onCostId].Value__c);

        // Update
        input.id = onCostId;
        input.value = 20;
        RateAgreementManagerController.upsertOnCost(version.Id, null, input);
        System.assertEquals(20, [SELECT Value__c FROM Employer_On_Cost__c WHERE Id = :onCostId].Value__c);

        // Delete
        RateAgreementManagerController.deleteOnCost(onCostId);
        System.assertEquals(0, [SELECT COUNT() FROM Employer_On_Cost__c WHERE Id = :onCostId]);

        // Copy defaults onto the line (line already had 1, defaults add 1 more)
        RateAgreementManagerController.copyDefaultOnCostsToLine(version.Id, line.Id);
        System.assertEquals(2, [SELECT COUNT() FROM Employer_On_Cost__c WHERE Rate_Agreement_Lines__c = :line.Id]);

        // Delete line removes its on-costs too
        RateAgreementManagerController.deleteLine(line.Id);
        System.assertEquals(0, [SELECT COUNT() FROM Rate_Agreement_Lines__c WHERE Id = :line.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Employer_On_Cost__c WHERE Rate_Agreement_Lines__c = :line.Id]);

        Test.stopTest();
    }

    // Contracts: search (unassigned only), add, list, remove
    @IsTest
    static void testContracts() {
        Rate_Agreements__c ra = [SELECT Id, Account__c FROM Rate_Agreements__c LIMIT 1];
        sirenum__ProActiveContract__c contract = [SELECT Id FROM sirenum__ProActiveContract__c LIMIT 1];

        Test.startTest();

        // No filter returns nothing
        System.assertEquals(0, RateAgreementManagerController.searchContracts(null, null).size());

        // Filtered search finds the unassigned contract
        System.assertEquals(1, RateAgreementManagerController.searchContracts('Test', ra.Account__c).size());

        // Add
        RateAgreementManagerController.addContractsToRateAgreement(ra.Id, new List<Id>{contract.Id});
        System.assertEquals(ra.Id, [SELECT Rate_Agreements__c FROM sirenum__ProActiveContract__c WHERE Id = :contract.Id].Rate_Agreements__c);
        System.assertEquals(1, RateAgreementManagerController.getContractsForRateAgreement(ra.Id).size());

        // Assigned contracts no longer appear in search
        System.assertEquals(0, RateAgreementManagerController.searchContracts('Test', ra.Account__c).size());

        // Remove
        RateAgreementManagerController.removeContractFromRateAgreement(contract.Id);
        System.assertEquals(null, [SELECT Rate_Agreements__c FROM sirenum__ProActiveContract__c WHERE Id = :contract.Id].Rate_Agreements__c);

        Test.stopTest();
    }

    // Guard clauses: null / empty arguments
    @IsTest
    static void testGuardClauses() {
        Test.startTest();

        System.assertEquals(0, RateAgreementManagerController.getScaleDefinitionsForRateAgreement(null).size());
        System.assertEquals(0, RateAgreementManagerController.getScaleDefinitionsWithLock(null).size());
        System.assertEquals(0, RateAgreementManagerController.getOnCosts(null, null).size());
        System.assertEquals(0, RateAgreementManagerController.getContractsForRateAgreement(null).size());
        RateAgreementManagerController.reorderScaleDefinitions(null);

        Integer blocked = 0;
        try { RateAgreementManagerController.getRateAgreementWorkspace(null); } catch (AuraHandledException e) { blocked++; }
        try { RateAgreementManagerController.getVersionWorkspace(null); } catch (AuraHandledException e) { blocked++; }
        try { RateAgreementManagerController.createScaleDefinition(null, 'X', null, 'R', 'D'); } catch (AuraHandledException e) { blocked++; }
        try { RateAgreementManagerController.createVersionWithScales(null, Date.today(), null); } catch (AuraHandledException e) { blocked++; }
        try { RateAgreementManagerController.cloneVersion(null, Date.today()); } catch (AuraHandledException e) { blocked++; }
        try { RateAgreementManagerController.deleteScaleDefinition(null); } catch (AuraHandledException e) { blocked++; }
        try { RateAgreementManagerController.upsertOnCost(null, null, null); } catch (AuraHandledException e) { blocked++; }
        try { RateAgreementManagerController.deleteOnCost(null); } catch (AuraHandledException e) { blocked++; }
        try { RateAgreementManagerController.copyDefaultOnCostsToLine(null, null); } catch (AuraHandledException e) { blocked++; }
        try { RateAgreementManagerController.deleteLine(null); } catch (AuraHandledException e) { blocked++; }
        try { RateAgreementManagerController.addContractsToRateAgreement(null, null); } catch (AuraHandledException e) { blocked++; }
        try { RateAgreementManagerController.removeContractFromRateAgreement(null); } catch (AuraHandledException e) { blocked++; }
        System.assertEquals(12, blocked);

        Test.stopTest();
    }
}