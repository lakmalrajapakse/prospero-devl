public without sharing class ClientContactSearchController {
    
    ///1 Method to get the default Radius and additonal config data
    @AuraEnabled(cacheable = true)
    public static ClientSearchConfigWrapper getConfig(){
        try {
            Integer radius = 50;
            Google_API_Setting__c setting = [SELECT Default_Radius__c, 
                                                    Country_Code__c, 
                                                    Default_Country_Code__c,
                                                    Display_Column_Fieldset_Name__c,
                                                    Default_Where_Clause__c 
                                             FROM Google_API_Setting__c LIMIT 1];

            ClientSearchConfigWrapper config = new ClientSearchConfigWrapper();
            config.defaultRadius = (setting.Default_Radius__c != null) ? Integer.valueOf(setting.Default_Radius__c) : radius;
            config.fieldSetName = (setting.Display_Column_Fieldset_Name__c != null) ? setting.Display_Column_Fieldset_Name__c: '';
            config.defaultCountryCode = (setting.Default_Country_Code__c != null) ? setting.Default_Country_Code__c : '' ;
            config.defaultWhereClause = (setting.Default_Where_Clause__c != null) ? setting.Default_Where_Clause__c : '' ;
            config.countryCodes = new List<SelectOptionWrapper>();

                if(String.isNotBlank(setting.Country_Code__c)){

                    for(String code : setting.Country_Code__c.split(',')){

                        SelectOptionWrapper option = new SelectOptionWrapper();

                        option.label = code.trim();
                        option.value = code.trim();

                        config.countryCodes.add(option);
                    }
                }
            return config;

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }


    ///2 Get the custom metadat setup for the filters
     /*
    ============================================
    GET DYNAMIC FILTERS
    ============================================
    */
    @AuraEnabled(cacheable=true)
    public static List<DynamicFilterWrapper> getDynamicFilters(String brand){
        try {

            List<DynamicFilterWrapper> filterList = new List<DynamicFilterWrapper>();

            for(Client_Search_Filter__mdt filter : [ SELECT MasterLabel,
                                                            Field_API_Name__c,
                                                            Help_Text__c,
                                                            Object_API_Name__c,
                                                            Placeholder__c,
                                                            Required__c,
                                                            Sequence__c,
                                                            UI_Type__c,
                                                            Lookup_Display_Fields__c,
                                                            Lookup_Where_Clause__c,
                                                            Max_Lookup_Record_Selection__c,
                                                            Related_Object_API_Name__c
                                                        FROM Client_Search_Filter__mdt
                                                        WHERE Active__c = true
                                                        ORDER BY Sequence__c]){

                DynamicFilterWrapper wrapper =  new DynamicFilterWrapper();
                
                wrapper.label = filter.MasterLabel;
                wrapper.fieldApiName = filter.Field_API_Name__c;
                wrapper.objectApiName = filter.Object_API_Name__c;
                wrapper.uiType = filter.UI_Type__c;
                wrapper.required = filter.Required__c;
                wrapper.placeholder = filter.Placeholder__c;
                wrapper.helpText = filter.Help_Text__c;
                wrapper.lookupClause = filter.Lookup_Where_Clause__c;
                wrapper.lookupDisplayName = filter.Lookup_Display_Fields__c;
                wrapper.maxSelection = Integer.valueOf(filter.Max_Lookup_Record_Selection__c);
                wrapper.sequence = filter.Sequence__c != null ? Integer.valueOf(filter.Sequence__c) : 0;
                wrapper.isVisible = true;
                /*
                ============================================
                FIELD LEVEL SECURITY AND RELATION FILTERS
                ============================================
                */

                String describeObject = String.isNotBlank(filter.Related_Object_API_Name__c)
                                                            ? filter.Related_Object_API_Name__c
                                                            : filter.Object_API_Name__c;

                /*
                For relationship fields like:
                Account.Type__c
                Use:
                Type__c
                for Describe/FLS/Picklist lookups
                */
                String describeFieldName = filter.Field_API_Name__c;

                if(String.isNotBlank(filter.Related_Object_API_Name__c)){

                    Integer dotIndex =  describeFieldName.lastIndexOf('.');

                    if(dotIndex > -1){

                        describeFieldName =describeFieldName.substring(dotIndex + 1);
                    }
                }

                Schema.SObjectType sObjectType =Schema.getGlobalDescribe().get(describeObject);

                if(sObjectType == null){
                    continue;
                }

                Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();

                if(!fieldMap.containsKey(describeFieldName)){
                    continue;
                }

                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(describeFieldName).getDescribe();

                if( !fieldDescribe.isAccessible()){
                    continue;
                }
                /*
                ============================================
                LOAD PICKLIST VALUES
                ============================================
                */

                if(filter.UI_Type__c == 'Picklist' || filter.UI_Type__c == 'MultiPicklist'){
                    wrapper.options = getPicklistOptions( describeObject, describeFieldName);
                }

                filterList.add(wrapper);
            }

            return filterList;

        } catch (Exception e) {

            throw new AuraHandledException( e.getMessage()  );
        }
    }

    /*
    ============================================
    GET PICKLIST VALUES DYNAMICALLY
    ============================================
    */
    private static List<SelectOptionWrapper> getPicklistOptions(  String objectApiName,  String fieldApiName ){

        List<SelectOptionWrapper> options = new List<SelectOptionWrapper>();

        try {
            /*
            ============================================
            OBJECT VALIDATION
            ============================================
            */

            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);

            if(sObjectType == null){
                return options;
            }

            /*
            ============================================
            FIELD VALIDATION
            ============================================
            */

            Schema.DescribeSObjectResult objDescribe = sObjectType.getDescribe();

            Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();

            if(!fieldMap.containsKey(fieldApiName)){
                return options;
            }
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();
            /*
            ============================================
            ADD NONE OPTION
            ONLY FOR NORMAL PICKLIST
            ============================================
            */

                if(fieldDescribe.getType() == Schema.DisplayType.Picklist){
                    SelectOptionWrapper noneOption = new SelectOptionWrapper();
                    noneOption.label = '--None--';
                    noneOption.value = '';

                    options.add(noneOption);
                }


            /*
            ============================================
            PICKLIST VALUES
            ============================================
            */

            for(
                Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()
            ){
                // Skip inactive values
                if(!entry.isActive()){
                    continue;
                }

                SelectOptionWrapper option =  new SelectOptionWrapper();

                option.label = entry.getLabel();
                option.value = entry.getValue();

                options.add(option);
            }

        } catch (Exception e) {

            System.debug( 'Picklist Error: ' + e.getMessage() );
        }

        return options;
    }

    ///3 Method for Custom Lookup Component
    @AuraEnabled(cacheable=true)
    public static List<SelectOptionWrapper> searchLookupRecords(String objectApiName, String fieldApiName ,String searchTerm, String whereClause ){

        List<SelectOptionWrapper> results = new List<SelectOptionWrapper>();

        if(String.isBlank(searchTerm)){
            return results;
        }
        String objectName = getLookupObjectName(objectApiName, fieldApiName);

        String query =
            'SELECT Id, Name ' +
            'FROM ' + objectName +
            ' WHERE Name LIKE \'%' +
            String.escapeSingleQuotes(searchTerm) +
            '%\' ';

        // Optional where clause
        if(String.isNotBlank(whereClause)){

            query +=
                ' AND ' + whereClause;
        }
        query += ' LIMIT 50';
        System.debug('Query: ' + query);
        for(SObject record : Database.query(query)){

            SelectOptionWrapper option = new SelectOptionWrapper();
            option.label = (String)record.get('Name');
            option.value = (String)record.get('Id');
            results.add(option);
        }

        return results;
    }

    // Helper method to get the Object API Name
    private static String getLookupObjectName(String objectApiName, String fieldApiName){

    try {
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);

        if(sObjectType == null){
            return null;
        }
        Schema.DescribeSObjectResult objDescribe =  sObjectType.getDescribe();

        Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();

        if(!fieldMap.containsKey(fieldApiName)){
            return null;
        }

        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName).getDescribe();

        // Ensure field is lookup/reference
        if(
            fieldDescribe.getType() != Schema.DisplayType.Reference
        ){
            return null;
        }

        // Get referenced objects
        List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();

        if(references.isEmpty()){
            return null;
        }
        return references[0] .getDescribe().getName();

    } catch (Exception e) {

        System.debug( 'Lookup Object Error: ' + e.getMessage() );

        return null;
    }
}

    ///4 Method to get the display fields and Lat/long of the given Postal Code
    @AuraEnabled
    public static SearchResponseWrapper searchPostCode(String fieldset, String country, String postCode){
        try {
            SearchResponseWrapper response = new SearchResponseWrapper();

        List<DataTableColumnWrapper> fieldList = getFields(fieldset);
        DataTableColumnWrapper distanceColumn = new DataTableColumnWrapper();
            distanceColumn.fieldName = 'Distance';
            distanceColumn.label = 'Distance (Miles)';
            distanceColumn.type = 'number';
            fieldList.add(distanceColumn);

        List<Geo_Location__c> geoLocation = [SELECT id, Country__c, Geo_Location__Latitude__s , Geo_Location__Longitude__s , Postcode__c 
                                                FROM Geo_Location__c
                                                WHERE Country__c =: country
                                                AND  Postcode__c =: postCode
                                                LIMIT 1];
            if(!geoLocation.isEmpty()){
                response.success = true;
                response.fields = fieldList;
                response.latitude =  geoLocation[0].Geo_Location__Latitude__s;
                response.longitude = geoLocation[0].Geo_Location__Longitude__s;
                System.debug('@@@Got Geolocation record'+ geoLocation);
                return response;
            }
        
        // map to store the Lat/long of the given country and postcode
        GeoCodeWrapper geoResponse  = getLatLongFromPostCode(country, postCode);
        // Validation failed
        if(!geoResponse.isValid){
            response.success = false;
            response.message = geoResponse.message;

            return response;
        }

        response.success = true;
        response.fields = fieldList;
        response.latitude =  geoResponse.latitude;
        response.longitude = geoResponse.longitude;

        return response;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }


    // helper method to return List<String> fields names from FieldSet
        private static List<DataTableColumnWrapper> getFields(String fieldset){

        List<DataTableColumnWrapper> fields = new List<DataTableColumnWrapper>();

        Schema.FieldSet fieldSetObj = Schema.SObjectType.Contact.FieldSets.getMap().get(fieldset);

        if(fieldSetObj == null){
            return fields;
        }

       Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Contact.fields.getMap();

        for( Schema.FieldSetMember member : fieldSetObj.getFields() ){
            String fieldName = member.getFieldPath();

            if( !fieldMap.containsKey(fieldName) ){
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName) .getDescribe();
            // Skip fields user cannot read
            if( !fieldDescribe.isAccessible() ){
                continue; 
            }

        DataTableColumnWrapper column = new DataTableColumnWrapper();

        column.fieldName = fieldName;

        column.label = member.getLabel();

        column.type = String.valueOf(  member.getType()).toLowerCase();
        fields.add(column);
    }

        // Ensure Name exists
        Boolean hasName = false;

        for(DataTableColumnWrapper col : fields){

            if(col.fieldName == 'Name'){

                hasName = true;
                break;
            }
        }

        if(!hasName){

            DataTableColumnWrapper nameCol = new DataTableColumnWrapper();

            nameCol.fieldName = 'Name';
            nameCol.label = 'Contact Name';
            nameCol.type = 'text';

            fields.add(0, nameCol);
        }

        return fields;
    }

    // Helper method to get the lat/long from given country and postcode
    // Helper method to get lat/long from postcode
    private static GeoCodeWrapper getLatLongFromPostCode( String country, String postCode){

        GeoCodeWrapper response = new GeoCodeWrapper();

        Google_API_Setting__c setting = [ SELECT Api_Key__c, Base_Url__c
                                            FROM Google_API_Setting__c
                                            LIMIT 1 ];

        Http http = new Http();
        HttpRequest req = new HttpRequest();
        String address = EncodingUtil.urlEncode( postCode + ',' + country, 'UTF-8' );
        String endpoint = setting.Base_Url__c + '/geocode/xml?address=' + address + '&key=' + setting.Api_Key__c;

        req.setEndpoint(endpoint);

        req.setMethod('GET');
        req.setTimeout(120000); 

        HttpResponse res = http.send(req);

        if(res.getStatusCode() != 200){
            response.isValid = false;
            response.message ='Error while validating postcode';
            return response;
        }

        Dom.Document doc = new Dom.Document();

        doc.load(res.getBody());

        Dom.XmlNode root = doc.getRootElement();
        // STATUS VALIDATION
        String status = root.getChildElement( 'status',  null ).getText();

        if(status != 'OK'){
            response.isValid = false;
            response.message = 'Invalid postcode';
            return response;
        }

        Dom.XmlNode resultNode = root.getChildElement('result',  null);

        // PARTIAL MATCH CHECK
        Dom.XmlNode partialMatch = resultNode.getChildElement('partial_match', null);
        if(partialMatch != null){
            response.isValid = false;
            response.message = 'Postcode does not match country';
            return response;
        }

        // TYPE VALIDATION
        Boolean hasPostalCode = false;

        for(Dom.XmlNode typeNode :
            resultNode.getChildren()){

            if(
                typeNode.getName() == 'type' &&
                typeNode.getText() == 'postal_code'
            ){

                hasPostalCode = true;
                break;
            }
        }

        if(!hasPostalCode){
            response.isValid = false;
            response.message ='Invalid postcode';
            return response;
        }

        // COUNTRY VALIDATION
        Boolean countryMatched = false;

        for(
            Dom.XmlNode component : resultNode.getChildElements()){
            if(component.getName() != 'address_component'){
                continue;
            }

            String shortName = '';
            Boolean isCountry = false;

            for(Dom.XmlNode child : component.getChildElements()){

                if( child.getName() == 'short_name' ){
                    shortName = child.getText();
                }

                if( child.getName() == 'type' && child.getText() == 'country' ){
                    isCountry = true;
                }
            }
            String inputCountry = normalizeCountryCode(country);

            String responseCountry = normalizeCountryCode(shortName);

            if( isCountry && inputCountry == responseCountry
            ){
                countryMatched = true;
                break;
            }
        }
        if(!countryMatched){
            response.isValid = false;
            response.message = 'Postcode does not belong to selected country';
            return response;
        }

        // LAT LONG
        Dom.XmlNode geometry = resultNode.getChildElement( 'geometry', null );
        Dom.XmlNode location = geometry.getChildElement( 'location', null );

        response.latitude = Decimal.valueOf( location.getChildElement( 'lat', null ).getText());
        response.longitude = Decimal.valueOf( location.getChildElement( 'lng', null).getText());
        response.isValid = true;

        // Insert geo location record: Country__c, Geo_Location__Latitude__s , Geo_Location__Longitude__s , Postcode__c
        List<Geo_Location__c> locations = new List<Geo_Location__c>{ new Geo_Location__c(
                                                                                            Country__c = country,
                                                                                            Postcode__c = postCode,
                                                                                            Geo_Location__Latitude__s = response.latitude,
                                                                                            Geo_Location__Longitude__s = response.longitude)
                                                                                    };

        System.debug('@@@Insert Geolocation record ' + locations );

        insert locations;
        return response;
    }
    private static String normalizeCountryCode(String country){

        Map<String, String> countryMap = new Map<String, String>{
                'UK' => 'GB',
                'GB' => 'GB',
                'US' => 'US',
                'USA' => 'US',
                'IN' => 'IN',
                'INDIA' => 'IN'
            };

        String normalized =  countryMap.get( country.toUpperCase() );
        return normalized != null ? normalized : country.toUpperCase();
    }

    /// 5 Method to get the client contacts within the desired radius by additional filters
    @AuraEnabled
    public static List<Map<String, Object>> getSearchedContact(
                                                            List<String> displayFields,
                                                            Map<String, Object> additionalFilters,
                                                            String whereClause,
                                                            Integer radius,
                                                            Decimal lat,
                                                            Decimal lon){

    try {

        List<Map<String, Object>> results = new List<Map<String, Object>>();
       /*
        ============================================
        ENSURE NAME EXISTS
        ============================================
        */

        if( displayFields != null && !displayFields.contains('Name') ){
            displayFields.add(0, 'Name');
        }

        /*
        ============================================
        BUILD SELECT FIELDS
        ============================================
        */

        List<String> fieldApiNames = new List<String>();

        if(displayFields != null){
            for(String field : displayFields){
                if( String.isNotBlank(field) &&  field != 'Distance' ){
                    fieldApiNames.add(field);
                }
            }
        }

        String selectFields = String.join(fieldApiNames,',');

        System.debug('@@selectFields: ' +selectFields);
        /*
        ============================================
        DISTANCE FIELD
        ============================================
        */

        String distanceField =
            'DISTANCE(' +
            'sirenum__Home_Coordinates__c,' +
            'GEOLOCATION(' + lat + ',' + lon + '),' +
            '\'mi\'' +
            ') distanceValue';

        /*
        ============================================
        BASE QUERY
        ============================================
        */

        String query =

            'SELECT Id,' +
            selectFields + ',' +
            distanceField +

            ' FROM Contact ' +

            ' WHERE ' +
            ' DISTANCE(' +
            'sirenum__Home_Coordinates__c ,' +
            'GEOLOCATION(' + lat + ',' + lon + '),' +
            '\'mi\'' +
            ') < ' + radius;

        /*
        ============================================
        DEFAULT WHERE CLAUSE
        ============================================
        */

        if(String.isNotBlank(whereClause)){
            query +=
                ' AND (' + whereClause + ')';
        }

        /*
        ============================================
        ADDITIONAL FILTERS
        ============================================
        */

        if( additionalFilters != null && !additionalFilters.isEmpty() ){

            for(String fieldName : additionalFilters.keySet()){
                Object value = additionalFilters.get(fieldName);
                // Skip empty
                if(value == null){
                    continue;
                }

                /*
                ====================================
                MULTI VALUE FILTER
                ====================================
                */

                if(value instanceof List<Object>){

                    List<Object> values = (List<Object>)value;

                    if(values.isEmpty()){
                        continue;
                    }

                    List<String> formattedValues = new List<String>();

                    for(Object val : values){

                        formattedValues.add(
                            '\'' +
                            String.escapeSingleQuotes(
                                String.valueOf(val)
                            ) +
                            '\''
                        );
                    }

                    query +=
                        ' AND ' + fieldName +
                        ' IN (' +
                        String.join(
                            formattedValues,
                            ','
                        ) +
                        ')';

                } else {

                    /*
                    ====================================
                    SINGLE VALUE FILTER
                    ====================================
                    */

                    // Get field describe
                    Schema.DescribeFieldResult fieldDescribe = Schema.SObjectType.Contact.fields.getMap().get(fieldName).getDescribe();

                    Schema.DisplayType fieldType = fieldDescribe.getType();

                    // TEXT FIELDS
                    if( fieldType == Schema.DisplayType.String ||
                        fieldType == Schema.DisplayType.TextArea ||
                        fieldType == Schema.DisplayType.Phone ||
                        fieldType == Schema.DisplayType.Email ||
                        fieldType == Schema.DisplayType.Url ){

                        query +=
                            ' AND ' + fieldName +
                            ' LIKE \'%' +
                            String.escapeSingleQuotes(
                                String.valueOf(value)
                            ) +
                            '%\'';

                    } else {

                        query +=
                            ' AND ' + fieldName +
                            ' = \'' +
                            String.escapeSingleQuotes(
                                String.valueOf(value)
                            ) +
                            '\'';
                    }
                                    }
                                }
                            }

        /*
        ============================================
        ORDER BY DISTANCE
        ============================================
        */
        query +=
            ' WITH USER_MODE';

        query +=
            ' ORDER BY DISTANCE(' +
            'sirenum__Home_Coordinates__c,' +
            'GEOLOCATION(' + lat + ',' + lon + '),' +
            '\'mi\'' +
            ') ASC';

        query +=
            ' LIMIT 10000';

        System.debug('@@Query: ' + query);

        /*
        ============================================
        EXECUTE QUERY
        ============================================
        */

        List<SObject> contacts = Database.query(query);
        /*
        ============================================
        PREPARE RESPONSE
        ============================================
        */                   
       for(SObject contact : contacts){
            Map<String, Object> row = new Map<String, Object>();

            // Dynamic fields
            for(String field : displayFields){
                if( String.isNotBlank(field) && field != 'Distance' ){
                    row.put(
                        field,
                        contact.get(field)
                    );
                }
            }

            // Distance column
        row.put(
                    'Distance',
                    ((Decimal)contact.get('distanceValue'))
                        .setScale(1)
                );

            row.put(
                'Id',
                (String)contact.get('Id' )
            );

            results.add(row);
        }

        return results;

    } catch (Exception e) {

        throw new AuraHandledException(
            e.getMessage()
        );
    }
}

    /// Method 6 Creating call List member
    @AuraEnabled
    public static void createCallListMembers(Id callListId, List<Id> contactIds){
        if( callListId == null ||contactIds == null || contactIds.isEmpty()){
            return;
        }

        List<TR1__Call_List_Member__c> members = new List<TR1__Call_List_Member__c>();
        for(Id contactId : contactIds){
            members.add( new TR1__Call_List_Member__c(
                                                        TR1__Call_List__c = callListId,
                                                        TR1__Contact__c = contactId
                                                    ) );
        }

        insert members;
    }


   public class DynamicFilterWrapper {
        @AuraEnabled
        public String label;

        @AuraEnabled
        public String fieldApiName;

        @AuraEnabled
        public String objectApiName;

        @AuraEnabled
        public String uiType;

        @AuraEnabled
        public Boolean required;

        @AuraEnabled
        public Boolean isVisible;

        @AuraEnabled
        public String placeholder;

        @AuraEnabled
        public Integer sequence;

        @AuraEnabled
        public String helpText;

         @AuraEnabled
        public String lookupClause;

         @AuraEnabled
        public String lookupDisplayName;

        @AuraEnabled
        public Integer maxSelection;

         @AuraEnabled
        public List<SelectOptionWrapper> options;
    }

    /// Wrapper for config:
    public class ClientSearchConfigWrapper {

        @AuraEnabled
        public Integer defaultRadius;

        @AuraEnabled
        public List<SelectOptionWrapper> countryCodes;

        @AuraEnabled
        public String defaultCountryCode;

        @AuraEnabled
        public String fieldSetName;

        @AuraEnabled
        public String defaultWhereClause;

    }
    /// wrapper for picklist options
    public class SelectOptionWrapper {

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String value;
    }

    /// Google geo code wrapper
    public class GeoCodeWrapper {

        @AuraEnabled
        public Decimal latitude;

        @AuraEnabled
        public Decimal longitude;

        @AuraEnabled
        public Boolean isValid;

        @AuraEnabled
        public String message;
    }
    public class SearchResponseWrapper {

        @AuraEnabled
        public Boolean success;

        @AuraEnabled
        public String message;

        @AuraEnabled
        public List<DataTableColumnWrapper> fields;

        @AuraEnabled
        public Decimal latitude;

        @AuraEnabled
        public Decimal longitude;
    }

    public class DataTableColumnWrapper {

        @AuraEnabled
        public String fieldName;

        @AuraEnabled
        public String label;

        @AuraEnabled
        public String type;
    }
}