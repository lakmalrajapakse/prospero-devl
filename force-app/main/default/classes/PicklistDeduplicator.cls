public class PicklistDeduplicator {
    @InvocableMethod(label='Remove Duplicate Picklist Values')
    public static List<String> deduplicate(List<Request> requests) {
        List<String> results = new List<String>();
        for (Request req : requests) {
            Set<String> uniqueValues = new Set<String>();
            if (String.isNotBlank(req.varTAG)) {
                uniqueValues.addAll(req.varTAG.split(';'));
            }
            if (String.isNotBlank(req.varHSAG)) {
                uniqueValues.addAll(req.varHSAG.split(';'));
            }
            results.add(String.join(new List<String>(uniqueValues), ';'));
        }
        return results;
    }
    
    public class Request {
        @InvocableVariable public String varTAG;
        @InvocableVariable public String varHSAG;
    }
}