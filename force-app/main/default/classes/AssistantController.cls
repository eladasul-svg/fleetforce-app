/**
 * @AuraEnabled facade for the fleetforceAssistant LWC: connection status and API-key management
 * (through the Claude_API external credential principals), session lifecycle, and chat turns.
 */
public with sharing class AssistantController {

    private static final String EXTERNAL_CREDENTIAL = 'Claude_API';
    private static final String ORG_PRINCIPAL = 'Org';
    private static final String KEY_PARAMETER = 'ApiKey';

    public class Context {
        @AuraEnabled public Boolean orgConfigured;
        @AuraEnabled public Boolean userConfigured;
        @AuraEnabled public Boolean canManageOrg;
        @AuraEnabled public String userName;
        @AuraEnabled public String model;
        @AuraEnabled public List<SessionSummary> sessions;
    }

    public class SessionSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public DateTime lastActivity;
    }

    public class SessionDetail {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public List<MessageView> messages = new List<MessageView>();
        @AuraEnabled public Map<String, Object> proposal;
        @AuraEnabled public Boolean awaitingContinue = false;
    }

    public class MessageView {
        @AuraEnabled public String role;
        @AuraEnabled public String text;
    }

    // ---------------------------------------------------------------------------------------------
    // Connection
    // ---------------------------------------------------------------------------------------------

    @AuraEnabled
    public static Context getContext() {
        try {
            Context c = new Context();
            c.orgConfigured = isConfigured(ConnectApi.CredentialPrincipalType.NamedPrincipal, ORG_PRINCIPAL);
            c.userConfigured = AssistantClaudeClient.hasUserKey();
            c.canManageOrg = canManageOrg();
            c.userName = UserInfo.getFirstName() != null ? UserInfo.getFirstName() : UserInfo.getName();
            c.model = AssistantClaudeClient.getModel();
            c.sessions = recentSessions();
            return c;
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    @AuraEnabled
    public static void saveApiKey(String scope, String apiKey) {
        try {
            if (String.isBlank(apiKey) || apiKey.trim().length() < 20) {
                throw new AssistantService.AssistantException('That does not look like an Anthropic API key.');
            }
            if (scope != 'org') {
                // Personal key: protected hierarchy custom setting, one record per user.
                Assistant_User_Setting__c s = Assistant_User_Setting__c.getValues(UserInfo.getUserId());
                if (s == null) {
                    s = new Assistant_User_Setting__c(SetupOwnerId = UserInfo.getUserId());
                }
                s.Api_Key__c = apiKey.trim();
                upsert s;
                return;
            }

            if (!canManageOrg()) {
                throw new AssistantService.AssistantException('Only administrators can set the organization key.');
            }
            ConnectApi.CredentialPrincipalType type = ConnectApi.CredentialPrincipalType.NamedPrincipal;
            ConnectApi.CredentialValueInput value = new ConnectApi.CredentialValueInput();
            value.value = apiKey.trim();
            value.encrypted = true;

            Exception last;
            for (String credName : credentialNames()) {
                ConnectApi.CredentialInput input = new ConnectApi.CredentialInput();
                input.externalCredential = credName;
                input.principalType = type;
                input.principalName = ORG_PRINCIPAL;
                input.authenticationProtocol = ConnectApi.CredentialAuthenticationProtocol.Custom;
                input.credentials = new Map<String, ConnectApi.CredentialValueInput>{ KEY_PARAMETER => value };
                try {
                    if (isConfigured(type, ORG_PRINCIPAL)) {
                        ConnectApi.NamedCredentials.updateCredential(input);
                    } else {
                        ConnectApi.NamedCredentials.createCredential(input);
                    }
                    return;
                } catch (Exception e) {
                    last = e;
                }
            }
            throw new AssistantService.AssistantException('Could not save the key: ' + (last == null ? 'unknown error' : last.getMessage()));
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    @AuraEnabled
    public static void clearUserKey() {
        try {
            Assistant_User_Setting__c s = Assistant_User_Setting__c.getValues(UserInfo.getUserId());
            if (s != null) {
                delete s;
            }
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    private static Boolean isConfigured(ConnectApi.CredentialPrincipalType type, String principal) {
        for (String credName : credentialNames()) {
            try {
                ConnectApi.Credential c = ConnectApi.NamedCredentials.getCredential(credName, principal, type);
                return c != null && c.credentials != null && c.credentials.containsKey(KEY_PARAMETER);
            } catch (Exception e) {
                continue;
            }
        }
        return false;
    }

    /** Namespace-qualified name first (subscriber orgs), bare name as fallback (namespace-owning org). */
    private static List<String> credentialNames() {
        String prefix = AssistantClaudeClient.namespacePrefix();
        List<String> names = new List<String>();
        if (prefix != '') {
            names.add(prefix + EXTERNAL_CREDENTIAL);
        }
        names.add(EXTERNAL_CREDENTIAL);
        return names;
    }

    private static Boolean canManageOrg() {
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.PermissionsModifyAllData = true
        ] > 0;
    }

    // ---------------------------------------------------------------------------------------------
    // Sessions
    // ---------------------------------------------------------------------------------------------

    @AuraEnabled
    public static Id startSession(String recordId, String objectApiName) {
        try {
            Assistant_Session__c s = new Assistant_Session__c(
                Record_Id__c = String.isBlank(recordId) ? null : recordId,
                Record_Object__c = String.isBlank(objectApiName) ? null : objectApiName,
                Last_Activity__c = System.now()
            );
            Database.insert(s, true, AccessLevel.USER_MODE);
            return s.Id;
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    @AuraEnabled
    public static SessionDetail getSession(Id sessionId) {
        try {
            Assistant_Session__c s = AssistantService.loadSession(sessionId);
            SessionDetail d = new SessionDetail();
            d.id = s.Id;
            d.title = s.Title__c;
            List<Assistant_Message__c> msgs = AssistantService.loadMessages(sessionId);
            for (Assistant_Message__c m : msgs) {
                String text = AssistantService.textOf((List<Object>) JSON.deserializeUntyped(m.Content__c));
                if (String.isBlank(text)) {
                    continue;
                }
                MessageView v = new MessageView();
                v.role = m.Role__c;
                v.text = text;
                d.messages.add(v);
            }
            if (String.isNotBlank(s.Pending_Proposal__c)) {
                d.proposal = (Map<String, Object>) JSON.deserializeUntyped(s.Pending_Proposal__c);
            } else if (!msgs.isEmpty() && msgs[msgs.size() - 1].Role__c == 'user') {
                d.awaitingContinue = true;
            }
            return d;
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    @AuraEnabled
    public static void deleteSession(Id sessionId) {
        try {
            Database.delete(AssistantService.loadSession(sessionId), true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    private static List<SessionSummary> recentSessions() {
        List<SessionSummary> out = new List<SessionSummary>();
        for (Assistant_Session__c s : [
            SELECT Id, Title__c, Last_Activity__c
            FROM Assistant_Session__c
            WHERE Title__c != null
            WITH USER_MODE
            ORDER BY Last_Activity__c DESC NULLS LAST
            LIMIT 10
        ]) {
            SessionSummary v = new SessionSummary();
            v.id = s.Id;
            v.title = s.Title__c;
            v.lastActivity = s.Last_Activity__c;
            out.add(v);
        }
        return out;
    }

    // ---------------------------------------------------------------------------------------------
    // Turns
    // ---------------------------------------------------------------------------------------------

    @AuraEnabled
    public static AssistantService.TurnResult sendMessage(Id sessionId, String text) {
        try {
            return AssistantService.sendMessage(sessionId, text);
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    @AuraEnabled
    public static AssistantService.TurnResult continueTurn(Id sessionId) {
        try {
            return AssistantService.continueTurn(sessionId);
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    @AuraEnabled
    public static AssistantService.TurnResult resolveProposal(Id sessionId, Boolean approved, String comment) {
        try {
            return AssistantService.resolveProposal(sessionId, approved, comment);
        } catch (Exception e) {
            throw wrap(e);
        }
    }

    private static AuraHandledException wrap(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        AuraHandledException ex = new AuraHandledException(e.getMessage());
        ex.setMessage(e.getMessage());
        return ex;
    }
}
