/**
 * The routing solver seam. Every provider speaks the neutral FleetForce contract (RoutingDtos), so
 * RoutePlanService never knows which engine answered.
 *
 * Implementations: FleetForceRoutingProvider (default, our Cloud Run service), OrsRoutingProvider
 * (openrouteservice, dev only), MockRoutingProvider (tests and offline demos). A
 * GoogleRouteOptimizationProvider can be added later without touching callers.
 *
 * Every method makes at most one callout, so callers must make it before any DML.
 */
public interface RoutingProvider {
  RoutingDtos.OptimizeResult optimize(RoutingDtos.OptimizeRequest request);

  /** locations are [lon, lat] pairs, the contract's order. */
  RoutingDtos.MatrixResult matrix(List<Location> locations);

  /** Legs and totals for waypoints in the given order (manual reordering). */
  RoutingDtos.RouteResult route(
    List<RoutingDtos.RouteWaypoint> waypoints,
    Datetime departure
  );
}
