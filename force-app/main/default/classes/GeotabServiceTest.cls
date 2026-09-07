@IsTest
private class GeotabServiceTest {

    // -------------------------------------------------------------------------
    // Stateful mock: call sequence drives which response is returned.
    // -------------------------------------------------------------------------
    private class GeotabMock implements HttpCalloutMock {
        List<String> responseBodies;
        List<Integer> statusCodes;
        Integer callCount = 0;

        GeotabMock(List<String> bodies, List<Integer> codes) {
            this.responseBodies = bodies;
            this.statusCodes    = codes;
        }

        public HttpResponse respond(HttpRequest req) {
            Integer i = Math.min(callCount, responseBodies.size() - 1);
            callCount++;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCodes[i]);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(responseBodies[i]);
            return res;
        }
    }

    private static final String AUTH_SUCCESS =
        '{"jsonrpc":"2.0","result":{"credentials":{"sessionId":"test-session-id-000",' +
        '"database":"test-fake-db-000","userName":"test-fake-user-000@example.com"},' +
        '"path":"ThisServer"},"id":1}';

    private static final String AUTH_REDIRECT =
        '{"jsonrpc":"2.0","result":{"path":"redirect-fake-000.geotab.com"},"id":1}';

    private static final String GPS_RESULT =
        '{"jsonrpc":"2.0","result":[{"device":{"id":"dev001"},"latitude":32.0853,"longitude":34.7818}],"id":2}';

    private static final String STATUS_DATA_ODOMETER =
        '{"jsonrpc":"2.0","result":[{"device":{"id":"dev001"},"data":1609344,"dateTime":"2024-01-01T12:00:00.000Z"}],"id":3}';

    private static final String API_ERROR =
        '{"jsonrpc":"2.0","error":{"code":-32000,"message":"InvalidUserException"},"id":2}';

    // Creates a GeotabService with fake credentials injected so authenticate()
    // skips the CMT query. CMT records cannot be created in tests.
    private static GeotabService makeService() {
        GeotabService svc = new GeotabService();
        svc.injectConfig(
            'test-fake-server-000.geotab.com',
            'test-fake-db-000',
            'test-fake-user-000@example.com',
            'test-fake-password-000'
        );
        return svc;
    }

    // -------------------------------------------------------------------------
    // authenticate() — no CMT record → clear AuraHandledException
    // -------------------------------------------------------------------------
    @IsTest
    static void testAuthenticate_noConfig_throws() {
        Integer cmtCount = [SELECT COUNT() FROM Geotab_Setting__mdt];
        if (cmtCount > 0) { return; } // skip in orgs where a CMT record is already deployed

        GeotabService svc = new GeotabService();
        Test.startTest();
        Boolean threw = false;
        try {
            svc.authenticate();
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'authenticate() should throw AuraHandledException when no CMT record exists');
    }

    // -------------------------------------------------------------------------
    // authenticate() — happy path, no redirect
    // -------------------------------------------------------------------------
    @IsTest
    static void testAuthenticate_success_noRedirect() {
        Test.setMock(HttpCalloutMock.class, new GeotabMock(
            new List<String>{ AUTH_SUCCESS },
            new List<Integer>{ 200 }
        ));

        GeotabService svc = makeService();
        Test.startTest();
        svc.authenticate();
        Test.stopTest();
    }

    // -------------------------------------------------------------------------
    // authenticate() — redirect path
    // -------------------------------------------------------------------------
    @IsTest
    static void testAuthenticate_redirect_thenSuccess() {
        Test.setMock(HttpCalloutMock.class, new GeotabMock(
            new List<String>{ AUTH_REDIRECT, AUTH_SUCCESS },
            new List<Integer>{ 200, 200 }
        ));

        GeotabService svc = makeService();
        Test.startTest();
        svc.authenticate();
        Test.stopTest();
    }

    // -------------------------------------------------------------------------
    // authenticate() — response has no credentials → AuraHandledException
    // -------------------------------------------------------------------------
    @IsTest
    static void testAuthenticate_noCredentials_throws() {
        String noCredBody = '{"jsonrpc":"2.0","result":{"path":"ThisServer"},"id":1}';
        Test.setMock(HttpCalloutMock.class, new GeotabMock(
            new List<String>{ noCredBody },
            new List<Integer>{ 200 }
        ));

        GeotabService svc = makeService();
        Test.startTest();
        Boolean threw = false;
        try {
            svc.authenticate();
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'authenticate() should throw when no credentials in response');
    }

    // -------------------------------------------------------------------------
    // authenticate() — HTTP non-200 → AuraHandledException
    // -------------------------------------------------------------------------
    @IsTest
    static void testAuthenticate_httpError_throws() {
        Test.setMock(HttpCalloutMock.class, new GeotabMock(
            new List<String>{ '{"error":"service unavailable"}' },
            new List<Integer>{ 503 }
        ));

        GeotabService svc = makeService();
        Test.startTest();
        Boolean threw = false;
        try {
            svc.authenticate();
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'authenticate() should throw on non-200 HTTP status');
    }

    // -------------------------------------------------------------------------
    // authenticate() — error body → AuraHandledException from parseResult
    // -------------------------------------------------------------------------
    @IsTest
    static void testAuthenticate_apiErrorInBody_throws() {
        String authErrorBody = '{"jsonrpc":"2.0","error":{"code":-32000,"message":"InvalidCredentials"},"id":1}';
        Test.setMock(HttpCalloutMock.class, new GeotabMock(
            new List<String>{ authErrorBody },
            new List<Integer>{ 200 }
        ));

        GeotabService svc = makeService();
        Test.startTest();
        Boolean threw = false;
        try {
            svc.authenticate();
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'authenticate() should throw when response body contains an error field');
    }

    // -------------------------------------------------------------------------
    // fetchDeviceStatusInfo() — not authenticated → immediate throw
    // -------------------------------------------------------------------------
    @IsTest
    static void testFetchDeviceStatusInfo_unauthenticated_throws() {
        GeotabService svc = new GeotabService();
        Test.startTest();
        Boolean threw = false;
        try {
            svc.fetchDeviceStatusInfo(new List<String>{ 'dev001' });
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'fetchDeviceStatusInfo without authenticate() should throw');
    }

    // -------------------------------------------------------------------------
    // fetchDeviceStatusInfo() — success after authenticate()
    // -------------------------------------------------------------------------
    @IsTest
    static void testFetchDeviceStatusInfo_success() {
        Test.setMock(HttpCalloutMock.class, new GeotabMock(
            new List<String>{ AUTH_SUCCESS, GPS_RESULT },
            new List<Integer>{ 200, 200 }
        ));

        GeotabService svc = makeService();
        Test.startTest();
        svc.authenticate();
        List<Map<String, Object>> result = svc.fetchDeviceStatusInfo(new List<String>{ 'dev001' });
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return one DeviceStatusInfo entry');
        Map<String, Object> device = (Map<String, Object>) result[0].get('device');
        System.assertEquals('dev001', device.get('id'));
    }

    // -------------------------------------------------------------------------
    // fetchDeviceStatusInfo() — API error body → AuraHandledException
    // -------------------------------------------------------------------------
    @IsTest
    static void testFetchDeviceStatusInfo_apiError_throws() {
        Test.setMock(HttpCalloutMock.class, new GeotabMock(
            new List<String>{ AUTH_SUCCESS, API_ERROR },
            new List<Integer>{ 200, 200 }
        ));

        GeotabService svc = makeService();
        Test.startTest();
        svc.authenticate();
        Boolean threw = false;
        try {
            svc.fetchDeviceStatusInfo(new List<String>{ 'dev001' });
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'fetchDeviceStatusInfo should throw on API error response');
    }

    // -------------------------------------------------------------------------
    // fetchStatusData() — not authenticated → immediate throw
    // -------------------------------------------------------------------------
    @IsTest
    static void testFetchStatusData_unauthenticated_throws() {
        GeotabService svc = new GeotabService();
        Test.startTest();
        Boolean threw = false;
        try {
            svc.fetchStatusData(new List<String>{ 'dev001' }, 'DiagnosticOdometerId');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'fetchStatusData without authenticate() should throw');
    }

    // -------------------------------------------------------------------------
    // fetchStatusData() — success after authenticate()
    // -------------------------------------------------------------------------
    @IsTest
    static void testFetchStatusData_success() {
        Test.setMock(HttpCalloutMock.class, new GeotabMock(
            new List<String>{ AUTH_SUCCESS, STATUS_DATA_ODOMETER },
            new List<Integer>{ 200, 200 }
        ));

        GeotabService svc = makeService();
        Test.startTest();
        svc.authenticate();
        List<Map<String, Object>> result = svc.fetchStatusData(
            new List<String>{ 'dev001' },
            'DiagnosticOdometerId'
        );
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return one StatusData entry');
    }

    // -------------------------------------------------------------------------
    // fetchStatusData() — API error body → AuraHandledException
    // -------------------------------------------------------------------------
    @IsTest
    static void testFetchStatusData_apiError_throws() {
        Test.setMock(HttpCalloutMock.class, new GeotabMock(
            new List<String>{ AUTH_SUCCESS, API_ERROR },
            new List<Integer>{ 200, 200 }
        ));

        GeotabService svc = makeService();
        Test.startTest();
        svc.authenticate();
        Boolean threw = false;
        try {
            svc.fetchStatusData(new List<String>{ 'dev001' }, 'DiagnosticOdometerId');
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'fetchStatusData should throw on API error response');
    }
}
