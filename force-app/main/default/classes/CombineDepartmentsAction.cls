public with sharing class CombineDepartmentsAction {

    public class Request {
        @InvocableVariable(required=true)
        public List<String> departments;
    }

    public class Response {
        @InvocableVariable
        public String departments;
    }

    @InvocableMethod(
        label='Combine Departments'
        description='Combines multiple multi-select picklist values and removes duplicates.'
    )
    public static List<Response> combineDepartments(List<Request> requests) {

        List<Response> responses = new List<Response>();

        for (Request request : requests) {

            Set<String> departmentsSet = new Set<String>();

            if (request.departments != null) {
                for (String departmentValues : request.departments) {

                    if (String.isBlank(departmentValues)) {
                        continue;
                    }

                    for (String value : departmentValues.split(';')) {

                        if (!String.isBlank(value)) {
                            departmentsSet.add(value.trim());
                        }
                    }
                }
            }

            List<String> sortedDepartments = new List<String>(departmentsSet);
            sortedDepartments.sort();

            Response response = new Response();
            response.departments = String.join(sortedDepartments, ';');

            responses.add(response);
        }

        return responses;
    }
}