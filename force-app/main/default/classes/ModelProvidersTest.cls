@IsTest
private class ModelProvidersTest {
  @IsTest
  static void claudeIsTheDefault() {
    System.assertEquals('claude', ModelProviders.current().name());
    System.assertEquals(
      'openai_compatible',
      ModelProviders.forName('openai_compatible').name()
    );
    System.assertEquals(
      'salesforce_models_api',
      ModelProviders.forName('salesforce_models_api').name()
    );
    System.assertEquals('claude', ModelProviders.forName(null).name());
    ModelProvider stub = new SalesforceModelsApiProvider();
    ModelProviders.useForTest(stub);
    System.assert(ModelProviders.current() === stub);
    try {
      stub.complete(new Map<String, Object>());
      System.assert(false, 'expected an exception');
    } catch (ModelProviders.ModelException e) {
      System.assert(e.getMessage().contains('not available yet'));
    }
  }

  @IsTest
  static void openAiMappingRoundTrips() {
    OpenAICompatibleProvider p = new OpenAICompatibleProvider();
    Map<String, Object> req = new Map<String, Object>{
      'max_tokens' => 100,
      'system' => new List<Object>{
        new Map<String, Object>{ 'type' => 'text', 'text' => 'Be brief.' }
      },
      'tools' => new List<Object>{
        new Map<String, Object>{
          'name' => 'get_route',
          'description' => 'Read the route',
          'input_schema' => new Map<String, Object>{ 'type' => 'object' }
        }
      },
      'messages' => new List<Object>{
        new Map<String, Object>{
          'role' => 'user',
          'content' => new List<Object>{
            new Map<String, Object>{ 'type' => 'text', 'text' => 'Hi' }
          }
        },
        new Map<String, Object>{
          'role' => 'assistant',
          'content' => new List<Object>{
            new Map<String, Object>{
              'type' => 'tool_use',
              'id' => 't1',
              'name' => 'get_route',
              'input' => new Map<String, Object>()
            }
          }
        },
        new Map<String, Object>{
          'role' => 'user',
          'content' => new List<Object>{
            new Map<String, Object>{
              'type' => 'tool_result',
              'tool_use_id' => 't1',
              'content' => '{}'
            }
          }
        }
      }
    };
    Map<String, Object> chat = p.toChatRequest(req);
    List<Object> messages = (List<Object>) chat.get('messages');
    System.assertEquals(
      'system',
      ((Map<String, Object>) messages[0]).get('role')
    );
    System.assertNotEquals(
      null,
      ((Map<String, Object>) messages[2]).get('tool_calls')
    );
    System.assertEquals(
      'tool',
      ((Map<String, Object>) messages[3]).get('role')
    );
    Map<String, Object> fn = (Map<String, Object>) ((Map<String, Object>) ((List<Object>) chat.get(
        'tools'
      ))[0])
      .get('function');
    System.assertEquals('get_route', fn.get('name'));

    Map<String, Object> res = p.fromChatResponse(
      (Map<String, Object>) JSON.deserializeUntyped(
        '{"choices":[{"finish_reason":"tool_calls","message":{"content":"Let me look.","tool_calls":' +
          '[{"id":"c1","type":"function","function":{"name":"get_route","arguments":"{\\"route_id\\":\\"x\\"}"}}]}}],' +
          '"usage":{"prompt_tokens":12,"completion_tokens":3}}'
      )
    );
    System.assertEquals('tool_use', res.get('stop_reason'));
    List<Object> content = (List<Object>) res.get('content');
    System.assertEquals('text', ((Map<String, Object>) content[0]).get('type'));
    System.assertEquals(
      'x',
      ((Map<String, Object>) ((Map<String, Object>) content[1]).get('input'))
        .get('route_id')
    );
    System.assertEquals(
      12,
      ((Map<String, Object>) res.get('usage')).get('input_tokens')
    );
    try {
      p.complete(req);
      System.assert(false, 'expected an exception');
    } catch (ModelProviders.ModelException e) {
      System.assert(e.getMessage().contains('No OpenAI-compatible endpoint'));
    }
  }

  @IsTest
  static void openAiCalloutWhenConfigured() {
    OpenAICompatibleProvider p = new OpenAICompatibleProvider();
    p.namedCredential = 'My_Model';
    Test.setMock(HttpCalloutMock.class, new Echo());
    Map<String, Object> res = p.complete(
      new Map<String, Object>{ 'messages' => new List<Object>() }
    );
    System.assertEquals('end_turn', res.get('stop_reason'));
  }

  private class Echo implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      System.assert(req.getEndpoint().startsWith('callout:My_Model/'));
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(
        '{"choices":[{"finish_reason":"stop","message":{"content":"Hi"}}]}'
      );
      return res;
    }
  }
}
