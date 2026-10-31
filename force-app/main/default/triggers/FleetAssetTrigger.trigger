trigger FleetAssetTrigger on Fleet_Asset__c(before insert, before update) {
  FleetAssetIdentity.setKeys(Trigger.new);
}
