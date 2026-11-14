trigger CitationTrigger on Citation__c(before insert, before update) {
  AutoNamingService.apply(Trigger.new);
}
