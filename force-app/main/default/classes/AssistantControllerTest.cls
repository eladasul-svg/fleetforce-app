@IsTest
private class AssistantControllerTest {

    private class TextMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(JSON.serialize(new Map<String, Object>{
                'content' => new List<Object>{ new Map<String, Object>{ 'type' => 'text', 'text' => 'Hello from Claude' } },
                'stop_reason' => 'end_turn',
                'usage' => new Map<String, Object>{ 'input_tokens' => 1, 'output_tokens' => 1 }
            }));
            return res;
        }
    }

    @TestSetup
    static void makeData() {
        AssistantServiceTest.grantAssistantAccess();
    }

    // A permission set assigned in @TestSetup is not picked up by USER_MODE checks later in the same
    // test unless the SUT call runs inside a fresh System.runAs(self) block. See AssistantServiceTest.
    private static User asSelfUser() {
        return new User(Id = UserInfo.getUserId());
    }

    @IsTest
    static void contextReportsConnectionAndSessions() {
        Assistant_Session__c titled = new Assistant_Session__c(Title__c = 'Earlier chat', Last_Activity__c = System.now());
        insert titled;
        insert new Assistant_Session__c(Last_Activity__c = System.now());

        AssistantController.Context c;
        System.runAs(asSelfUser()) {
            c = AssistantController.getContext();
        }
        System.assertNotEquals(null, c.orgConfigured);
        System.assertNotEquals(null, c.userConfigured);
        System.assertEquals(true, c.canManageOrg, 'test user is an admin');
        System.assert(String.isNotBlank(c.userName));
        System.assertEquals('claude-opus-5', c.model);
        System.assertEquals(1, c.sessions.size(), 'untitled sessions are hidden');
        System.assertEquals('Earlier chat', c.sessions[0].title);
    }

    @IsTest
    static void sessionLifecycle() {
        Account a = new Account(Name = 'Ctx');
        insert a;
        Id sessionId;
        AssistantController.SessionDetail empty;
        System.runAs(asSelfUser()) {
            sessionId = AssistantController.startSession(a.Id, 'Account');
            empty = AssistantController.getSession(sessionId);
        }
        Assistant_Session__c s = [SELECT Record_Id__c, Record_Object__c FROM Assistant_Session__c WHERE Id = :sessionId];
        System.assertEquals(String.valueOf(a.Id), s.Record_Id__c);
        System.assertEquals('Account', s.Record_Object__c);
        System.assertEquals(0, empty.messages.size());
        System.assertEquals(false, empty.awaitingContinue);

        insert new List<Assistant_Message__c>{
            new Assistant_Message__c(Session__c = sessionId, Role__c = 'user', Sequence__c = 1,
                Content__c = '[{"type":"text","text":"Hi"}]'),
            new Assistant_Message__c(Session__c = sessionId, Role__c = 'assistant', Sequence__c = 2,
                Content__c = '[{"type":"text","text":"Hello"},{"type":"tool_use","id":"t1","name":"list_objects","input":{}}]'),
            new Assistant_Message__c(Session__c = sessionId, Role__c = 'user', Sequence__c = 3,
                Content__c = '[{"type":"tool_result","tool_use_id":"t1","content":"{}"}]')
        };
        AssistantController.SessionDetail d;
        System.runAs(asSelfUser()) {
            d = AssistantController.getSession(sessionId);
        }
        System.assertEquals(2, d.messages.size(), 'tool-only messages are not shown');
        System.assertEquals('Hi', d.messages[0].text);
        System.assertEquals('Hello', d.messages[1].text);
        System.assertEquals(true, d.awaitingContinue, 'last message is a tool result, client must continue');

        s.Pending_Proposal__c = '{"toolUseId":"t1","action":"create","objectLabel":"Account","changes":[]}';
        update s;
        System.runAs(asSelfUser()) {
            d = AssistantController.getSession(sessionId);
        }
        System.assertNotEquals(null, d.proposal);
        System.assertEquals(false, d.awaitingContinue);

        Boolean threw = false;
        System.runAs(asSelfUser()) {
            AssistantController.deleteSession(sessionId);
            try {
                AssistantController.getSession(sessionId);
            } catch (AuraHandledException e) {
                threw = true;
                System.assert(e.getMessage().contains('no longer exists'), e.getMessage());
            }
        }
        System.assertEquals(0, [SELECT COUNT() FROM Assistant_Session__c WHERE Id = :sessionId]);
        System.assert(threw);
    }

    @IsTest
    static void turnMethodsDelegateToService() {
        Id sessionId;
        System.runAs(asSelfUser()) {
            sessionId = AssistantController.startSession(null, null);
        }
        Test.setMock(HttpCalloutMock.class, new TextMock());
        AssistantService.TurnResult r;
        Boolean threw = false;

        Test.startTest();
        System.runAs(asSelfUser()) {
            r = AssistantController.sendMessage(sessionId, 'Hi');
        }
        Test.stopTest();
        System.assertEquals('Hello from Claude', r.text);

        System.runAs(asSelfUser()) {
            try {
                AssistantController.continueTurn(sessionId);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'continue after a finished turn should fail');

        threw = false;
        System.runAs(asSelfUser()) {
            try {
                AssistantController.resolveProposal(sessionId, true, null);
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw, 'resolve without a proposal should fail');

        threw = false;
        System.runAs(asSelfUser()) {
            try {
                AssistantController.sendMessage(sessionId, ' ');
            } catch (AuraHandledException e) {
                threw = true;
            }
        }
        System.assert(threw);
    }

    @IsTest
    static void saveApiKeyValidatesInput() {
        Boolean threw = false;
        try {
            AssistantController.saveApiKey('user', 'short');
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(e.getMessage().contains('does not look like'), e.getMessage());
        }
        System.assert(threw);

        AssistantController.saveApiKey('user', 'sk-ant-test-0000000000000000000000');
        System.assertEquals('sk-ant-test-0000000000000000000000', Assistant_User_Setting__c.getValues(UserInfo.getUserId()).Api_Key__c);
        Boolean userConfigured;
        System.runAs(asSelfUser()) {
            userConfigured = AssistantController.getContext().userConfigured;
        }
        System.assertEquals(true, userConfigured);

        AssistantController.saveApiKey('user', 'sk-ant-test-1111111111111111111111');
        System.assertEquals('sk-ant-test-1111111111111111111111', Assistant_User_Setting__c.getValues(UserInfo.getUserId()).Api_Key__c);

        AssistantController.clearUserKey();
        System.assertEquals(null, Assistant_User_Setting__c.getValues(UserInfo.getUserId()));
        System.runAs(asSelfUser()) {
            userConfigured = AssistantController.getContext().userConfigured;
        }
        System.assertEquals(false, userConfigured);
        AssistantController.clearUserKey(); // idempotent

        // ConnectApi credential calls are not available in test context; the org path must surface a
        // readable error rather than an unhandled exception.
        try {
            AssistantController.saveApiKey('org', 'sk-ant-test-0000000000000000000000');
        } catch (AuraHandledException e) {
            System.assert(String.isNotBlank(e.getMessage()));
        }
    }
}
