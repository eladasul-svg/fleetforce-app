/**
 * The routing tools as an invocable action, so a customer with Agentforce can build a "FleetForce
 * Dispatcher" agent on the same logic and policy as the built-in assistant.
 *
 * Salesforce allows one @InvocableMethod per class, so the eight tools share one action with a tool
 * name and JSON input (the same input schema the assistant gets). Tools that change a route return a
 * proposal; call again with approveProposalJson set to apply it, after the agent has confirmed with
 * the user. RoutingPolicy decides, at approval, whether the running user may approve it.
 */
public with sharing class RoutingActions {
  public class Request {
    @InvocableVariable(
      label='Tool'
      description='get_route, report_delay, update_window, skip_stop, add_waypoint, reoptimize_remaining, what_if or propose_handoff'
      required=true
    )
    public String toolName;

    @InvocableVariable(
      label='Route Id'
      description='The route the tool works on'
      required=true
    )
    public Id routeId;

    @InvocableVariable(
      label='Input (JSON)'
      description='Tool input as a JSON object, e.g. {"minutes": 40}'
    )
    public String inputJson;

    @InvocableVariable(
      label='Approve proposal (JSON)'
      description='A proposal returned by an earlier call. When set, the proposal is applied instead of running the tool.'
    )
    public String approveProposalJson;
  }

  public class Result {
    @InvocableVariable(label='Success')
    public Boolean success = true;
    @InvocableVariable(label='Message')
    public String message;
    @InvocableVariable(label='Result (JSON)')
    public String resultJson;
    @InvocableVariable(
      label='Proposal (JSON)'
      description='Present when the tool proposes a change'
    )
    public String proposalJson;
    @InvocableVariable(
      label='Approver'
      description='Driver or Dispatcher: who may approve the proposal'
    )
    public String approver;
  }

  @InvocableMethod(
    label='FleetForce Routing Tool'
    description='Read a route, report a delay, or propose and apply route changes through the FleetForce routing solver and policy.'
    category='FleetForce Routing'
  )
  public static List<Result> run(List<Request> requests) {
    List<Result> results = new List<Result>();
    // Tools first (they may call the solver), then approvals and buffered events (DML).
    Map<Integer, Request> approvals = new Map<Integer, Request>();
    for (Integer i = 0; i < requests.size(); i++) {
      Request req = requests[i];
      Result res = new Result();
      results.add(res);
      if (String.isNotBlank(req.approveProposalJson)) {
        approvals.put(i, req);
        continue;
      }
      if (!RoutingAssistantTools.handles(req.toolName)) {
        res.success = false;
        res.message = 'Unknown routing tool: ' + req.toolName;
        continue;
      }
      Map<String, Object> input;
      try {
        input = String.isBlank(req.inputJson)
          ? new Map<String, Object>()
          : (Map<String, Object>) JSON.deserializeUntyped(req.inputJson);
      } catch (Exception e) {
        res.success = false;
        res.message = 'inputJson must be a JSON object.';
        continue;
      }
      AssistantTools.ToolResult tr = RoutingAssistantTools.execute(
        req.toolName,
        input,
        new Assistant_Session__c(Record_Id__c = req.routeId)
      );
      res.success = !tr.isError;
      res.message = tr.summary;
      if (tr.proposal != null) {
        res.proposalJson = JSON.serialize(tr.proposal);
        res.approver = String.valueOf(tr.proposal.get('approver'));
        res.message = tr.summary + ' (needs approval by: ' + res.approver + ')';
      } else {
        res.resultJson = tr.content;
        if (tr.isError) {
          res.message = tr.content;
        }
      }
    }
    RoutingAssistantTools.commitPending(null);
    for (Integer i : approvals.keySet()) {
      Result res = results[i];
      try {
        Map<String, Object> proposal = (Map<String, Object>) JSON.deserializeUntyped(
          approvals.get(i).approveProposalJson
        );
        if (!RoutingAssistantTools.isRoutingProposal(proposal)) {
          throw new RoutingProviders.RoutingException(
            'That is not a routing proposal.'
          );
        }
        Map<String, Object> outcome = RoutingAssistantTools.executeProposal(
          proposal,
          null
        );
        res.success = outcome.get('success') == true;
        res.message = res.success
          ? 'Applied: ' + proposal.get('title')
          : String.valueOf(outcome.get('error'));
        res.resultJson = JSON.serialize(outcome);
      } catch (Exception e) {
        res.success = false;
        res.message = e.getMessage();
      }
    }
    return results;
  }
}
