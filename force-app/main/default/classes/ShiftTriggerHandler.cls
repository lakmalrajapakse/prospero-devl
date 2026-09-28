/*
@author: Gandhi Naidu Bokam
@Date: 01-09-2026
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/36248202

*/
public class ShiftTriggerHandler {

    private static Set<Id> processedShiftIds = new Set<Id>();

    /**
     * Entry point for after-insert trigger context.
     * Passes all newly inserted shifts to be related to their placements.
     */
    public static void handleAfterInsert(List<sirenum__Shift__c> newShifts) {
        relateShiftsToPlacements(newShifts);
    }

    /**
     * Entry point for after-update trigger context.
     * Filters shifts to only those where the Contact, Job, or Date field has
     * changed (all three drive Placement matching), then passes the changed
     * shifts to be related to their placements.
     */
    public static void handleAfterUpdate(List<sirenum__Shift__c> newShifts, Map<Id, sirenum__Shift__c> oldMap) {
        List<sirenum__Shift__c> changedShifts = new List<sirenum__Shift__c>();

        for (sirenum__Shift__c shift : newShifts) {
            sirenum__Shift__c oldShift = oldMap.get(shift.Id);
            if (oldShift == null) {
                continue;
            }
            if (shift.sirenum__Contact__c != oldShift.sirenum__Contact__c || shift.s5m__BH4SFJob__c != oldShift.s5m__BH4SFJob__c ) {
                changedShifts.add(shift);
            }
        }

        relateShiftsToPlacements(changedShifts);
    }

    /**
     * Core logic that links Shift records to Placement records based on the
     * combination of Contact, Job, and Date on each shift.
     *
     * For each Shift (with Contact, Job, and Date populated):
     *   Rule 1: If a Placement exists for the same Contact/Job where the
     *           Placement's Start Date is on/before the Shift's Date, AND
     *           either the Placement has no End Date or the Shift's Date is
     *           on/before the Placement's End Date -> relate the Shift to
     *           that Placement.
     *   Rule 2: Else, if an open-ended Placement (no End Date) exists for the
     *           same Contact/Job whose Start Date is after the Shift's Date
     *           -> relate the Shift to that Placement and pull the
     *           Placement's Start Date back to the Shift's Date.
     *   Rule 3: Else -> create a new Placement using the (earliest, if more
     *           than one unmatched Shift shares the key) Shift Date as the
     *           Start Date, and the Contract/Job Role from the related Job
     *           record, then relate the Shift to it.
     */
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

        Map<Id, TR1__Job__c> jobMap = new Map<Id, TR1__Job__c>([SELECT Id,Name,TR1__Contact__r.Name, s5m__Contract__c, s5m__JobRole__c
                                                                FROM TR1__Job__c
                                                                WHERE Id IN :jobIds
                                                             ]);

        // Existing Placements grouped by Contact/Job key. Several Placements
        // can share the same Contact/Job (e.g. separate engagements over time).
        Map<String, List<sirenum__Placement__c>> placementsByKey = new Map<String, List<sirenum__Placement__c>>();

        for (sirenum__Placement__c placement : [SELECT Id, Job__c, sirenum__Contact__c, sirenum__Contract__c,
                                                       sirenum__Job_Role__c, sirenum__Start_Date__c,
                                                       sirenum__End_Date__c
                                                FROM sirenum__Placement__c
                                                WHERE sirenum__Contact__c IN :contactIds
                                                AND Job__c IN :jobIds
                                                ]) {
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

            if (shift.sirenum__Contact__c == null ||shift.s5m__BH4SFJob__c == null ||shift.sirenum__Date__c == null) {
                continue;
            }

            String key = buildKey(shift.sirenum__Contact__c, shift.s5m__BH4SFJob__c);
            List<sirenum__Placement__c> candidates = placementsByKey.get(key);

            sirenum__Placement__c matched = findMatchingPlacement(shift, candidates);

            if (matched != null) {
                placementAssignmentByShiftId.put(shift.Id, matched);

                // Rule 2: extend the Placement's Start Date backwards if this
                // Shift's Date precedes it.
                if (matched.sirenum__Start_Date__c != null && shift.sirenum__Date__c < matched.sirenum__Start_Date__c) {

                    matched.sirenum__Start_Date__c = shift.sirenum__Date__c.date();
                    placementsToUpdate.put(matched.Id, matched);
                }
            } else {
                if (!unmatchedShiftsByKey.containsKey(key)) {
                    unmatchedShiftsByKey.put(key, new List<sirenum__Shift__c>());
                }
                unmatchedShiftsByKey.get(key).add(shift);
            }
        }

        // Second pass (Rule 3): create one new Placement per Contact/Job key
        // that still has unmatched Shifts, using the earliest Shift Date as
        // the Start Date.
        Map<String, sirenum__Placement__c> newPlacementsByKey = new Map<String, sirenum__Placement__c>();

        for (String key : unmatchedShiftsByKey.keySet()) {

            List<sirenum__Shift__c> unmatchedShifts = unmatchedShiftsByKey.get(key);

            Date earliestDate = null;
            for (sirenum__Shift__c shift : unmatchedShifts) {
                if (earliestDate == null || shift.sirenum__Date__c < earliestDate) {
                    earliestDate = shift.sirenum__Date__c.date();
                }
            }

            sirenum__Shift__c sampleShift = unmatchedShifts[0];
            TR1__Job__c job = jobMap.get(sampleShift.s5m__BH4SFJob__c);

            if (job == null || job.s5m__Contract__c == null || job.s5m__JobRole__c == null) {
                continue;
            }
            
            sirenum__Placement__c newPlacement = new sirenum__Placement__c(
                Name                   = (job.TR1__Contact__r.Name + ' - ' + job.Name + '- '+String.valueOf(sampleShift.sirenum__Date__c.date())).left(80),
                sirenum__Contact__c    = sampleShift.sirenum__Contact__c,
                Job__c                 = sampleShift.s5m__BH4SFJob__c,
                sirenum__Contract__c   = job.s5m__Contract__c,
                sirenum__Job_Role__c   = job.s5m__JobRole__c,
                sirenum__Start_Date__c = earliestDate
            );
            
            
            

            newPlacementsByKey.put(key, newPlacement);
        }

        if (!newPlacementsByKey.isEmpty()) {
            List<sirenum__Placement__c> placementsToCreate = newPlacementsByKey.values();
            insert placementsToCreate;

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

        // Build the final list of Shift updates.
        List<sirenum__Shift__c> shiftsToUpdate = new List<sirenum__Shift__c>();
        for (sirenum__Shift__c shift : shiftsToProcess) {
            sirenum__Placement__c placement = placementAssignmentByShiftId.get(shift.Id);
            if (placement == null || shift.sirenum__Placement__c == placement.Id) {
                continue;
            }
            shiftsToUpdate.add(new sirenum__Shift__c( Id = shift.Id,sirenum__Placement__c = placement.Id));
        }

        if (!placementsToUpdate.isEmpty()) {
            update placementsToUpdate.values();
        }

        if (!shiftsToUpdate.isEmpty()) {
            update shiftsToUpdate;
        }
    }

    /**
     * Finds a Placement among the candidates that matches the Shift per the
     * business rules:
     *   Rule 1: Placement Start Date <= Shift Date AND
     *           (Placement End Date is blank OR Shift Date <= Placement End Date)
     *   Rule 2: Placement End Date is blank AND Shift Date < Placement Start Date
     * Rule 1 matches take priority over Rule 2. If several candidates satisfy
     * the same rule, the one with the closest Start Date is preferred.
     */
    @TestVisible
    private static sirenum__Placement__c findMatchingPlacement(sirenum__Shift__c shift, List<sirenum__Placement__c> Placements) {

        if (Placements == null || Placements.isEmpty()) {
            return null;
        }

        sirenum__Placement__c rule1Match = null;
        sirenum__Placement__c rule2Match = null;

        for (sirenum__Placement__c placement : Placements) {

            if (placement.sirenum__Start_Date__c == null) {
                continue;
            }

            Boolean onOrAfterStart = shift.sirenum__Date__c >= placement.sirenum__Start_Date__c;
            Boolean noEndDate = placement.sirenum__End_Date__c == null;
            Boolean onOrBeforeEnd = !noEndDate && shift.sirenum__Date__c <= placement.sirenum__End_Date__c;

            if (onOrAfterStart && (noEndDate || onOrBeforeEnd)) {
                if (rule1Match == null || placement.sirenum__Start_Date__c > rule1Match.sirenum__Start_Date__c) {
                    rule1Match = placement;
                }
                continue;
            }

            if (noEndDate && shift.sirenum__Date__c < placement.sirenum__Start_Date__c) {
                if (rule2Match == null || placement.sirenum__Start_Date__c < rule2Match.sirenum__Start_Date__c) {
                    rule2Match = placement;
                }
            }
        }

        return rule1Match != null ? rule1Match : rule2Match;
    }

    /**
     * Builds a unique composite key from a Contact Id and Job Id,
     * used to group Placements by Contact/Job without repeated SOQL lookups.
     */
    private static String buildKey(Id contactId, Id jobId) {
        return contactId + '-' + jobId;
    }
}