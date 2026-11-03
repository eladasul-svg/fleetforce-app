/**
 * Stub adapter for any OpenAI-compatible /chat/completions endpoint with tool calling (bring your own
 * model). The message and tool mapping is implemented and tested; the callout is not wired yet because
 * it needs a customer-supplied named credential, which the package does not ship. Until then complete()
 * throws, and ModelProviders keeps Claude as the default.
 */
public with sharing class OpenAICompatibleProvider implements ModelProvider {
  public String model = 'gpt-compatible';
  /** Named credential developer name, set when a customer configures the endpoint. */
  public String namedCredential;

  public String name() {
    return 'openai_compatible';
  }

  public Map<String, Object> complete(Map<String, Object> request) {
    if (String.isBlank(namedCredential)) {
      throw new ModelProviders.ModelException(
        'No OpenAI-compatible endpoint is configured. The FleetForce Assistant uses Claude.'
      );
    }
    String body = RoutingProviders.send(
      'callout:' + namedCredential + '/v1/chat/completions',
      JSON.serialize(toChatRequest(request)),
      null
    );
    return fromChatResponse(
      (Map<String, Object>) JSON.deserializeUntyped(body)
    );
  }

  /** Claude Messages request -> chat/completions request. */
  public Map<String, Object> toChatRequest(Map<String, Object> req) {
    List<Object> messages = new List<Object>();
    List<String> system = new List<String>();
    for (Object o : RoutingDtos.toList(req.get('system'))) {
      system.add(String.valueOf(((Map<String, Object>) o).get('text')));
    }
    if (!system.isEmpty()) {
      messages.add(
        new Map<String, Object>{
          'role' => 'system',
          'content' => String.join(system, '\n\n')
        }
      );
    }
    for (Object o : RoutingDtos.toList(req.get('messages'))) {
      Map<String, Object> m = (Map<String, Object>) o;
      String role = String.valueOf(m.get('role'));
      List<String> texts = new List<String>();
      List<Object> toolCalls = new List<Object>();
      for (Object bo : RoutingDtos.toList(m.get('content'))) {
        Map<String, Object> block = (Map<String, Object>) bo;
        String type = String.valueOf(block.get('type'));
        if (type == 'text') {
          texts.add(String.valueOf(block.get('text')));
        } else if (type == 'tool_use') {
          toolCalls.add(
            new Map<String, Object>{
              'id' => block.get('id'),
              'type' => 'function',
              'function' => new Map<String, Object>{
                'name' => block.get('name'),
                'arguments' => JSON.serialize(block.get('input'))
              }
            }
          );
        } else if (type == 'tool_result') {
          messages.add(
            new Map<String, Object>{
              'role' => 'tool',
              'tool_call_id' => block.get('tool_use_id'),
              'content' => String.valueOf(block.get('content'))
            }
          );
        }
      }
      if (!texts.isEmpty() || !toolCalls.isEmpty()) {
        Map<String, Object> out = new Map<String, Object>{
          'role' => role,
          'content' => texts.isEmpty() ? null : String.join(texts, '\n\n')
        };
        if (!toolCalls.isEmpty()) {
          out.put('tool_calls', toolCalls);
        }
        messages.add(out);
      }
    }
    List<Object> tools = new List<Object>();
    for (Object o : RoutingDtos.toList(req.get('tools'))) {
      Map<String, Object> t = (Map<String, Object>) o;
      tools.add(
        new Map<String, Object>{
          'type' => 'function',
          'function' => new Map<String, Object>{
            'name' => t.get('name'),
            'description' => t.get('description'),
            'parameters' => t.get('input_schema')
          }
        }
      );
    }
    Map<String, Object> out = new Map<String, Object>{
      'model' => model,
      'messages' => messages,
      'max_tokens' => req.get('max_tokens')
    };
    if (!tools.isEmpty()) {
      out.put('tools', tools);
    }
    return out;
  }

  /** chat/completions response -> Claude Messages response shape. */
  public Map<String, Object> fromChatResponse(Map<String, Object> res) {
    Map<String, Object> choice = (Map<String, Object>) RoutingDtos.toList(
      res.get('choices')
    )[0];
    Map<String, Object> message = (Map<String, Object>) choice.get('message');
    List<Object> content = new List<Object>();
    if (
      message.get('content') != null &&
      String.isNotBlank(String.valueOf(message.get('content')))
    ) {
      content.add(
        new Map<String, Object>{
          'type' => 'text',
          'text' => String.valueOf(message.get('content'))
        }
      );
    }
    for (Object o : RoutingDtos.toList(message.get('tool_calls'))) {
      Map<String, Object> call = (Map<String, Object>) o;
      Map<String, Object> fn = (Map<String, Object>) call.get('function');
      Object args = fn.get('arguments');
      content.add(
        new Map<String, Object>{
          'type' => 'tool_use',
          'id' => call.get('id'),
          'name' => fn.get('name'),
          'input' => args instanceof String
            ? JSON.deserializeUntyped((String) args)
            : args
        }
      );
    }
    String finish = String.valueOf(choice.get('finish_reason'));
    String stop = finish == 'tool_calls'
      ? 'tool_use'
      : (finish == 'length' ? 'max_tokens' : 'end_turn');
    Map<String, Object> usage = (Map<String, Object>) res.get('usage');
    return new Map<String, Object>{
      'content' => content,
      'stop_reason' => stop,
      'usage' => usage == null
        ? null
        : new Map<String, Object>{
            'input_tokens' => usage.get('prompt_tokens'),
            'output_tokens' => usage.get('completion_tokens')
          }
    };
  }
}
