public with sharing class CombineRolesAction {

    public class Request {
        @InvocableVariable(required=true)
        public List<String> roles;
    }

    public class Response {
        @InvocableVariable
        public String roles;
    }

    @InvocableMethod(
        label='Combine Roles'
        description='Combines multiple multi-select picklist values and removes duplicates.'
    )
    public static List<Response> combineRoles(List<Request> requests) {

        List<Response> responses = new List<Response>();

        for (Request request : requests) {

            Set<String> rolesSet = new Set<String>();

            if (request.roles != null) {
                for (String rolesValues : request.roles) {

                    if (String.isBlank(rolesValues)) {
                        continue;
                    }

                    for (String value : rolesValues.split(';')) {

                        if (!String.isBlank(value)) {
                            rolesSet.add(value.trim());
                        }
                    }
                }
            }

            List<String> sortedRoles = new List<String>(rolesSet);
            sortedRoles.sort();

            Response response = new Response();
            response.roles = String.join(sortedRoles, ';');

            responses.add(response);
        }

        return responses;
    }
}