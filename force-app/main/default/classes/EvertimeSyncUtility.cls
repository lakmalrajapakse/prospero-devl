/*
@author: Rishikesh Kumar Suman
@Date: 09-30-2026
@Desc: 
     * Main method called from BEFORE UPDATE triggers.
     *
     * The method dynamically reads the Evertime_Sync_Field
     * Field Set from the object and checks whether any field
     * in that Field Set has changed.
     *
     * If:
     * 1. Last_Evertime_Sync__c is populated
     * 2. Any field in Evertime_Sync_Field has changed
     *
     * Then:
     * Evertime_Sync_Required__c is set to the current date/time.
*/
public without sharing class EvertimeSyncUtility {

    private static final String FIELD_SET_NAME = 'Evertime_Sync_Field';
    private static final String SYNC_REQUIRED_FIELD = 'Evertime_Sync_Required__c';
    private static final String LAST_SYNC_FIELD = 'Last_Evertime_Sync__c';
    
    public static void process(List<SObject> newRecords,Map<Id, SObject> oldMap) {
        if (newRecords == null ||newRecords.isEmpty() ||oldMap == null ||oldMap.isEmpty()) {
            return;
        }
        Schema.SObjectType objectType = newRecords[0].getSObjectType();
        List<String> fieldsToCheck = getEvertimeFields(objectType);

        if (fieldsToCheck.isEmpty()) {
            return;
        }
        Datetime currentDateTime = System.now();

        for (SObject newRecord : newRecords) {

            if (newRecord == null || newRecord.Id == null) {
                continue;
            }
            SObject oldRecord = oldMap.get(newRecord.Id);

            if (oldRecord == null) {
                continue;
            }
            Datetime lastEvertimeSync = (Datetime)newRecord.get(LAST_SYNC_FIELD);

            if (lastEvertimeSync == null) {
                continue;
            }
            if (hasFieldChanged(newRecord,oldRecord,fieldsToCheck)) {
                newRecord.put(SYNC_REQUIRED_FIELD,currentDateTime);
            }
        }
    }
    /**
     * Dynamically gets all field API names from the
     * Evertime_Sync_Field Field Set for the current object.
     *
     * Example:
     *
     * Account
     *   -> Evertime_Sync_Field
     *      -> Email__c
     *      -> Description
     *      -> Phone
     *      -> Industry
     *
     * The number of fields can be different for every object.
     */
    private static List<String> getEvertimeFields(Schema.SObjectType objectType) {
        List<String> fieldNames = new List<String>();

        if (objectType == null) {
            return fieldNames;
        }
        Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
        Map<String, Schema.FieldSet> fieldSets = objectDescribe.fieldSets.getMap();

        if (!fieldSets.containsKey(FIELD_SET_NAME)) {
            return fieldNames;
        }
        Schema.FieldSet evertimeFieldSet = fieldSets.get(FIELD_SET_NAME);
        for (Schema.FieldSetMember fieldMember :evertimeFieldSet.getFields()) {
            fieldNames.add(fieldMember.getFieldPath());
        }
        return fieldNames;
    }

    /**
     * Checks whether any field in the Evertime
     * Field Set has changed.
     *
     * Handles:
     *
     * NULL -> NULL       = No change
     * NULL -> Value      = Changed
     * Value -> NULL      = Changed
     * Same Value -> Same = No change
     * Value -> Value     = Changed
     */
    private static Boolean hasFieldChanged(SObject newRecord,SObject oldRecord,List<String> fieldsToCheck) {
        for (String fieldName : fieldsToCheck) {

            Object oldValue = oldRecord.get(fieldName);
            Object newValue = newRecord.get(fieldName);
            
            if (oldValue == null && newValue == null) {
                continue;
            }
            if (oldValue == null || newValue == null) {
                return true;
            }
            if (!oldValue.equals(newValue)) {
                return true;
            }
        }

        return false;
    }
}