public with sharing class RateAgreementManagerController {
    public class PageResult {
        @AuraEnabled public List<Rate_Agreements__c> records;
        @AuraEnabled public Boolean hasNextPage;
        public PageResult(List<Rate_Agreements__c> records, Boolean hasNextPage) {
            this.records = records;
            this.hasNextPage = hasNextPage;
        }
    }

    public class WorkspaceResult {
        @AuraEnabled public List<Rate_Agreement_Version__c> versions;
        public WorkspaceResult() {
            versions = new List<Rate_Agreement_Version__c>();
        }
    }

    public class VersionWorkspaceResult {
        @AuraEnabled public List<Rate_Agreement_Scale__c> scales;
        @AuraEnabled public List<Rate_Agreement_Lines__c> lines;
        public VersionWorkspaceResult() {
            scales = new List<Rate_Agreement_Scale__c>();
            lines = new List<Rate_Agreement_Lines__c>();
        }
    }

    public class ScaleInput {
        @AuraEnabled public Id scaleDefinitionId { get; set; }
        @AuraEnabled public Decimal minAmount { get; set; }
        @AuraEnabled public Decimal maxAmount { get; set; }
    }

    public class OnCostInput {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String workerType { get; set; }
        @AuraEnabled public String onCostType { get; set; }
        @AuraEnabled public String calcType { get; set; }
        @AuraEnabled public Decimal value { get; set; }
    }

    public class DefinitionRankingInput {
        @AuraEnabled public Id definitionId { get; set; }
        @AuraEnabled public Decimal ranking { get; set; }
    }

    public class DefinitionWithLock {
        @AuraEnabled public Rate_Agreement_Scale_Definition__c definition;
        @AuraEnabled public Boolean isLocked;
    }

    // Returns a page of Pay Based Rate Agreements, most recently viewed first.
    @AuraEnabled
    public static PageResult getRateAgreementsPage(
        String agreementName, Id accountId, /* String agreementType, */ Integer pageNumber
    ) {
        Integer safePage = pageNumber == null || pageNumber < 1 ? 1 : pageNumber;
        Integer pageSize = 50;
        Integer recordOffset = (safePage - 1) * pageSize;
        String nameFilter = String.isBlank(agreementName) ? null : '%' + agreementName.trim() + '%';

        List<String> filters = new List<String>();
        filters.add('Type__c = \'Pay Based\'');
        if (nameFilter != null) filters.add('Name LIKE :nameFilter');
        if (accountId != null) filters.add('Account__c = :accountId');
        // if (!String.isBlank(agreementType)) filters.add('Type__c = :agreementType');

        Integer queryLimit = pageSize + 1;
        String query = 'SELECT Id, Name, Account__c, Account__r.Name ' +
            /* 'SELECT Id, Name, Account__c, Account__r.Name, Type__c ' + */
            'FROM Rate_Agreements__c';
        if (!filters.isEmpty()) query += ' WHERE ' + String.join(filters, ' AND ');
        query += ' ORDER BY LastViewedDate DESC NULLS LAST, Id DESC LIMIT :queryLimit OFFSET :recordOffset';

        List<Rate_Agreements__c> rows = Database.query(query);

        Boolean hasNext = rows.size() > pageSize;
        if (hasNext) rows.remove(rows.size() - 1);
        return new PageResult(rows, hasNext);
    }

    // Returns a Rate Agreement's versions and marks it as viewed.
    @AuraEnabled
    public static WorkspaceResult getRateAgreementWorkspace(Id rateAgreementId) {
        if (rateAgreementId == null) throw new AuraHandledException('A Rate Agreement is required.');

        List<Rate_Agreements__c> touched = [
            SELECT Id FROM Rate_Agreements__c WHERE Id = :rateAgreementId FOR VIEW
        ];

        WorkspaceResult result = new WorkspaceResult();
        result.versions = [
            SELECT Id, Name, Effective_Date__c
            FROM Rate_Agreement_Version__c
            WHERE Rate_Agreement__c = :rateAgreementId
            ORDER BY Effective_Date__c DESC, CreatedDate DESC
        ];
        return result;
    }

    // Returns Scale Definitions in ranking order, flagging those already used by a Scale.
    @AuraEnabled
    public static List<DefinitionWithLock> getScaleDefinitionsWithLock(Id rateAgreementId) {
        if (rateAgreementId == null) return new List<DefinitionWithLock>();

        List<Rate_Agreement_Scale_Definition__c> defs = [
            SELECT Id, Name, Job_Type__c, Region__c, Description__c, Ranking__c
            FROM Rate_Agreement_Scale_Definition__c
            WHERE Rate_Agreements__c = :rateAgreementId
            ORDER BY Ranking__c, Name
        ];

        Set<Id> defIds = new Set<Id>();
        for (Rate_Agreement_Scale_Definition__c d : defs) defIds.add(d.Id);

        Set<Id> lockedIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Rate_Agreement_Scale_Definition__c defId
            FROM Rate_Agreement_Scale__c
            WHERE Rate_Agreement_Scale_Definition__c IN :defIds
            GROUP BY Rate_Agreement_Scale_Definition__c
        ]) {
            lockedIds.add((Id) ar.get('defId'));
        }

        List<DefinitionWithLock> result = new List<DefinitionWithLock>();
        for (Rate_Agreement_Scale_Definition__c d : defs) {
            DefinitionWithLock w = new DefinitionWithLock();
            w.definition = d;
            w.isLocked = lockedIds.contains(d.Id);
            result.add(w);
        }
        return result;
    }

    // Creates a Scale Definition ranked after the current highest.
    @AuraEnabled
    public static Id createScaleDefinition(
        Id rateAgreementId, String name, String jobType, String region, String description
    ) {
        if (rateAgreementId == null) throw new AuraHandledException('A Rate Agreement is required.');

        Decimal maxRanking = 0;
        for (AggregateResult ar : [
            SELECT MAX(Ranking__c) maxRank
            FROM Rate_Agreement_Scale_Definition__c
            WHERE Rate_Agreements__c = :rateAgreementId
        ]) {
            Object m = ar.get('maxRank');
            if (m != null) maxRanking = (Decimal) m;
        }

        Rate_Agreement_Scale_Definition__c def = new Rate_Agreement_Scale_Definition__c(
            Rate_Agreements__c = rateAgreementId,
            Name = name,
            Job_Type__c = jobType,
            Region__c = region,
            Description__c = description,
            Ranking__c = maxRanking + 1
        );
        insert def;
        return def.Id;
    }

    // Saves new rankings; rejects definitions already used by a Scale.
    @AuraEnabled
    public static void reorderScaleDefinitions(List<DefinitionRankingInput> orderedDefinitions) {
        if (orderedDefinitions == null || orderedDefinitions.isEmpty()) return;

        Set<Id> defIds = new Set<Id>();
        for (DefinitionRankingInput r : orderedDefinitions) defIds.add(r.definitionId);

        Set<Id> lockedIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Rate_Agreement_Scale_Definition__c defId
            FROM Rate_Agreement_Scale__c
            WHERE Rate_Agreement_Scale_Definition__c IN :defIds
            GROUP BY Rate_Agreement_Scale_Definition__c
        ]) {
            lockedIds.add((Id) ar.get('defId'));
        }
        if (!lockedIds.isEmpty()) {
            throw new AuraHandledException('One or more Scale Definitions are linked to existing Rate Agreement Scales and cannot be reordered.');
        }

        List<Rate_Agreement_Scale_Definition__c> toUpdate = new List<Rate_Agreement_Scale_Definition__c>();
        for (DefinitionRankingInput r : orderedDefinitions) {
            toUpdate.add(new Rate_Agreement_Scale_Definition__c(
                Id = r.definitionId,
                Ranking__c = r.ranking
            ));
        }
        update toUpdate;
    }

    // Deletes a Scale Definition unless a Scale uses it.
    @AuraEnabled
    public static void deleteScaleDefinition(Id definitionId) {
        if (definitionId == null) throw new AuraHandledException('A Scale Definition is required.');

        Integer linkedCount = [
            SELECT COUNT()
            FROM Rate_Agreement_Scale__c
            WHERE Rate_Agreement_Scale_Definition__c = :definitionId
        ];
        if (linkedCount > 0) {
            throw new AuraHandledException('This Scale Definition is linked to existing Rate Agreement Scales and cannot be deleted.');
        }

        delete new Rate_Agreement_Scale_Definition__c(Id = definitionId);
    }

    // Returns a Rate Agreement's Scale Definitions in ranking order.
    @AuraEnabled(cacheable=true)
    public static List<Rate_Agreement_Scale_Definition__c> getScaleDefinitionsForRateAgreement(Id rateAgreementId) {
        if (rateAgreementId == null) return new List<Rate_Agreement_Scale_Definition__c>();
        return [
            SELECT Id, Name, Job_Type__c, Region__c, Description__c, Ranking__c
            FROM Rate_Agreement_Scale_Definition__c
            WHERE Rate_Agreements__c = :rateAgreementId
            ORDER BY Ranking__c, Name
        ];
    }

    // Throws if the Rate Agreement already has a version on this date.
    private static void validateNoDuplicateEffectiveDate(Id rateAgreementId, Date effectiveDate) {
        Integer existing = [
            SELECT COUNT()
            FROM Rate_Agreement_Version__c
            WHERE Rate_Agreement__c = :rateAgreementId
            AND Effective_Date__c = :effectiveDate
        ];
        if (existing > 0) {
            throw new AuraHandledException('A version with this Effective Date already exists for this Rate Agreement. Please choose a different date.');
        }
    }

    // Creates a version and its Scales in one transaction.
    @AuraEnabled
    public static Id createVersionWithScales(
        Id rateAgreementId, Date effectiveDate, List<ScaleInput> scales
    ) {
        if (rateAgreementId == null) throw new AuraHandledException('A Rate Agreement is required.');
        if (effectiveDate == null) throw new AuraHandledException('An Effective Date is required.');
        validateNoDuplicateEffectiveDate(rateAgreementId, effectiveDate);

        Rate_Agreement_Version__c version = new Rate_Agreement_Version__c(
            Rate_Agreement__c = rateAgreementId,
            Effective_Date__c = effectiveDate
        );
        insert version;

        List<Rate_Agreement_Scale__c> newScales = new List<Rate_Agreement_Scale__c>();
        if (scales != null) {
            for (ScaleInput s : scales) {
                if (s.scaleDefinitionId == null) continue;
                newScales.add(new Rate_Agreement_Scale__c(
                    Rate_Agreement_Version__c = version.Id,
                    Rate_Agreement_Scale_Definition__c = s.scaleDefinitionId,
                    Min_Amount__c = s.minAmount,
                    Max_Amount__c = s.maxAmount
                ));
            }
        }
        if (!newScales.isEmpty()) insert newScales;

        return version.Id;
    }

    // Copies a version, with its Scales, Lines and on-costs, to a new effective date.
    @AuraEnabled
    public static Id cloneVersion(Id sourceVersionId, Date newEffectiveDate) {
        if (sourceVersionId == null) throw new AuraHandledException('A source Version is required.');
        if (newEffectiveDate == null) throw new AuraHandledException('A new Effective Date is required.');

        Rate_Agreement_Version__c source = [
            SELECT Id, Rate_Agreement__c
            FROM Rate_Agreement_Version__c
            WHERE Id = :sourceVersionId
        ];

        validateNoDuplicateEffectiveDate(source.Rate_Agreement__c, newEffectiveDate);

        Rate_Agreement_Version__c newVersion = new Rate_Agreement_Version__c(
            Rate_Agreement__c = source.Rate_Agreement__c,
            Effective_Date__c = newEffectiveDate
        );
        insert newVersion;

        Map<Id, Id> scaleIdMap = new Map<Id, Id>();
        List<Rate_Agreement_Scale__c> sourceScales = [
            SELECT Id, Rate_Agreement_Scale_Definition__c, Min_Amount__c, Max_Amount__c
            FROM Rate_Agreement_Scale__c
            WHERE Rate_Agreement_Version__c = :sourceVersionId
        ];
        List<Rate_Agreement_Scale__c> newScales = new List<Rate_Agreement_Scale__c>();
        for (Rate_Agreement_Scale__c s : sourceScales) {
            newScales.add(new Rate_Agreement_Scale__c(
                Rate_Agreement_Version__c = newVersion.Id,
                Rate_Agreement_Scale_Definition__c = s.Rate_Agreement_Scale_Definition__c,
                Min_Amount__c = s.Min_Amount__c,
                Max_Amount__c = s.Max_Amount__c
            ));
        }
        if (!newScales.isEmpty()) {
            insert newScales;
            for (Integer i = 0; i < sourceScales.size(); i++) {
                scaleIdMap.put(sourceScales[i].Id, newScales[i].Id);
            }
        }

        Map<Id, Id> lineIdMap = new Map<Id, Id>();
        List<Rate_Agreement_Lines__c> sourceLines = [
            SELECT Id, Worker_Type__c, Min_Scale__c, Max_Scale__c, Calc_Type__c, Margin_Value__c
            FROM Rate_Agreement_Lines__c
            WHERE Rate_Agreement_Version__c = :sourceVersionId
        ];
        List<Rate_Agreement_Lines__c> newLines = new List<Rate_Agreement_Lines__c>();
        for (Rate_Agreement_Lines__c l : sourceLines) {
            newLines.add(new Rate_Agreement_Lines__c(
                Rate_Agreement_Version__c = newVersion.Id,
                Worker_Type__c = l.Worker_Type__c,
                Min_Scale__c = scaleIdMap.get(l.Min_Scale__c),
                Max_Scale__c = scaleIdMap.get(l.Max_Scale__c),
                Calc_Type__c = l.Calc_Type__c,
                Margin_Value__c = l.Margin_Value__c
            ));
        }
        if (!newLines.isEmpty()) {
            insert newLines;
            for (Integer i = 0; i < sourceLines.size(); i++) {
                lineIdMap.put(sourceLines[i].Id, newLines[i].Id);
            }
        }

        List<Employer_On_Cost__c> sourceOnCosts = [
            SELECT Id, Rate_Agreement_Lines__c, Worker_Type__c, On_Cost_Type__c, Calc_Type__c, Value__c
            FROM Employer_On_Cost__c
            WHERE Rate_Agreement_Version__c = :sourceVersionId
        ];
        List<Employer_On_Cost__c> newOnCosts = new List<Employer_On_Cost__c>();
        for (Employer_On_Cost__c oc : sourceOnCosts) {
            Id newLineId;
            if (oc.Rate_Agreement_Lines__c != null) {
                newLineId = lineIdMap.get(oc.Rate_Agreement_Lines__c);
                if (newLineId == null) continue;
            }
            newOnCosts.add(new Employer_On_Cost__c(
                Rate_Agreement_Version__c = newVersion.Id,
                Rate_Agreement_Lines__c = newLineId,
                Worker_Type__c = oc.Worker_Type__c,
                On_Cost_Type__c = oc.On_Cost_Type__c,
                Calc_Type__c = oc.Calc_Type__c,
                Value__c = oc.Value__c
            ));
        }
        if (!newOnCosts.isEmpty()) insert newOnCosts;

        return newVersion.Id;
    }

    // Returns a version's Scales and Lines.
    @AuraEnabled
    public static VersionWorkspaceResult getVersionWorkspace(Id versionId) {
        if (versionId == null) throw new AuraHandledException('A Rate Agreement Version is required.');
        VersionWorkspaceResult result = new VersionWorkspaceResult();
        result.scales = [
            SELECT Id, Name, Min_Amount__c, Max_Amount__c,
                   Rate_Agreement_Scale_Definition__c,
                   Rate_Agreement_Scale_Definition__r.Name,
                   Rate_Agreement_Scale_Definition__r.Job_Type__c,
                   Rate_Agreement_Scale_Definition__r.Region__c,
                   Rate_Agreement_Scale_Definition__r.Description__c,
                   Rate_Agreement_Scale_Definition__r.Ranking__c
            FROM Rate_Agreement_Scale__c
            WHERE Rate_Agreement_Version__c = :versionId
            ORDER BY Rate_Agreement_Scale_Definition__r.Ranking__c, Name
        ];
        result.lines = [
            SELECT Id, Name, Worker_Type__c, Min_Scale__c, Max_Scale__c, Calc_Type__c, Margin_Value__c
            FROM Rate_Agreement_Lines__c
            WHERE Rate_Agreement_Version__c = :versionId
            ORDER BY CreatedDate
        ];
        return result;
    }

    // Returns a version's default on-costs, or a Line's on-costs when lineId is given.
    @AuraEnabled
    public static List<Employer_On_Cost__c> getOnCosts(Id versionId, Id lineId) {
        if (versionId == null) return new List<Employer_On_Cost__c>();
        String query = 'SELECT Id, Name, Worker_Type__c, On_Cost_Type__c, Calc_Type__c, Value__c ' +
            'FROM Employer_On_Cost__c WHERE Rate_Agreement_Version__c = :versionId';
        query += lineId != null ? ' AND Rate_Agreement_Lines__c = :lineId' : ' AND Rate_Agreement_Lines__c = NULL';
        query += ' ORDER BY CreatedDate';
        return Database.query(query);
    }

    // Inserts or updates one Employer On Cost.
    @AuraEnabled
    public static Id upsertOnCost(Id versionId, Id lineId, OnCostInput input) {
        if (versionId == null) throw new AuraHandledException('A Version is required.');

        Employer_On_Cost__c rec = input.id != null
            ? new Employer_On_Cost__c(Id = input.id)
            : new Employer_On_Cost__c(
                Rate_Agreement_Version__c = versionId,
                Rate_Agreement_Lines__c = lineId
              );

        rec.Worker_Type__c = input.workerType;
        rec.On_Cost_Type__c = input.onCostType;
        rec.Calc_Type__c = input.calcType;
        rec.Value__c = input.value;
        upsert rec;
        return rec.Id;
    }

    // Deletes one Employer On Cost.
    @AuraEnabled
    public static void deleteOnCost(Id onCostId) {
        if (onCostId == null) throw new AuraHandledException('An Employer On Cost record is required.');
        delete new Employer_On_Cost__c(Id = onCostId);
    }

    // Copies a version's default on-costs onto a Line.
    @AuraEnabled
    public static void copyDefaultOnCostsToLine(Id versionId, Id lineId) {
        if (versionId == null || lineId == null) throw new AuraHandledException('A Version and Line are required.');

        List<Employer_On_Cost__c> defaults = [
            SELECT Worker_Type__c, On_Cost_Type__c, Calc_Type__c, Value__c
            FROM Employer_On_Cost__c
            WHERE Rate_Agreement_Version__c = :versionId AND Rate_Agreement_Lines__c = NULL
        ];

        List<Employer_On_Cost__c> lineOnCosts = new List<Employer_On_Cost__c>();
        for (Employer_On_Cost__c d : defaults) {
            lineOnCosts.add(new Employer_On_Cost__c(
                Rate_Agreement_Version__c = versionId,
                Rate_Agreement_Lines__c = lineId,
                Worker_Type__c = d.Worker_Type__c,
                On_Cost_Type__c = d.On_Cost_Type__c,
                Calc_Type__c = d.Calc_Type__c,
                Value__c = d.Value__c
            ));
        }
        if (!lineOnCosts.isEmpty()) insert lineOnCosts;
    }

    // Deletes a Line and its on-costs.
    @AuraEnabled
    public static void deleteLine(Id lineId) {
        if (lineId == null) throw new AuraHandledException('A Rate Agreement Line is required.');
        delete [SELECT Id FROM Employer_On_Cost__c WHERE Rate_Agreement_Lines__c = :lineId];
        delete new Rate_Agreement_Lines__c(Id = lineId);
    }

    // Searches Contracts not yet assigned to any Rate Agreement; needs a name or account.
    @AuraEnabled
    public static List<sirenum__ProActiveContract__c> searchContracts(String contractName, Id accountId) {
        Boolean hasAnyFilter = !String.isBlank(contractName) || accountId != null;
        if (!hasAnyFilter) {
            return new List<sirenum__ProActiveContract__c>();
        }

        List<String> filters = new List<String>();
        filters.add('Rate_Agreements__c = NULL');

        String nameFilter = String.isBlank(contractName) ? null : '%' + contractName.trim() + '%';
        if (nameFilter != null) filters.add('Name LIKE :nameFilter');
        if (accountId != null) filters.add('sirenum__Client__c = :accountId');

        String query = 'SELECT Id, Name, sirenum__Client__c, sirenum__Client__r.Name ' +
            'FROM sirenum__ProActiveContract__c WHERE ' + String.join(filters, ' AND ') +
            ' ORDER BY Name LIMIT 50';

        return Database.query(query);
    }

    // Returns the Contracts assigned to a Rate Agreement.
    @AuraEnabled
    public static List<sirenum__ProActiveContract__c> getContractsForRateAgreement(Id rateAgreementId) {
        if (rateAgreementId == null) return new List<sirenum__ProActiveContract__c>();
        return [
            SELECT Id, Name, sirenum__Client__c, sirenum__Client__r.Name
            FROM sirenum__ProActiveContract__c
            WHERE Rate_Agreements__c = :rateAgreementId
            ORDER BY Name
        ];
    }

    // Assigns Contracts to a Rate Agreement.
    @AuraEnabled
    public static void addContractsToRateAgreement(Id rateAgreementId, List<Id> contractIds) {
        if (rateAgreementId == null) throw new AuraHandledException('A Rate Agreement is required.');
        if (contractIds == null || contractIds.isEmpty()) throw new AuraHandledException('Select at least one Contract.');

        List<sirenum__ProActiveContract__c> toUpdate = new List<sirenum__ProActiveContract__c>();
        for (Id contractId : contractIds) {
            toUpdate.add(new sirenum__ProActiveContract__c(
                Id = contractId,
                Rate_Agreements__c = rateAgreementId
            ));
        }
        update toUpdate;
    }

    // Clears a Contract's Rate Agreement.
    @AuraEnabled
    public static void removeContractFromRateAgreement(Id contractId) {
        if (contractId == null) throw new AuraHandledException('A Contract is required.');
        update new sirenum__ProActiveContract__c(
            Id = contractId,
            Rate_Agreements__c = null
        );
    }
}