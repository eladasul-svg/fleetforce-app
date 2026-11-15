/**
 * Default provider: the FleetForce Routing Service on Cloud Run (services/routing), reached through
 * the FleetForce_Routing named credential, whose external credential adds the X-FleetForce-Key header.
 * The service already speaks the neutral contract, so this class only does the HTTP.
 */
public with sharing class FleetForceRoutingProvider implements RoutingProvider {
  public static final String NAMED_CREDENTIAL = 'FleetForce_Routing';

  public static String namedCredentialName() {
    return RoutingProviders.namedCredential(NAMED_CREDENTIAL);
  }

  private static String endpoint(String path) {
    return 'callout:' + namedCredentialName() + path;
  }

  public RoutingDtos.OptimizeResult optimize(
    RoutingDtos.OptimizeRequest request
  ) {
    String body = RoutingProviders.send(
      endpoint('/v1/optimize'),
      request.toJson(),
      null
    );
    return RoutingDtos.parseOptimize(body);
  }

  public RoutingDtos.MatrixResult matrix(List<Location> locations) {
    List<Object> coords = new List<Object>();
    for (Location l : locations) {
      coords.add(RoutingDtos.coord(l));
    }
    String body = RoutingProviders.send(
      endpoint('/v1/matrix'),
      JSON.serialize(new Map<String, Object>{ 'locations' => coords }),
      null
    );
    return RoutingDtos.parseMatrix(body);
  }

  public RoutingDtos.RouteResult route(
    List<RoutingDtos.RouteWaypoint> waypoints,
    Datetime departure
  ) {
    List<Object> wps = new List<Object>();
    for (RoutingDtos.RouteWaypoint w : waypoints) {
      wps.add(
        new Map<String, Object>{
          'id' => w.id,
          'location' => RoutingDtos.coord(w.location)
        }
      );
    }
    Map<String, Object> req = new Map<String, Object>{
      'waypoints' => wps,
      'geometry' => true
    };
    if (departure != null) {
      req.put('departure', RoutingDtos.iso(departure));
    }
    String body = RoutingProviders.send(
      endpoint('/v1/route'),
      JSON.serialize(req),
      null
    );
    return RoutingDtos.parseRoute(body);
  }
}
