public without sharing class EmployerOnCostManagerController {

    public class Workspace {
        @AuraEnabled public Id versionId;
        @AuraEnabled public List<Employer_On_Cost__c> costs;
    }

    // A Margin Calculator Template Rate Agreement is treated as having a single "default"
    // Version (the one this component creates, effective 01/01/1900) -- the earliest Version is
    // used if more than one somehow exists. Reads go through Apex (not a related-list LDS wire)
    // for the same reliability reason as rateManager's Rate Card Pages lookup: a related list not
    // exposed on the parent's page layout can silently return empty instead of erroring.
    @AuraEnabled(cacheable=true)
    public static Workspace getWorkspace(Id rateAgreementId){
        Workspace workspace = new Workspace();
        workspace.costs = new List<Employer_On_Cost__c>();

        List<Rate_Agreement_Version__c> versions = [
            SELECT Id
            FROM Rate_Agreement_Version__c
            WHERE Rate_Agreement__c = :rateAgreementId
            ORDER BY Effective_Date__c ASC
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            return workspace;
        }

        workspace.versionId = versions[0].Id;
        workspace.costs = [
            SELECT Id, Name, On_Cost_Type__c, Calc_Type__c, Value__c, Worker_Type__c
            FROM Employer_On_Cost__c
            WHERE Rate_Agreement_Version__c = :workspace.versionId
            ORDER BY CreatedDate ASC
        ];
        return workspace;
    }

    public class RateLineUsage {
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public List<String> sampleNames;
    }

    // A Rate Line points at a whole Rate Agreement (Employer_On_Cost__c on sirenum__Rate_Line__c
    // -- a lookup to Rate_Agreements__c despite its name), not at an individual Employer On Cost
    // row, so deleting ANY cost row under an in-use Rate Agreement is blocked the same way. Called
    // before every delete attempt in employerOnCostManager rather than cached, since it gates a
    // destructive action and must reflect the current state.
    @AuraEnabled
    public static RateLineUsage getRateLineUsage(Id rateAgreementId){
        RateLineUsage usage = new RateLineUsage();
        usage.totalCount = 0;
        usage.sampleNames = new List<String>();
        if (rateAgreementId == null) return usage;

        usage.totalCount = [SELECT COUNT() FROM sirenum__Rate_Line__c WHERE Employer_On_Cost__c = :rateAgreementId];
        if (usage.totalCount == 0) return usage;

        for (sirenum__Rate_Line__c line : [
            SELECT Name
            FROM sirenum__Rate_Line__c
            WHERE Employer_On_Cost__c = :rateAgreementId
            ORDER BY Name ASC
            LIMIT 5
        ]) {
            usage.sampleNames.add(line.Name);
        }
        return usage;
    }
}