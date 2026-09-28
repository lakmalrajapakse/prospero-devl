/* 
@auther: Emmanuel Jesse Madasu
@Date: 06-05-2026
@description:This class checks which Textkernel access roles apply to a record’s owner by checking their role and role hierarchy
@ref: https://1218globaluk.eu.teamwork.com/app/tasks/36058236
*/
public with sharing class SharingRulesRole {
 
    public class Request {
        @InvocableVariable(required=true)
        public Id userId;
    }

    public class Response {
        @InvocableVariable
        public String matchedRoleName;
    }

    @InvocableMethod(label='Get Owner Role'
    description='Returns the matching role name from the owner role hierarchy based on Role Mapping metadata.')
    public static List<Response> getRoles(List<Request> requests) {

        Set<Id> userIds = new Set<Id>();

        for (Request r : requests) {
            if (r.userId != null) {
                userIds.add(r.userId);
            }
        }

        // Get users
        Map<Id, User> users = new Map<Id, User>([
            SELECT Id, UserRoleId
            FROM User
            WHERE Id IN :userIds
        ]);

        // Metadata labels contain Role Developer Names
        Set<String> allowedRoles = new Set<String>();
        for (Role_Mapping__mdt mdt : [
            SELECT DeveloperName
            FROM Role_Mapping__mdt
        ]) {
        allowedRoles.add(mdt.DeveloperName);
        }

        // Get all roles
        Map<Id, UserRole> roleMap = new Map<Id, UserRole>([
            SELECT Id,
                   Name,
                   DeveloperName,
                   ParentRoleId
            FROM UserRole
        ]);

        // Search Policy Name -> Search Access Policy API value, e.g. 'Prospero Teaching' -> 'ProsperoTeaching'
        Map<String, String> policyApiNames = new Map<String, String>();
        for (Textkernel1__SearchPolicy__c policy : [
            SELECT Name, Textkernel1__ApiName__c
            FROM Textkernel1__SearchPolicy__c
        ]) {
            policyApiNames.put(policy.Name, policy.Textkernel1__ApiName__c);
        }

        List<Response> results = new List<Response>();

        for (Request req : requests) {

            Response res = new Response();

            User u = users.get(req.userId);

            if (u != null && u.UserRoleId != null) {

                Id currentRoleId = u.UserRoleId;

                // Traverse current role and parent hierarchy
                while (
                    currentRoleId != null &&
                    roleMap.containsKey(currentRoleId)
                ) {

                    UserRole role = roleMap.get(currentRoleId);

                    // Match using Role DeveloperName
                    if (allowedRoles.contains(role.DeveloperName)) {

                        // Return the matching Search Access Policy API value
                        res.matchedRoleName = policyApiNames.get(role.Name);
                        break;
                    }

                    currentRoleId = role.ParentRoleId;
                }
            }

            results.add(res);
        }

        return results;
    }

}