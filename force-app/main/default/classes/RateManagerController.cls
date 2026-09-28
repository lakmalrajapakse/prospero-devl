public without sharing class RateManagerController {

    //Method 1: To get the Rate card pages info from Rate Card ID
    @AuraEnabled(cacheable=true)
    public static List<sirenum__Rate_Card_Page__c> getRateCardPages(Id rateCardId){
        return [
            SELECT Id, sirenum__Condition_Suggestions__c, sirenum__Condition_value__c, sirenum__SortOrder__c
            FROM sirenum__Rate_Card_Page__c
            WHERE sirenum__Rate_Card__c = :rateCardId
        ];
    }

    // Gates "Create Shift Rate Card Page" -- a Shift-specific Page is only offered once the
    // Placement's own (no-condition) Rate Card Page already has at least one Rate Line; there'd be
    // nothing sensible to prefill a Shift-specific Line from otherwise (see getPrefillRateLineId).
    @AuraEnabled(cacheable=true)
    public static Integer getRateLineCount(Id rateCardPageId){
        if(rateCardPageId == null) return 0;
        return [SELECT COUNT() FROM sirenum__Rate_Line__c WHERE sirenum__Rate_Card_Page__c = :rateCardPageId];
    }

    // Resolves which existing Rate Line to prefill a new Shift-specific Rate Line's form from --
    // the FIRST (lowest Sort Order) Rate Line on whichever Placement-level (no-condition) Rate
    // Card Page is actually in effect on the Shift's own date:
    // 1) a Page whose [Valid From, Valid Until] window brackets shiftDate (the one with the latest
    //    Valid From Date among any that do, in the rare case more than one somehow does), or
    // 2) failing that, an open-ended Page (blank Valid Until) whose Valid From Date is on or
    //    before shiftDate -- again the latest (most recently effective) one if several qualify.
    // Returns null if no Placement-level Page/Line is applicable (the Add Rate Line modal then
    // just opens blank, same as before this existed).
    @AuraEnabled(cacheable=true)
    public static Id getPrefillRateLineId(Id rateCardId, Date shiftDate){
        if(rateCardId == null || shiftDate == null) return null;

        sirenum__Rate_Card_Page__c bracketingMatch;
        sirenum__Rate_Card_Page__c openEndedMatch;

        for(sirenum__Rate_Card_Page__c page : [
            SELECT Id, sirenum__Valid_From_Date__c, sirenum__Valid_Until_Date__c
            FROM sirenum__Rate_Card_Page__c
            WHERE sirenum__Rate_Card__c = :rateCardId AND sirenum__Condition_Suggestions__c = null
        ]){
            if(page.sirenum__Valid_From_Date__c == null || page.sirenum__Valid_From_Date__c > shiftDate) continue;

            if(page.sirenum__Valid_Until_Date__c != null){
                if(page.sirenum__Valid_Until_Date__c >= shiftDate
                    && (bracketingMatch == null || page.sirenum__Valid_From_Date__c > bracketingMatch.sirenum__Valid_From_Date__c)){
                    bracketingMatch = page;
                }
            } else if(openEndedMatch == null || page.sirenum__Valid_From_Date__c > openEndedMatch.sirenum__Valid_From_Date__c){
                openEndedMatch = page;
            }
        }

        sirenum__Rate_Card_Page__c matchedPage = bracketingMatch != null ? bracketingMatch : openEndedMatch;
        if(matchedPage == null) return null;

        List<sirenum__Rate_Line__c> lines = [
            SELECT Id
            FROM sirenum__Rate_Line__c
            WHERE sirenum__Rate_Card_Page__c = :matchedPage.Id
            ORDER BY sirenum__SortOrder__c ASC
            LIMIT 1
        ];
        return lines.isEmpty() ? null : lines[0].Id;
    }
}