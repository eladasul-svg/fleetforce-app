/**
 * The model behind the FleetForce Assistant. Requests and responses use the Claude Messages API shape
 * (system blocks, tools with input_schema, content blocks with tool_use / tool_result), which is the
 * assistant's internal format; each adapter maps it to its own API.
 *
 * Implementations: AssistantClaudeClient (default), OpenAICompatibleProvider (any /chat/completions
 * endpoint with tool calling) and SalesforceModelsApiProvider (Agentforce Models API), both stubs for now.
 */
public interface ModelProvider {
  String name();

  /** One model turn. Throws on transport or API errors. */
  Map<String, Object> complete(Map<String, Object> request);
}
