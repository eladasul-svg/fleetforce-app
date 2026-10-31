trigger FleetBranchTrigger on Fleet_Branch__c(before insert, before update) {
  CountryProfiles.prefillBranches(Trigger.new, Trigger.oldMap);
}
