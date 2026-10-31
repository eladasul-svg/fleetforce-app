/**
 * Stored odometer readings keep the unit they were entered in. When a vehicle moves to a branch with a different
 * distance unit and has no override, the old unit is stamped into Distance_Unit_Override__c so the readings
 * (and Odometer_Km__c) stay correct. Open question for the design partner: docs/project files/design-partner-decisions.csv, D-001.
 */
public with sharing class FleetAssetUnits {
  /** Before update: keep the distance unit of vehicles that change branch. */
  public static void keepDistanceUnitOnMove(
    List<Fleet_Asset__c> assets,
    Map<Id, Fleet_Asset__c> oldMap
  ) {
    List<Fleet_Asset__c> moved = new List<Fleet_Asset__c>();
    Set<Id> branchIds = new Set<Id>();
    for (Fleet_Asset__c a : assets) {
      Fleet_Asset__c old = oldMap.get(a.Id);
      if (
        a.Branch__c != old.Branch__c &&
        String.isBlank(a.Distance_Unit_Override__c)
      ) {
        moved.add(a);
        branchIds.add(a.Branch__c);
        branchIds.add(old.Branch__c);
      }
    }
    if (moved.isEmpty()) {
      return;
    }
    branchIds.remove(null);
    Map<Id, Fleet_Branch__c> branches = new Map<Id, Fleet_Branch__c>(
      [SELECT Distance_Unit__c FROM Fleet_Branch__c WHERE Id IN :branchIds]
    );
    String orgUnit = Fleet_Display_Setting__c.getInstance()
      ?.Default_Distance_Unit__c;
    if (String.isBlank(orgUnit)) {
      orgUnit = 'km';
    }

    for (Fleet_Asset__c a : moved) {
      String oldUnit = unitOf(
        branches.get(oldMap.get(a.Id).Branch__c),
        orgUnit
      );
      if (oldUnit != unitOf(branches.get(a.Branch__c), orgUnit)) {
        a.Distance_Unit_Override__c = oldUnit;
      }
    }
  }

  private static String unitOf(Fleet_Branch__c branch, String orgUnit) {
    return branch == null || String.isBlank(branch.Distance_Unit__c)
      ? orgUnit
      : branch.Distance_Unit__c;
  }
}
