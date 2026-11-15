@IsTest
private class DriverRouteScanControllerTest {
  private class MultiCalloutMock implements HttpCalloutMock {
    public List<HttpRequest> requests = new List<HttpRequest>();
    public Boolean failClaude = false;
    public Boolean invalidClaudeJson = false;
    public Boolean missFirstGeocode = true;
    public Boolean missAllGeocode = false;
    public Boolean failGeocode = false;
    public Boolean returnUnassigned = false;

    public HttpResponse respond(HttpRequest req) {
      requests.add(req);
      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'application/json');
      String endpoint = req.getEndpoint();

      if (endpoint.contains('/v1/messages')) {
        if (failClaude) {
          res.setStatusCode(401);
          res.setBody('{"error":{"message":"Invalid key"}}');
          return res;
        }
        res.setStatusCode(200);
        String textJson = invalidClaudeJson
          ? 'not valid json'
          : '```json\n' +
            JSON.serialize(
              new Map<String, Object>{
                'docType' => 'Delivery Note',
                'docNumber' => 'SH26011985',
                'bolNumber' => '7998',
                'orderNumber' => 'SO26007097',
                'customerName' => 'חוליות גפני בע"מ',
                'customerCode' => '6000423207',
                'supplierName' => 'סלע אספקת מוצרי בטון ואנרגיה בע"מ',
                'origin' => 'אשקלון',
                'destinationAddress' => 'נצרת שכונת הגליל (אתר 1625800)',
                'destinationCity' => 'נצרת',
                'siteCode' => '1625800',
                'contactName' => 'מחבר',
                'contactPhone' => '054-9230336',
                'truckPlate' => '28598703',
                'serviceDate' => '2026-08-31',
                'cargoSummary' => 'גלית 30/30/6 אפור · 237.6 מ"ר',
                'weightKg' => 32076
              }
            ) +
            '\n```';
        res.setBody(
          JSON.serialize(
            new Map<String, Object>{
              'id' => 'msg_test',
              'type' => 'message',
              'content' => new List<Object>{
                new Map<String, Object>{
                  'type' => 'thinking',
                  'thinking' => 'reading hebrew bol'
                },
                new Map<String, Object>{ 'type' => 'text', 'text' => textJson }
              }
            }
          )
        );
        return res;
      }

      if (endpoint.contains('/geocode/search')) {
        if (failGeocode) {
          res.setStatusCode(500);
          res.setBody('{"error":"Geocoder down"}');
          return res;
        }
        res.setStatusCode(200);
        if (
          missAllGeocode ||
          (missFirstGeocode &&
          (endpoint.contains('1625800') ||
          endpoint.contains(EncodingUtil.urlEncode('שכונת הגליל', 'UTF-8'))))
        ) {
          res.setBody('{"features":[]}');
          return res;
        }
        res.setBody(
          JSON.serialize(
            new Map<String, Object>{
              'features' => new List<Object>{
                new Map<String, Object>{
                  'geometry' => new Map<String, Object>{
                    'coordinates' => new List<Object>{ 35.3027, 32.7021 }
                  },
                  'properties' => new Map<String, Object>{
                    'label' => 'Nazareth, Northern District, Israel'
                  }
                }
              }
            }
          )
        );
        return res;
      }

      if (endpoint.contains('/optimization')) {
        res.setStatusCode(200);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
          req.getBody()
        );
        List<Object> vehicles = (List<Object>) body.get('vehicles');
        Map<String, Object> veh = (Map<String, Object>) vehicles[0];
        Integer vid = (Integer) veh.get('id');
        List<Object> startLoc = (List<Object>) veh.get('start');
        List<Object> jobs = (List<Object>) body.get('jobs');

        List<Object> steps = new List<Object>();
        Long nowSec = System.now().getTime() / 1000;
        steps.add(
          new Map<String, Object>{
            'type' => 'start',
            'location' => startLoc,
            'arrival' => nowSec,
            'waiting_time' => 0,
            'service' => 0,
            'distance' => 0,
            'duration' => 0
          }
        );

        List<Object> unassigned = new List<Object>();
        Integer cumDist = 0;
        Integer cumDur = 0;
        for (Integer i = 0; i < jobs.size(); i++) {
          Map<String, Object> j = (Map<String, Object>) jobs[i];
          if (returnUnassigned && i == jobs.size() - 1) {
            unassigned.add(new Map<String, Object>{ 'id' => j.get('id') });
            continue;
          }
          cumDist += 5000;
          cumDur += 600;
          steps.add(
            new Map<String, Object>{
              'type' => 'job',
              'id' => j.get('id'),
              'location' => j.get('location'),
              'arrival' => nowSec + cumDur,
              'waiting_time' => 0,
              'service' => j.get('service'),
              'distance' => cumDist,
              'duration' => cumDur
            }
          );
        }
        cumDist += 4000;
        cumDur += 500;
        steps.add(
          new Map<String, Object>{
            'type' => 'end',
            'location' => veh.containsKey('end') ? veh.get('end') : startLoc,
            'arrival' => nowSec + cumDur,
            'waiting_time' => 0,
            'service' => 0,
            'distance' => cumDist,
            'duration' => cumDur
          }
        );

        res.setBody(
          JSON.serialize(
            new Map<String, Object>{
              'routes' => new List<Object>{
                new Map<String, Object>{
                  'vehicle' => vid,
                  'geometry' => 'mockPolyline',
                  'distance' => cumDist,
                  'service' => 600,
                  'waiting_time' => 0,
                  'steps' => steps
                }
              },
              'unassigned' => unassigned,
              'summary' => new Map<String, Object>{
                'distance' => cumDist,
                'duration' => cumDur,
                'service' => 600,
                'waiting_time' => 0,
                'cost' => cumDur
              }
            }
          )
        );
        return res;
      }

      res.setStatusCode(404);
      return res;
    }
  }

  @TestSetup
  static void makeData() {
    RoutingTestData.grantAccess();
    Id planId = RoutingTestData.scenario(2);
    update new Route_Plan__c(
      Id = planId,
      Plan_Date__c = Date.today(),
      Provider__c = 'Openrouteservice'
    );
    List<Route_Job__c> jobs = [
      SELECT Id
      FROM Route_Job__c
      WHERE Service_Date__c = :RoutingTestData.planDate()
    ];
    for (Route_Job__c j : jobs) {
      j.Service_Date__c = Date.today();
    }
    update jobs;
    System.runAs(RoutingTestData.self()) {
      RoutePlanService.PlanContext ctx = RoutePlanService.buildRequest(planId);
      RoutePlanService.applyResult(
        ctx,
        RoutingDtos.parseOptimize(RoutingTestData.answer(ctx.request.toJson()))
      );
    }
  }

  @IsTest
  static void scansPdfWithCityFallbackGeocode() {
    MultiCalloutMock mock = new MultiCalloutMock();
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    DriverRouteScanService.ScanResult res = DriverRouteScanController.scanDocument(
      EncodingUtil.base64Encode(Blob.valueOf('%PDF-1.4 fake')),
      'application/pdf',
      'bol.pdf'
    );
    Test.stopTest();

    System.assertEquals('SH26011985', res.docNumber);
    System.assertEquals('7998', res.bolNumber);
    System.assertEquals('חוליות גפני בע"מ', res.customerName);
    System.assertEquals(32076, res.weightKg);
    System.assertEquals(32.7021, res.latitude);
    System.assertEquals(35.3027, res.longitude);
    System.assert(res.geocodeWarning.contains('Matched broader location'));

    // Verify Claude received a document block for PDF
    Map<String, Object> claudeReq = (Map<String, Object>) JSON.deserializeUntyped(
      mock.requests[0].getBody()
    );
    List<Object> msgs = (List<Object>) claudeReq.get('messages');
    List<Object> content = (List<Object>) ((Map<String, Object>) msgs[0])
      .get('content');
    System.assertEquals(
      'document',
      ((Map<String, Object>) content[0]).get('type')
    );
  }

  @IsTest
  static void scansImageAndRegeocodes() {
    MultiCalloutMock mock = new MultiCalloutMock();
    mock.missFirstGeocode = false;
    Test.setMock(HttpCalloutMock.class, mock);

    Test.startTest();
    DriverRouteScanService.ScanResult res = DriverRouteScanController.scanDocument(
      EncodingUtil.base64Encode(Blob.valueOf('jpegbytes')),
      'image/jpeg',
      'note.jpg'
    );
    DriverRouteScanService.GeoPoint geo = DriverRouteScanController.geocodeAddress(
      'נצרת',
      null
    );
    DriverRouteScanService.GeoPoint emptyGeo = DriverRouteScanController.geocodeAddress(
      '',
      ''
    );
    Test.stopTest();

    System.assertEquals(null, res.geocodeWarning);
    System.assertEquals(32.7021, geo.latitude);
    System.assert(emptyGeo.warning.contains('No destination address'));

    Map<String, Object> claudeReq = (Map<String, Object>) JSON.deserializeUntyped(
      mock.requests[0].getBody()
    );
    List<Object> msgs = (List<Object>) claudeReq.get('messages');
    List<Object> content = (List<Object>) ((Map<String, Object>) msgs[0])
      .get('content');
    System.assertEquals(
      'image',
      ((Map<String, Object>) content[0]).get('type')
    );
  }

  @IsTest
  static void scanHandlesErrorsCleanly() {
    Test.startTest();
    try {
      DriverRouteScanController.scanDocument('', 'image/jpeg', 'x.jpg');
      System.assert(false, 'expected error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('choose an image or PDF'));
    }

    MultiCalloutMock mock = new MultiCalloutMock();
    mock.failClaude = true;
    Test.setMock(HttpCalloutMock.class, mock);
    try {
      DriverRouteScanController.scanDocument('YWJj', 'image/png', 'x.png');
      System.assert(false, 'expected error');
    } catch (AuraHandledException e) {
      System.assert(
        e.getMessage().contains('rejected the API key'),
        'Actual: ' + e.getMessage()
      );
    }

    mock.failClaude = false;
    mock.invalidClaudeJson = true;
    try {
      DriverRouteScanController.scanDocument('YWJj', '', 'x.webp');
      System.assert(false, 'expected error');
    } catch (AuraHandledException e) {
      System.assert(
        e.getMessage().contains('parse extracted document JSON'),
        'Actual: ' + e.getMessage()
      );
    }

    mock.invalidClaudeJson = false;
    mock.missAllGeocode = true;
    DriverRouteScanService.ScanResult noGeo = DriverRouteScanController.scanDocument(
      'YWJj',
      'image/gif',
      'x.gif'
    );
    System.assertEquals(null, noGeo.latitude);
    System.assert(noGeo.geocodeWarning.contains('Could not geocode'));

    mock.missAllGeocode = false;
    mock.failGeocode = true;
    DriverRouteScanService.GeoPoint geoErr = DriverRouteScanController.geocodeAddress(
      'נצרת',
      null
    );
    System.assertEquals(null, geoErr.latitude);
    System.assert(geoErr.warning.contains('Geocoding failed'));
    Test.stopTest();
  }

  @IsTest
  static void createsJobAndAddsVisitToRouteInUserMode() {
    Route__c route = [
      SELECT Id, Driver__c, Revision__c, Route_Plan__c
      FROM Route__c
      WHERE Fleet_Asset__r.Name = 'RT-VAN-1'
      LIMIT 1
    ];
    MultiCalloutMock mock = new MultiCalloutMock();
    Test.setMock(HttpCalloutMock.class, mock);

    String payload = JSON.serialize(
      new Map<String, Object>{
        'docNumber' => 'SH26011985',
        'bolNumber' => '7998',
        'orderNumber' => 'SO26007097',
        'customerName' => 'חוליות גפני בע"מ',
        'destinationAddress' => 'נצרת שכונת הגליל (אתר 1625800)',
        'contactName' => 'מחבר',
        'contactPhone' => '054-9230336',
        'cargoSummary' => 'גלית 30/30/6 אפור',
        'extractedWeightKg' => 32076,
        'loadKg' => 100,
        'latitude' => 32.7021,
        'longitude' => 35.3027
      }
    );

    DriverRouteScanService.CreatedJobResult created = DriverRouteScanController.createScannedJob(
      route.Id,
      route.Driver__c,
      payload,
      EncodingUtil.base64Encode(Blob.valueOf('pdfbytes')),
      'application/pdf',
      'bol.pdf'
    );
    // Repeat with same docNumber to verify duplicate External_Id__c protection
    DriverRouteScanService.CreatedJobResult createdDup = DriverRouteScanController.createScannedJob(
      route.Id,
      route.Driver__c,
      payload,
      null,
      null,
      null
    );

    Test.startTest();
    DriverRouteScanService.AddVisitResult added;
    System.runAs(RoutingTestData.self()) {
      added = DriverRouteScanController.addVisitToRoute(
        route.Id,
        created.visitId
      );
    }
    Test.stopTest();

    System.assertNotEquals(null, created.jobId);
    System.assertNotEquals(null, created.visitId);
    System.assertNotEquals(null, created.contentVersionId);
    System.assertNotEquals(created.jobId, createdDup.jobId);

    System.assertEquals(true, added.assigned);
    System.assertEquals(null, added.unassignedReason);
    System.assertEquals(route.Id, added.routeId);
    System.assert(added.revision > route.Revision__c);

    Route_Job__c savedJob = [
      SELECT Status__c, Planned_Route__c, Notes__c
      FROM Route_Job__c
      WHERE Id = :created.jobId
    ];
    System.assertEquals('Planned', savedJob.Status__c);
    System.assertEquals(route.Id, savedJob.Planned_Route__c);
    System.assert(savedJob.Notes__c.contains('SO26007097'));

    List<Route_Event__c> events = [
      SELECT Type__c, Actor_Type__c
      FROM Route_Event__c
      WHERE Route__c = :route.Id AND Type__c IN ('Stop Added', 'Reoptimized')
    ];
    System.assertEquals(2, events.size());

    Job_Visit__c savedVisit = [
      SELECT Waypoint__c, Address__c
      FROM Job_Visit__c
      WHERE Id = :created.visitId
    ];
    System.assertNotEquals(null, savedVisit.Waypoint__c);

    DriverRouteController.DriverRoute refreshed = DriverRouteController.getTodayRoute(
      route.Driver__c
    );
    Boolean foundNazareth = false;
    for (DriverRouteController.Stop s : refreshed.stops) {
      if (s.address != null && s.address.contains('נצרת')) {
        foundNazareth = true;
      }
    }
    System.assert(
      foundNazareth,
      'Expected scanned Nazareth stop in refreshed route'
    );
  }

  @IsTest
  static void addsVisitInSystemModeFallbackAndHandlesUnassigned() {
    Route__c route = [
      SELECT Id, Driver__c, Revision__c
      FROM Route__c
      WHERE Fleet_Asset__r.Name = 'RT-VAN-1'
      LIMIT 1
    ];
    // Mark one waypoint locked to verify ORS fixed-step clearing works
    Waypoint__c firstJobWp = [
      SELECT Id
      FROM Waypoint__c
      WHERE Route__c = :route.Id AND Type__c = 'Job Stop'
      ORDER BY Sequence__c
      LIMIT 1
    ];
    update new Waypoint__c(Id = firstJobWp.Id, Locked__c = true);

    MultiCalloutMock mock = new MultiCalloutMock();
    mock.returnUnassigned = true;
    Test.setMock(HttpCalloutMock.class, mock);

    String payload = JSON.serialize(
      new Map<String, Object>{
        'docNumber' => 'SH-UNASSIGNED',
        'destinationAddress' => 'נצרת',
        'latitude' => 32.7021,
        'longitude' => 35.3027,
        'loadKg' => 50000
      }
    );

    DriverRouteScanService.CreatedJobResult created = DriverRouteScanController.createScannedJob(
      route.Id,
      route.Driver__c,
      payload,
      null,
      null,
      null
    );

    Test.startTest();
    DriverRouteScanService.forceSystemModeForTest = true;
    DriverRouteScanService.AddVisitResult added = DriverRouteScanController.addVisitToRoute(
      route.Id,
      created.visitId
    );
    DriverRouteScanService.forceSystemModeForTest = false;
    Test.stopTest();

    System.assertEquals(false, added.assigned);
    System.assert(added.unassignedReason.contains('no_room'));
  }

  @IsTest
  static void validatesCreateAndAddInputs() {
    try {
      DriverRouteScanController.createScannedJob(
        null,
        null,
        '{}',
        null,
        null,
        null
      );
      System.assert(false, 'expected error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('No active route'));
    }

    Route__c route = [SELECT Id FROM Route__c LIMIT 1];
    try {
      DriverRouteScanController.createScannedJob(
        route.Id,
        null,
        '',
        null,
        null,
        null
      );
      System.assert(false, 'expected error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('Stop details are required'));
    }

    try {
      DriverRouteScanController.createScannedJob(
        route.Id,
        null,
        '{bad json',
        null,
        null,
        null
      );
      System.assert(false, 'expected error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('Invalid stop payload'));
    }

    try {
      DriverRouteScanController.createScannedJob(
        UserInfo.getUserId(),
        null,
        '{}',
        null,
        null,
        null
      );
      System.assert(false, 'expected error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('could not be loaded'));
    }

    try {
      DriverRouteScanController.createScannedJob(
        route.Id,
        null,
        '{}',
        null,
        null,
        null
      );
      System.assert(false, 'expected error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('Destination address is required'));
    }

    try {
      DriverRouteScanController.createScannedJob(
        route.Id,
        null,
        JSON.serialize(
          new Map<String, Object>{ 'destinationAddress' => 'Nazareth' }
        ),
        null,
        null,
        null
      );
      System.assert(false, 'expected error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('Coordinates are required'));
    }

    try {
      DriverRouteScanController.addVisitToRoute(null, null);
      System.assert(false, 'expected error');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('required'));
    }
  }
}
