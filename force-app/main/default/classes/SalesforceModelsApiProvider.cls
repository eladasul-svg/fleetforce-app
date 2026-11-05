/**
 * Stub: the Agentforce Models API (Salesforce-managed Claude on Bedrock, or the customer's own Bedrock,
 * Azure OpenAI, OpenAI or Vertex model through Bring Your Own LLM, with the Trust Layer).
 *
 * Not implemented in v1. The Models API Apex classes (aiplatform namespace) only compile in orgs with
 * Einstein generative AI enabled, so the real adapter belongs in an add-on package or behind a
 * dependency-free callout to the Models REST API. Tool definitions stay plain JSON Schema either way.
 */
public with sharing class SalesforceModelsApiProvider implements ModelProvider {
  public String name() {
    return 'salesforce_models_api';
  }

  public Map<String, Object> complete(Map<String, Object> request) {
    throw new ModelProviders.ModelException(
      'The Agentforce Models API provider is not available yet. The FleetForce Assistant uses Claude.'
    );
  }
}
