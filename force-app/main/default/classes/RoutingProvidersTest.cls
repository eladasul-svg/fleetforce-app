@IsTest
private class RoutingProvidersTest {
  private class Fixed implements HttpCalloutMock {
    Integer code;
    String body;
    Boolean fail = false;
    HttpRequest last;
    Fixed(Integer code, String body) {
      this.code = code;
      this.body = body;
    }
    public HttpResponse respond(HttpRequest req) {
      last = req;
      if (fail) {
        throw new CalloutException('connection refused');
      }
      HttpResponse res = new HttpResponse();
      res.setStatusCode(code);
      res.setBody(body);
      return res;
    }
  }

  private static RoutingDtos.OptimizeRequest request() {
    RoutingDtos.OptimizeRequest req = new RoutingDtos.OptimizeRequest();
    RoutingDtos.Vehicle v = new RoutingDtos.Vehicle();
    v.id = 'van-1';
    v.startLocation = Location.newInstance(31.2518, 34.7913);
    v.endLocation = v.startLocation;
    v.shiftStart = Datetime.newInstanceGmt(2026, 11, 4, 5, 0, 0);
    v.shiftEnd = v.shiftStart.addHours(10);
    req.vehicles.add(v);
    RoutingDtos.Job j = new RoutingDtos.Job();
    j.id = 'visit-1';
    j.location = Location.newInstance(31.26, 34.8);
    req.jobs.add(j);
    return req;
  }

  @IsTest
  static void forNamePicksTheProvider() {
    System.assert(
      RoutingProviders.forName(
        'FleetForce Routing'
      ) instanceof FleetForceRoutingProvider
    );
    System.assert(
      RoutingProviders.forName(null) instanceof FleetForceRoutingProvider
    );
    System.assert(
      RoutingProviders.forName('Openrouteservice') instanceof OrsRoutingProvider
    );
    System.assert(
      RoutingProviders.forName('Mock') instanceof MockRoutingProvider
    );
    try {
      RoutingProviders.forName('Google');
      System.assert(false, 'expected an exception');
    } catch (RoutingProviders.RoutingException e) {
      System.assert(e.getMessage().contains('not available yet'));
    }
    MockRoutingProvider mock = new MockRoutingProvider();
    RoutingProviders.useForTest(mock);
    System.assert(RoutingProviders.forName('Google') === mock);
  }

  @IsTest
  static void optimizeCallsTheServiceThroughTheNamedCredential() {
    RoutingDtos.OptimizeRequest req = request();
    Fixed mock = new Fixed(200, RoutingTestData.answer(req.toJson()));
    Test.setMock(HttpCalloutMock.class, mock);
    Test.startTest();
    RoutingDtos.OptimizeResult r = new FleetForceRoutingProvider()
      .optimize(req);
    Test.stopTest();
    System.assertEquals(
      'callout:' +
        FleetForceRoutingProvider.namedCredentialName() +
        '/v1/optimize',
      mock.last.getEndpoint()
    );
    System.assertEquals('POST', mock.last.getMethod());
    System.assertEquals(
      'application/json',
      mock.last.getHeader('Content-Type')
    );
    System.assertEquals(RoutingProviders.TIMEOUT_MS, 120000);
    Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(
      mock.last.getBody()
    );
    Map<String, Object> v = (Map<String, Object>) ((List<Object>) sent.get(
      'vehicles'
    ))[0];
    System.assertEquals('2026-11-04T05:00:00Z', v.get('shift_start'));
    System.assertEquals(
      34.7913,
      ((List<Object>) v.get('start'))[0],
      'coordinates are [lon, lat]'
    );
    System.assertEquals(1, r.routes.size());
    System.assertEquals('van-1', r.routes[0].vehicleId);
    System.assertEquals('visit-1', r.routes[0].steps[1].id);
    System.assertEquals('haversine', r.summary.matrixSource);
  }

  @IsTest
  static void matrixAndRoute() {
    Test.setMock(
      HttpCalloutMock.class,
      new Fixed(
        200,
        '{"durations":[[0,61],[60,0]],"distances":[[0,812],[790,0]],"matrix_source":"osrm"}'
      )
    );
    RoutingDtos.MatrixResult m = new FleetForceRoutingProvider()
      .matrix(
        new List<Location>{
          Location.newInstance(31.25, 34.79),
          Location.newInstance(31.26, 34.8)
        }
      );
    System.assertEquals(61, m.durations[0][1]);
    System.assertEquals(790, m.distances[1][0]);
    System.assertEquals('osrm', m.matrixSource);

    Fixed mock = new Fixed(
      200,
      '{"legs":[{"from_id":"a","to_id":"b","distance_m":812,"duration_s":61,"arrival":"2026-11-04T05:01:01Z"}],' +
      '"distance_m":812,"duration_s":61,"geometry":"abc","matrix_source":"osrm"}'
    );
    Test.setMock(HttpCalloutMock.class, mock);
    RoutingDtos.RouteResult r = new FleetForceRoutingProvider()
      .route(
        new List<RoutingDtos.RouteWaypoint>{
          new RoutingDtos.RouteWaypoint(
            'a',
            Location.newInstance(31.25, 34.79)
          ),
          new RoutingDtos.RouteWaypoint('b', Location.newInstance(31.26, 34.8))
        },
        Datetime.newInstanceGmt(2026, 11, 4, 5, 0, 0)
      );
    System.assert(mock.last.getEndpoint().endsWith('/v1/route'));
    System.assert(
      mock.last.getBody().contains('"departure":"2026-11-04T05:00:00Z"')
    );
    System.assertEquals(1, r.legs.size());
    System.assertEquals('b', r.legs[0].toId);
    System.assertEquals(
      Datetime.newInstanceGmt(2026, 11, 4, 5, 1, 1),
      r.legs[0].arrival
    );
    System.assertEquals('abc', r.geometry);
  }

  @IsTest
  static void errorsAreReadable() {
    Fixed mock = new Fixed(
      401,
      '{"detail":"Missing or unknown X-FleetForce-Key"}'
    );
    Test.setMock(HttpCalloutMock.class, mock);
    assertFails(mock, 'rejected the key');
    mock.code = 422;
    mock.body = '{"detail":[{"msg":"duplicate task id"}]}';
    assertFails(mock, 'duplicate task id');
    mock.code = 503;
    mock.body = 'down';
    assertFails(mock, 'temporarily unavailable');
    mock.code = 429;
    assertFails(mock, 'rate-limited');
    mock.code = 404;
    mock.body = '{"error":"nope"}';
    assertFails(mock, 'nope');
    mock.fail = true;
    assertFails(mock, 'Could not reach');
  }

  private static void assertFails(Fixed mock, String expected) {
    try {
      new FleetForceRoutingProvider().optimize(request());
      System.assert(false, 'expected an exception');
    } catch (RoutingProviders.RoutingException e) {
      System.assert(e.getMessage().contains(expected), e.getMessage());
    }
  }

  @IsTest
  static void sendWithoutBodyIsAGet() {
    Fixed mock = new Fixed(200, '{}');
    Test.setMock(HttpCalloutMock.class, mock);
    RoutingProviders.send(
      'callout:X/healthz',
      null,
      new Map<String, String>{ 'X-Test' => '1' }
    );
    System.assertEquals('GET', mock.last.getMethod());
    System.assertEquals('1', mock.last.getHeader('X-Test'));
  }
}
