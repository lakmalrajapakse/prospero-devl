/* 
@author: Emmanuel Jesse Madasu
@Date: 01-07-2026
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/36180184
*/
public without sharing class SensitiveDataDuplicateChecker {
    
    public class InputWrapper {
        @InvocableVariable(label = 'First Name' required = true)
        public String firstName;
        
        @InvocableVariable(label = 'Last Name' required = true)
        public String lastName;
        
        @InvocableVariable(label = 'Date of Birth' required = true)
        public Date dateOfBirth;
    }
    
    public class OutputWrapper {
        @InvocableVariable(label = 'Duplicate Found With Access')
        public Boolean duplicateWithAccess;
        
        @InvocableVariable(label = 'Duplicate Found Without Access')
        public Boolean duplicateWithoutAccess;
        
        @InvocableVariable(label = 'No Duplicate Found')
        public Boolean noDuplicateFound;
        
        @InvocableVariable(label = 'Matched Record Owner Name')
        public String ownerName;
        
        @InvocableVariable(label = 'Matched Record Reference ID')
        public String referenceId;
        
        @InvocableVariable(label = 'Matched Record Type Name')
        public String recordTypeName;
        
        @InvocableVariable(label = 'Matched Record Type Developer Name')
        public String recordTypeDevName;
        
        @InvocableVariable(label = 'Matched Record Id')
        public Id matchedRecordId;
        
        @InvocableVariable(label = 'Address Street')
        public String addressStreet;

        @InvocableVariable(label = 'Address City')
        public String addressCity;

        @InvocableVariable(label = 'Address State')
        public String addressState;

        @InvocableVariable(label = 'Address Postal Code')
        public String addressPostalCode;

        @InvocableVariable(label = 'Address Country')
        public String addressCountry;
    }
    
    @InvocableMethod(label = 'Check Sensitive Data Duplicate')
    public static List<OutputWrapper> checkDuplicate(List<InputWrapper> inputs) {
        List<OutputWrapper> results = new List<OutputWrapper>();
        
        // Get thresholds from Custom Settings
        General_Settings__c setting = General_Settings__c.getOrgDefaults();
        Decimal fNameThreshold = (setting != null && setting.First_Name_Fuzzy_Threshold__c != null)
            ? setting.First_Name_Fuzzy_Threshold__c
            : 70;
        Decimal lNameThreshold = (setting != null && setting.Fuzzy_Match_Threshold__c != null)
            ? setting.Fuzzy_Match_Threshold__c
            : 80;

        Set<Date> allDobs = new Set<Date>();
        for (InputWrapper input : inputs) {
            if (input.dateOfBirth != null) {
                allDobs.add(input.dateOfBirth);
            }
        }

        List<Sensitive_Data__c> allRecords = new List<Sensitive_Data__c>();
        if (!allDobs.isEmpty()) {
            allRecords = [
                SELECT Id, First_Name__c, Last_Name__c, Owner.Name,
                       RecordType.Name, RecordType.DeveloperName, Reference_ID__c,
                       Address__Street__s, Address__City__s, Address__StateCode__s,
                       Address__PostalCode__s, Address__CountryCode__s,
                       Date_of_Birth__c
                FROM Sensitive_Data__c
                WHERE Date_of_Birth__c IN :allDobs
                WITH SYSTEM_MODE];
        }

        // Group records by DOB for efficient lookup
        Map<Date, List<Sensitive_Data__c>> recordsByDob = new Map<Date, List<Sensitive_Data__c>>();
        for (Sensitive_Data__c record : allRecords) {
            if (!recordsByDob.containsKey(record.Date_of_Birth__c)) {
                recordsByDob.put(record.Date_of_Birth__c, new List<Sensitive_Data__c>());
            }
            recordsByDob.get(record.Date_of_Birth__c).add(record);
        }

        // Process each input against its DOB matched candidates
        for (InputWrapper input : inputs) {
            OutputWrapper output = new OutputWrapper();

            List<Sensitive_Data__c> candidates = recordsByDob.containsKey(input.dateOfBirth)
                ? recordsByDob.get(input.dateOfBirth)
                : new List<Sensitive_Data__c>();

            Sensitive_Data__c matchedRecord = null;

            for (Sensitive_Data__c record : candidates) {
                Decimal fNameMatch = 0;
                Decimal lNameMatch = 0;

                if (!String.isBlank(record.First_Name__c) && !String.isBlank(input.firstName)) {
                    String normalizedNew = input.firstName.trim().toLowerCase();
                    String normalizedExisting = record.First_Name__c.trim().toLowerCase();
                    Decimal fDistance = normalizedNew.getLevenshteinDistance(normalizedExisting);
                    Integer biggestFName = Math.max(normalizedNew.length(), normalizedExisting.length());
                    fNameMatch = (1 - (fDistance / biggestFName)) * 100;
                }

                if (!String.isBlank(record.Last_Name__c) && !String.isBlank(input.lastName)) {
                    String normalizedNew = input.lastName.trim().toLowerCase();
                    String normalizedExisting = record.Last_Name__c.trim().toLowerCase();
                    Decimal lDistance = normalizedNew.getLevenshteinDistance(normalizedExisting);
                    Integer biggestLName = Math.max(normalizedNew.length(), normalizedExisting.length());
                    lNameMatch = (1 - (lDistance / biggestLName)) * 100;
                }

                // Both First and Last Names must independently clear their threshold
                if (fNameMatch >= fNameThreshold && lNameMatch >= lNameThreshold) {
                    matchedRecord = record;
                    break;
                }
            }

            if (matchedRecord != null) {
                output.noDuplicateFound = false;

                List<UserRecordAccess> accessList = [
                    SELECT RecordId, HasReadAccess
                    FROM UserRecordAccess
                    WHERE UserId = :UserInfo.getUserId()
                    AND RecordId = :matchedRecord.Id];

                Boolean hasAccess = !accessList.isEmpty() && accessList[0].HasReadAccess;
                output.duplicateWithAccess = hasAccess;
                output.duplicateWithoutAccess = !hasAccess;
                output.ownerName = matchedRecord.Owner.Name;

                if (hasAccess) {
                    output.matchedRecordId = matchedRecord.Id;
                    output.referenceId = matchedRecord.Reference_ID__c;
                    output.recordTypeName = matchedRecord.RecordType.Name;
                    output.recordTypeDevName = matchedRecord.RecordType.DeveloperName;
                    output.addressStreet = matchedRecord.Address__Street__s;
                    output.addressCity = matchedRecord.Address__City__s;
                    output.addressState = matchedRecord.Address__StateCode__s;
                    output.addressPostalCode = matchedRecord.Address__PostalCode__s;
                    output.addressCountry = matchedRecord.Address__CountryCode__s;
                }
            } else {
                output.noDuplicateFound = true;
                output.duplicateWithAccess = false;
                output.duplicateWithoutAccess = false;
            }

            results.add(output);
        }

        return results;
    }
}