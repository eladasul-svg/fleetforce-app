/**
 * The FleetForce Assistant's routing tools, offered only in a chat opened from a Route__c record.
 *
 * Claude never invents a sequence: every change to stop order goes through the solver
 * (reoptimize_remaining, propose_handoff, what_if) and then RoutingPolicy, and comes back as a
 * proposal the user approves. Reads run in USER_MODE. Tool execution never does DML, because
 * AssistantService may still need a callout in the same turn: report_delay and "proposed" events are
 * buffered and written by commitPending() with the turn's own DML. Applying an approved proposal is
 * DML only (it reuses the solver result stored in the proposal).
 */
public with sharing class RoutingAssistantTools {
  public static final String ACTION_PREFIX = 'routing.';
  public static final Set<String> TOOL_NAMES = new Set<String>{
    'get_route',
    'report_delay',
    'update_window',
    'skip_stop',
    'add_waypoint',
    'reoptimize_remaining',
    'what_if',
    'propose_handoff'
  };
  public static final Set<String> ADDABLE_TYPES = new Set<String>{
    'Break',
    'Refuel',
    'Charge',
    'Driver Added'
  };

  @TestVisible
  private static List<RouteEvents.Builder> pending = new List<RouteEvents.Builder>();
  @TestVisible
  private static Map<Id, Integer> pendingDelay = new Map<Id, Integer>();

  // ---------------------------------------------------------------------------------------------
  // Registration
  // ---------------------------------------------------------------------------------------------

  public static Boolean handles(String toolName) {
    return TOOL_NAMES.contains(toolName);
  }

  public static Id routeIdOf(Assistant_Session__c s) {
    if (s == null || String.isBlank(s.Record_Id__c)) {
      return null;
    }
    try {
      Id rid = Id.valueOf(s.Record_Id__c);
      return rid.getSObjectType() == Route__c.SObjectType ? rid : null;
    } catch (Exception e) {
      return null;
    }
  }

  public static Boolean appliesTo(Assistant_Session__c s) {
    return routeIdOf(s) != null;
  }

  public static String contextPrompt() {
    return '\n\nRouting: this chat is about a delivery route. You are the dispatcher\'s assistant, not the ' +
      'route solver: never invent a stop order. Use get_route to see the remaining stops. When something ' +
      'changes on the road (a delay, a customer\'s new time window, a stop that cannot be served), record it ' +
      'with report_delay, update_window or skip_stop, then call reoptimize_remaining so the solver re-plans, ' +
      'and explain its before/after in plain words. Hand-offs to another route go through propose_handoff ' +
      'and need a dispatcher. Keep answers to drivers to two short sentences; they may be driving.';
  }

  public static List<Object> definitions() {
    return new List<Object>{
      tool(
        'get_route',
        'Get the route: vehicle, driver, remaining stops in order with ETAs, time windows, loads, lock state, ' +
        'and any delay reported since the last re-plan.',
        new Map<String, Object>{
          'route_id' => prop(
            'string',
            'Route Id. Defaults to the route this chat is about.'
          )
        },
        new List<String>()
      ),
      tool(
        'report_delay',
        'Record that the route is running late. Writes a Delay Reported event (no proposal). Call ' +
        'reoptimize_remaining afterwards to re-plan the remaining stops with the delay.',
        new Map<String, Object>{
          'minutes' => prop('integer', 'How many minutes late, 1-600.'),
          'reason' => prop('string', 'Short reason, e.g. "loading was late".'),
          'route_id' => prop('string', 'Optional route Id.')
        },
        new List<String>{ 'minutes' }
      ),
      tool(
        'update_window',
        'Propose a new time window for a visit (the customer changed it). The user approves it in the UI.',
        new Map<String, Object>{
          'visit_id' => prop('string', 'Job Visit Id (from get_route).'),
          'start' => prop(
            'string',
            'New window start, ISO 8601 with time zone, e.g. 2026-11-04T15:00:00+02:00.'
          ),
          'end' => prop('string', 'New window end, ISO 8601 with time zone.'),
          'reason' => prop('string', 'One sentence shown to the user.')
        },
        new List<String>{ 'visit_id', 'start', 'end' }
      ),
      tool(
        'skip_stop',
        'Propose skipping a stop: it is marked Skipped and its job goes back to Ready for re-planning.',
        new Map<String, Object>{
          'waypoint_id' => prop('string', 'Waypoint Id (from get_route).'),
          'reason' => prop('string', 'Why the stop is skipped.')
        },
        new List<String>{ 'waypoint_id', 'reason' }
      ),
      tool(
        'add_waypoint',
        'Propose adding a Break, Refuel, Charge or Driver Added stop after a given stop (default: after the ' +
        'next stop). Later ETAs move by its duration.',
        new Map<String, Object>{
          'type' => new Map<String, Object>{
            'type' => 'string',
            'enum' => new List<String>(ADDABLE_TYPES),
            'description' => 'Kind of stop.'
          },
          'minutes' => prop('integer', 'How long the stop takes, 1-240.'),
          'after_waypoint_id' => prop(
            'string',
            'Optional waypoint Id to add the stop after.'
          ),
          'reason' => prop('string', 'Why the stop is added.')
        },
        new List<String>{ 'type', 'minutes' }
      ),
      tool(
        'reoptimize_remaining',
        'Ask the route solver to re-plan the remaining stops from where the vehicle is now, including any ' +
          'reported delay. Locked stops keep their place at the front. Returns the before/after difference as a ' +
          'proposal; nothing changes until it is approved.',
        new Map<String, Object>{
          'locked_waypoint_ids' => new Map<String, Object>{
            'type' => 'array',
            'items' => new Map<String, Object>{ 'type' => 'string' },
            'description' => 'Waypoint Ids that must stay first, in their current order (e.g. the stop the driver is heading to).'
          },
          'route_id' => prop('string', 'Optional route Id.')
        },
        new List<String>()
      ),
      tool(
        'what_if',
        'Dispatchers only. Re-solve the whole plan with a change and return the difference in routes, ' +
        'unassigned jobs, distance and time, without saving anything.',
        new Map<String, Object>{
          'exclude_route_ids' => new Map<String, Object>{
            'type' => 'array',
            'items' => new Map<String, Object>{ 'type' => 'string' },
            'description' => 'Routes whose vehicles are taken out (e.g. a breakdown).'
          },
          'extra_delay_minutes' => prop(
            'integer',
            'Delay every vehicle\'s start by this many minutes.'
          )
        },
        new List<String>()
      ),
      tool(
        'propose_handoff',
        'Dispatchers only. Propose moving a visit (and the rest of its job) to another route; both routes are ' +
        're-optimized by the solver and the dispatcher approves.',
        new Map<String, Object>{
          'visit_id' => prop('string', 'Job Visit Id to move.'),
          'to_route_id' => prop('string', 'Route Id that takes it over.')
        },
        new List<String>{ 'visit_id', 'to_route_id' }
      )
    };
  }

  private static Map<String, Object> tool(
    String name,
    String description,
    Map<String, Object> props,
    List<String> required
  ) {
    return new Map<String, Object>{
      'name' => name,
      'description' => description,
      'input_schema' => new Map<String, Object>{
        'type' => 'object',
        'properties' => props,
        'required' => required
      }
    };
  }

  private static Map<String, Object> prop(String type, String description) {
    return new Map<String, Object>{
      'type' => type,
      'description' => description
    };
  }

  // ---------------------------------------------------------------------------------------------
  // Execution
  // ---------------------------------------------------------------------------------------------

  public static AssistantTools.ToolResult execute(
    String name,
    Map<String, Object> input,
    Assistant_Session__c s
  ) {
    if (input == null) {
      input = new Map<String, Object>();
    }
    try {
      Id routeId = resolveRoute((String) input.get('route_id'), s);
      switch on name {
        when 'get_route' {
          return getRoute(routeId);
        }
        when 'report_delay' {
          return reportDelay(
            routeId,
            input.get('minutes'),
            (String) input.get('reason')
          );
        }
        when 'update_window' {
          return updateWindow(
            routeId,
            (String) input.get('visit_id'),
            (String) input.get('start'),
            (String) input.get('end'),
            (String) input.get('reason')
          );
        }
        when 'skip_stop' {
          return skipStop(
            routeId,
            (String) input.get('waypoint_id'),
            (String) input.get('reason')
          );
        }
        when 'add_waypoint' {
          return addWaypoint(
            routeId,
            (String) input.get('type'),
            input.get('minutes'),
            (String) input.get('after_waypoint_id'),
            (String) input.get('reason')
          );
        }
        when 'reoptimize_remaining' {
          return reoptimize(routeId, ids(input.get('locked_waypoint_ids')));
        }
        when 'what_if' {
          return whatIf(
            routeId,
            ids(input.get('exclude_route_ids')),
            input.get('extra_delay_minutes')
          );
        }
        when 'propose_handoff' {
          return proposeHandoff(
            routeId,
            (String) input.get('visit_id'),
            (String) input.get('to_route_id')
          );
        }
        when else {
          return error('Unknown routing tool: ' + name);
        }
      }
    } catch (Exception e) {
      return error(e.getMessage());
    }
  }

  private static Id resolveRoute(String routeId, Assistant_Session__c s) {
    if (String.isNotBlank(routeId)) {
      Id rid = parseId(routeId, 'route_id');
      if (rid.getSObjectType() != Route__c.SObjectType) {
        throw new RoutingProviders.RoutingException(
          'route_id must be a Route Id.'
        );
      }
      return rid;
    }
    Id fromSession = routeIdOf(s);
    if (fromSession == null) {
      throw new RoutingProviders.RoutingException(
        'Pass route_id: this chat is not about a route.'
      );
    }
    return fromSession;
  }

  // ---- get_route ------------------------------------------------------------------------------

  private static AssistantTools.ToolResult getRoute(Id routeId) {
    Route__c route = RouteReplanService.loadRoute(routeId);
    Map<Id, List<Job_Visit__c>> byWaypoint = new Map<Id, List<Job_Visit__c>>();
    for (Job_Visit__c jv : RouteReplanService.visits(routeId, null).values()) {
      if (!byWaypoint.containsKey(jv.Waypoint__c)) {
        byWaypoint.put(jv.Waypoint__c, new List<Job_Visit__c>());
      }
      byWaypoint.get(jv.Waypoint__c).add(jv);
    }
    List<Object> stops = new List<Object>();
    Integer completed = 0;
    for (Waypoint__c w : RouteReplanService.waypoints(routeId)) {
      if (RouteReplanService.DONE_STATUSES.contains(w.Status__c)) {
        completed++;
        continue;
      }
      if (w.Type__c == 'Start') {
        continue;
      }
      List<Object> visits = new List<Object>();
      if (byWaypoint.containsKey(w.Id)) {
        for (Job_Visit__c jv : byWaypoint.get(w.Id)) {
          visits.add(
            new Map<String, Object>{
              'visitId' => jv.Id,
              'job' => jv.Route_Job__r.Name,
              'role' => jv.Role__c,
              'windowStart' => RoutingDtos.iso(jv.Window_Start__c),
              'windowEnd' => RoutingDtos.iso(jv.Window_End__c),
              'hardWindow' => jv.Hard_Window__c,
              'load' => new List<Object>{
                jv.Load_1__c,
                jv.Load_2__c,
                jv.Load_3__c
              },
              'accessNotes' => jv.Access_Notes__c,
              'address' => jv.Address__c
            }
          );
        }
      }
      stops.add(
        new Map<String, Object>{
          'waypointId' => w.Id,
          'sequence' => w.Sequence__c,
          'type' => w.Type__c,
          'status' => w.Status__c,
          'eta' => RoutingDtos.iso(
            w.ETA__c != null ? w.ETA__c : w.Planned_Arrival__c
          ),
          'locked' => w.Locked__c,
          'visits' => visits
        }
      );
    }
    Integer delay =
      RouteReplanService.pendingDelayMinutes(routeId) + delayInTurn(routeId);
    AssistantTools.ToolResult r = ok(
      new Map<String, Object>{
        'route' => new Map<String, Object>{
          'id' => route.Id,
          'name' => route.Name,
          'status' => route.Status__c,
          'vehicle' => route.Fleet_Asset__r == null
            ? null
            : route.Fleet_Asset__r.Name,
          'driver' => route.Driver__r == null ? null : route.Driver__r.Name,
          'plannedEnd' => RoutingDtos.iso(route.Planned_End__c),
          'revision' => route.Revision__c
        },
        'completedStops' => completed,
        'remainingStops' => stops,
        'delayMinutesSinceLastReplan' => delay,
        'you' => RoutingPolicy.actorRole(route)
      }
    );
    r.summary =
      'Read route ' +
      route.Name +
      ' (' +
      stops.size() +
      ' stops left)';
    return r;
  }

  // ---- report_delay ---------------------------------------------------------------------------

  private static AssistantTools.ToolResult reportDelay(
    Id routeId,
    Object minutesRaw,
    String reason
  ) {
    Integer minutes = RoutingDtos.toInt(minutesRaw);
    if (minutes < 1 || minutes > 600) {
      return error('minutes must be between 1 and 600.');
    }
    Route__c route = RouteReplanService.loadRoute(routeId);
    pending.add(
      RouteEvents.event(
          'Delay Reported',
          RoutingPolicy.actorRole(route) == RoutingPolicy.DRIVER
            ? 'Driver'
            : 'Dispatcher'
        )
        .forPlan(route.Route_Plan__c)
        .forRoute(route.Id)
        .payload(
          new Map<String, Object>{ 'minutes' => minutes, 'reason' => reason }
        )
    );
    pendingDelay.put(routeId, delayInTurn(routeId) + minutes);
    AssistantTools.ToolResult r = ok(
      new Map<String, Object>{
        'recorded' => true,
        'minutes' => minutes,
        'totalDelayMinutesSinceLastReplan' => RouteReplanService.pendingDelayMinutes(
          routeId
        ) + delayInTurn(routeId),
        'next' => 'Call reoptimize_remaining to re-plan the remaining stops with this delay.'
      }
    );
    r.summary = 'Reported a ' + minutes + '-minute delay';
    return r;
  }

  private static Integer delayInTurn(Id routeId) {
    return pendingDelay.containsKey(routeId) ? pendingDelay.get(routeId) : 0;
  }

  // ---- update_window --------------------------------------------------------------------------

  private static AssistantTools.ToolResult updateWindow(
    Id routeId,
    String visitId,
    String startRaw,
    String endRaw,
    String reason
  ) {
    Id vid = parseId(visitId, 'visit_id');
    Job_Visit__c jv = RouteReplanService.visits(routeId, new Set<Id>{ vid })
      .get(vid);
    if (jv == null) {
      return error('Visit ' + visitId + ' was not found or you cannot see it.');
    }
    Datetime st = RoutingDtos.dt(startRaw);
    Datetime en = RoutingDtos.dt(endRaw);
    if (st == null || en == null || en <= st) {
      return error(
        'start and end must be ISO 8601 datetimes with end after start.'
      );
    }
    Route__c route = RouteReplanService.loadRoute(routeId);
    RoutingPolicy.Decision d = RoutingPolicy.forWindowChange(jv);
    return proposal(
      'update_window',
      route,
      'Change the time window of ' + RouteReplanService.label(jv),
      reason,
      new List<Object>{
        change('Window start', jv.Window_Start__c, st),
        change('Window end', jv.Window_End__c, en)
      },
      new Map<String, Object>{
        'visitId' => jv.Id,
        'start' => RoutingDtos.iso(st),
        'end' => RoutingDtos.iso(en)
      },
      d
    );
  }

  // ---- skip_stop ------------------------------------------------------------------------------

  private static AssistantTools.ToolResult skipStop(
    Id routeId,
    String waypointId,
    String reason
  ) {
    Id wid = parseId(waypointId, 'waypoint_id');
    Waypoint__c w = findWaypoint(routeId, wid);
    if (w == null) {
      return error('Waypoint ' + waypointId + ' is not on this route.');
    }
    if (RouteReplanService.DONE_STATUSES.contains(w.Status__c)) {
      return error('That stop is already ' + w.Status__c + '.');
    }
    List<String> jobs = new List<String>();
    List<String> visitIds = new List<String>();
    for (Job_Visit__c jv : RouteReplanService.visits(routeId, null).values()) {
      if (jv.Waypoint__c == wid) {
        jobs.add(RouteReplanService.label(jv));
        visitIds.add(jv.Id);
      }
    }
    Route__c route = RouteReplanService.loadRoute(routeId);
    return proposal(
      'skip_stop',
      route,
      'Skip stop ' +
        w.Sequence__c +
        (jobs.isEmpty() ? '' : ' (' + String.join(jobs, ', ') + ')'),
      reason,
      new List<Object>{
        change('Stop status', w.Status__c, 'Skipped'),
        change(
          'Jobs back to Ready',
          '',
          jobs.isEmpty() ? 'None' : String.join(jobs, ', ')
        )
      },
      new Map<String, Object>{
        'waypointId' => w.Id,
        'visitIds' => visitIds,
        'reason' => reason
      },
      RoutingPolicy.forSkip()
    );
  }

  // ---- add_waypoint ---------------------------------------------------------------------------

  private static AssistantTools.ToolResult addWaypoint(
    Id routeId,
    String type,
    Object minutesRaw,
    String afterId,
    String reason
  ) {
    if (!ADDABLE_TYPES.contains(type)) {
      return error(
        'type must be one of: ' +
          String.join(new List<String>(ADDABLE_TYPES), ', ') +
          '.'
      );
    }
    Integer minutes = RoutingDtos.toInt(minutesRaw);
    if (minutes < 1 || minutes > 240) {
      return error('minutes must be between 1 and 240.');
    }
    Waypoint__c after;
    if (String.isNotBlank(afterId)) {
      after = findWaypoint(routeId, parseId(afterId, 'after_waypoint_id'));
    } else {
      for (Waypoint__c w : RouteReplanService.waypoints(routeId)) {
        if (
          !RouteReplanService.DONE_STATUSES.contains(w.Status__c) &&
          w.Type__c != 'Start' &&
          w.Type__c != 'End'
        ) {
          after = w;
          break;
        }
      }
    }
    if (after == null) {
      return error('There is no remaining stop to add the ' + type + ' after.');
    }
    Route__c route = RouteReplanService.loadRoute(routeId);
    return proposal(
      'add_waypoint',
      route,
      'Add a ' +
        minutes +
        '-minute ' +
        type +
        ' stop after stop ' +
        after.Sequence__c,
      reason,
      new List<Object>{
        change('New stop', '', type + ', ' + minutes + ' min'),
        change('Later ETAs', '', '+' + minutes + ' min')
      },
      new Map<String, Object>{
        'afterWaypointId' => after.Id,
        'type' => type,
        'minutes' => minutes,
        'reason' => reason
      },
      RoutingPolicy.forAddWaypoint(type)
    );
  }

  // ---- reoptimize_remaining -------------------------------------------------------------------

  private static AssistantTools.ToolResult reoptimize(
    Id routeId,
    Set<Id> lockedIds
  ) {
    RouteReplanService.RouteContext ctx = RouteReplanService.buildRequest(
      routeId,
      lockedIds,
      delayInTurn(routeId),
      null,
      null
    );
    if (ctx.request.taskCount() == 0) {
      return error('There are no remaining stops to re-plan.');
    }
    RoutingDtos.OptimizeResult result = RoutingProviders.forName(
        ctx.route.Route_Plan__r.Provider__c
      )
      .optimize(ctx.request);
    Map<String, Object> diff = RouteReplanService.diff(ctx, result);
    RoutingPolicy.Decision d = RoutingPolicy.forReoptimize(diff);
    List<Object> late = (List<Object>) diff.get('late');
    List<Object> unassigned = (List<Object>) diff.get('unassigned');
    List<String> unassignedNames = new List<String>();
    for (Object o : unassigned) {
      unassignedNames.add(
        String.valueOf(((Map<String, Object>) o).get('name'))
      );
    }
    AssistantTools.ToolResult r = proposal(
      'reoptimize',
      ctx.route,
      'Re-plan the remaining stops of ' + ctx.route.Name,
      ctx.delayMinutes > 0
        ? 'Running ' + ctx.delayMinutes + ' minutes late.'
        : null,
      new List<Object>{
        change(
          'Stop order',
          String.join((List<String>) diff.get('before'), ' → '),
          String.join((List<String>) diff.get('after'), ' → ')
        ),
        change(
          'Finish',
          ctx.route.Planned_End__c,
          RoutingDtos.dt(diff.get('plannedEnd'))
        ),
        change('Late stops', '', late.isEmpty() ? 'None' : joinObjects(late)),
        change(
          'Unassigned',
          '',
          unassignedNames.isEmpty()
            ? 'None'
            : String.join(unassignedNames, ', ')
        )
      },
      new Map<String, Object>{
        'routeId' => ctx.route.Id,
        'lockedIds' => new List<Id>(lockedIds),
        'remainingIds' => idsOf(ctx.remaining),
        'result' => RoutingDtos.toContractJson(result),
        'diff' => diff
      },
      d
    );
    // Claude sees the difference with the proposal so it can explain it.
    r.proposal.put('diff', diff);
    return r;
  }

  // ---- what_if --------------------------------------------------------------------------------

  private static AssistantTools.ToolResult whatIf(
    Id routeId,
    Set<Id> excludeRouteIds,
    Object delayRaw
  ) {
    Route__c route = RouteReplanService.loadRoute(routeId);
    if (RoutingPolicy.actorRole(route) == RoutingPolicy.DRIVER) {
      return error('what_if is for dispatchers.');
    }
    Integer delay = RoutingDtos.toInt(delayRaw);
    RoutePlanService.PlanContext ctx = RoutePlanService.buildRequest(
      route.Route_Plan__c
    );
    Set<String> excludedAssets = new Set<String>();
    for (Route__c r : [
      SELECT Fleet_Asset__c
      FROM Route__c
      WHERE Id IN :excludeRouteIds
      WITH USER_MODE
    ]) {
      excludedAssets.add(r.Fleet_Asset__c);
    }
    List<RoutingDtos.Vehicle> kept = new List<RoutingDtos.Vehicle>();
    for (RoutingDtos.Vehicle v : ctx.request.vehicles) {
      if (excludedAssets.contains(v.id)) {
        continue;
      }
      if (delay > 0) {
        v.shiftStart = v.shiftStart.addMinutes(delay);
      }
      kept.add(v);
    }
    ctx.request.vehicles = kept;
    if (kept.isEmpty()) {
      return error('No vehicle would be left to plan with.');
    }
    RoutingDtos.OptimizeResult result = RoutePlanService.provider(ctx.plan)
      .optimize(ctx.request);
    Route_Plan__c plan = [
      SELECT
        Total_Distance_Km__c,
        Total_Duration_Min__c,
        Unassigned_Count__c,
        (SELECT Id FROM Routes)
      FROM Route_Plan__c
      WHERE Id = :route.Route_Plan__c
      WITH USER_MODE
    ];
    AssistantTools.ToolResult r = ok(
      new Map<String, Object>{
        'saved' => false,
        'before' => new Map<String, Object>{
          'routes' => plan.Routes.size(),
          'unassigned' => plan.Unassigned_Count__c,
          'distanceKm' => plan.Total_Distance_Km__c,
          'durationMin' => plan.Total_Duration_Min__c
        },
        'after' => new Map<String, Object>{
          'routes' => result.routes.size(),
          'unassigned' => result.unassigned.size() +
          ctx.request.skippedJobs.size(),
          'distanceKm' => (Decimal.valueOf(result.summary.distanceM) / 1000)
            .setScale(1),
          'durationMin' => RoutePlanService.minutes(result.summary.durationS)
        },
        'unassignedReasons' => unassignedSummary(result)
      }
    );
    r.summary = 'Ran a what-if on the plan (nothing saved)';
    return r;
  }

  private static List<Object> unassignedSummary(
    RoutingDtos.OptimizeResult result
  ) {
    List<Object> out = new List<Object>();
    for (RoutingDtos.Unassigned u : result.unassigned) {
      out.add(
        new Map<String, Object>{
          'id' => u.id,
          'reason' => u.reason,
          'detail' => u.detail
        }
      );
    }
    return out;
  }

  // ---- propose_handoff ------------------------------------------------------------------------

  private static AssistantTools.ToolResult proposeHandoff(
    Id fromRouteId,
    String visitId,
    String toRouteId
  ) {
    Id vid = parseId(visitId, 'visit_id');
    Id toId = parseId(toRouteId, 'to_route_id');
    Route__c source = RouteReplanService.loadRoute(fromRouteId);
    if (RoutingPolicy.actorRole(source) == RoutingPolicy.DRIVER) {
      return error('Hand-offs are proposed by dispatchers.');
    }
    if (toId == fromRouteId) {
      return error('The visit is already on that route.');
    }
    Route__c target = RouteReplanService.loadRoute(toId);
    Date day = source.Route_Plan__r.Plan_Date__c == null
      ? Date.today()
      : source.Route_Plan__r.Plan_Date__c;
    RoutingPolicy.Decision d = RoutingPolicy.forHandoff(target, day);
    if (!d.allowed) {
      return error('Not allowed: ' + String.join(d.reasons, ' '));
    }
    Map<Id, Job_Visit__c> fromVisits = RouteReplanService.visits(
      fromRouteId,
      null
    );
    Job_Visit__c moving = fromVisits.get(vid);
    if (moving == null) {
      return error('Visit ' + visitId + ' is not on this route.');
    }
    Set<Id> moveIds = new Set<Id>();
    for (Job_Visit__c jv : fromVisits.values()) {
      if (jv.Route_Job__c == moving.Route_Job__c && jv.Status__c != 'Done') {
        moveIds.add(jv.Id);
      }
    }
    RouteReplanService.RouteContext fromCtx = RouteReplanService.buildRequest(
      fromRouteId,
      null,
      delayInTurn(fromRouteId),
      null,
      moveIds
    );
    RouteReplanService.RouteContext toCtx = RouteReplanService.buildRequest(
      toId,
      null,
      delayInTurn(toId),
      moveIds,
      null
    );
    RoutingDtos.OptimizeResult fromResult = fromCtx.request.taskCount() == 0
      ? new RoutingDtos.OptimizeResult()
      : RoutingProviders.forName(source.Route_Plan__r.Provider__c)
          .optimize(fromCtx.request);
    RoutingDtos.OptimizeResult toResult = RoutingProviders.forName(
        target.Route_Plan__r.Provider__c
      )
      .optimize(toCtx.request);
    Map<String, Object> toDiff = RouteReplanService.diff(toCtx, toResult);
    List<Object> late = (List<Object>) toDiff.get('late');
    for (Object o : (List<Object>) toDiff.get('unassigned')) {
      if (
        moveIds.contains(
          (Id) String.valueOf(((Map<String, Object>) o).get('id'))
        )
      ) {
        return error(
          target.Name +
            ' cannot take ' +
            RouteReplanService.label(moving) +
            ': ' +
            ((Map<String, Object>) o).get('detail')
        );
      }
    }
    pending.add(
      RouteEvents.event('Handoff Proposed', 'Assistant')
        .forPlan(source.Route_Plan__c)
        .forRoute(source.Id)
        .payload(
          new Map<String, Object>{
            'visitIds' => new List<Id>(moveIds),
            'toRouteId' => target.Id
          }
        )
    );
    AssistantTools.ToolResult r = proposal(
      'handoff',
      source,
      'Move ' +
        RouteReplanService.label(moving) +
        ' from ' +
        source.Name +
        ' to ' +
        target.Name,
      null,
      new List<Object>{
        change('Route', source.Name, target.Name),
        change(
          target.Name + ' order',
          String.join((List<String>) toDiff.get('before'), ' → '),
          String.join((List<String>) toDiff.get('after'), ' → ')
        ),
        change(
          'Late stops on ' + target.Name,
          '',
          late.isEmpty() ? 'None' : joinObjects(late)
        )
      },
      new Map<String, Object>{
        'fromRouteId' => source.Id,
        'toRouteId' => target.Id,
        'visitIds' => new List<Id>(moveIds),
        'fromRemainingIds' => idsOf(fromCtx.remaining),
        'toRemainingIds' => idsOf(toCtx.remaining),
        'fromResult' => RoutingDtos.toContractJson(fromResult),
        'toResult' => RoutingDtos.toContractJson(toResult),
        'diff' => toDiff
      },
      d
    );
    r.proposal.put('diff', toDiff);
    return r;
  }

  // ---------------------------------------------------------------------------------------------
  // Proposals
  // ---------------------------------------------------------------------------------------------

  private static AssistantTools.ToolResult proposal(
    String kind,
    Route__c route,
    String title,
    String reason,
    List<Object> changes,
    Map<String, Object> routing,
    RoutingPolicy.Decision decision
  ) {
    AssistantTools.ToolResult r = new AssistantTools.ToolResult();
    r.proposal = new Map<String, Object>{
      'action' => ACTION_PREFIX + kind,
      'objectApiName' => 'Route__c',
      'objectLabel' => 'Route',
      'recordId' => String.valueOf(route.Id),
      'recordName' => route.Name,
      'title' => title,
      'reason' => decision.approver == RoutingPolicy.DISPATCHER
        ? ((reason == null ? '' : reason + ' ') +
            'Needs a dispatcher: ' +
            String.join(decision.reasons, ' '))
            .trim()
        : reason,
      'changes' => changes,
      'routing' => routing,
      'approver' => decision.approver,
      'policy' => decision.toMap()
    };
    r.summary = 'Proposed: ' + title;
    r.content = 'Proposal shown to the user; waiting for their decision.';
    return r;
  }

  public static Boolean isRoutingProposal(Map<String, Object> proposal) {
    return proposal != null &&
      String.valueOf(proposal.get('action')).startsWith(ACTION_PREFIX);
  }

  /** Applies an approved routing proposal. DML only, in USER_MODE. */
  public static Map<String, Object> executeProposal(
    Map<String, Object> proposal,
    Id sessionId
  ) {
    String action = String.valueOf(proposal.get('action'))
      .removeStart(ACTION_PREFIX);
    Map<String, Object> routing = (Map<String, Object>) proposal.get('routing');
    Id routeId = (Id) String.valueOf(proposal.get('recordId'));
    Map<String, Object> outcome = new Map<String, Object>{
      'approved' => true,
      'action' => action,
      'objectApiName' => 'Route__c',
      'objectLabel' => 'Route',
      'recordId' => String.valueOf(routeId)
    };
    Savepoint sp = Database.setSavepoint();
    try {
      Route__c route = RouteReplanService.loadRoute(routeId);
      String blocked = RoutingPolicy.approvalError(
        String.valueOf(proposal.get('approver')),
        route
      );
      if (blocked != null) {
        outcome.put('success', false);
        outcome.put('error', blocked);
        return outcome;
      }
      String actor = RoutingPolicy.actorRole(route);
      switch on action {
        when 'update_window' {
          applyWindow(route, routing, sessionId, actor);
        }
        when 'skip_stop' {
          applySkip(route, routing, sessionId, actor);
        }
        when 'add_waypoint' {
          applyAddWaypoint(route, routing, sessionId, actor);
        }
        when 'reoptimize' {
          applyReoptimize(route, routing, sessionId, actor);
        }
        when 'handoff' {
          applyHandoff(route, routing, sessionId);
        }
        when else {
          throw new RoutingProviders.RoutingException(
            'Unknown routing proposal: ' + action
          );
        }
      }
      RoutePlanOptimizeJob.publish(
        route.Route_Plan__c,
        'Route Changed',
        route.Revision__c,
        action
      );
      outcome.put('success', true);
    } catch (Exception e) {
      Database.rollback(sp);
      outcome.put('success', false);
      outcome.put(
        'error',
        e instanceof DmlException
          ? ((DmlException) e).getDmlMessage(0)
          : e.getMessage()
      );
    }
    return outcome;
  }

  private static void applyWindow(
    Route__c route,
    Map<String, Object> routing,
    Id sessionId,
    String actor
  ) {
    Id vid = (Id) String.valueOf(routing.get('visitId'));
    Job_Visit__c before = RouteReplanService.visits(
        route.Id,
        new Set<Id>{ vid }
      )
      .get(vid);
    Database.update(
      new Job_Visit__c(
        Id = vid,
        Window_Start__c = RoutingDtos.dt(routing.get('start')),
        Window_End__c = RoutingDtos.dt(routing.get('end'))
      ),
      true,
      AccessLevel.USER_MODE
    );
    log(
      'Window Changed',
      actor,
      route,
      before == null ? null : before.Waypoint__c,
      sessionId,
      new Map<String, Object>{
        'visitId' => vid,
        'before' => before == null
          ? null
          : new List<Object>{
              RoutingDtos.iso(before.Window_Start__c),
              RoutingDtos.iso(before.Window_End__c)
            },
        'after' => new List<Object>{ routing.get('start'), routing.get('end') }
      }
    );
  }

  private static void applySkip(
    Route__c route,
    Map<String, Object> routing,
    Id sessionId,
    String actor
  ) {
    Id wid = (Id) String.valueOf(routing.get('waypointId'));
    Database.update(
      new Waypoint__c(
        Id = wid,
        Status__c = 'Skipped',
        Reason__c = String.valueOf(routing.get('reason')).abbreviate(255)
      ),
      true,
      AccessLevel.USER_MODE
    );
    List<Job_Visit__c> visits = new List<Job_Visit__c>();
    Map<Id, Route_Job__c> jobs = new Map<Id, Route_Job__c>();
    Map<Id, Job_Visit__c> known = RouteReplanService.visits(route.Id, null);
    for (Object o : (List<Object>) routing.get('visitIds')) {
      Id vid = (Id) String.valueOf(o);
      visits.add(
        new Job_Visit__c(Id = vid, Waypoint__c = null, Status__c = 'Pending')
      );
      if (known.containsKey(vid)) {
        Id jobId = known.get(vid).Route_Job__c;
        jobs.put(
          jobId,
          new Route_Job__c(
            Id = jobId,
            Status__c = 'Ready',
            Planned_Route__c = null,
            Unassigned_Reason__c = 'Skipped on the road'
          )
        );
      }
    }
    if (!visits.isEmpty()) {
      Database.update(visits, true, AccessLevel.USER_MODE);
    }
    if (!jobs.isEmpty()) {
      Database.update(jobs.values(), true, AccessLevel.USER_MODE);
    }
    log('Stop Skipped', actor, route, wid, sessionId, routing);
  }

  private static void applyAddWaypoint(
    Route__c route,
    Map<String, Object> routing,
    Id sessionId,
    String actor
  ) {
    Id afterId = (Id) String.valueOf(routing.get('afterWaypointId'));
    Integer minutes = RoutingDtos.toInt(routing.get('minutes'));
    String type = String.valueOf(routing.get('type'));
    List<Waypoint__c> all = RouteReplanService.waypoints(route.Id);
    Waypoint__c after;
    List<Waypoint__c> later = new List<Waypoint__c>();
    for (Waypoint__c w : all) {
      if (w.Id == afterId) {
        after = w;
      } else if (after != null) {
        later.add(w);
      }
    }
    if (after == null) {
      throw new RoutingProviders.RoutingException(
        'The stop to add after is no longer on the route.'
      );
    }
    Datetime arrive = after.Planned_Departure__c != null
      ? after.Planned_Departure__c
      : System.now();
    for (Waypoint__c w : later) {
      w.Sequence__c = w.Sequence__c + 1;
      if (!RouteReplanService.DONE_STATUSES.contains(w.Status__c)) {
        Datetime eta = w.ETA__c != null ? w.ETA__c : w.Planned_Arrival__c;
        if (eta != null) {
          w.ETA__c = eta.addMinutes(minutes);
          w.ETA_Updated_At__c = System.now();
        }
      }
    }
    if (!later.isEmpty()) {
      Database.update(later, true, AccessLevel.USER_MODE);
    }
    Waypoint__c added = new Waypoint__c(
      Route__c = route.Id,
      Sequence__c = after.Sequence__c + 1,
      Type__c = type,
      Status__c = 'Planned',
      Location__Latitude__s = after.Location__Latitude__s,
      Location__Longitude__s = after.Location__Longitude__s,
      Planned_Arrival__c = arrive,
      Planned_Departure__c = arrive.addMinutes(minutes),
      ETA__c = arrive,
      Service_Minutes__c = minutes,
      Leg_Distance_Km__c = 0,
      Leg_Duration_Min__c = 0,
      Reason__c = routing.get('reason') == null
        ? null
        : String.valueOf(routing.get('reason')).abbreviate(255)
    );
    Database.insert(added, true, AccessLevel.USER_MODE);
    log('Stop Added', actor, route, added.Id, sessionId, routing);
  }

  private static void applyReoptimize(
    Route__c route,
    Map<String, Object> routing,
    Id sessionId,
    String actor
  ) {
    RouteReplanService.RouteContext ctx = RouteReplanService.buildRequest(
      route.Id,
      ids(routing.get('lockedIds')),
      0,
      null,
      null
    );
    requireUnchanged(ctx, routing.get('remainingIds'));
    RoutingDtos.OptimizeResult result = RoutingDtos.parseOptimize(
      String.valueOf(routing.get('result'))
    );
    RouteReplanService.apply(ctx, result, sessionId, actor);
    log('Reoptimized', actor, route, null, sessionId, routing.get('diff'));
  }

  private static void applyHandoff(
    Route__c source,
    Map<String, Object> routing,
    Id sessionId
  ) {
    Set<Id> moveIds = ids(routing.get('visitIds'));
    Id toId = (Id) String.valueOf(routing.get('toRouteId'));
    RouteReplanService.RouteContext fromCtx = RouteReplanService.buildRequest(
      source.Id,
      null,
      0,
      null,
      moveIds
    );
    RouteReplanService.RouteContext toCtx = RouteReplanService.buildRequest(
      toId,
      null,
      0,
      moveIds,
      null
    );
    requireUnchanged(fromCtx, routing.get('fromRemainingIds'));
    requireUnchanged(toCtx, routing.get('toRemainingIds'));
    RouteReplanService.apply(
      fromCtx,
      RoutingDtos.parseOptimize(String.valueOf(routing.get('fromResult'))),
      sessionId,
      'Dispatcher'
    );
    RouteReplanService.apply(
      toCtx,
      RoutingDtos.parseOptimize(String.valueOf(routing.get('toResult'))),
      sessionId,
      'Dispatcher'
    );
    log(
      'Handoff Approved',
      'Dispatcher',
      source,
      null,
      sessionId,
      routing.get('diff')
    );
    log(
      'Handoff Approved',
      'Dispatcher',
      toCtx.route,
      null,
      sessionId,
      routing.get('diff')
    );
  }

  /** The solver result is only valid for the stops it was computed source. */
  private static void requireUnchanged(
    RouteReplanService.RouteContext ctx,
    Object storedIds
  ) {
    Set<Id> stored = ids(storedIds);
    Set<Id> now = new Set<Id>();
    for (Waypoint__c w : ctx.remaining) {
      now.add(w.Id);
    }
    if (!stored.equals(now)) {
      throw new RoutingProviders.RoutingException(
        'The route changed since this was proposed. Ask for a new re-plan.'
      );
    }
  }

  public static void logRejected(
    Map<String, Object> proposal,
    Id sessionId,
    String comment
  ) {
    try {
      Id routeId = (Id) String.valueOf(proposal.get('recordId'));
      Route__c route = RouteReplanService.loadRoute(routeId);
      log(
        'Proposal Rejected',
        RoutingPolicy.actorRole(route),
        route,
        null,
        sessionId,
        new Map<String, Object>{
          'action' => proposal.get('action'),
          'title' => proposal.get('title'),
          'comment' => comment
        }
      );
    } catch (Exception e) {
      // The decline itself must still go through; the audit line is best effort here.
      System.debug(
        LoggingLevel.WARN,
        'Could not log the rejected routing proposal: ' + e.getMessage()
      );
    }
  }

  private static void log(
    String type,
    String actor,
    Route__c route,
    Id waypointId,
    Id sessionId,
    Object payload
  ) {
    RouteEvents.log(
      RouteEvents.event(type, actor)
        .forPlan(route.Route_Plan__c)
        .forRoute(route.Id)
        .forWaypoint(waypointId)
        .session(sessionId)
        .payload(payload)
    );
  }

  /** Writes the events buffered during the turn (report_delay, Handoff Proposed). */
  public static void commitPending(Id sessionId) {
    if (pending.isEmpty()) {
      return;
    }
    for (RouteEvents.Builder b : pending) {
      b.session(sessionId);
    }
    RouteEvents.log(pending);
    pending.clear();
    pendingDelay.clear();
  }

  // ---------------------------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------------------------

  private static Waypoint__c findWaypoint(Id routeId, Id waypointId) {
    for (Waypoint__c w : RouteReplanService.waypoints(routeId)) {
      if (w.Id == waypointId) {
        return w;
      }
    }
    return null;
  }

  private static Map<String, Object> change(
    String label,
    Object current,
    Object proposed
  ) {
    return new Map<String, Object>{
      'apiName' => label,
      'label' => label,
      'type' => 'STRING',
      'current' => display(current),
      'proposed' => display(proposed)
    };
  }

  private static String display(Object v) {
    if (v == null) {
      return '';
    }
    if (v instanceof Datetime) {
      return ((Datetime) v).format('EEE HH:mm', UserInfo.getTimeZone().getID());
    }
    return String.valueOf(v);
  }

  private static List<Id> idsOf(List<Waypoint__c> rows) {
    List<Id> out = new List<Id>();
    for (Waypoint__c w : rows) {
      out.add(w.Id);
    }
    return out;
  }

  private static Set<Id> ids(Object o) {
    Set<Id> out = new Set<Id>();
    for (Object v : RoutingDtos.toList(o)) {
      if (v != null && String.isNotBlank(String.valueOf(v))) {
        out.add(parseId(String.valueOf(v), 'id'));
      }
    }
    return out;
  }

  private static Id parseId(String value, String name) {
    try {
      return Id.valueOf(value);
    } catch (Exception e) {
      throw new RoutingProviders.RoutingException(
        name + ' "' + value + '" is not a valid record Id.'
      );
    }
  }

  private static String joinObjects(List<Object> items) {
    List<String> out = new List<String>();
    for (Object o : items) {
      out.add(String.valueOf(o));
    }
    return String.join(out, ', ');
  }

  private static AssistantTools.ToolResult ok(Map<String, Object> payload) {
    AssistantTools.ToolResult r = new AssistantTools.ToolResult();
    String json = JSON.serialize(payload);
    if (json.length() > AssistantTools.MAX_RESULT_CHARS) {
      json =
        json.substring(0, AssistantTools.MAX_RESULT_CHARS) + '... [truncated]';
    }
    r.content = json;
    return r;
  }

  private static AssistantTools.ToolResult error(String message) {
    AssistantTools.ToolResult r = new AssistantTools.ToolResult();
    r.isError = true;
    r.content = message;
    r.summary =
      'Tool error: ' + (message == null ? '' : message.abbreviate(80));
    return r;
  }
}
