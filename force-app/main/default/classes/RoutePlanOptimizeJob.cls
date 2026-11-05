/**
 * Optimizes one Route_Plan__c asynchronously: reads (USER_MODE), one callout, then DML, in that order,
 * because Salesforce forbids a callout after uncommitted DML. Publishes Route_Plan_Update__e so open
 * route boards refresh.
 */
public with sharing class RoutePlanOptimizeJob implements Queueable, Database.AllowsCallouts {
  private final Id planId;

  public RoutePlanOptimizeJob(Id planId) {
    this.planId = planId;
  }

  public void execute(QueueableContext context) {
    run(planId);
  }

  /** Synchronous body, also used by tests and RoutingActions. Returns the applied result. */
  public static RoutingDtos.OptimizeResult run(Id planId) {
    RoutingDtos.OptimizeResult result;
    String error;
    RoutePlanService.PlanContext ctx;
    try {
      ctx = RoutePlanService.buildRequest(planId);
      if (ctx.request.vehicles.isEmpty()) {
        throw new RoutingProviders.RoutingException(
          'No vehicle at the depot can be routed' +
          (ctx.request.excludedVehicles.isEmpty()
            ? '.'
            : ': ' + String.join(ctx.request.excludedVehicles.values(), '; '))
        );
      }
      result = ctx.request.taskCount() == 0
        ? new RoutingDtos.OptimizeResult()
        : RoutePlanService.provider(ctx.plan).optimize(ctx.request);
    } catch (Exception e) {
      error = e.getMessage();
    }

    if (error == null) {
      Savepoint sp = Database.setSavepoint();
      try {
        RoutePlanService.applyResult(ctx, result);
      } catch (Exception e) {
        Database.rollback(sp);
        error = 'Could not save the optimized routes: ' + e.getMessage();
      }
    }
    if (error != null) {
      RoutePlanService.recordFailure(planId, error);
      publish(planId, 'Failed', null, error);
      return null;
    }
    publish(
      planId,
      'Optimized',
      ctx.plan.Revision__c,
      result.routes.size() +
        ' routes, ' +
        (result.unassigned.size() + ctx.request.skippedJobs.size()) +
        ' unassigned'
    );
    return result;
  }

  public static void publish(
    Id planId,
    String status,
    Decimal revision,
    String message
  ) {
    EventBus.publish(
      new Route_Plan_Update__e(
        Route_Plan_Id__c = planId,
        Status__c = status,
        Revision__c = revision,
        Message__c = message == null ? null : message.abbreviate(255)
      )
    );
  }
}
