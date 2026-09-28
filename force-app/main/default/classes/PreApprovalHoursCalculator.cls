/*
@author: Gandhi Naidu Bokam
@Date: 12-09-2026
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/35989281
*/
public with sharing class PreApprovalHoursCalculator {

    public static void recalculateAvailableHours(
        List<sirenum__Shift__c> newShifts,
        Map<Id, sirenum__Shift__c> oldMap,
        Boolean isInsert,
        Boolean isUpdate,
        Boolean isDelete,
        Boolean isUndelete
    ) {
        Set<Id> preApprovalIdsToRecalculate = collectPreApprovalIds(
            newShifts, oldMap, isInsert, isUpdate, isDelete, isUndelete
        );

        if (preApprovalIdsToRecalculate.isEmpty()) {
            return;
        }

        // Only recalc Pre-Approval records whose Hours field is populated (>0).
        Map<Id, Pre_Approval__c> preApprovalsToRecalculate = new Map<Id, Pre_Approval__c>([SELECT Id, Hours__c, Available_Hours__c
                                                                                           FROM Pre_Approval__c
                                                                                           WHERE Id IN :preApprovalIdsToRecalculate
                                                                                           AND Hours__c > 0
                                                                                          ]);

        if (preApprovalsToRecalculate.isEmpty()) {
            return;
        }

        Map<Id, Decimal> totalHoursSpentByPreApprovalId =
            sumActiveShiftHoursByPreApproval(preApprovalsToRecalculate.keySet());

        List<Pre_Approval__c> preApprovalsToUpdate = new List<Pre_Approval__c>();

        for (Pre_Approval__c pa : preApprovalsToRecalculate.values()) {
            Decimal totalHoursSpent = totalHoursSpentByPreApprovalId.containsKey(pa.Id)
                ? totalHoursSpentByPreApprovalId.get(pa.Id)
                : 0;

            preApprovalsToUpdate.add(new Pre_Approval__c(
                Id = pa.Id,
                Available_Hours__c = pa.Hours__c - totalHoursSpent
            ));
        }

        if (!preApprovalsToUpdate.isEmpty()) {
            update preApprovalsToUpdate;
        }
    }

    /**
     * Works out which Pre-Approval Ids need to be recalculated based on the
     * trigger context and the field-level conditions from the spec.
     */
    private static Set<Id> collectPreApprovalIds(
        List<sirenum__Shift__c> newShifts,
        Map<Id, sirenum__Shift__c> oldMap,
        Boolean isInsert,
        Boolean isUpdate,
        Boolean isDelete,
        Boolean isUndelete
    ) {
        Set<Id> preApprovalIds = new Set<Id>();

        if (isInsert || isUndelete) {
            for (sirenum__Shift__c shift : newShifts) {
                if (shift.Pre_Approval__c != null) {
                    preApprovalIds.add(shift.Pre_Approval__c);
                }
            }
        } else if (isDelete) {
            for (sirenum__Shift__c shift : oldMap.values()) {
                if (shift.Pre_Approval__c != null) {
                    preApprovalIds.add(shift.Pre_Approval__c);
                }
            }
        } else if (isUpdate) {
            for (sirenum__Shift__c newShift : newShifts) {
                sirenum__Shift__c oldShift = oldMap.get(newShift.Id);

                Boolean preApprovalPopulated =
                    newShift.Pre_Approval__c != null || oldShift.Pre_Approval__c != null;

                if (!preApprovalPopulated) {
                    continue;
                }

                Boolean relevantFieldChanged =
                    newShift.Pre_Approval__c != oldShift.Pre_Approval__c ||
                    newShift.sirenum__Scheduled_Start_Time__c != oldShift.sirenum__Scheduled_Start_Time__c ||
                    newShift.sirenum__Scheduled_End_Time__c != oldShift.sirenum__Scheduled_End_Time__c ||
                    newShift.sirenum__Cancelled__c != oldShift.sirenum__Cancelled__c;

                if (!relevantFieldChanged) {
                    continue;
                }

                if (newShift.Pre_Approval__c != null) {
                    preApprovalIds.add(newShift.Pre_Approval__c);
                }

                if (oldShift.Pre_Approval__c != null) {
                    preApprovalIds.add(oldShift.Pre_Approval__c);
                }
            }
        }

        return preApprovalIds;
    }

    /**
     * Queries every currently-active shift linked to the given Pre-Approval
     * Ids and sums (End Time - Start Time) in hours, grouped by Pre-Approval Id.
     */
    private static Map<Id, Decimal> sumActiveShiftHoursByPreApproval(Set<Id> preApprovalIds) {
        Map<Id, Decimal> totalHoursByPreApprovalId = new Map<Id, Decimal>();

        // Seed every requested Id at zero so Pre-Approvals with no remaining
        // active shifts still get their Available Hours reset correctly.
        for (Id paId : preApprovalIds) {
            totalHoursByPreApprovalId.put(paId, 0);
        }

        for (sirenum__Shift__c activeShift : [SELECT Id,Pre_Approval__c,sirenum__Scheduled_Start_Time__c,sirenum__Scheduled_End_Time__c
                                              FROM sirenum__Shift__c
                                              WHERE Pre_Approval__c IN :preApprovalIds
                                              AND sirenum__Cancelled__c = false
                                              AND sirenum__Scheduled_Start_Time__c != null
                                              AND sirenum__Scheduled_End_Time__c != null
                                              ]) {

            // Calculate the difference between End Time and Start Time
            // directly using DateTime.getTime(), which returns milliseconds.
            Long milliseconds = activeShift.sirenum__Scheduled_End_Time__c.getTime() - activeShift.sirenum__Scheduled_Start_Time__c.getTime();

            Decimal hoursForShift = millisecondsToHours(milliseconds);

            Decimal runningTotal = totalHoursByPreApprovalId.get(activeShift.Pre_Approval__c);

            totalHoursByPreApprovalId.put(activeShift.Pre_Approval__c,runningTotal + hoursForShift);
        }

        return totalHoursByPreApprovalId;
    }

    private static Decimal millisecondsToHours(Long milliseconds) {
        return ((Decimal) milliseconds) / (1000 * 60 * 60);
    }
}