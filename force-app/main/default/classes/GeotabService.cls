/**
 * GeotabService
 * Core service for communicating with the Geotab JSON-RPC 2.0 API.
 * Handles authentication and fetching device telemetry data.
 */
public with sharing class GeotabService {

    private String server;
    private String database;
    private String username;
    private String sessionId;

    /**
     * Authenticates with Geotab and stores the session credentials.
     * Geotab uses a multi-step auth: first call may return a redirect server.
     */
    public void authenticate() {
        Geotab_Setting__mdt cfg = [
            SELECT Server__c, Database__c, Username__c, Password__c
            FROM Geotab_Setting__mdt LIMIT 1
        ];

        this.server = cfg.Server__c;
        this.database = cfg.Database__c;
        this.username = cfg.Username__c;

        // Step 1: Authenticate
        Map<String, Object> authPayload = new Map<String, Object>{
            'jsonrpc' => '2.0',
            'method' => 'Authenticate',
            'params' => new Map<String, Object>{
                'database' => this.database,
                'userName' => this.username,
                'password' => cfg.Password__c
            },
            'id' => 1
        };

        HttpResponse authRes = callGeotab(this.server, authPayload);
        Map<String, Object> authResult = parseResult(authRes);

        // Geotab may redirect us to a specific server
        if (authResult.containsKey('path')) {
            String newPath = (String) authResult.get('path');
            if (String.isNotBlank(newPath) && newPath != 'ThisServer') {
                this.server = newPath;
                // Re-authenticate on the new server
                authRes = callGeotab(this.server, authPayload);
                authResult = parseResult(authRes);
            }
        }

        // Extract session credentials
        Map<String, Object> credentials = (Map<String, Object>) authResult.get('credentials');
        if (credentials == null) {
            throw new AuraHandledException('Geotab authentication failed: no credentials returned.');
        }
        this.sessionId = (String) credentials.get('sessionId');
        this.database = (String) credentials.get('database');
    }

    /**
     * Fetches the latest device status (GPS location) for a list of Geotab Device IDs.
     * @param geotabDeviceIds  List of Geotab device ID strings to fetch
     * @return List of DeviceStatusInfo maps containing device data
     */
    public List<Map<String, Object>> fetchDeviceStatusInfo(List<String> geotabDeviceIds) {
        if (this.sessionId == null) {
            throw new AuraHandledException('Not authenticated. Call authenticate() first.');
        }

        // Build device search list
        List<Object> searchList = new List<Object>();
        for (String deviceId : geotabDeviceIds) {
            searchList.add(new Map<String, Object>{ 'id' => deviceId });
        }

        // Use GetFeed or Get for DeviceStatusInfo (most recent GPS per device)
        Map<String, Object> payload = new Map<String, Object>{
            'jsonrpc' => '2.0',
            'method' => 'Get',
            'params' => new Map<String, Object>{
                'typeName' => 'DeviceStatusInfo',
                'credentials' => getCredentials(),
                'search' => new Map<String, Object>{
                    'deviceSearch' => searchList
                }
            },
            'id' => 2
        };

        HttpResponse res = callGeotab(this.server, payload);
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (result.containsKey('error')) {
            throw new AuraHandledException('Geotab Get Error: ' + JSON.serialize(result.get('error')));
        }
        return (List<Map<String, Object>>) JSON.deserializeUntyped(
            JSON.serialize(result.get('result'))
        );
    }

    /**
     * Fetches diagnostic data (odometer, fuel level) for given device IDs.
     * @param geotabDeviceIds  List of Geotab device IDs
     * @param diagnosticId     The Geotab diagnostic ID (e.g. 'DiagnosticOdometerId', 'DiagnosticFuelLevelPercentageId')
     */
    public List<Map<String, Object>> fetchStatusData(List<String> geotabDeviceIds, String diagnosticId) {
        if (this.sessionId == null) {
            throw new AuraHandledException('Not authenticated. Call authenticate() first.');
        }

        List<Object> deviceSearchList = new List<Object>();
        for (String deviceId : geotabDeviceIds) {
            deviceSearchList.add(new Map<String, Object>{ 'id' => deviceId });
        }

        Map<String, Object> payload = new Map<String, Object>{
            'jsonrpc' => '2.0',
            'method' => 'Get',
            'params' => new Map<String, Object>{
                'typeName' => 'StatusData',
                'credentials' => getCredentials(),
                'search' => new Map<String, Object>{
                    'deviceSearch' => deviceSearchList,
                    'diagnosticSearch' => new Map<String, Object>{ 'id' => diagnosticId },
                    'fromDate' => DateTime.now().addHours(-1).format('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
                },
                'resultsLimit' => 1000
            },
            'id' => 3
        };

        HttpResponse res = callGeotab(this.server, payload);
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (result.containsKey('error')) {
            throw new AuraHandledException('Geotab Get Error: ' + JSON.serialize(result.get('error')));
        }
        return (List<Map<String, Object>>) JSON.deserializeUntyped(
            JSON.serialize(result.get('result'))
        );
    }

    // --------------------------------------------------------------------------
    // Private Helpers
    // --------------------------------------------------------------------------

    private Map<String, Object> getCredentials() {
        return new Map<String, Object>{
            'sessionId' => this.sessionId,
            'database'  => this.database,
            'userName'  => this.username
        };
    }

    private HttpResponse callGeotab(String server, Map<String, Object> payload) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://' + server + '/apiv1');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(payload));
        req.setTimeout(30000);
        Http http = new Http();
        HttpResponse res = http.send(req);
        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('Geotab HTTP Error: ' + res.getStatusCode() + ' ' + res.getBody());
        }
        return res;
    }

    private Map<String, Object> parseResult(HttpResponse res) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        if (body.containsKey('error')) {
            Map<String, Object> err = (Map<String, Object>) body.get('error');
            throw new AuraHandledException('Geotab API Error: ' + JSON.serialize(err));
        }
        return (Map<String, Object>) body.get('result');
    }
}
