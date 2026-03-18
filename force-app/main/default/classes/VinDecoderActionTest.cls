@IsTest
public class VinDecoderActionTest {
    
    private class MockVinResponse implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"Results": [{"Make": "TOYOTA", "Model": "CAMRY", "ModelYear": "2023", "BodyClass": "Sedan", "DriveType": "FWD", "FuelTypePrimary": "Gasoline", "ErrorCode": "0"}]}');
            res.setStatusCode(200);
            return res;
        }
    }

    @IsTest
    static void testVinDecoding() {
        Test.setMock(HttpCalloutMock.class, new MockVinResponse());
        
        VinDecoderAction.VinRequest req = new VinDecoderAction.VinRequest();
        req.vin = 'TESTVIN1234567890';
        
        Test.startTest();
        List<VinDecoderAction.VinResult> results = VinDecoderAction.decodeVin(new List<VinDecoderAction.VinRequest>{req});
        Test.stopTest();
        
        System.assertEquals(1, results.size());
        System.assertEquals('TOYOTA', results[0].make);
        System.assertEquals('CAMRY', results[0].model);
    }
}