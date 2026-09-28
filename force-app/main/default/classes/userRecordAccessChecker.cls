public class userRecordAccessChecker {
    
    @InvocableMethod(label='Check Running Users Record Access')
    public static List<Boolean> checkAccess(List<Id> recordIds) {
        List<Boolean> results = new List<Boolean>();
        
        List<UserRecordAccess> accessList = [
            SELECT RecordId, HasReadAccess 
            FROM UserRecordAccess 
            WHERE UserId = :UserInfo.getUserId() 
            AND RecordId IN :recordIds
        ];
        
        Map<Id, Boolean> accessMap = new Map<Id, Boolean>();
        for (UserRecordAccess ua : accessList) {
            accessMap.put(ua.RecordId, ua.HasReadAccess);
        }
        
        for (Id recordId : recordIds) {
            results.add(accessMap.containsKey(recordId) && accessMap.get(recordId));
        }
        
        return results;
    }
}