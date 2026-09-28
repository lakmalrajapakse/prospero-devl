public with sharing class JobRoleScaleController {

    public class JobRoleSearchResult {
        @AuraEnabled public Id jobRoleId;
        @AuraEnabled public String jobRoleName;
        @AuraEnabled public String jobTypeName;
        @AuraEnabled public String contractName;
        @AuraEnabled public String accountName;
    }

    // Searches Job Roles whose Contract belongs to the Rate Agreement; needs at least one filter.
    @AuraEnabled
    public static List<JobRoleSearchResult> searchJobRoles(
        Id rateAgreementId, String searchText, Id jobTypeId, Id accountId
    ) {
        if (rateAgreementId == null) return new List<JobRoleSearchResult>();

        Boolean hasAnyFilter = !String.isBlank(searchText) || jobTypeId != null || accountId != null;
        if (!hasAnyFilter) {
            return new List<JobRoleSearchResult>();
        }

        Map<Id, sirenum__ProActiveContract__c> eligibleContracts = new Map<Id, sirenum__ProActiveContract__c>([
            SELECT Id, Name, sirenum__Client__c, sirenum__Client__r.Name
            FROM sirenum__ProActiveContract__c
            WHERE Rate_Agreements__c = :rateAgreementId
        ]);

        if (eligibleContracts.isEmpty()) {
            return new List<JobRoleSearchResult>();
        }

        Set<Id> eligibleContractIds = eligibleContracts.keySet();

        if (accountId != null) {
            Set<Id> narrowed = new Set<Id>();
            for (sirenum__ProActiveContract__c c : eligibleContracts.values()) {
                if (c.sirenum__Client__c == accountId) {
                    narrowed.add(c.Id);
                }
            }
            eligibleContractIds = narrowed;
            if (eligibleContractIds.isEmpty()) {
                return new List<JobRoleSearchResult>();
            }
        }

        List<String> filters = new List<String>();
        filters.add('sirenum__Account__c IN :eligibleContractIds');

        String term = String.isBlank(searchText) ? null : '%' + searchText.trim() + '%';
        if (term != null) filters.add('Name LIKE :term');
        if (jobTypeId != null) filters.add('sirenum__Job_Type__c = :jobTypeId');

        String query = 'SELECT Id, Name, sirenum__Account__c, sirenum__Job_Type__r.Name ' +
            'FROM sirenum__Team__c WHERE ' + String.join(filters, ' AND ') +
            ' ORDER BY Name LIMIT 50';

        List<JobRoleSearchResult> results = new List<JobRoleSearchResult>();
        for (sirenum__Team__c jr : (List<sirenum__Team__c>) Database.query(query)) {
            sirenum__ProActiveContract__c contract = eligibleContracts.get(jr.sirenum__Account__c);

            JobRoleSearchResult r = new JobRoleSearchResult();
            r.jobRoleId = jr.Id;
            r.jobRoleName = jr.Name;
            r.jobTypeName = jr.sirenum__Job_Type__r?.Name;
            r.contractName = contract?.Name;
            r.accountName = contract?.sirenum__Client__r?.Name;
            results.add(r);
        }
        return results;
    }

    // Returns the Job Roles assigned to a Scale Definition, with their Contract and Account.
    @AuraEnabled
    public static List<Job_Role_Scale__c> getAssignmentsForDefinition(Id definitionId) {
        if (definitionId == null) return new List<Job_Role_Scale__c>();
        return [
            SELECT Id, Job_Role__c, Job_Role__r.Name,
                   Job_Role__r.sirenum__Account__r.Name,
                   Job_Role__r.sirenum__Account__r.sirenum__Client__r.Name
            FROM Job_Role_Scale__c
            WHERE Rate_Agreement_Scale_Definition__c = :definitionId
            ORDER BY Job_Role__r.Name
        ];
    }

    // Assigns Job Roles to a Scale Definition, skipping ones already assigned.
    @AuraEnabled
    public static void assignJobRoles(Id definitionId, List<Id> jobRoleIds) {
        if (definitionId == null) throw new AuraHandledException('A Scale Definition is required.');
        if (jobRoleIds == null || jobRoleIds.isEmpty()) throw new AuraHandledException('Select at least one Job Role.');

        Set<Id> existing = new Set<Id>();
        for (Job_Role_Scale__c jrs : [
            SELECT Job_Role__c
            FROM Job_Role_Scale__c
            WHERE Rate_Agreement_Scale_Definition__c = :definitionId
            AND Job_Role__c IN :jobRoleIds
        ]) {
            existing.add(jrs.Job_Role__c);
        }

        List<Job_Role_Scale__c> toInsert = new List<Job_Role_Scale__c>();
        for (Id jobRoleId : jobRoleIds) {
            if (existing.contains(jobRoleId)) continue;
            toInsert.add(new Job_Role_Scale__c(
                Job_Role__c = jobRoleId,
                Rate_Agreement_Scale_Definition__c = definitionId
            ));
        }
        if (!toInsert.isEmpty()) insert toInsert;
    }

    // Removes one Job Role assignment.
    @AuraEnabled
    public static void removeAssignment(Id junctionId) {
        if (junctionId == null) throw new AuraHandledException('A Job Role Scale assignment is required.');
        delete new Job_Role_Scale__c(Id = junctionId);
    }
}