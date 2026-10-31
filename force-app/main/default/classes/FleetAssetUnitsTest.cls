@IsTest
private class FleetAssetUnitsTest {
  static Fleet_Branch__c branch(String name, String unit) {
    Fleet_Branch__c b = new Fleet_Branch__c(
      Name = name,
      Distance_Unit__c = unit
    );
    insert b;
    return b;
  }

  static Fleet_Asset__c reload(Id assetId) {
    return [
      SELECT
        Distance_Unit_Override__c,
        Effective_Distance_Unit__c,
        Odometer_Km__c
      FROM Fleet_Asset__c
      WHERE Id = :assetId
    ];
  }

  @IsTest
  static void moveToOtherUnitKeepsOldUnit() {
    Fleet_Branch__c london = branch('London', 'mi');
    Fleet_Branch__c lisbon = branch('Lisbon', 'km');
    Fleet_Asset__c a = new Fleet_Asset__c(
      Name = 'Car',
      Branch__c = london.Id,
      Odometer__c = 1000
    );
    insert a;

    a.Branch__c = lisbon.Id;
    update a;

    a = reload(a.Id);
    System.assertEquals('mi', a.Distance_Unit_Override__c);
    System.assertEquals('mi', a.Effective_Distance_Unit__c);
    System.assertEquals(1609.3, a.Odometer_Km__c);
  }

  @IsTest
  static void moveToSameUnitLeavesOverrideBlank() {
    Fleet_Branch__c lisbon = branch('Lisbon', 'km');
    Fleet_Branch__c telAviv = branch('Tel Aviv', 'km');
    Fleet_Asset__c a = new Fleet_Asset__c(Name = 'Car', Branch__c = lisbon.Id);
    insert a;

    a.Branch__c = telAviv.Id;
    update a;

    System.assertEquals(null, reload(a.Id).Distance_Unit_Override__c);
  }

  @IsTest
  static void moveFromNoBranchUsesOrgDefault() {
    Fleet_Branch__c london = branch('London', 'mi');
    Fleet_Asset__c a = new Fleet_Asset__c(Name = 'Car');
    insert a;

    a.Branch__c = london.Id;
    update a;

    System.assertEquals('km', reload(a.Id).Distance_Unit_Override__c);
  }

  @IsTest
  static void existingOverrideIsKept() {
    Fleet_Branch__c london = branch('London', 'mi');
    Fleet_Branch__c lisbon = branch('Lisbon', 'km');
    Fleet_Asset__c a = new Fleet_Asset__c(
      Name = 'Car',
      Branch__c = lisbon.Id,
      Distance_Unit_Override__c = 'km'
    );
    insert a;

    a.Branch__c = london.Id;
    update a;

    System.assertEquals('km', reload(a.Id).Distance_Unit_Override__c);
  }
}
