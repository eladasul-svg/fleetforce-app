/**
 * Thin HTTP client for the Claude Messages API, called through the Claude_API named credential.
 * The named credential injects the x-api-key header from whichever principal applies to the
 * running user (their own key if they saved one, otherwise the org-wide key).
 */
public with sharing class AssistantClaudeClient {

    public class ClaudeException extends Exception {}

    @TestVisible private static String model = 'claude-opus-5';
    private static final String API_VERSION = '2023-06-01';
    @TestVisible private static final String DIRECT_ENDPOINT = 'https://api.anthropic.com/v1/messages';
    // Server-side refusal fallback: if Claude Opus 5 declines a request on policy grounds,
    // the API re-runs it on the default fallback model inside the same call.
    private static final String BETAS = 'server-side-fallback-2026-07-01';

    public static String getModel() {
        return model;
    }

    /** Named credential developer name, namespace-qualified when this class runs from the package. */
    public static String namedCredentialName() {
        return namespacePrefix() + 'Claude_API';
    }

    public static String namespacePrefix() {
        String cls = AssistantClaudeClient.class.getName();
        return cls.contains('.') ? cls.substringBefore('.') + '__' : '';
    }

    /** The user's own key from the protected custom setting, or null when they rely on the org connection. */
    public static String userKey() {
        Assistant_User_Setting__c s = Assistant_User_Setting__c.getValues(UserInfo.getUserId());
        return s == null || String.isBlank(s.Api_Key__c) ? null : s.Api_Key__c;
    }

    public static Boolean hasUserKey() {
        return userKey() != null;
    }

    public static Map<String, Object> send(Map<String, Object> body) {
        HttpRequest req = new HttpRequest();
        String key = userKey();
        if (key != null) {
            req.setEndpoint(DIRECT_ENDPOINT);
            req.setHeader('x-api-key', key);
        } else {
            req.setEndpoint('callout:' + namedCredentialName() + '/v1/messages');
        }
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('anthropic-version', API_VERSION);
        req.setHeader('anthropic-beta', BETAS);
        req.setTimeout(120000);
        req.setBody(JSON.serialize(body));

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (CalloutException e) {
            throw new ClaudeException('Could not reach Claude: ' + e.getMessage());
        }

        if (res.getStatusCode() == 200) {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        }
        throw new ClaudeException(describeError(res.getStatusCode(), res.getBody()));
    }

    @TestVisible
    private static String describeError(Integer code, String body) {
        String detail = body;
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(body);
            Map<String, Object> err = (Map<String, Object>) parsed.get('error');
            if (err != null && err.get('message') != null) {
                detail = (String) err.get('message');
            }
        } catch (Exception ignored) {}

        if (code == 401) {
            return 'Claude rejected the API key. Open the connection settings and check the key.';
        }
        if (code == 403) {
            return 'This API key is not allowed to use the requested model: ' + detail;
        }
        if (code == 429) {
            return 'Claude is rate-limited right now. Please try again in a moment.';
        }
        if (code == 529 || code >= 500) {
            return 'Claude is temporarily unavailable (' + code + '). Please try again.';
        }
        return 'Claude returned an error (' + code + '): ' + detail;
    }
}
