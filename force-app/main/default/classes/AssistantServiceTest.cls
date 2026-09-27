@IsTest
public class AssistantServiceTest {

    // ---------------------------------------------------------------------------------------------
    // Mock Claude
    // ---------------------------------------------------------------------------------------------

    private class ClaudeMock implements HttpCalloutMock {
        List<String> bodies;
        List<Integer> codes;
        Integer calls = 0;
        String lastRequestBody;
        String lastEndpoint;
        Map<String, String> lastHeaders = new Map<String, String>();

        ClaudeMock(String body) {
            this(new List<String>{ body }, new List<Integer>{ 200 });
        }
        ClaudeMock(List<String> bodies, List<Integer> codes) {
            this.bodies = bodies;
            this.codes = codes;
        }
        public HttpResponse respond(HttpRequest req) {
            Integer i = Math.min(calls, bodies.size() - 1);
            calls++;
            lastRequestBody = req.getBody();
            lastEndpoint = req.getEndpoint();
            lastHeaders.put('anthropic-version', req.getHeader('anthropic-version'));
            lastHeaders.put('anthropic-beta', req.getHeader('anthropic-beta'));
            lastHeaders.put('x-api-key', req.getHeader('x-api-key'));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(codes[i]);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(bodies[i]);
            return res;
        }
    }

    private static String response(List<Object> content, String stopReason) {
        return JSON.serialize(new Map<String, Object>{
            'id' => 'msg_test', 'type' => 'message', 'role' => 'assistant', 'model' => 'claude-opus-5',
            'content' => content, 'stop_reason' => stopReason,
            'usage' => new Map<String, Object>{ 'input_tokens' => 120, 'output_tokens' => 40 }
        });
    }

    private static String textResponse(String text) {
        return response(new List<Object>{ textBlock(text) }, 'end_turn');
    }

    private static String toolUseResponse(String toolName, Map<String, Object> input) {
        return response(new List<Object>{
            textBlock('Let me check.'),
            new Map<String, Object>{ 'type' => 'tool_use', 'id' => 'toolu_1', 'name' => toolName, 'input' => input }
        }, 'tool_use');
    }

    private static Map<String, Object> textBlock(String text) {
        return new Map<String, Object>{ 'type' => 'text', 'text' => text };
    }

    // ---------------------------------------------------------------------------------------------
    // Data
    // ---------------------------------------------------------------------------------------------

    @TestSetup
    static void makeData() {
        grantAssistantAccess();
        insert new Account(Name = 'Service Vendor');
    }

    // The session objects are only reachable in USER_MODE through the FleetForce Assistant permission
    // set. A permission set assigned in @TestSetup is not picked up by USER_MODE checks later in the
    // same test unless the SUT call itself runs inside a fresh System.runAs(self) block - re-entering
    // as the same user forces Salesforce to rebuild the permission context. See asSelf() below.
    public static void grantAssistantAccess() {
        Id userId = UserInfo.getUserId();
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'FleetforceAssistantUser' LIMIT 1];
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSetId = :ps.Id] == 0) {
            System.runAs(new User(Id = userId)) {
                insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
            }
        }
    }

    private static User asSelfUser() {
        return new User(Id = UserInfo.getUserId());
    }

    private static Assistant_Session__c newSession() {
        Assistant_Session__c s = new Assistant_Session__c(Last_Activity__c = System.now());
        insert s;
        return s;
    }

    private static Assistant_Message__c msg(Id sessionId, String role, List<Object> content, Integer seq) {
        return new Assistant_Message__c(Session__c = sessionId, Role__c = role, Content__c = JSON.serialize(content), Sequence__c = seq);
    }

    private static List<Assistant_Message__c> messagesOf(Id sessionId) {
        return [SELECT Role__c, Content__c, Sequence__c, Input_Tokens__c, Output_Tokens__c FROM Assistant_Message__c WHERE Session__c = :sessionId ORDER BY Sequence__c];
    }

    // ---------------------------------------------------------------------------------------------
    // Tests
    // ---------------------------------------------------------------------------------------------

    @IsTest
    static void sendMessageStoresTurnAndSetsTitle() {
        Assistant_Session__c s = newSession();
        ClaudeMock mock = new ClaudeMock(textResponse('You have **3** assets.'));
        Test.setMock(HttpCalloutMock.class, mock);

        AssistantService.TurnResult r;
        Test.startTest();
        System.runAs(asSelfUser()) {
            r = AssistantService.sendMessage(s.Id, 'How many assets do I have?');
        }
        Test.stopTest();

        System.assertEquals('text', r.kind);
        System.assertEquals('You have **3** assets.', r.text);
        System.assertEquals(false, r.truncated);

        List<Assistant_Message__c> msgs = messagesOf(s.Id);
        System.assertEquals(2, msgs.size());
        System.assertEquals('user', msgs[0].Role__c);
        System.assertEquals('assistant', msgs[1].Role__c);
        System.assertEquals(120, msgs[1].Input_Tokens__c);
        System.assertEquals(40, msgs[1].Output_Tokens__c);
        System.assertEquals('How many assets do I have?', [SELECT Title__c FROM Assistant_Session__c WHERE Id = :s.Id].Title__c);

        Map<String, Object> req = (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequestBody);
        System.assertEquals('claude-opus-5', req.get('model'));
        System.assertEquals('default', req.get('fallbacks'));
        System.assertEquals(6, ((List<Object>) req.get('tools')).size());
        List<Object> systemBlocks = (List<Object>) req.get('system');
        System.assert(((Map<String, Object>) systemBlocks[0]).containsKey('cache_control'), 'stable prompt should be cached');
        System.assert(((String) ((Map<String, Object>) systemBlocks[1]).get('text')).contains(UserInfo.getName()));
        System.assertEquals('2023-06-01', mock.lastHeaders.get('anthropic-version'));
        System.assert(mock.lastHeaders.get('anthropic-beta').contains('server-side-fallback'));
        System.assert(mock.lastEndpoint.startsWith('callout:'), 'org connection goes through the named credential: ' + mock.lastEndpoint);
        System.assertEquals(null, mock.lastHeaders.get('x-api-key'), 'the named credential injects the org key');
    }

    @IsTest
    static void personalKeyCallsAnthropicDirectly() {
        insert new Assistant_User_Setting__c(SetupOwnerId = UserInfo.getUserId(), Api_Key__c = 'sk-ant-personal-test-key-000');
        Assistant_Session__c s = newSession();
        ClaudeMock mock = new ClaudeMock(textResponse('Hi'));
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.runAs(asSelfUser()) {
            AssistantService.sendMessage(s.Id, 'Hello');
        }
        Test.stopTest();

        System.assertEquals(AssistantClaudeClient.DIRECT_ENDPOINT, mock.lastEndpoint);
        System.assertEquals('sk-ant-personal-test-key-000', mock.lastHeaders.get('x-api-key'));
        System.assert(AssistantClaudeClient.hasUserKey());
    }

    @IsTest
    static void toolUseExecutesToolAndReturnsToolStep() {
        Assistant_Session__c s = newSession();
        Test.setMock(HttpCalloutMock.class, new ClaudeMock(toolUseResponse('query_records',
            new Map<String, Object>{ 'soql' => 'SELECT Id, Name FROM Account' })));

        AssistantService.TurnResult r;
        Test.startTest();
        System.runAs(asSelfUser()) {
            r = AssistantService.sendMessage(s.Id, 'List accounts');
        }
        Test.stopTest();

        System.assertEquals('tool_step', r.kind);
        System.assertEquals('Let me check.', r.text);
        System.assertEquals(1, r.steps.size());
        System.assert(r.steps[0].startsWith('Queried'), r.steps[0]);

        List<Assistant_Message__c> msgs = messagesOf(s.Id);
        System.assertEquals(3, msgs.size());
        System.assertEquals('user', msgs[2].Role__c);
        Map<String, Object> result = (Map<String, Object>) ((List<Object>) JSON.deserializeUntyped(msgs[2].Content__c))[0];
        System.assertEquals('tool_result', result.get('type'));
        System.assertEquals('toolu_1', result.get('tool_use_id'));
        System.assert(!result.containsKey('is_error'));
        System.assert(((String) result.get('content')).contains('Service Vendor'));
    }

    @IsTest
    static void toolErrorIsFedBackAsErrorResult() {
        Assistant_Session__c s = newSession();
        Test.setMock(HttpCalloutMock.class, new ClaudeMock(toolUseResponse('query_records',
            new Map<String, Object>{ 'soql' => 'DELETE FROM Account' })));

        AssistantService.TurnResult r;
        Test.startTest();
        System.runAs(asSelfUser()) {
            r = AssistantService.sendMessage(s.Id, 'Delete everything');
        }
        Test.stopTest();

        System.assertEquals('tool_step', r.kind);
        List<Assistant_Message__c> msgs = messagesOf(s.Id);
        Map<String, Object> result = (Map<String, Object>) ((List<Object>) JSON.deserializeUntyped(msgs[2].Content__c))[0];
        System.assertEquals(true, result.get('is_error'));
    }

    @IsTest
    static void continueTurnSendsHistoryAndFinishes() {
        Assistant_Session__c s = newSession();
        insert new List<Assistant_Message__c>{
            msg(s.Id, 'user', new List<Object>{ textBlock('List accounts') }, 1),
            msg(s.Id, 'assistant', new List<Object>{
                new Map<String, Object>{ 'type' => 'tool_use', 'id' => 'toolu_1', 'name' => 'query_records', 'input' => new Map<String, Object>{ 'soql' => 'SELECT Id FROM Account' } }
            }, 2),
            msg(s.Id, 'user', new List<Object>{
                new Map<String, Object>{ 'type' => 'tool_result', 'tool_use_id' => 'toolu_1', 'content' => '{"count":1}' }
            }, 3)
        };
        ClaudeMock mock = new ClaudeMock(textResponse('There is one account.'));
        Test.setMock(HttpCalloutMock.class, mock);

        AssistantService.TurnResult r;
        Test.startTest();
        System.runAs(asSelfUser()) {
            r = AssistantService.continueTurn(s.Id);
        }
        Test.stopTest();

        System.assertEquals('text', r.kind);
        System.assertEquals(4, messagesOf(s.Id).size());
        Map<String, Object> req = (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequestBody);
        System.assertEquals(3, ((List<Object>) req.get('messages')).size());
    }

    @IsTest
    static void continueTurnRejectsBadStates() {
        Assistant_Session__c empty = newSession();
        Boolean threw = false;
        System.runAs(asSelfUser()) {
            try {
                AssistantService.continueTurn(empty.Id);
            } catch (AssistantService.AssistantException e) {
                threw = true;
            }
        }
        System.assert(threw, 'nothing to continue should throw');

        Assistant_Session__c pending = newSession();
        pending.Pending_Proposal__c = '{"toolUseId":"x"}';
        update pending;
        threw = false;
        System.runAs(asSelfUser()) {
            try {
                AssistantService.continueTurn(pending.Id);
            } catch (AssistantService.AssistantException e) {
                threw = true;
            }
        }
        System.assert(threw, 'pending proposal should block continue');
    }

    @IsTest
    static void proposalPausesTurnAndApprovalAppliesIt() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Assistant_Session__c s = newSession();
        Test.setMock(HttpCalloutMock.class, new ClaudeMock(toolUseResponse('propose_update', new Map<String, Object>{
            'recordId' => a.Id, 'fields' => new Map<String, Object>{ 'Name' => 'Approved Vendor' }, 'reason' => 'You asked to rename it.'
        })));

        AssistantService.TurnResult r;
        Test.startTest();
        System.runAs(asSelfUser()) {
            r = AssistantService.sendMessage(s.Id, 'Rename the vendor');
        }
        Test.stopTest();

        System.assertEquals('proposal', r.kind);
        System.assertEquals('update', r.proposal.get('action'));
        System.assertEquals('toolu_1', r.proposal.get('toolUseId'));
        System.assertEquals(1, r.steps.size());
        System.assert(String.isNotBlank([SELECT Pending_Proposal__c FROM Assistant_Session__c WHERE Id = :s.Id].Pending_Proposal__c));
        System.assertEquals(2, messagesOf(s.Id).size(), 'no tool_result yet');

        AssistantService.TurnResult decided;
        System.runAs(asSelfUser()) {
            decided = AssistantService.resolveProposal(s.Id, true, null);
        }
        System.assertEquals('tool_step', decided.kind);
        System.assertEquals(true, decided.outcome.get('success'));
        System.assertEquals('Updated Account', decided.steps[0]);
        System.assertEquals('Approved Vendor', [SELECT Name FROM Account WHERE Id = :a.Id].Name);

        Assistant_Session__c after = [SELECT Pending_Proposal__c FROM Assistant_Session__c WHERE Id = :s.Id];
        System.assertEquals(null, after.Pending_Proposal__c);
        List<Assistant_Message__c> msgs = messagesOf(s.Id);
        System.assertEquals(3, msgs.size());
        Map<String, Object> resultBlock = (Map<String, Object>) ((List<Object>) JSON.deserializeUntyped(msgs[2].Content__c))[0];
        System.assertEquals('toolu_1', resultBlock.get('tool_use_id'));
        Map<String, Object> reported = (Map<String, Object>) JSON.deserializeUntyped((String) resultBlock.get('content'));
        System.assertEquals(true, reported.get('success'));
        System.assertEquals(String.valueOf(a.Id), reported.get('recordId'));
    }

    @IsTest
    static void decliningProposalRecordsComment() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Assistant_Session__c s = newSession();
        Test.setMock(HttpCalloutMock.class, new ClaudeMock(toolUseResponse('propose_update', new Map<String, Object>{
            'recordId' => a.Id, 'fields' => new Map<String, Object>{ 'Name' => 'Nope' }
        })));

        Test.startTest();
        System.runAs(asSelfUser()) {
            AssistantService.sendMessage(s.Id, 'Rename the vendor');
        }
        Test.stopTest();

        AssistantService.TurnResult decided;
        System.runAs(asSelfUser()) {
            decided = AssistantService.resolveProposal(s.Id, false, 'keep the old name');
        }
        System.assertEquals(false, decided.outcome.get('approved'));
        System.assert(decided.steps[0].startsWith('Declined'));
        System.assertEquals('Service Vendor', [SELECT Name FROM Account WHERE Id = :a.Id].Name);
        System.assert(messagesOf(s.Id)[2].Content__c.contains('keep the old name'));

        Boolean threw = false;
        System.runAs(asSelfUser()) {
            try {
                AssistantService.resolveProposal(s.Id, true, null);
            } catch (AssistantService.AssistantException e) {
                threw = true;
            }
        }
        System.assert(threw, 'second resolve should fail');
    }

    @IsTest
    static void newMessageWhilePendingDeclinesProposalFirst() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Assistant_Session__c s = newSession();
        insert new List<Assistant_Message__c>{
            msg(s.Id, 'user', new List<Object>{ textBlock('Rename it') }, 1),
            msg(s.Id, 'assistant', new List<Object>{
                new Map<String, Object>{ 'type' => 'tool_use', 'id' => 'toolu_9', 'name' => 'propose_update', 'input' => new Map<String, Object>() }
            }, 2)
        };
        s.Pending_Proposal__c = JSON.serialize(new Map<String, Object>{
            'toolUseId' => 'toolu_9', 'action' => 'update', 'objectApiName' => 'Account', 'objectLabel' => 'Account',
            'recordId' => a.Id, 'changes' => new List<Object>(), 'otherResults' => new List<Object>()
        });
        update s;
        Test.setMock(HttpCalloutMock.class, new ClaudeMock(textResponse('Okay, moving on.')));

        AssistantService.TurnResult r;
        Test.startTest();
        System.runAs(asSelfUser()) {
            r = AssistantService.sendMessage(s.Id, 'Actually, never mind');
        }
        Test.stopTest();

        System.assertEquals('text', r.kind);
        System.assertEquals('Proposal declined', r.steps[0]);
        List<Assistant_Message__c> msgs = messagesOf(s.Id);
        System.assertEquals(4, msgs.size());
        List<Object> blocks = (List<Object>) JSON.deserializeUntyped(msgs[2].Content__c);
        System.assertEquals(2, blocks.size());
        System.assertEquals('tool_result', ((Map<String, Object>) blocks[0]).get('type'));
        System.assertEquals('text', ((Map<String, Object>) blocks[1]).get('type'));
        System.assertEquals(null, [SELECT Pending_Proposal__c FROM Assistant_Session__c WHERE Id = :s.Id].Pending_Proposal__c);
    }

    @IsTest
    static void refusalIsReported() {
        Assistant_Session__c s = newSession();
        Test.setMock(HttpCalloutMock.class, new ClaudeMock(response(new List<Object>(), 'refusal')));

        AssistantService.TurnResult r;
        Test.startTest();
        System.runAs(asSelfUser()) {
            r = AssistantService.sendMessage(s.Id, 'Something');
        }
        Test.stopTest();

        System.assertEquals('text', r.kind);
        System.assert(r.text.contains('can\'t help'));
    }

    @IsTest
    static void maxTokensIsReported() {
        Assistant_Session__c s = newSession();
        Test.setMock(HttpCalloutMock.class, new ClaudeMock(response(new List<Object>{ textBlock('Long answer') }, 'max_tokens')));

        AssistantService.TurnResult r;
        Test.startTest();
        System.runAs(asSelfUser()) {
            r = AssistantService.sendMessage(s.Id, 'Something long');
        }
        Test.stopTest();

        System.assertEquals(true, r.truncated);
        System.assertEquals('Long answer', r.text);
    }

    @IsTest
    static void apiErrorsBecomeReadableMessages() {
        Assistant_Session__c s = newSession();
        Test.setMock(HttpCalloutMock.class, new ClaudeMock(
            new List<String>{ '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}' },
            new List<Integer>{ 401 }));

        Test.startTest();
        String message;
        System.runAs(asSelfUser()) {
            try {
                AssistantService.sendMessage(s.Id, 'Hello');
            } catch (AssistantClaudeClient.ClaudeException e) {
                message = e.getMessage();
            }
        }
        Test.stopTest();

        System.assert(message != null && message.contains('rejected the API key'), message);
        System.assertEquals(0, messagesOf(s.Id).size(), 'nothing is stored when the callout fails');

        System.assert(AssistantClaudeClient.describeError(429, '').contains('rate-limited'));
        System.assert(AssistantClaudeClient.describeError(503, 'x').contains('unavailable'));
        System.assert(AssistantClaudeClient.describeError(403, '{"error":{"message":"model not allowed"}}').contains('model not allowed'));
        System.assert(AssistantClaudeClient.describeError(400, '{"error":{"message":"bad request"}}').contains('bad request'));
        System.assert(AssistantClaudeClient.namedCredentialName().endsWith('Claude_API'));
    }

    @IsTest
    static void blankMessageIsRejected() {
        Assistant_Session__c s = newSession();
        Boolean threw = false;
        System.runAs(asSelfUser()) {
            try {
                AssistantService.sendMessage(s.Id, '   ');
            } catch (AssistantService.AssistantException e) {
                threw = true;
            }
        }
        System.assert(threw);
    }

    @IsTest
    static void longHistoryIsTrimmedAtUserTextBoundary() {
        Assistant_Session__c s = newSession();
        List<Assistant_Message__c> history = new List<Assistant_Message__c>();
        for (Integer i = 1; i <= 70; i++) {
            Boolean userTurn = Math.mod(i, 2) == 1;
            // Every other user turn is a tool_result so the trim has to skip it.
            List<Object> content = userTurn && Math.mod(i, 4) == 3
                ? new List<Object>{ new Map<String, Object>{ 'type' => 'tool_result', 'tool_use_id' => 't', 'content' => '' } }
                : new List<Object>{ textBlock('m' + i) };
            history.add(msg(s.Id, userTurn ? 'user' : 'assistant', content, i));
        }
        Integer start = AssistantService.trimStart(history);
        System.assert(start >= 10, 'should drop at least the oldest 10');
        System.assertEquals('user', history[start].Role__c);
        System.assert(history[start].Content__c.contains('"text"'));
        System.assertEquals(0, AssistantService.trimStart(new List<Assistant_Message__c>{ history[0] }));

        Map<String, Object> req = AssistantService.buildRequest(s, history);
        System.assertEquals(70 - start, ((List<Object>) req.get('messages')).size());
        System.assertEquals(AssistantService.MAX_TOKENS, req.get('max_tokens'));
    }

    @IsTest
    static void recordContextIsDescribedInPrompt() {
        Account a = [SELECT Id FROM Account LIMIT 1];
        Assistant_Session__c s = new Assistant_Session__c(Record_Id__c = a.Id, Record_Object__c = 'Account');
        insert s;
        Map<String, Object> req = AssistantService.buildRequest(s, new List<Assistant_Message__c>{
            msg(s.Id, 'user', new List<Object>{ textBlock('hi') }, 1)
        });
        String context = (String) ((Map<String, Object>) ((List<Object>) req.get('system'))[1]).get('text');
        System.assert(context.contains(a.Id), context);
        System.assert(context.contains('Account record'), context);
    }
}
