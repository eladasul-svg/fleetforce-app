/** Picks the assistant's ModelProvider. Claude is the default; tests and future settings can swap it. */
public with sharing class ModelProviders {
  public class ModelException extends Exception {
  }

  @TestVisible
  private static ModelProvider forced;

  public static ModelProvider current() {
    return forced != null ? forced : new AssistantClaudeClient();
  }

  public static ModelProvider forName(String name) {
    switch on name {
      when 'openai_compatible' {
        return new OpenAICompatibleProvider();
      }
      when 'salesforce_models_api' {
        return new SalesforceModelsApiProvider();
      }
      when else {
        return new AssistantClaudeClient();
      }
    }
  }

  public static void useForTest(ModelProvider provider) {
    forced = provider;
  }
}
