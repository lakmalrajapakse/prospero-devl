public without sharing class ClientPortalShiftController {

    public class ShiftDTO {
        @AuraEnabled public Id Id;
        @AuraEnabled public Datetime scheduledStart;
        @AuraEnabled public Datetime scheduledEnd;
        @AuraEnabled public String siteName;
    }

    @AuraEnabled(cacheable=true)
    public static List<ShiftDTO> getShiftsForCandidate(Id contactId) {
        Id currentAccountId = ClientPortalCandidateControllers.getCurrentUserAccountId();
        List<ShiftDTO> output = new List<ShiftDTO>();

        if (contactId == null || currentAccountId == null) {
            return output;
        }

        Map<Id, sirenum__Site__c> sitesById = new Map<Id, sirenum__Site__c>([
            SELECT Id, Name
            FROM sirenum__Site__c
            WHERE sirenum__Operating_Company__c = :currentAccountId
        ]);

        if (sitesById.isEmpty()) {
            return output;
        }

        List<sirenum__Shift__c> results = [
            SELECT Id, sirenum__Scheduled_Start_Time__c, sirenum__Scheduled_End_Time__c,
                   sirenum__Site__c
            FROM sirenum__Shift__c
            WHERE sirenum__Contact__c = :contactId
              AND sirenum__Site__c IN :sitesById.keySet()
            ORDER BY sirenum__Scheduled_Start_Time__c DESC
            LIMIT 200
        ];

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.READABLE, results
        );
        results = (List<sirenum__Shift__c>) decision.getRecords();

        for (sirenum__Shift__c shift : results) {
            ShiftDTO dto = new ShiftDTO();
            dto.Id = shift.Id;
            dto.scheduledStart = shift.sirenum__Scheduled_Start_Time__c;
            dto.scheduledEnd = shift.sirenum__Scheduled_End_Time__c;
            sirenum__Site__c site = sitesById.get(shift.sirenum__Site__c);
            dto.siteName = site != null ? site.Name : '';
            output.add(dto);
        }

        return output;
    }
}