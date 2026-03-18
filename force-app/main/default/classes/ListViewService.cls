public with sharing class ListViewService {
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getListViewRecords(String objectApiName, String listViewDevName) {
        try {
            // 1. Get List View ID
            ListView lv = [SELECT Id, Name FROM ListView 
                          WHERE SobjectType = :objectApiName 
                          AND DeveloperName = :listViewDevName LIMIT 1];
            
            String lvId = lv.Id;
            
            // 2. Call REST API to get the Query
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();
            String endpoint = baseUrl + '/services/data/v60.0/sobjects/' + objectApiName + '/listviews/' + lvId + '/describe';
            
            String sessionId = '';
            if (!Test.isRunningTest()) {
                String content = Page.SessionIdGenerator.getContent().toString();
                // Extract session ID from the HTML body if it exists
                Integer start = content.indexOf('00D'); // Common start for Org ID based session tokens
                if (start != -1) {
                    sessionId = content.substring(start).split('<')[0].split(' ')[0].split('\n')[0].trim();
                } else {
                    sessionId = content.trim(); // Fallback
                }
            } else {
                sessionId = 'TEST_SESSION_ID';
            }

            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + sessionId);
            
            Http http = new Http();
            HttpResponse res = http.send(req);
            
            if (res.getStatusCode() == 200) {
                Map<String, Object> describe = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String query = (String) describe.get('query');
                
                // Inject critical fields for the Map UI if they aren't in the list view columns
                List<String> fieldsToInject = new List<String>{
                    'fleetforce__Last_Location__Latitude__s', 
                    'fleetforce__Last_Location__Longitude__s',
                    'fleetforce__Status__c',
                    'fleetforce__License_Plate__c',
                    'fleetforce__Fuel_Energy_Level__c',
                    'fleetforce__Odometer__c'
                };
                
                String injection = 'SELECT ';
                for(String f : fieldsToInject) {
                    if(!query.toLowerCase().contains(f.toLowerCase())) {
                        injection += f + ', ';
                    }
                }
                
                if(injection != 'SELECT ') {
                    query = query.replaceFirst('(?i)SELECT', injection);
                }
                
                // 3. Execute Query
                List<SObject> records = Database.query(query);
                
                // 4. Transform to List of Maps for JS
                List<Map<String, Object>> result = new List<Map<String, Object>>();
                for (SObject sobj : records) {
                    Map<String, Object> recordMap = new Map<String, Object>();
                    // Flatten all fields to their clean API names (ignoring namespace)
                    Map<String, Object> populated = sobj.getPopulatedFieldsAsMap();
                    for (String key : populated.keySet()) {
                        String cleanKey = key;
                        // Handle Namespace__Field__c or Namespace__Field__s
                        if (key.countMatches('__') == 2) {
                            cleanKey = key.substringAfter('__');
                        }
                        recordMap.put(cleanKey, populated.get(key));
                        // Also keep the original key just in case
                        recordMap.put(key, populated.get(key));
                    }
                    // Core standard fields
                    recordMap.put('Id', sobj.get('Id'));
                    recordMap.put('Name', sobj.get('Name'));
                    
                    result.add(recordMap);
                }
                return result;
            } else {
                throw new AuraHandledException('REST API Error: ' + res.getBody());
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // Helper to get List View Label
    @AuraEnabled(cacheable=true)
    public static String getListViewLabel(String objectApiName, String listViewDevName) {
        ListView lv = [SELECT Name FROM ListView 
                      WHERE SobjectType = :objectApiName 
                      AND DeveloperName = :listViewDevName LIMIT 1];
        return lv.Name;
    }
}