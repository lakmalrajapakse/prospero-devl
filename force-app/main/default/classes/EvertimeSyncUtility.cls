public without sharing class EvertimeSyncUtility {

    private static final String SYNC_REQUIRED_FIELD = 'Evertime_Sync_Required__c';
    private static final String LAST_SYNC_FIELD = 'Last_Evertime_Sync__c';

    /**
     * Object → Evertime fields.
     * Evertime Sync fields from the spreadsheet.
     */
    private static final Map<String, List<String>> EVERTIME_FIELDS = new Map<String, List<String>>{
            'Account' => new List<String>{
                'Email__c',
                'Description',
                'Diocese__c'
            },

            'Contact' => new List<String>{
                'TR1__Batch_ID__c',
                'Birthdate',
                'Brand_Single_Pick__c'
            },

            'Commission_Split__c' => new List<String>{
                'Placement__c',
                'Closing_Report__c',
                'Split_Percentage__c'
            },

            'sirenum__Placement__c' => new List<String>{
                'sirenum__Dirty__c',
                'sirenum__End_Date__c',
                'sirenum__Charge_Rate__c'
            },

            'sirenum__ProActiveContract__c' => new List<String>{
                'sirenum__PO_Number__c',
                'sirenum__PO_Source__c',
                'sirenum__PO_Expires__c'
            },

            'sirenum__Rate_Card__c' => new List<String>{
                'sirenum__Sirenum_Contract__c',
                'sirenum__Site__c',
                'sirenum__Job_Type__c'
            },

            'sirenum__Rate_Card_Page__c' => new List<String>{
                'sirenum__Valid_From_Date__c',
                'sirenum__Valid_Until_Date__c',
                'sirenum__Rate_Type__c'
            },

            'sirenum__Rate_Line__c' => new List<String>{
                'sirenum__Day_Type__c',
                'sirenum__End_Hour__c',
                'Margin__c'
            },

            'sirenum__Rate_Modifier__c' => new List<String>{
                'Margin__c',
                'Margin_Type__c',
                'sirenum__Pay_Rate__c'
            },

            'sirenum__Shift__c' => new List<String>{
                'sirenum__Break_Length__c',
                'sirenum__Break_Override__c',
                'sirenum__BreakStartTime__c'
            },

            'sirenum__Site__c' => new List<String>{
                'sirenum__City__c',
                'sirenum__Country__c',
                'sirenum__AWR_Group__c'
            },

            'Team_User__c' => new List<String>{
                'User__c',
                'Team__c'
            },

            'TR1__Closing_Report__c' => new List<String>{
                'Academic_Year__c',
                'TR1__Assignment_Ended__c',
                'TR1__Contract_End_Date__c'
            },

            'TR1__Job__c' => new List<String>{
                'TR1__Actual_Total__c',
                'TR1__Actual_Bonus__c',
                'TR1__Bonus__c'
            },

            'User' => new List<String>{
                'CompanyName',
                'Division',
                'Department'
            },

            'sirenum__Expense__c' => new List<String>{
                'sirenum__Charge_Code__c',
                'sirenum__Comments__c',
                'sirenum__Date_of_expense__c'
            }
        };


    /**
     * Main method called from the BEFORE UPDATE trigger.
     */
    public static void process(List<SObject> newRecords,Map<Id, SObject> oldMap) {
        if (newRecords == null ||newRecords.isEmpty() ||oldMap == null ||oldMap.isEmpty()) {
            return;
        }

        String objectName = newRecords[0]
            .getSObjectType()
            .getDescribe()
            .getName();

        List<String> fieldsToCheck = EVERTIME_FIELDS.get(objectName);

        if (fieldsToCheck == null || fieldsToCheck.isEmpty()) {
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

            /*
             * Only process records that have already been
             * synchronized with Evertime.
             */
            Datetime lastEvertimeSync =(Datetime) newRecord.get(LAST_SYNC_FIELD);

            if (lastEvertimeSync == null) {
                continue;
            }
            /*
             * Check the 3 configured Evertime fields.
             */
            if (hasFieldChanged(newRecord,oldRecord,fieldsToCheck)) {
                newRecord.put(SYNC_REQUIRED_FIELD,currentDateTime);
            }
        }
    }
    /**
     * Checks whether any configured Evertime field changed.
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