public without sharing class MarginCalculatorController {

    public class AgreementDetails {
        @AuraEnabled public String jobRoleName;
        @AuraEnabled public String workerName;
        @AuraEnabled public String contractName;
        @AuraEnabled public String rateAgreementName;
        // True when the Placement's Contract has its own Rate Agreement -- the Rate-Agreement
        // mode of the Add/Edit Rate Line modal (see getRateAgreementLineContext) only applies
        // when this is true; otherwise the Employer On Cost mode applies, same as always.
        @AuraEnabled public Boolean hasRateAgreement;
        // Set (only when hasRateAgreement is true) when the Placement can't actually be validated
        // against that Rate Agreement -- no Job Role Scale assigned, or that Scale has no Rate
        // Agreement Scale Definition configured. rateManager and marginCalculatorComponent both
        // block ALL Rate Card/Page/Line creation on this and show it as an on-screen error,
        // mirroring the same prerequisite rateLineTriggerCustomHandler itself requires before it
        // can resolve a Rate Agreement Version to validate against.
        @AuraEnabled public String blockingError;
    }

    public class LineWithAwr {
        @AuraEnabled public sirenum__Rate_Line__c line;
        // Null when this Rate Line has no AWR (sirenum__Rate_Modifier_Type__c.Name = 'AWR')
        // sirenum__Rate_Modifier__c child.
        @AuraEnabled public sirenum__Rate_Modifier__c awrModifier;
    }

    public class PageWithLines {
        @AuraEnabled public sirenum__Rate_Card_Page__c page;
        @AuraEnabled public List<LineWithAwr> lines;
    }

    @AuraEnabled(cacheable=true)
    public static AgreementDetails getAgreementDetails(Id placementId){
        AgreementDetails details = new AgreementDetails();
        if(placementId == null) return details;

        List<sirenum__Placement__c> placements = [
            SELECT sirenum__Job_Role__r.Name, sirenum__Contact__r.Name, sirenum__Contract__r.Name,
                   sirenum__Contract__r.Rate_Agreements__c, sirenum__Contract__r.Rate_Agreements__r.Name,
                   Job_Role_Scale__c, Job_Role_Scale__r.Rate_Agreement_Scale_Definition__c
            FROM sirenum__Placement__c
            WHERE Id = :placementId
            LIMIT 1
        ];
        if(placements.isEmpty()) return details;

        sirenum__Placement__c placement = placements[0];
        details.jobRoleName = placement.sirenum__Job_Role__r?.Name;
        details.workerName = placement.sirenum__Contact__r?.Name;
        details.contractName = placement.sirenum__Contract__r?.Name;
        details.rateAgreementName = placement.sirenum__Contract__r?.Rate_Agreements__r?.Name;

        details.hasRateAgreement = placement.sirenum__Contract__r?.Rate_Agreements__c != null;
        if(details.hasRateAgreement){
            if(placement.Job_Role_Scale__c == null){
                details.blockingError = 'This Placement\'s Contract has a Rate Agreement, but the Placement has no Job Role Scale assigned. Rate Card/Page/Rate Line creation is blocked until one is set.';
            } else if(placement.Job_Role_Scale__r?.Rate_Agreement_Scale_Definition__c == null){
                details.blockingError = 'This Placement\'s Contract has a Rate Agreement, but its Job Role Scale has no Rate Agreement Scale Definition configured. Rate Card/Page/Rate Line creation is blocked until one is set.';
            }
        }
        return details;
    }

    // When onlyPageId is given (Shift "restricted" mode), just that one Page scoped to
    // rateCardId for safety. Otherwise (Placement/Job Role "full" mode), every Page with a
    // blank condition under rateCardId -- a Placement can have several of these over time (each
    // its own effective-dated version), but never a Shift-condition Page, which only ever shows
    // via onlyPageId. A direct query, not a related-list LDS wire (unreliable for this schema --
    // see rateManager's Rate Card Page fix).
    @AuraEnabled(cacheable=true)
    public static List<PageWithLines> getRateCardPages(Id rateCardId, Id onlyPageId){
        List<PageWithLines> results = new List<PageWithLines>();
        if(rateCardId == null) return results;

        List<sirenum__Rate_Card_Page__c> pages = onlyPageId != null
            ? [SELECT Id, Name, sirenum__Valid_From_Date__c, sirenum__Valid_Until_Date__c, sirenum__SortOrder__c
               FROM sirenum__Rate_Card_Page__c
               WHERE Id = :onlyPageId AND sirenum__Rate_Card__c = :rateCardId]
            : [SELECT Id, Name, sirenum__Valid_From_Date__c, sirenum__Valid_Until_Date__c, sirenum__SortOrder__c
               FROM sirenum__Rate_Card_Page__c
               WHERE sirenum__Rate_Card__c = :rateCardId AND sirenum__Condition_Suggestions__c = null
               ORDER BY sirenum__SortOrder__c ASC];

        if(pages.isEmpty()) return results;

        Set<Id> pageIds = new Set<Id>();
        for(sirenum__Rate_Card_Page__c p : pages) pageIds.add(p.Id);

        Set<Id> lineIds = new Set<Id>();
        Map<Id, List<sirenum__Rate_Line__c>> linesByPage = new Map<Id, List<sirenum__Rate_Line__c>>();
        for(sirenum__Rate_Line__c line : [
            SELECT Id, Name, sirenum__Rate_Card_Page__c, sirenum__Code__c, sirenum__Standard_Rate_Type__c,
                   sirenum__Standard_Rate_Type__r.Name, sirenum__Pay_Rate__c, sirenum__Charge_Rate__c,
                   Margin__c, Margin_Type__c, Employer_On_Cost__c, sirenum__Unit__c,
                   sirenum__Start_Hour__c, sirenum__End_Hour__c, sirenum__Day_Type__c, sirenum__SortOrder__c
            FROM sirenum__Rate_Line__c
            WHERE sirenum__Rate_Card_Page__c IN :pageIds
            ORDER BY sirenum__SortOrder__c ASC
        ]){
            lineIds.add(line.Id);
            if(!linesByPage.containsKey(line.sirenum__Rate_Card_Page__c)){
                linesByPage.put(line.sirenum__Rate_Card_Page__c, new List<sirenum__Rate_Line__c>());
            }
            linesByPage.get(line.sirenum__Rate_Card_Page__c).add(line);
        }

        // At most one AWR (sirenum__Rate_Modifier_Type__c.Name = 'AWR') Rate Modifier per Rate
        // Line -- the toggle in the Add/Edit Rate Line modal creates/updates/deletes exactly one.
        Map<Id, sirenum__Rate_Modifier__c> awrByLine = new Map<Id, sirenum__Rate_Modifier__c>();
        if(!lineIds.isEmpty()){
            for(sirenum__Rate_Modifier__c modifier : [
                SELECT Id, sirenum__Rate_Line__c, sirenum__Pay_Rate__c, sirenum__Charge_Rate__c,
                       Margin__c, Margin_Type__c
                FROM sirenum__Rate_Modifier__c
                WHERE sirenum__Rate_Line__c IN :lineIds AND sirenum__Rate_Modifier_Type__r.Name = 'AWR'
            ]){
                awrByLine.put(modifier.sirenum__Rate_Line__c, modifier);
            }
        }

        for(sirenum__Rate_Card_Page__c p : pages){
            PageWithLines pwl = new PageWithLines();
            pwl.page = p;
            pwl.lines = new List<LineWithAwr>();
            for(sirenum__Rate_Line__c line : (linesByPage.containsKey(p.Id) ? linesByPage.get(p.Id) : new List<sirenum__Rate_Line__c>())){
                LineWithAwr lwa = new LineWithAwr();
                lwa.line = line;
                lwa.awrModifier = awrByLine.get(line.Id);
                pwl.lines.add(lwa);
            }
            results.add(pwl);
        }
        return results;
    }

    // "Clone" on a Rate Card Page -- creates a new Page on the SAME Rate Card (named newPageName,
    // effective from newValidFromDate), with every one of the source Page's Rate Lines, and each
    // Line's own AWR modifier (if any), copied onto it. The source Page is "ended" as part of the
    // same clone -- its own Valid Until Date is set to the day before newValidFromDate, so the two
    // Pages' effective windows never overlap. A bulk Apex operation rather than many individual
    // LWC createRecord() calls -- both for one round trip and so the whole clone (source Page
    // update + new Page + Lines + Modifiers) succeeds or fails together. Every inserted Rate
    // Line/Rate Modifier still runs through rateLineTriggerCustomHandler like any other insert --
    // a clone onto a Page whose own dates resolve to a different Rate Agreement Version is
    // validated against THAT Version, not blindly accepted just because the source Line was
    // already valid.
    @AuraEnabled
    public static Id clonePage(Id sourcePageId, String newPageName, Date newValidFromDate){
        if(sourcePageId == null || String.isBlank(newPageName) || newValidFromDate == null){
            throw new AuraHandledException('A source Page, a new Page Name, and an Effective Date are required.');
        }

        List<sirenum__Rate_Card_Page__c> sourcePages = [
            SELECT Id, sirenum__Rate_Card__c, sirenum__Valid_From_Date__c, sirenum__Valid_Until_Date__c
            FROM sirenum__Rate_Card_Page__c
            WHERE Id = :sourcePageId
            LIMIT 1
        ];
        if(sourcePages.isEmpty()){
            throw new AuraHandledException('Source Rate Card Page not found.');
        }
        sirenum__Rate_Card_Page__c sourcePage = sourcePages[0];

        if(sourcePage.sirenum__Valid_From_Date__c != null && newValidFromDate <= sourcePage.sirenum__Valid_From_Date__c){
            throw new AuraHandledException('Effective Date must be after the source Page\'s own Valid From Date (' + sourcePage.sirenum__Valid_From_Date__c + ').');
        }

        // The new Page inherits whatever end date the source Page originally had (often none --
        // open-ended) -- captured BEFORE the source Page's own end date is overwritten below.
        Date inheritedValidUntil = sourcePage.sirenum__Valid_Until_Date__c;

        sourcePage.sirenum__Valid_Until_Date__c = newValidFromDate.addDays(-1);
        update sourcePage;

        Decimal maxSortOrder = 0;
        for(AggregateResult ar : [
            SELECT MAX(sirenum__SortOrder__c) maxOrder
            FROM sirenum__Rate_Card_Page__c
            WHERE sirenum__Rate_Card__c = :sourcePage.sirenum__Rate_Card__c
        ]){
            Object maxVal = ar.get('maxOrder');
            if(maxVal != null) maxSortOrder = (Decimal) maxVal;
        }

        sirenum__Rate_Card_Page__c newPage = new sirenum__Rate_Card_Page__c(
            sirenum__Rate_Card__c = sourcePage.sirenum__Rate_Card__c,
            Name = newPageName,
            sirenum__Valid_From_Date__c = newValidFromDate,
            sirenum__Valid_Until_Date__c = inheritedValidUntil,
            sirenum__SortOrder__c = maxSortOrder + 1
        );
        insert newPage;

        List<sirenum__Rate_Line__c> sourceLines = [
            SELECT Id, sirenum__Standard_Rate_Type__c, sirenum__Code__c, Employer_On_Cost__c,
                   sirenum__Unit__c, sirenum__Start_Hour__c, sirenum__End_Hour__c, sirenum__Day_Type__c,
                   sirenum__Pay_Rate__c, sirenum__Charge_Rate__c, Margin__c, Margin_Type__c, sirenum__SortOrder__c
            FROM sirenum__Rate_Line__c
            WHERE sirenum__Rate_Card_Page__c = :sourcePageId
            ORDER BY sirenum__SortOrder__c ASC
        ];
        if(sourceLines.isEmpty()){
            return newPage.Id;
        }

        List<sirenum__Rate_Line__c> newLines = new List<sirenum__Rate_Line__c>();
        for(sirenum__Rate_Line__c line : sourceLines){
            newLines.add(new sirenum__Rate_Line__c(
                sirenum__Rate_Card_Page__c = newPage.Id,
                sirenum__Standard_Rate_Type__c = line.sirenum__Standard_Rate_Type__c,
                sirenum__Code__c = line.sirenum__Code__c,
                Employer_On_Cost__c = line.Employer_On_Cost__c,
                sirenum__Unit__c = line.sirenum__Unit__c,
                sirenum__Start_Hour__c = line.sirenum__Start_Hour__c,
                sirenum__End_Hour__c = line.sirenum__End_Hour__c,
                sirenum__Day_Type__c = line.sirenum__Day_Type__c,
                sirenum__Pay_Rate__c = line.sirenum__Pay_Rate__c,
                sirenum__Charge_Rate__c = line.sirenum__Charge_Rate__c,
                Margin__c = line.Margin__c,
                Margin_Type__c = line.Margin_Type__c,
                sirenum__SortOrder__c = line.sirenum__SortOrder__c
            ));
        }
        insert newLines;

        Map<Id, Id> oldLineIdToNewLineId = new Map<Id, Id>();
        for(Integer i = 0; i < sourceLines.size(); i++){
            oldLineIdToNewLineId.put(sourceLines[i].Id, newLines[i].Id);
        }

        List<sirenum__Rate_Modifier__c> sourceModifiers = [
            SELECT Id, sirenum__Rate_Line__c, sirenum__Rate_Modifier_Type__c, sirenum__Pay_Rate__c,
                   sirenum__Charge_Rate__c, Margin__c, Margin_Type__c
            FROM sirenum__Rate_Modifier__c
            WHERE sirenum__Rate_Line__c IN :oldLineIdToNewLineId.keySet()
        ];
        if(!sourceModifiers.isEmpty()){
            List<sirenum__Rate_Modifier__c> newModifiers = new List<sirenum__Rate_Modifier__c>();
            for(sirenum__Rate_Modifier__c modifier : sourceModifiers){
                Id newLineId = oldLineIdToNewLineId.get(modifier.sirenum__Rate_Line__c);
                if(newLineId == null) continue;
                newModifiers.add(new sirenum__Rate_Modifier__c(
                    sirenum__Rate_Line__c = newLineId,
                    sirenum__Rate_Modifier_Type__c = modifier.sirenum__Rate_Modifier_Type__c,
                    sirenum__Pay_Rate__c = modifier.sirenum__Pay_Rate__c,
                    sirenum__Charge_Rate__c = modifier.sirenum__Charge_Rate__c,
                    Margin__c = modifier.Margin__c,
                    Margin_Type__c = modifier.Margin_Type__c
                ));
            }
            if(!newModifiers.isEmpty()){
                insert newModifiers;
            }
        }

        return newPage.Id;
    }

    // The single sirenum__Rate_Modifier_Type__c record representing AWR -- the Add/Edit Rate
    // Line modal's "AWR Applies" toggle links every AWR Rate Modifier it creates to this same
    // record, so it never needs the user to pick one.
    @AuraEnabled(cacheable=true)
    public static Id getAwrRateModifierTypeId(){
        List<sirenum__Rate_Modifier_Type__c> types = [
            SELECT Id FROM sirenum__Rate_Modifier_Type__c WHERE Name = 'AWR' LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }

    public class RateAgreementLineContext {
        // Set when resolution fails at any step (no Rate Agreement Version/Scale/Line applicable)
        // -- the Add/Edit Rate Line modal shows this instead of the Pay Rate/Calculate UI.
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Id rateAgreementLineId;
        // Rate_Agreement_Lines__c.Calc_Type__c -- 'Fixed Margin Amount' / 'Fixed Margin %' /
        // 'Max Margin Amount' / 'Max Margin %'.
        @AuraEnabled public String calcType;
        @AuraEnabled public Decimal marginValue;
        @AuraEnabled public Decimal payScaleMin;
        @AuraEnabled public Decimal payScaleMax;
        @AuraEnabled public String workerType;
        // ALL Employer On Cost rows for this Rate Agreement Line (Type__c = 'Record Agreement
        // Line'), unfiltered by Worker Type -- used both for the "View Employer On Cost" table
        // (every row, every field) and, filtered client-side the same way getEmployerOnCosts
        // filters above, for the live Total Cost calculation (including AWR, which reuses it).
        @AuraEnabled public List<Employer_On_Cost__c> employerOnCosts;
    }

    // Resolves the SAME chain rateLineTriggerCustomHandler.validateRateAgreementMargin resolves
    // for a Rate Line on this Rate Card Page -- Rate Agreement Version (by the Page's validity
    // window) -> the Placement's own Pay Scale (by its Job Role Scale's Scale Definition) ->
    // applicable Rate Agreement Line (by that scale's ranking + resolved Worker Type). Read-only
    // and reuses the trigger's own public static resolution helpers directly, so it can never
    // resolve something different from what the trigger itself would enforce on save.
    @AuraEnabled(cacheable=true)
    public static RateAgreementLineContext getRateAgreementLineContext(Id placementId, Id rateCardPageId){
        RateAgreementLineContext ctx = new RateAgreementLineContext();
        if(placementId == null || rateCardPageId == null){
            ctx.errorMessage = 'Placement and Rate Card Page are required.';
            return ctx;
        }

        List<sirenum__Rate_Card_Page__c> pages = [
            SELECT Id, sirenum__Valid_From_Date__c, sirenum__Valid_Until_Date__c
            FROM sirenum__Rate_Card_Page__c
            WHERE Id = :rateCardPageId
            LIMIT 1
        ];
        if(pages.isEmpty()){
            ctx.errorMessage = 'Rate Card Page not found.';
            return ctx;
        }
        sirenum__Rate_Card_Page__c page = pages[0];

        List<sirenum__Placement__c> placements = [
            SELECT sirenum__Contract__r.Rate_Agreements__c,
                   Job_Role_Scale__c, Job_Role_Scale__r.Rate_Agreement_Scale_Definition__c,
                   Job_Role_Scale__r.Rate_Agreement_Scale_Definition__r.Ranking__c,
                   sirenum__Contact__r.Worker_Type_Payroll_Provider__c
            FROM sirenum__Placement__c
            WHERE Id = :placementId
            LIMIT 1
        ];
        if(placements.isEmpty()){
            ctx.errorMessage = 'Placement not found.';
            return ctx;
        }
        sirenum__Placement__c placement = placements[0];

        Id rateAgreementId = placement.sirenum__Contract__r?.Rate_Agreements__c;
        if(rateAgreementId == null){
            ctx.errorMessage = 'This Placement\'s Contract has no Rate Agreement.';
            return ctx;
        }
        if(placement.Job_Role_Scale__c == null || placement.Job_Role_Scale__r?.Rate_Agreement_Scale_Definition__c == null){
            ctx.errorMessage = 'Placement is missing Rate Agreement Scale Definition.';
            return ctx;
        }

        List<rateLineTriggerCustomHandler.RateAgreementVersionRequest> versionRequests = new List<rateLineTriggerCustomHandler.RateAgreementVersionRequest>{
            new rateLineTriggerCustomHandler.RateAgreementVersionRequest(rateAgreementId, page.sirenum__Valid_From_Date__c, page.sirenum__Valid_Until_Date__c)
        };
        rateLineTriggerCustomHandler.RateAgreementVersionResult versionResult =
            rateLineTriggerCustomHandler.getApplicableRateAgreementVersions(versionRequests)[0];
        if(versionResult.version == null){
            ctx.errorMessage = versionResult.errorMessage;
            return ctx;
        }

        Map<Id, List<Rate_Agreement_Scale__c>> scalesByVersion =
            rateLineTriggerCustomHandler.getScalesByVersion(new Set<Id>{ versionResult.version.Id });
        Rate_Agreement_Scale__c matchedScale = rateLineTriggerCustomHandler.findScaleForDefinition(
            placement.Job_Role_Scale__r.Rate_Agreement_Scale_Definition__c, scalesByVersion.get(versionResult.version.Id));
        if(matchedScale == null){
            ctx.errorMessage = 'No Rate Agreement Scale is configured for the Placement\'s Pay Scale under this Rate Agreement Version.';
            return ctx;
        }
        ctx.payScaleMin = matchedScale.Min_Amount__c;
        ctx.payScaleMax = matchedScale.Max_Amount__c;
        ctx.workerType = rateLineTriggerCustomHandler.mapWorkerType(placement.sirenum__Contact__r?.Worker_Type_Payroll_Provider__c);

        List<rateLineTriggerCustomHandler.RateAgreementLineRequest> lineRequests = new List<rateLineTriggerCustomHandler.RateAgreementLineRequest>{
            new rateLineTriggerCustomHandler.RateAgreementLineRequest(
                versionResult.version.Id,
                matchedScale.Rate_Agreement_Scale_Definition__r != null ? matchedScale.Rate_Agreement_Scale_Definition__r.Ranking__c : null,
                ctx.workerType
            )
        };
        rateLineTriggerCustomHandler.RateAgreementLineResult lineResult =
            rateLineTriggerCustomHandler.getApplicableRateAgreementLines(lineRequests)[0];
        if(lineResult.line == null){
            ctx.errorMessage = lineResult.errorMessage;
            return ctx;
        }

        ctx.rateAgreementLineId = lineResult.line.Id;
        ctx.calcType = lineResult.line.Calc_Type__c;
        ctx.marginValue = lineResult.line.Margin_Value__c;

        Map<Id, List<Employer_On_Cost__c>> costsByLine =
            rateLineTriggerCustomHandler.getEmployerOnCostsByLine(new Set<Id>{ lineResult.line.Id });
        ctx.employerOnCosts = costsByLine.containsKey(lineResult.line.Id) ? costsByLine.get(lineResult.line.Id) : new List<Employer_On_Cost__c>();

        return ctx;
    }

    public class MarginCalculationResult {
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Decimal totalCost;
        @AuraEnabled public Decimal employerOnCost;
        @AuraEnabled public Decimal marginAmount;
        @AuraEnabled public Decimal marginPercent;
    }

    // The Add/Edit Rate Line modal's "Calculate" button (and Recalculate, and the pre-Save sanity
    // check) for a Rate-Agreement-governed Rate Line or its AWR modifier -- deliberately reuses
    // rateLineTriggerCustomHandler's own validatePayRateAgainstScale/calculateTotalEmployerOnCost/
    // validateMarginAgainstLine directly rather than re-implementing any of those rules, so this
    // preview can never drift from what the trigger will actually enforce on save. NOT cacheable
    // -- always recomputed fresh against whatever Pay Rate/Charge Rate the user is currently
    // trying.
    @AuraEnabled
    public static MarginCalculationResult calculateRateAgreementMargin(Id rateAgreementLineId, String workerType, Decimal payRate, Decimal chargeRate, Decimal payScaleMin, Decimal payScaleMax){
        MarginCalculationResult result = new MarginCalculationResult();
        if(rateAgreementLineId == null){
            result.errorMessage = 'No applicable Rate Agreement Line.';
            return result;
        }

        String rangeError = rateLineTriggerCustomHandler.validatePayRateAgainstScale(
            payRate, new Rate_Agreement_Scale__c(Min_Amount__c = payScaleMin, Max_Amount__c = payScaleMax));
        if(rangeError != null){
            result.errorMessage = rangeError;
            return result;
        }

        List<Rate_Agreement_Lines__c> lines = [
            SELECT Id, Calc_Type__c, Margin_Value__c
            FROM Rate_Agreement_Lines__c
            WHERE Id = :rateAgreementLineId
            LIMIT 1
        ];
        if(lines.isEmpty()){
            result.errorMessage = 'Rate Agreement Line not found.';
            return result;
        }

        Map<Id, List<Employer_On_Cost__c>> costsByLine =
            rateLineTriggerCustomHandler.getEmployerOnCostsByLine(new Set<Id>{ rateAgreementLineId });
        List<Employer_On_Cost__c> costs = costsByLine.get(rateAgreementLineId);
        Decimal employerOnCost = rateLineTriggerCustomHandler.calculateTotalEmployerOnCost(payRate, costs, workerType);
        Decimal totalCost = (payRate == null ? 0 : payRate) + employerOnCost;

        result.employerOnCost = employerOnCost;
        result.totalCost = totalCost;
        result.errorMessage = rateLineTriggerCustomHandler.validateMarginAgainstLine(payRate, totalCost, chargeRate, lines[0]);
        if(chargeRate != null){
            result.marginAmount = chargeRate - totalCost;
            result.marginPercent = (totalCost == 0) ? null : (result.marginAmount / totalCost) * 100;
        }
        return result;
    }

    // The Employer On Cost rows (from the Rate Agreement's earliest Version, same convention as
    // EmployerOnCostManagerController) that apply to this Placement's Worker Type -- a blank
    // Worker_Type__c on a row applies to any worker type. Mirrors
    // rateLineTriggerCustomHandler.mapWorkerType()'s own resolution exactly, so the live Add Rate
    // Line calculation matches the trigger's margin validation: Contact's
    // Worker_Type_Payroll_Provider__c of 'Pay As You Earn' maps to 'PAYE', any other populated
    // value maps to 'Umbrella', blank leaves it unresolved (only blank-Worker_Type__c rows apply).
    // Percent-type rows carry their raw Value__c (a percentage) -- the caller multiplies by Pay
    // Rate itself, since that's live client-side input this shouldn't be re-fetched for.
    @AuraEnabled(cacheable=true)
    public static List<Employer_On_Cost__c> getEmployerOnCosts(Id rateAgreementId, Id placementId){
        List<Employer_On_Cost__c> results = new List<Employer_On_Cost__c>();
        if(rateAgreementId == null) return results;

        List<Rate_Agreement_Version__c> versions = [
            SELECT Id
            FROM Rate_Agreement_Version__c
            WHERE Rate_Agreement__c = :rateAgreementId
            ORDER BY Effective_Date__c ASC
            LIMIT 1
        ];
        if(versions.isEmpty()) return results;

        String workerType = null;
        if(placementId != null){
            List<sirenum__Placement__c> placements = [
                SELECT sirenum__Contact__r.Worker_Type_Payroll_Provider__c
                FROM sirenum__Placement__c
                WHERE Id = :placementId
                LIMIT 1
            ];
            if(!placements.isEmpty()){
                String payrollProvider = placements[0].sirenum__Contact__r?.Worker_Type_Payroll_Provider__c;
                if(!String.isBlank(payrollProvider)){
                    workerType = payrollProvider == 'Pay As You Earn' ? 'PAYE' : 'Umbrella';
                }
            }
        }

        for(Employer_On_Cost__c cost : [
            SELECT Calc_Type__c, Value__c, Worker_Type__c
            FROM Employer_On_Cost__c
            WHERE Rate_Agreement_Version__c = :versions[0].Id
        ]){
            Boolean applies = String.isBlank(cost.Worker_Type__c) || cost.Worker_Type__c == workerType;
            if(applies) results.add(cost);
        }
        return results;
    }
}