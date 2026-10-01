public without sharing class tutexaFieldsUpdateHandler {
    
    Public static void checkFieldUpdate(list<sirenum__Shift__c> newshifts, Map<id, sirenum__Shift__c> oldShifts){

        // get Additional fields for shift: 
          Set<String> monitoredFields = getMonitoredFields();
          
          // add fixed fields in this MonitiredFields
          Set<String> fixedShiftFields = new Set<String>{   'sirenum__Date__c',
                                                            'sirenum__Scheduled_Start_Time__c',
                                                            'sirenum__Scheduled_Shift_Length_Decimal__c',
                                                            'sirenum__Cancelled__c'};
          monitoredFields.addAll(fixedShiftFields);

          for(sirenum__Shift__c shift: newshifts){
            
             sirenum__Shift__c oldShift = oldShifts.get(shift.Id);

             if(isMonitoredFieldChanged(monitoredFields, shift, oldShift)){
                shift.Tutexa_Export_Date__c = null;
             }
          }

    }

    ///Helper method to get the shift fields from CMDT
    @testVisible
    private static Set<String> getMonitoredFields() {
        Set<String> monitoredFields = new Set<String>();

        Map<String, Schema.SObjectField> shiftFields = sirenum__Shift__c.SObjectType.getDescribe().fields.getMap();

        for (Tutexa_Report_Additional_Field__mdt config : [ SELECT Field_API_Name__c
                                                                FROM Tutexa_Report_Additional_Field__mdt
                                                                WHERE Active__c = TRUE]) {
            String fieldName = config.Field_API_Name__c?.trim();

            if (String.isNotBlank(fieldName) && shiftFields.containsKey(fieldName)) {
                monitoredFields.add(fieldName);
            }
        }

        return monitoredFields;
    }   

    ///Helper method to check if moonitored fields have been modified
    @testVisible
    private static Boolean isMonitoredFieldChanged(Set<String> monitoredFields, sirenum__Shift__c NewShift, sirenum__Shift__c OldShift) {

        For(String fieldName: monitoredFields){
            if(NewShift.get(fieldName) != OldShift.get(fieldName) ){
                return true;
            }
        }
        return false;
    }
}