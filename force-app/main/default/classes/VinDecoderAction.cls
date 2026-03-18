public with sharing class VinDecoderAction {
    
    public class VinRequest {
        @InvocableVariable(label='VIN' description='The 17-character VIN to decode' required=true)
        public String vin;
    }

    public class VinResult {
        @InvocableVariable(label='Make')
        public String make;
        @InvocableVariable(label='Model')
        public String model;
        @InvocableVariable(label='Year')
        public String year;
        @InvocableVariable(label='Body Class')
        public String bodyClass;
        @InvocableVariable(label='Drive Type')
        public String driveType;
        @InvocableVariable(label='Fuel Type')
        public String fuelType;
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(label='Decode VIN via NHTSA' description='Fetches vehicle specifications from NHTSA vPIC API' category='Fleetforce')
    public static List<VinResult> decodeVin(List<VinRequest> requests) {
        List<VinResult> results = new List<VinResult>();
        
        for (VinRequest req : requests) {
            results.add(fetchVinData(req.vin));
        }
        
        return results;
    }

    private static VinResult fetchVinData(String vin) {
        VinResult res = new VinResult();
        if (String.isBlank(vin)) {
            res.errorMessage = 'VIN is empty';
            return res;
        }

        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint('https://vpic.nhtsa.dot.gov/api/vehicles/decodevinvalues/' + vin + '?format=json');
        request.setMethod('GET');
        request.setTimeout(10000);

        try {
            HttpResponse response = http.send(request);
            if (response.getStatusCode() == 200) {
                Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                List<Object> resultsList = (List<Object>) root.get('Results');
                
                if (resultsList != null && !resultsList.isEmpty()) {
                    Map<String, Object> data = (Map<String, Object>) resultsList[0];
                    
                    res.make = (String) data.get('Make');
                    res.model = (String) data.get('Model');
                    res.year = (String) data.get('ModelYear');
                    res.bodyClass = (String) data.get('BodyClass');
                    res.driveType = (String) data.get('DriveType');
                    res.fuelType = (String) data.get('FuelTypePrimary');
                    
                    // Basic error check from API content
                    String errorCode = (String) data.get('ErrorCode');
                    if (errorCode != '0') {
                        res.errorMessage = (String) data.get('ErrorText');
                    }
                }
            } else {
                res.errorMessage = 'API returned status code ' + response.getStatusCode();
            }
        } catch (Exception e) {
            res.errorMessage = 'Exception: ' + e.getMessage();
        }
        
        return res;
    }
}