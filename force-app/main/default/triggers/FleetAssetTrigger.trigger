trigger FleetAssetTrigger on Fleet_Asset__c(before insert, before update) {
  if (Trigger.isUpdate) {
    FleetAssetUnits.keepDistanceUnitOnMove(Trigger.new, Trigger.oldMap);
  }
  FleetAssetIdentity.setKeys(Trigger.new);
}
