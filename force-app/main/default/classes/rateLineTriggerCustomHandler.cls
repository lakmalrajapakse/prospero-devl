public without sharing class rateLineTriggerCustomHandler {
    

    public static void validateRateLine(List<sirenum__Rate_Line__c> rateLines){
        List<LineValidationInput> inputs = new List<LineValidationInput>();
        for(sirenum__Rate_Line__c line : rateLines){
            inputs.add(new LineValidationInput(line, line.sirenum__Rate_Card_Page__c, line.sirenum__Pay_Rate__c, line.sirenum__Charge_Rate__c));
        }
        validateRateAgreementMargin(inputs);
    }

    // Rate Modifier is a child of Rate Line (sirenum__Rate_Line__c lookup) and carries its own
    // Pay Rate / Charge Rate, but has no Rate Card Page of its own — that's fetched via its
    // parent Rate Line. Everything else in the pipeline is identical, so it's shared via
    // validateRateAgreementMargin rather than duplicated.
    public static void validateRateModifier(List<sirenum__Rate_Modifier__c> modifiers){
        Set<Id> rateLineIds = new Set<Id>();
        for(sirenum__Rate_Modifier__c modifier : modifiers){
            if(modifier.sirenum__Rate_Line__c != null) rateLineIds.add(modifier.sirenum__Rate_Line__c);
        }

        Map<Id, sirenum__Rate_Line__c> rateLineById = new Map<Id, sirenum__Rate_Line__c>(
            [SELECT Id, sirenum__Rate_Card_Page__c FROM sirenum__Rate_Line__c WHERE Id IN :rateLineIds]);

        List<LineValidationInput> inputs = new List<LineValidationInput>();
        for(sirenum__Rate_Modifier__c modifier : modifiers){
            sirenum__Rate_Line__c parentLine = modifier.sirenum__Rate_Line__c == null ? null : rateLineById.get(modifier.sirenum__Rate_Line__c);
            if(parentLine == null){
                system.debug('@@@@Rate Line not found for modifier: ' + modifier.sirenum__Rate_Line__c);
                modifier.addError('Rate Modifier is not linked to a valid Rate Line.');
                continue;
            }
            inputs.add(new LineValidationInput(modifier, parentLine.sirenum__Rate_Card_Page__c, modifier.sirenum__Pay_Rate__c, modifier.sirenum__Charge_Rate__c));
        }
        validateRateAgreementMargin(inputs);
    }

    // Bundles what differs per calling object (Rate Line vs Rate Modifier) so the whole margin
    // validation pipeline below is written once and shared by both. sourceRecord is whichever
    // record addError() should land on — a Rate Line or a Rate Modifier, both are SObjects.
    public class LineValidationInput {
        public SObject sourceRecord;
        public Id rateCardPageId;
        public Decimal payRate;
        public Decimal chargeRate;

        public LineValidationInput(SObject sourceRecord, Id rateCardPageId, Decimal payRate, Decimal chargeRate){
            this.sourceRecord = sourceRecord;
            this.rateCardPageId = rateCardPageId;
            this.payRate = payRate;
            this.chargeRate = chargeRate;
        }
    }

    public static void validateRateAgreementMargin(List<LineValidationInput> inputs){
        Set<Id> pageIds = new Set<Id>();
        for(LineValidationInput input : inputs){
            pageIds.add(input.rateCardPageId);
        }

        // Rate Card Page -> Rate Card
        Map<Id, sirenum__Rate_Card_Page__c> pageById = new Map<Id, sirenum__Rate_Card_Page__c>(
                                                            [SELECT Id, sirenum__Rate_Card__c, sirenum__Valid_From_Date__c, sirenum__Valid_Until_Date__c
                                                            FROM sirenum__Rate_Card_Page__c
                                                            WHERE Id IN :pageIds]);

        Set<Id> rateCardIds = new Set<Id>();
        for(sirenum__Rate_Card_Page__c page : pageById.values()){
            if(page.sirenum__Rate_Card__c != null) rateCardIds.add(page.sirenum__Rate_Card__c);
        }

        // Placement has a DIRECT lookup to Rate Card — query it from there,
        // and pull the Contract's Rate Agreement in the same trip.
        // A rate card is associated with only one placement, so this is a 1:1 map.
        Map<Id, sirenum__Placement__c> placementByRateCard = new Map<Id, sirenum__Placement__c>();
        for(sirenum__Placement__c pl : [SELECT Id, sirenum__Rate_Card__c, sirenum__Contract__c,
                                                sirenum__Contract__r.Rate_Agreements__c,
                                                Job_Role_Scale__r.Rate_Agreement_Scale_Definition__c,
                                                Job_Role_Scale__r.Rate_Agreement_Scale_Definition__r.Rate_Agreements__c,
                                                sirenum__Contact__r.Worker_Type_Payroll_Provider__c
                                        FROM sirenum__Placement__c
                                        WHERE sirenum__Rate_Card__c IN :rateCardIds]){
            placementByRateCard.put(pl.sirenum__Rate_Card__c, pl);
        }

        // Inputs that clear every prior check still need a Rate Agreement Version resolved.
        // Kept as parallel lists (not a Map<Id, ...>) because before-insert records have no Id yet.
        List<LineValidationInput> inputsNeedingVersion = new List<LineValidationInput>();
        List<RateAgreementVersionRequest> versionRequests = new List<RateAgreementVersionRequest>();

        for(LineValidationInput input : inputs){
            sirenum__Rate_Card_Page__c page = pageById.get(input.rateCardPageId);
            if(page == null){
                system.debug('@@@@Rate Card Page not Found for: ' + input.rateCardPageId);
                continue;
            }

            sirenum__Placement__c placement = placementByRateCard.get(page.sirenum__Rate_Card__c);
            if(placement == null){
                system.debug('@@@@Placement not Found: ');
                continue; // no placement on this rate card at all
            }

            if(placement.sirenum__Contract__c == null || placement.sirenum__Contract__r.Rate_Agreements__c == null){
                system.debug('@@@@No contract or Rate Agreement found on Placement: ' + placement.Id);
                continue; // not linked to a contract with a Rate Agreement -> stop validation processing
            }

            /// Check placement has rate agreement
            if(placement.Job_Role_Scale__c == null || placement.Job_Role_Scale__r.Rate_Agreement_Scale_Definition__c == null){
                system.debug('@@@@Placement has no Rate Agreement Scale Defination: ' + placement.Id);
                input.sourceRecord.addError('Placement is missing Rate Agreement Scale Definition.');
                continue;
            }

            /// Find appropriate Rate Agreement Version to validate the pay rate against
            inputsNeedingVersion.add(input);
            versionRequests.add(new RateAgreementVersionRequest(
                placement.Job_Role_Scale__r.Rate_Agreement_Scale_Definition__r.Rate_Agreements__c,
                page.sirenum__Valid_From_Date__c,
                page.sirenum__Valid_Until_Date__c
            ));
        }

        List<RateAgreementVersionResult> versionResults = getApplicableRateAgreementVersions(versionRequests);

        Set<Id> resolvedVersionIds = new Set<Id>();
        for(RateAgreementVersionResult result : versionResults){
            if(result.version != null) resolvedVersionIds.add(result.version.Id);
        }
        Map<Id, List<Rate_Agreement_Scale__c>> scalesByVersion = getScalesByVersion(resolvedVersionIds);

        // Inputs that clear the scale check still need an applicable Rate Agreement Line resolved
        // (for the margin check). Parallel lists again, for the same before-insert-has-no-Id reason.
        List<LineValidationInput> inputsNeedingMarginCheck = new List<LineValidationInput>();
        List<RateAgreementLineRequest> lineRequests = new List<RateAgreementLineRequest>();

        for(Integer i = 0; i < inputsNeedingVersion.size(); i++){
            LineValidationInput input = inputsNeedingVersion[i];
            RateAgreementVersionResult result = versionResults[i];

            if(result.version == null){
                system.debug('@@@@No applicable Rate Agreement Version: ' + result.errorMessage);
                input.sourceRecord.addError(result.errorMessage);
                continue;
            }

            system.debug('@@@@Applicable Rate Agreement Version resolved: ' + result.version.Id);

            sirenum__Rate_Card_Page__c page = pageById.get(input.rateCardPageId);
            sirenum__Placement__c placement = placementByRateCard.get(page.sirenum__Rate_Card__c);

            // Validate Pay Rate against the ONE scale tied to the Placement's own Job Role Scale
            // (Job_Role_Scale__r.Rate_Agreement_Scale_Definition__c) — not against any scale under
            // the version that happens to contain the value.
            List<Rate_Agreement_Scale__c> scales = scalesByVersion.get(result.version.Id);
            Rate_Agreement_Scale__c matchedScale = findScaleForDefinition(
                placement.Job_Role_Scale__r.Rate_Agreement_Scale_Definition__c, scales);
            if(matchedScale == null){
                system.debug('@@@@No Rate Agreement Scale configured for Scale Definition '
                    + placement.Job_Role_Scale__r.Rate_Agreement_Scale_Definition__c + ' under version: ' + result.version.Id);
                input.sourceRecord.addError('No Rate Agreement Scale is configured for the Placement\'s Pay Scale under this Rate Agreement Version.');
                continue;
            }
            String payRateRangeError = validatePayRateAgainstScale(input.payRate, matchedScale);
            if(payRateRangeError != null){
                system.debug('@@@@' + payRateRangeError);
                input.sourceRecord.addError(payRateRangeError);
                continue;
            }

            /// Find appropriate Rate Agreement Line to validate the margin against
            inputsNeedingMarginCheck.add(input);
            lineRequests.add(new RateAgreementLineRequest(
                result.version.Id,
                matchedScale.Rate_Agreement_Scale_Definition__r != null ? matchedScale.Rate_Agreement_Scale_Definition__r.Ranking__c : null,
                mapWorkerType(placement.sirenum__Contact__r != null ? placement.sirenum__Contact__r.Worker_Type_Payroll_Provider__c : null)
            ));
        }

        List<RateAgreementLineResult> lineResults = getApplicableRateAgreementLines(lineRequests);

        Set<Id> resolvedLineIds = new Set<Id>();
        for(RateAgreementLineResult result : lineResults){
            if(result.line != null) resolvedLineIds.add(result.line.Id);
        }
        Map<Id, List<Employer_On_Cost__c>> costsByLine = getEmployerOnCostsByLine(resolvedLineIds);

        for(Integer i = 0; i < inputsNeedingMarginCheck.size(); i++){
            LineValidationInput input = inputsNeedingMarginCheck[i];
            RateAgreementLineResult result = lineResults[i];

            if(result.line == null){
                system.debug('@@@@No applicable Rate Agreement Line: ' + result.errorMessage);
                input.sourceRecord.addError(result.errorMessage);
                continue;
            }

            String workerType = lineRequests[i].workerType;
            List<Employer_On_Cost__c> costs = costsByLine.get(result.line.Id);
            Decimal employerOnCost = calculateTotalEmployerOnCost(input.payRate, costs, workerType);
            Decimal totalCost = (input.payRate == null ? 0 : input.payRate) + employerOnCost;

            String marginError = validateMarginAgainstLine(input.payRate, totalCost, input.chargeRate, result.line);
            if(marginError != null){
                system.debug('@@@@Margin violation: ' + marginError);
                input.sourceRecord.addError(marginError);
            }
        }
    }

    // Bulk-fetches every Rate Agreement Scale row for the given Rate Agreement Version Ids.
    // Caller-agnostic — reused by both the Rate Line and (planned) Rate Modifier validations.
    public static Map<Id, List<Rate_Agreement_Scale__c>> getScalesByVersion(Set<Id> versionIds){
        Map<Id, List<Rate_Agreement_Scale__c>> scalesByVersion = new Map<Id, List<Rate_Agreement_Scale__c>>();
        if(versionIds == null || versionIds.isEmpty()) return scalesByVersion;

        for(Rate_Agreement_Scale__c scale : [SELECT Id, Rate_Agreement_Version__c, Min_Amount__c, Max_Amount__c,
                                                     Rate_Agreement_Scale_Definition__c, Rate_Agreement_Scale_Definition__r.Ranking__c
                                              FROM Rate_Agreement_Scale__c
                                              WHERE Rate_Agreement_Version__c IN :versionIds]){
            if(!scalesByVersion.containsKey(scale.Rate_Agreement_Version__c)){
                scalesByVersion.put(scale.Rate_Agreement_Version__c, new List<Rate_Agreement_Scale__c>());
            }
            scalesByVersion.get(scale.Rate_Agreement_Version__c).add(scale);
        }
        return scalesByVersion;
    }

    // Returns the ONE scale (from `scales`, all under the same version) whose
    // Rate_Agreement_Scale_Definition__c matches scaleDefinitionId — i.e. the Placement's own
    // assigned Job Role Scale — or null if this version has no scale configured for it.
    // Pay Rate is validated against this specific scale, not against whichever scale under the
    // version happens to contain the value.
    public static Rate_Agreement_Scale__c findScaleForDefinition(Id scaleDefinitionId, List<Rate_Agreement_Scale__c> scales){
        if(scaleDefinitionId == null || scales == null) return null;
        for(Rate_Agreement_Scale__c scale : scales){
            if(scale.Rate_Agreement_Scale_Definition__c == scaleDefinitionId) return scale;
        }
        return null;
    }

    // True if payRate falls within this one scale's [Min_Amount__c, Max_Amount__c] range (a null
    // bound is treated as open-ended on that side). Takes the pay rate as a plain Decimal so
    // callers can pass whichever field holds it (sirenum__Pay_Rate__c on Rate Line today; a
    // different field on Rate Modifier later).
    public static Boolean isPayRateWithinScale(Decimal payRate, Rate_Agreement_Scale__c scale){
        if(payRate == null || scale == null) return false;
        // Guard the null bound first — Apex throws a NullPointerException comparing a
        // Decimal to null, it does not evaluate to false.
        Boolean aboveMin = scale.Min_Amount__c == null || payRate >= scale.Min_Amount__c;
        Boolean belowMax = scale.Max_Amount__c == null || payRate <= scale.Max_Amount__c;
        return aboveMin && belowMax;
    }

    // Split out of validateRateAgreementMargin's inline loop so MarginCalculatorController's
    // client-facing "Calculate" preview (for a Rate-Agreement-governed Rate Line/Rate Modifier)
    // can reuse the exact same range check and message wording without duplicating either.
    // Returns null when payRate is within scale's range, or a detailed error message otherwise.
    public static String validatePayRateAgainstScale(Decimal payRate, Rate_Agreement_Scale__c scale){
        if(isPayRateWithinScale(payRate, scale)) return null;
        return 'Pay Rate ' + fmt(payRate) + ' is outside the allowed range ('
            + fmt(scale.Min_Amount__c) + ' - ' + fmt(scale.Max_Amount__c)
            + ') for the Placement\'s Pay Scale.';
    }

    // ---- Rate Agreement Line resolution (margin validation) ----

    // Request/result pair for getApplicableRateAgreementLines — caller-agnostic like the version
    // resolver, so a sirenum__Rate_Modifier__c trigger can reuse it with its own scale/worker type.
    public class RateAgreementLineRequest {
        public Id rateAgreementVersionId;
        public Decimal placementScaleRanking; // Ranking__c of the Rate_Agreement_Scale_Definition__c linked to the
                                               // Placement's own scale (from findScaleForDefinition); nullable
        public String workerType;             // 'PAYE' or 'Umbrella' — see mapWorkerType(); nullable

        public RateAgreementLineRequest(Id rateAgreementVersionId, Decimal placementScaleRanking, String workerType){
            this.rateAgreementVersionId = rateAgreementVersionId;
            this.placementScaleRanking = placementScaleRanking;
            this.workerType = workerType;
        }
    }

    public class RateAgreementLineResult {
        public Rate_Agreement_Lines__c line; // resolved line, or null if errorMessage is set
        public String errorMessage;
    }

    // Bulk-resolves the single Rate Agreement Line applicable to each request:
    // 1) eligible by Min/Max Scale range — Min_Scale__c/Max_Scale__c point at Rate_Agreement_Scale__c
    //    (the same pay-band object used for the Pay Rate check), so ordering goes one hop further
    //    through each band's own Rate_Agreement_Scale_Definition__r.Ranking__c (a null bound on
    //    either side, or a null placement ranking, is treated as open on that side);
    // 2) among eligible lines, one whose Worker_Type__c matches the placement's resolved Worker
    //    Type (see mapWorkerType) wins over a line with a null/blank Worker_Type__c (general).
    // Positional, like getApplicableRateAgreementVersions, for the same before-insert reason.
    public static List<RateAgreementLineResult> getApplicableRateAgreementLines(List<RateAgreementLineRequest> requests){
        List<RateAgreementLineResult> results = new List<RateAgreementLineResult>();
        if(requests == null || requests.isEmpty()) return results;

        Set<Id> versionIds = new Set<Id>();
        for(RateAgreementLineRequest req : requests){
            if(req.rateAgreementVersionId != null) versionIds.add(req.rateAgreementVersionId);
        }

        Map<Id, List<Rate_Agreement_Lines__c>> linesByVersion = new Map<Id, List<Rate_Agreement_Lines__c>>();
        for(Rate_Agreement_Lines__c line : [SELECT Id, Rate_Agreement_Version__c, Worker_Type__c, Calc_Type__c, Margin_Value__c,
                                                    Min_Scale__c, Min_Scale__r.Rate_Agreement_Scale_Definition__r.Ranking__c,
                                                    Max_Scale__c, Max_Scale__r.Rate_Agreement_Scale_Definition__r.Ranking__c
                                            FROM Rate_Agreement_Lines__c
                                            WHERE Rate_Agreement_Version__c IN :versionIds]){
            if(!linesByVersion.containsKey(line.Rate_Agreement_Version__c)){
                linesByVersion.put(line.Rate_Agreement_Version__c, new List<Rate_Agreement_Lines__c>());
            }
            linesByVersion.get(line.Rate_Agreement_Version__c).add(line);
        }

        for(RateAgreementLineRequest req : requests){
            RateAgreementLineResult result = new RateAgreementLineResult();
            List<Rate_Agreement_Lines__c> candidates = req.rateAgreementVersionId == null ? null : linesByVersion.get(req.rateAgreementVersionId);

            if(candidates == null || candidates.isEmpty()){
                result.errorMessage = 'No Rate Agreement Line found for Rate Agreement Version ' + req.rateAgreementVersionId + '.';
                results.add(result);
                continue;
            }

            Rate_Agreement_Lines__c specificMatch;
            Rate_Agreement_Lines__c generalMatch; // Worker_Type__c blank on the line -> applies to any worker type

            for(Rate_Agreement_Lines__c candidate : candidates){
                Decimal minRanking = (candidate.Min_Scale__c == null || candidate.Min_Scale__r.Rate_Agreement_Scale_Definition__r == null)
                    ? null : candidate.Min_Scale__r.Rate_Agreement_Scale_Definition__r.Ranking__c;
                Decimal maxRanking = (candidate.Max_Scale__c == null || candidate.Max_Scale__r.Rate_Agreement_Scale_Definition__r == null)
                    ? null : candidate.Max_Scale__r.Rate_Agreement_Scale_Definition__r.Ranking__c;

                Boolean aboveMinScale = minRanking == null || req.placementScaleRanking == null || req.placementScaleRanking >= minRanking;
                Boolean belowMaxScale = maxRanking == null || req.placementScaleRanking == null || req.placementScaleRanking <= maxRanking;

                if(!aboveMinScale || !belowMaxScale) continue;

                if(String.isBlank(candidate.Worker_Type__c)){
                    if(generalMatch == null) generalMatch = candidate;
                } else if(candidate.Worker_Type__c == req.workerType){
                    if(specificMatch == null) specificMatch = candidate;
                }
            }

            Rate_Agreement_Lines__c resolved = specificMatch != null ? specificMatch : generalMatch;
            if(resolved == null){
                result.errorMessage = 'No applicable Rate Agreement Line was found (Worker Type / Pay Scale did not match any Rate Agreement Line).';
            } else {
                result.line = resolved;
            }

            results.add(result);
        }

        return results;
    }

    // Maps Contact.Worker_Type_Payroll_Provider__c to the 'PAYE'/'Umbrella' values used by
    // Rate_Agreement_Lines__c.Worker_Type__c and Employer_On_Cost__c.Worker_Type__c: 'Pay As You
    // Earn' means PAYE, any other populated value means Umbrella. Null/blank stays null (unknown).
    // Public so MarginCalculatorController's read-side context resolution (the Add/Edit Rate Line
    // modal's Rate-Agreement mode) resolves Worker Type identically to this trigger.
    public static String mapWorkerType(String payrollProvider){
        if(String.isBlank(payrollProvider)) return null;
        return payrollProvider == 'Pay As You Earn' ? 'PAYE' : 'Umbrella';
    }

    // ---- Employer On Cost ----

    // Bulk-fetches the Rate Agreement Line's OWN Employer On Costs (Type__c = 'Record Agreement
    // Line') for the given line Ids. Deliberately excludes 'Record Agreement' rows — those are
    // template defaults at the Version level and are not used for this validation.
    public static Map<Id, List<Employer_On_Cost__c>> getEmployerOnCostsByLine(Set<Id> lineIds){
        Map<Id, List<Employer_On_Cost__c>> costsByLine = new Map<Id, List<Employer_On_Cost__c>>();
        if(lineIds == null || lineIds.isEmpty()) return costsByLine;

        for(Employer_On_Cost__c cost : [SELECT Id, Rate_Agreement_Lines__c, Worker_Type__c, Calc_Type__c, Value__c
                                         FROM Employer_On_Cost__c
                                         WHERE Rate_Agreement_Lines__c IN :lineIds
                                         AND Type__c = 'Record Agreement Line']){
            if(!costsByLine.containsKey(cost.Rate_Agreement_Lines__c)){
                costsByLine.put(cost.Rate_Agreement_Lines__c, new List<Employer_On_Cost__c>());
            }
            costsByLine.get(cost.Rate_Agreement_Lines__c).add(cost);
        }
        return costsByLine;
    }

    // Sums every Employer On Cost that applies to this worker type (a blank Worker_Type__c on the
    // cost row applies to all worker types). Fixed costs add Value__c directly; Percent costs are
    // calculated against Pay Rate. Caller-agnostic — same math for Rate Line and Rate Modifier.
    public static Decimal calculateTotalEmployerOnCost(Decimal payRate, List<Employer_On_Cost__c> costs, String workerType){
        Decimal total = 0;
        if(payRate == null || costs == null) return total;

        for(Employer_On_Cost__c cost : costs){
            if(cost.Value__c == null) continue;
            Boolean applies = String.isBlank(cost.Worker_Type__c) || cost.Worker_Type__c == workerType;
            if(!applies) continue;

            total += (cost.Calc_Type__c == 'Percent') ? (cost.Value__c / 100) * payRate : cost.Value__c;
        }
        return total;
    }

    // ---- Margin validation ----

    // Validates chargeRate against the margin rule on `line`, given the already-calculated
    // totalCost (Pay Rate + applicable Employer On Costs). Returns null when the margin is
    // satisfied, or a detailed error message otherwise.
    // Margin % = (Charge Rate - Total Cost) / Total Cost.
    // Caller-agnostic: pass whichever pay/charge rate values apply (Rate Line today; Rate
    // Modifier's own fields later).
    public static String validateMarginAgainstLine(Decimal payRate, Decimal totalCost, Decimal chargeRate, Rate_Agreement_Lines__c line){
        if(line == null || line.Margin_Value__c == null) return null;

        Decimal employerOnCosts = totalCost - (payRate == null ? 0 : payRate);
        String breakdown = ' Pay Rate: ' + fmt(payRate)
            + ' | Employer On Costs: ' + fmt(employerOnCosts)
            + ' | Total Cost: ' + fmt(totalCost)
            + ' | Charge Rate: ' + fmt(chargeRate);

        if(chargeRate == null){
            return 'Charge Rate is required to validate against the Rate Agreement margin.' + breakdown;
        }

        Decimal marginAmount = chargeRate - totalCost;
        Decimal marginPercent = (totalCost == 0) ? null : (marginAmount / totalCost) * 100;
        Boolean isPercentRule = line.Calc_Type__c == 'Fixed Margin %' || line.Calc_Type__c == 'Max Margin %';

        if(isPercentRule && marginPercent == null){
            return 'Total Cost of 0 cannot be used to calculate a margin percentage.' + breakdown;
        }

        if(line.Calc_Type__c == 'Fixed Margin Amount'){
            if(marginAmount.setScale(2) != line.Margin_Value__c.setScale(2)){
                Decimal diff = marginAmount - line.Margin_Value__c;
                return 'Margin of ' + fmt(marginAmount) + ' does not match the fixed margin of ' + fmt(line.Margin_Value__c)
                    + ' required by the Rate Agreement (' + fmt(diff.abs()) + ' too ' + (diff > 0 ? 'high' : 'low') + ').' + breakdown;
            }
        } else if(line.Calc_Type__c == 'Fixed Margin %'){
            if(marginPercent.setScale(2) != line.Margin_Value__c.setScale(2)){
                Decimal diff = marginPercent - line.Margin_Value__c;
                return 'Margin of ' + fmt(marginPercent) + '% does not match the fixed margin of ' + fmt(line.Margin_Value__c)
                    + '% required by the Rate Agreement (' + fmt(diff.abs()) + ' points too ' + (diff > 0 ? 'high' : 'low') + ').' + breakdown;
            }
        } else if(line.Calc_Type__c == 'Max Margin Amount'){
            if(marginAmount > line.Margin_Value__c){
                Decimal excess = marginAmount - line.Margin_Value__c;
                return 'Charge Rate exceeds the maximum allowed margin of ' + fmt(line.Margin_Value__c)
                    + ' by ' + fmt(excess) + ' (actual margin: ' + fmt(marginAmount) + ').' + breakdown;
            }
        } else if(line.Calc_Type__c == 'Max Margin %'){
            if(marginPercent > line.Margin_Value__c){
                Decimal excess = marginPercent - line.Margin_Value__c;
                return 'Charge Rate exceeds the maximum allowed margin of ' + fmt(line.Margin_Value__c)
                    + '% by ' + fmt(excess) + ' points (actual margin: ' + fmt(marginPercent) + '%).' + breakdown;
            }
        }

        return null;
    }

    // Formats a Decimal to 2dp for user-facing error messages; null-safe.
    private static String fmt(Decimal value){
        return value == null ? 'n/a' : String.valueOf(value.setScale(2));
    }

    // Request/result pair for getApplicableRateAgreementVersions — deliberately caller-agnostic
    // supplying its own Rate Agreement Id + validity window and comparing pay rate from its own field.
    public class RateAgreementVersionRequest {
        public Id rateAgreementId;
        public Date validFromDate;
        public Date validUntilDate; // nullable

        public RateAgreementVersionRequest(Id rateAgreementId, Date validFromDate, Date validUntilDate){
            this.rateAgreementId = rateAgreementId;
            this.validFromDate = validFromDate;
            this.validUntilDate = validUntilDate;
        }
    }

    public class RateAgreementVersionResult {
        public Rate_Agreement_Version__c version;  // resolved version, or null if errorMessage is set
        public String errorMessage;
    }

    // Bulk-resolves the single Rate Agreement Version that covers each request's validity window.
    // A version has no explicit end date — it is in effect from its own Effective_Date__c up to
    // (but not including) the next version's Effective_Date__c, or indefinitely if it's the latest.
    // Returned list is positional (same order/size as `requests`), so it works even when the
    // caller has no record Id yet (e.g. a before-insert trigger).
    public static List<RateAgreementVersionResult> getApplicableRateAgreementVersions(List<RateAgreementVersionRequest> requests){
        List<RateAgreementVersionResult> results = new List<RateAgreementVersionResult>();
        if(requests == null || requests.isEmpty()) return results;

        Set<Id> rateAgreementIds = new Set<Id>();
        for(RateAgreementVersionRequest req : requests){
            if(req.rateAgreementId != null) rateAgreementIds.add(req.rateAgreementId);
        }

        // All versions per Rate Agreement, oldest -> newest.
        Map<Id, List<Rate_Agreement_Version__c>> versionsByAgreement = new Map<Id, List<Rate_Agreement_Version__c>>();
        for(Rate_Agreement_Version__c v : [SELECT Id, Rate_Agreement__c, Effective_Date__c
                                            FROM Rate_Agreement_Version__c
                                            WHERE Rate_Agreement__c IN :rateAgreementIds
                                            ORDER BY Rate_Agreement__c, Effective_Date__c ASC]){
            if(!versionsByAgreement.containsKey(v.Rate_Agreement__c)){
                versionsByAgreement.put(v.Rate_Agreement__c, new List<Rate_Agreement_Version__c>());
            }
            versionsByAgreement.get(v.Rate_Agreement__c).add(v);
        }

        for(RateAgreementVersionRequest req : requests){
            RateAgreementVersionResult result = new RateAgreementVersionResult();
            List<Rate_Agreement_Version__c> versions = req.rateAgreementId == null ? null : versionsByAgreement.get(req.rateAgreementId);

            if(versions == null || versions.isEmpty()){
                result.errorMessage = 'No Rate Agreement Version found for Rate Agreement ' + req.rateAgreementId + '.';
                results.add(result);
                continue;
            }

            Rate_Agreement_Version__c current;
            Rate_Agreement_Version__c nextVersion;
            for(Integer i = 0; i < versions.size(); i++){
                if(versions[i].Effective_Date__c <= req.validFromDate){
                    current = versions[i];
                    nextVersion = (i + 1 < versions.size()) ? versions[i + 1] : null;
                } else {
                    break; // ascending order — nothing further can qualify
                }
            }

            if(current == null){
                result.errorMessage = 'No Rate Agreement Version effective on or before ' + req.validFromDate + '.';
            } else if(req.validUntilDate != null && nextVersion != null && nextVersion.Effective_Date__c <= req.validUntilDate){
                // A newer version takes effect before the validity window ends, so no single
                // version covers the whole [validFrom, validUntil] range.
                result.errorMessage = 'Rate Agreement Version changes on ' + nextVersion.Effective_Date__c
                                        + ', before the validity end date ' + req.validUntilDate + '.';
            } else {
                result.version = current;
            }

            results.add(result);
        }

        return results;
    }
}