/*
@author: Gandhi Naidu Bokam
@Date: 12-09-2026
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/35989281
*/
public with sharing class ShiftPreApprovalHandler {

    public static final String NO_PREAPPROVAL_ERROR =
        'Cannot publish shift as there is no pre-approval record for this CYP Site';

    
    public static void assignPreApprovalOnPublish(List<sirenum__Shift__c> newShifts, Map<Id, sirenum__Shift__c> oldMap) {

        // 1. Only act on shifts being newly published, that don't already
        //    have a Pre-Approval assigned, and that reference a site.
        List<sirenum__Shift__c> candidateShifts = new List<sirenum__Shift__c>();
        Set<Id> candidateSiteIds = new Set<Id>();

        for (sirenum__Shift__c shift : newShifts) {
            sirenum__Shift__c oldShift = (oldMap != null) ? oldMap.get(shift.Id) : null;

            Boolean isBeingPublished =
                shift.sirenum__Published__c == true &&
                (oldShift == null || oldShift.sirenum__Published__c != true);

            if (isBeingPublished && shift.Pre_Approval__c == null && shift.sirenum__Site__c != null) {
                candidateShifts.add(shift);
                candidateSiteIds.add(shift.sirenum__Site__c);
            }
        }

        if (candidateShifts.isEmpty()) {
            return;
        }

        // 2. Of those sites, find which are CYP sites that actually require pre-approval.
        //    Shifts on any other site are left alone entirely.
        Map<Id, sirenum__Site__c> cypSitesRequiringApproval = new Map<Id, sirenum__Site__c>([SELECT Id
                                                                                             FROM sirenum__Site__c
                                                                                             WHERE Id IN :candidateSiteIds
                                                                                             AND Requires_Pre_approval__c = true
                                                                                            ]);

        if (cypSitesRequiringApproval.isEmpty()) {
            return;
        }

        List<sirenum__Shift__c> shiftsNeedingPreApproval = new List<sirenum__Shift__c>();
        Set<Id> qualifyingSiteIds = new Set<Id>();

        for (sirenum__Shift__c shift : candidateShifts) {
            if (cypSitesRequiringApproval.containsKey(shift.sirenum__Site__c)) {
                shiftsNeedingPreApproval.add(shift);
                qualifyingSiteIds.add(shift.sirenum__Site__c);
            }
        }

        if (shiftsNeedingPreApproval.isEmpty()) {
            return;
        }

        // Get the earliest and latest shift dates.
        Date minShiftDate;
        Date maxShiftDate;

        for (sirenum__Shift__c shift : shiftsNeedingPreApproval) {
            if (shift.sirenum__Date__c != null) {
                Date shiftDate = shift.sirenum__Date__c.date();

                if (minShiftDate == null || shiftDate < minShiftDate) {
                    minShiftDate = shiftDate;
                }

                if (maxShiftDate == null || shiftDate > maxShiftDate) {
                    maxShiftDate = shiftDate;
                }
            }
        }

        // 3. Pull active Pre-Approval records overlapping the shift window with available hours.
        List<Pre_Approval__c> allCandidatePreApprovals = [SELECT Id, Site__c, Start_Date__c, End_Date__c, Available_Hours__c, Hours__c
                                                          FROM Pre_Approval__c
                                                          WHERE Site__c IN :qualifyingSiteIds
                                                          AND Start_Date__c <= :minShiftDate
                                                          AND (End_Date__c >= :maxShiftDate OR Available_Hours__c > 0)
                                                          ORDER BY Start_Date__c ASC NULLS LAST
                                                         ];
        

        // 4. Group by site and seed the in-memory running balance per record.
        Map<Id, List<Pre_Approval__c>> preApprovalsBySite = new Map<Id, List<Pre_Approval__c>>();
        Map<Id, Decimal> remainingHoursByPreApprovalId = new Map<Id, Decimal>();

        for (Pre_Approval__c pa : allCandidatePreApprovals) {
            if (!preApprovalsBySite.containsKey(pa.Site__c)) {
                preApprovalsBySite.put(pa.Site__c, new List<Pre_Approval__c>());
            }
            preApprovalsBySite.get(pa.Site__c).add(pa);

            Decimal available = pa.Available_Hours__c == null ? 0 : pa.Available_Hours__c;
            Decimal consumed = pa.Hours__c == null ? 0 : pa.Hours__c;
            remainingHoursByPreApprovalId.put(pa.Id, available - consumed);
        }

        // 5. Walk the shifts in a deterministic (first-in-list = first-served)
        //    order, matching each to a Pre-Approval and updating the running balance.
        for (sirenum__Shift__c shift : shiftsNeedingPreApproval) {
            List<Pre_Approval__c> siteCandidates = preApprovalsBySite.get(shift.sirenum__Site__c);
            Pre_Approval__c matched = findMatchingPreApproval(shift, siteCandidates, remainingHoursByPreApprovalId);

            if (matched == null) {
                shift.addError(NO_PREAPPROVAL_ERROR);
                continue;
            }

            shift.Pre_Approval__c = matched.Id;

            Decimal shiftHours = 0;
            if (shift.sirenum__Scheduled_Start_Time__c != null &&
                shift.sirenum__Scheduled_End_Time__c != null) {
                shiftHours =
                    (shift.sirenum__Scheduled_End_Time__c.getTime() -
                     shift.sirenum__Scheduled_Start_Time__c.getTime()) / (1000 * 60 * 60);
            }

            Decimal remaining = remainingHoursByPreApprovalId.get(matched.Id);
            remainingHoursByPreApprovalId.put(matched.Id, remaining - shiftHours);
        }
    }

    /**
     * Returns the first Pre-Approval record (in date order) that is eligible
     * for the given shift, using the running balance to check hour capacity.
     */
    private static Pre_Approval__c findMatchingPreApproval(
        sirenum__Shift__c shift,
        List<Pre_Approval__c> preApproval,
        Map<Id, Decimal> remainingHoursByPreApprovalId
    ) {
        if (preApproval == null || preApproval.isEmpty()) {
            return null;
        }

        Decimal shiftHours = 0;
        if (shift.sirenum__Scheduled_Start_Time__c != null &&
            shift.sirenum__Scheduled_End_Time__c != null) {
            shiftHours =
                (shift.sirenum__Scheduled_End_Time__c.getTime() -
                 shift.sirenum__Scheduled_Start_Time__c.getTime()) / (1000 * 60 * 60);
        }

        for (Pre_Approval__c pa : preApproval) {
            Boolean withinDateRange = isWithinDateRange(shift.sirenum__Date__c.date(), pa.Start_Date__c, pa.End_Date__c);

            Decimal remainingHours = remainingHoursByPreApprovalId.get(pa.Id);
            Boolean hasHoursAvailable = remainingHours != null && remainingHours >= shiftHours;

            if (withinDateRange || hasHoursAvailable) {
                return pa;
            }
        }

        return null;
    }

    private static Boolean isWithinDateRange(Date shiftDate, Date rangeStart, Date rangeEnd) {
        if (shiftDate == null || rangeStart == null || rangeEnd == null) {
            return false;
        }
        return shiftDate >= rangeStart && shiftDate <= rangeEnd;
    }
}