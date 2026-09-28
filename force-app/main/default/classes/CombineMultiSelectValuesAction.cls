public with sharing class CombineMultiSelectValuesAction {
    public class Request {
        @InvocableVariable
        public List<String> values1;
 
        @InvocableVariable
        public List<String> values2;
 
        @InvocableVariable
        public List<String> values3;
    }
 
    public class Response {
        @InvocableVariable
        public String result1;
 
        @InvocableVariable
        public String result2;
 
        @InvocableVariable
        public String result3;
    }
 
    @InvocableMethod(label='Remove Duplicate Multi-Select Values')
    public static List<Response> removeDuplicates(List<Request> requests) {
        List<Response> responses = new List<Response>();
 
        for (Request request : requests) {
            Response response = new Response();
            response.result1 = processValues(request.values1);
            response.result2 = processValues(request.values2);
            response.result3 = processValues(request.values3);
            responses.add(response);
        }
 
        return responses;
    }
 
    private static String processValues(List<String> values) {
        Set<String> uniqueValues = new Set<String>();
 
        if (values != null) {
            for (String value : values) {
                if (String.isBlank(value)) {
                    continue;
                }
 
                for (String item : value.split(';')) {
                    if (!String.isBlank(item)) {
                        uniqueValues.add(item.trim());
                    }
                }
            }
        }
 
        List<String> sortedValues = new List<String>(uniqueValues);
        sortedValues.sort();
 
        return String.join(sortedValues, ';');
    }
}