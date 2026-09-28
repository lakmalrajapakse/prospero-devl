public class SensitiveDataSharingUtility {

    // Load full hierarchy in bulk
    public static Map<Id, User> loadHierarchy(Set<Id> startUserIds) {
        Map<Id, User> userMap = new Map<Id, User>();
        Set<Id> toProcess = new Set<Id>(startUserIds);

        while (!toProcess.isEmpty()) {

            List<User> users = [
                                    SELECT Id, ManagerId, Stop_Sensitive_Data_Share_Process__c
                                    FROM User
                                    WHERE Id IN :toProcess
                                ];

            toProcess.clear();

            for (User u : users) {
                userMap.put(u.Id, u);
                if (u.ManagerId != null && !userMap.containsKey(u.ManagerId)) {
                    toProcess.add(u.ManagerId);
                }
            }
        }

        return userMap;
    }

    // Get manager chain
    public static Set<Id> getManagerChain(Id ownerId, Map<Id, User> userMap) {

        Set<Id> managers = new Set<Id>();
        Set<Id> visitedUser = new Set<Id>();
        User current = userMap.get(ownerId);

        while (current != null && current.ManagerId != null) {

            /// prevent infite loop of hierarchy
            if(visitedUser.contains(current.Id)){
                break;
            }

            visitedUser.add(current.Id);

            User manager = userMap.get(current.ManagerId);
            if (manager == null) break;

            managers.add(manager.Id);

            if (manager.Stop_Sensitive_Data_Share_Process__c) {
                break;
            }

            current = manager;
        }

        return managers;
    }
    // User hierarchy for batch
    public static Set<Id> getAllSubordinateUsers(Set<Id> managerIds){

        Set<Id> allUsers = new Set<Id>();
        Set<Id> usersToProcess = new Set<Id>(managerIds);

        while(!usersToProcess.isEmpty()){

            List<User> subordinateUsers = [
                                                SELECT Id
                                                FROM User
                                                WHERE ManagerId IN :usersToProcess
                                            ];

            usersToProcess.clear();

            for(User u : subordinateUsers){
                if(!allUsers.contains(u.Id)){
                    allUsers.add(u.Id);
                    usersToProcess.add(u.Id);
                }
            }
        }
        // Include original managers too
        allUsers.addAll(managerIds);

        return allUsers;
    }

    // Utility method to create and delete the sharing
    // Used by UpdateSensitiveDataSharingBatch, CreateSensitiveDataSharingHandler
    public static void syncManagerShares(List<Sensitive_Data__c> records) {

        if(records.isEmpty()) return;

        Set<Id> recordIds = new Set<Id>();
        Set<Id> ownerIds = new Set<Id>();

        for(Sensitive_Data__c rec : records){
            recordIds.add(rec.Id);
            ownerIds.add(rec.OwnerId);
        }

        // Load hierarchy
        Map<Id, User> userMap = loadHierarchy(ownerIds);

        // Existing shares
        List<Sensitive_Data__Share> existingShares = [
                                                        SELECT Id, ParentId, UserOrGroupId
                                                        FROM Sensitive_Data__Share
                                                        WHERE ParentId IN :recordIds
                                                        AND RowCause = 'Sensitive_Data_Sharing__c'
                                                    ];

        // Existing share map
        Map<Id, Map<Id, Sensitive_Data__Share>> existingShareMap = new Map<Id, Map<Id, Sensitive_Data__Share>>();

        for(Sensitive_Data__Share share : existingShares){

            if(!existingShareMap.containsKey(share.ParentId)){
                existingShareMap.put(share.ParentId, new Map<Id, Sensitive_Data__Share>());
            }

            existingShareMap.get(share.ParentId).put(share.UserOrGroupId, share);
        }

        List<Sensitive_Data__Share> sharesToInsert = new List<Sensitive_Data__Share>();

        List<Sensitive_Data__Share> sharesToDelete =  new List<Sensitive_Data__Share>();

        // Compare expected vs existing
        for(Sensitive_Data__c rec : records){

            Set<Id> expectedManagers = getManagerChain(rec.OwnerId, userMap);

            Map<Id, Sensitive_Data__Share> existingManagers =
                existingShareMap.containsKey(rec.Id)
                ? existingShareMap.get(rec.Id)
                : new Map<Id, Sensitive_Data__Share>();

            // INSERT missing shares
            for(Id mgrId : expectedManagers){

                if(!existingManagers.containsKey(mgrId)){

                    sharesToInsert.add(new Sensitive_Data__Share(
                        ParentId = rec.Id,
                        UserOrGroupId = mgrId,
                        AccessLevel = 'Edit',
                        RowCause = Schema.Sensitive_Data__Share.RowCause.Sensitive_Data_Sharing__c
                    ));
                }
            }

            // DELETE obsolete shares
            for(Id existingMgrId : existingManagers.keySet()){

                if(!expectedManagers.contains(existingMgrId)){

                    sharesToDelete.add(existingManagers.get(existingMgrId));
                }
            }
        }

        if(!sharesToDelete.isEmpty()){
            delete sharesToDelete;
        }

        if(!sharesToInsert.isEmpty()){
            insert sharesToInsert;
        }
    }
}