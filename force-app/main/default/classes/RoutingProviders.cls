/**
 * Picks the RoutingProvider for a plan (Route_Plan__c.Provider__c) and holds what the providers share:
 * the namespace-safe named credential names, the HTTP call, and the exception type.
 */
public with sharing class RoutingProviders {
  public class RoutingException extends Exception {
  }

  public static final Integer TIMEOUT_MS = 120000;

  /** Tests and demos can force a provider for the whole transaction. */
  @TestVisible
  private static RoutingProvider forced;

  public static RoutingProvider forName(String providerName) {
    if (forced != null) {
      return forced;
    }
    switch on providerName {
      when 'Openrouteservice' {
        return new OrsRoutingProvider();
      }
      when 'Mock' {
        return new MockRoutingProvider();
      }
      when 'Google' {
        throw new RoutingException(
          'The Google Route Optimization provider is not available yet. Use FleetForce Routing.'
        );
      }
      when else {
        return new FleetForceRoutingProvider();
      }
    }
  }

  public static void useForTest(RoutingProvider provider) {
    forced = provider;
  }

  /** Named credential developer name, namespace-qualified when running from the package. */
  public static String namedCredential(String developerName) {
    return AssistantClaudeClient.namespacePrefix() + developerName;
  }

  /** One JSON POST (or GET when body is null). Throws RoutingException on anything but 200. */
  public static String send(
    String endpoint,
    String body,
    Map<String, String> headers
  ) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint);
    req.setMethod(body == null ? 'GET' : 'POST');
    req.setHeader('Content-Type', 'application/json');
    req.setHeader('Accept', 'application/json');
    if (headers != null) {
      for (String h : headers.keySet()) {
        req.setHeader(h, headers.get(h));
      }
    }
    req.setTimeout(TIMEOUT_MS);
    if (body != null) {
      req.setBody(body);
    }
    HttpResponse res;
    try {
      res = new Http().send(req);
    } catch (CalloutException e) {
      throw new RoutingException(
        'Could not reach the routing service: ' + e.getMessage()
      );
    }
    if (res.getStatusCode() == 200) {
      return res.getBody();
    }
    throw new RoutingException(
      describeError(res.getStatusCode(), res.getBody())
    );
  }

  @TestVisible
  private static String describeError(Integer code, String body) {
    String detail = body == null ? '' : body.abbreviate(500);
    try {
      Object parsed = JSON.deserializeUntyped(body);
      if (parsed instanceof Map<String, Object>) {
        Object d = ((Map<String, Object>) parsed).get('detail');
        if (d == null) {
          d = ((Map<String, Object>) parsed).get('error');
        }
        if (d != null) {
          detail = (d instanceof String ? (String) d : JSON.serialize(d))
            .abbreviate(500);
        }
      }
    } catch (Exception ignored) {
    }
    if (code == 401 || code == 403) {
      return 'The routing service rejected the key (' +
        code +
        '). Check the routing connection settings.';
    }
    if (code == 422 || code == 400) {
      return 'The routing service could not use the plan (' +
        code +
        '): ' +
        detail;
    }
    if (code == 429) {
      return 'The routing service is rate-limited right now. Try again in a moment.';
    }
    if (code >= 500) {
      return 'The routing service is temporarily unavailable (' +
        code +
        '). Try again.';
    }
    return 'The routing service returned an error (' + code + '): ' + detail;
  }
}
