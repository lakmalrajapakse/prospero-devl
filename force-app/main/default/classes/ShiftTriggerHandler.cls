/*
@author: Gandhi Naidu Bokam
@Date: 01-09-2026
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/36248202
*/
public without sharing class ShiftTriggerHandler {

    private static Set<Id> processedShiftIds = new Set<Id>();

    @TestVisible
    private static final String SHIFT_TIME_ZONE = 'Europe/London';

    public static void handleAfterInsert(List<sirenum__Shift__c> newShifts) {
        relateShiftsToPlacements(newShifts);
    }

    public static void handleAfterUpdate(List<sirenum__Shift__c> newShifts, Map<Id, sirenum__Shift__c> oldMap) {
        List<sirenum__Shift__c> changedShifts = new List<sirenum__Shift__c>();

        for (sirenum__Shift__c shift : newShifts) {
            sirenum__Shift__c oldShift = oldMap.get(shift.Id);
            if (oldShift == null) {
                continue;
            }
            if (shift.sirenum__Contact__c != oldShift.sirenum__Contact__c
                || shift.s5m__BH4SFJob__c != oldShift.s5m__BH4SFJob__c
                || shift.sirenum__Date__c != oldShift.sirenum__Date__c) {
                changedShifts.add(shift);
            }
        }

        relateShiftsToPlacements(changedShifts);
    }

    /**
     * Primary shift date (Date) in the shift time zone. Used for Start Date
     * pull-back, new Placement Start Date and Name.
     */
    @TestVisible
    private static Date getShiftDate(sirenum__Shift__c shift) {
        if (shift == null || shift.sirenum__Date__c == null) {
            return null;
        }
        return Date.valueOf(shift.sirenum__Date__c.format('yyyy-MM-dd', SHIFT_TIME_ZONE));
    }

    /**
     * All plausible calendar dates for the Shift DateTime (London, GMT and
     * running-user time zone). Used for matching so that time-zone / DST
     * boundaries (e.g. 00:30 on Start Date, any time on End Date) never cause
     * a valid Placement to be missed.
     */
    @TestVisible
    private static Set<Date> getCandidateDates(sirenum__Shift__c shift) {
        Set<Date> dates = new Set<Date>();
        if (shift == null || shift.sirenum__Date__c == null) {
            return dates;
        }
        Datetime dt = shift.sirenum__Date__c;
        dates.add(Date.valueOf(dt.format('yyyy-MM-dd', SHIFT_TIME_ZONE)));
        dates.add(Date.valueOf(dt.format('yyyy-MM-dd', 'GMT')));
        dates.add(dt.date());
        return dates;
    }

    public static void relateShiftsToPlacements(List<sirenum__Shift__c> shifts) {

        if (shifts == null || shifts.isEmpty()) {
            return;
        }

        List<sirenum__Shift__c> shiftsToProcess = new List<sirenum__Shift__c>();
        for (sirenum__Shift__c shift : shifts) {
            if (!processedShiftIds.contains(shift.Id)) {
                shiftsToProcess.add(shift);
                processedShiftIds.add(shift.Id);
            }
        }

        if (shiftsToProcess.isEmpty()) {
            return;
        }

        Set<Id> contactIds = new Set<Id>();
        Set<Id> jobIds = new Set<Id>();

        for (sirenum__Shift__c shift : shiftsToProcess) {
            if (shift.sirenum__Contact__c != null && shift.s5m__BH4SFJob__c != null && shift.sirenum__Date__c != null) {
                contactIds.add(shift.sirenum__Contact__c);
                jobIds.add(shift.s5m__BH4SFJob__c);
            }
        }

        if (contactIds.isEmpty() || jobIds.isEmpty()) {
            return;
        }

        Map<Id, TR1__Job__c> jobMap = new Map<Id, TR1__Job__c>([SELECT Id, Name, TR1__Contact__r.Name, s5m__Contract__c, s5m__JobRole__c
                                                                FROM TR1__Job__c
                                                                WHERE Id IN :jobIds]);

        Map<String, List<sirenum__Placement__c>> placementsByKey = new Map<String, List<sirenum__Placement__c>>();

        for (sirenum__Placement__c placement : [SELECT Id, Job__c, sirenum__Contact__c, sirenum__Contract__c,
                                                       sirenum__Job_Role__c, sirenum__Start_Date__c,
                                                       sirenum__End_Date__c
                                                FROM sirenum__Placement__c
                                                WHERE sirenum__Contact__c IN :contactIds
                                                AND Job__c IN :jobIds]) {
            String key = buildKey(placement.sirenum__Contact__c, placement.Job__c);
            if (!placementsByKey.containsKey(key)) {
                placementsByKey.put(key, new List<sirenum__Placement__c>());
            }
            placementsByKey.get(key).add(placement);
        }

        Map<Id, sirenum__Placement__c> placementAssignmentByShiftId = new Map<Id, sirenum__Placement__c>();
        Map<Id, sirenum__Placement__c> placementsToUpdate = new Map<Id, sirenum__Placement__c>();
        Map<String, List<sirenum__Shift__c>> unmatchedShiftsByKey = new Map<String, List<sirenum__Shift__c>>();

        // First pass: match against existing Placements (Rule 1 / Rule 2).
        for (sirenum__Shift__c shift : shiftsToProcess) {

            if (shift.sirenum__Contact__c == null || shift.s5m__BH4SFJob__c == null || shift.sirenum__Date__c == null) {
                continue;
            }

            Date shiftDate = getShiftDate(shift);
            String key = buildKey(shift.sirenum__Contact__c, shift.s5m__BH4SFJob__c);
            List<sirenum__Placement__c> candidates = placementsByKey.get(key);

            sirenum__Placement__c matched = findMatchingPlacement(shift, candidates);

            if (matched != null) {
                placementAssignmentByShiftId.put(shift.Id, matched);

                // Rule 2 only: shift is before Start Date under every interpretation
                if (!isRule1Match(shift, matched)
                    && matched.sirenum__Start_Date__c != null
                    && shiftDate < matched.sirenum__Start_Date__c) {
                    matched.sirenum__Start_Date__c = shiftDate;
                    placementsToUpdate.put(matched.Id, matched);
                }
            } else {
                System.debug(LoggingLevel.WARN, 'ShiftTriggerHandler: no Placement match for Shift ' + shift.Id
                    + ' | shift datetime=' + shift.sirenum__Date__c
                    + ' | candidateDates=' + getCandidateDates(shift)
                    + ' | existing placements for key=' + (candidates == null ? 0 : candidates.size()));

                if (!unmatchedShiftsByKey.containsKey(key)) {
                    unmatchedShiftsByKey.put(key, new List<sirenum__Shift__c>());
                }
                unmatchedShiftsByKey.get(key).add(shift);
            }
        }

        // Second pass (Rule 3): one new Placement per Contact/Job key.
        Map<String, sirenum__Placement__c> newPlacementsByKey = new Map<String, sirenum__Placement__c>();

        for (String key : unmatchedShiftsByKey.keySet()) {

            List<sirenum__Shift__c> unmatchedShifts = unmatchedShiftsByKey.get(key);

            Date earliestDate = null;
            for (sirenum__Shift__c shift : unmatchedShifts) {
                Date d = getShiftDate(shift);
                if (earliestDate == null || d < earliestDate) {
                    earliestDate = d;
                }
            }

            sirenum__Shift__c sampleShift = unmatchedShifts[0];
            TR1__Job__c job = jobMap.get(sampleShift.s5m__BH4SFJob__c);

            if (job == null || job.s5m__Contract__c == null || job.s5m__JobRole__c == null) {
                continue;
            }

            sirenum__Placement__c newPlacement = new sirenum__Placement__c(
                Name                   = (job.TR1__Contact__r.Name + ' - ' + job.Name + '- ' + String.valueOf(earliestDate)).left(80),
                sirenum__Contact__c    = sampleShift.sirenum__Contact__c,
                Job__c                 = sampleShift.s5m__BH4SFJob__c,
                sirenum__Contract__c   = job.s5m__Contract__c,
                sirenum__Job_Role__c   = job.s5m__JobRole__c,
                sirenum__Start_Date__c = earliestDate
            );

            newPlacementsByKey.put(key, newPlacement);
        }

        if (!newPlacementsByKey.isEmpty()) {
            insert newPlacementsByKey.values();

            for (String key : unmatchedShiftsByKey.keySet()) {
                sirenum__Placement__c newPlacement = newPlacementsByKey.get(key);
                if (newPlacement == null || newPlacement.Id == null) {
                    continue;
                }
                for (sirenum__Shift__c shift : unmatchedShiftsByKey.get(key)) {
                    placementAssignmentByShiftId.put(shift.Id, newPlacement);
                }
            }
        }

        List<sirenum__Shift__c> shiftsToUpdate = new List<sirenum__Shift__c>();
        for (sirenum__Shift__c shift : shiftsToProcess) {
            sirenum__Placement__c placement = placementAssignmentByShiftId.get(shift.Id);
            if (placement == null || shift.sirenum__Placement__c == placement.Id) {
                continue;
            }
            shiftsToUpdate.add(new sirenum__Shift__c(Id = shift.Id, sirenum__Placement__c = placement.Id));
        }

        if (!placementsToUpdate.isEmpty()) {
            update placementsToUpdate.values();
        }

        if (!shiftsToUpdate.isEmpty()) {
            update shiftsToUpdate;
        }
    }

    /**
     * Rule 1 test: for ANY candidate date of the shift,
     * Start <= date AND (End blank OR date <= End)  (inclusive both ends).
     */
    @TestVisible
    private static Boolean isRule1Match(sirenum__Shift__c shift, sirenum__Placement__c placement) {
        if (placement == null || placement.sirenum__Start_Date__c == null) {
            return false;
        }
        for (Date d : getCandidateDates(shift)) {
            Boolean onOrAfterStart = d >= placement.sirenum__Start_Date__c;
            Boolean noEndDate = placement.sirenum__End_Date__c == null;
            if (onOrAfterStart && (noEndDate || d <= placement.sirenum__End_Date__c)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Rule 1: shift falls within Placement range (see isRule1Match).
     * Rule 2: Placement has no End Date AND shift is before Start Date.
     * Rule 1 has priority; ties resolved by closest Start Date.
     */
    @TestVisible
    private static sirenum__Placement__c findMatchingPlacement(sirenum__Shift__c shift, List<sirenum__Placement__c> Placements) {

        if (Placements == null || Placements.isEmpty()) {
            return null;
        }

        Date shiftDate = getShiftDate(shift);
        if (shiftDate == null) {
            return null;
        }

        sirenum__Placement__c rule1Match = null;
        sirenum__Placement__c rule2Match = null;

        for (sirenum__Placement__c placement : Placements) {

            if (placement.sirenum__Start_Date__c == null) {
                continue;
            }

            if (isRule1Match(shift, placement)) {
                if (rule1Match == null || placement.sirenum__Start_Date__c > rule1Match.sirenum__Start_Date__c) {
                    rule1Match = placement;
                }
                continue;
            }

            if (placement.sirenum__End_Date__c == null && shiftDate < placement.sirenum__Start_Date__c) {
                if (rule2Match == null || placement.sirenum__Start_Date__c < rule2Match.sirenum__Start_Date__c) {
                    rule2Match = placement;
                }
            }
        }

        return rule1Match != null ? rule1Match : rule2Match;
    }

    private static String buildKey(Id contactId, Id jobId) {
        return contactId + '-' + jobId;
    }
}