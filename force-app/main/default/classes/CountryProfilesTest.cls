@IsTest
private class CountryProfilesTest {
  static Fleet_Branch__c reload(Id branchId) {
    return [
      SELECT
        Country__c,
        Time_Zone__c,
        Currency_Code__c,
        Distance_Unit__c,
        Volume_Unit__c,
        Weight_Unit__c
      FROM Fleet_Branch__c
      WHERE Id = :branchId
    ];
  }

  @IsTest
  static void newBranchIsFilledFromProfile() {
    Fleet_Branch__c b = new Fleet_Branch__c(Name = 'London', Country__c = 'GB');
    insert b;

    b = reload(b.Id);
    System.assertEquals('Europe/London', b.Time_Zone__c);
    System.assertEquals('GBP', b.Currency_Code__c);
    System.assertEquals('mi', b.Distance_Unit__c);
    System.assertEquals('L', b.Volume_Unit__c);
    System.assertEquals('kg', b.Weight_Unit__c);
  }

  @IsTest
  static void valuesTheUserSetAreKept() {
    Fleet_Branch__c b = new Fleet_Branch__c(
      Name = 'Chicago',
      Country__c = 'US',
      Time_Zone__c = 'America/Chicago'
    );
    insert b;

    b = reload(b.Id);
    System.assertEquals('America/Chicago', b.Time_Zone__c);
    System.assertEquals('USD', b.Currency_Code__c);
    System.assertEquals('gal_US', b.Volume_Unit__c);
  }

  @IsTest
  static void countryChangeFillsOnlyBlanks() {
    Fleet_Branch__c b = new Fleet_Branch__c(
      Name = 'Hub',
      Distance_Unit__c = 'mi'
    );
    insert b;

    b.Country__c = 'PT';
    update b;

    b = reload(b.Id);
    System.assertEquals('Europe/Lisbon', b.Time_Zone__c);
    System.assertEquals('EUR', b.Currency_Code__c);
    System.assertEquals(
      'mi',
      b.Distance_Unit__c,
      'a unit the user set is not overwritten'
    );
  }

  @IsTest
  static void newBranchWithoutCountryUsesOrgDefaults() {
    insert new Fleet_Display_Setting__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      Default_Country__c = 'IL'
    );
    Fleet_Branch__c b = new Fleet_Branch__c(Name = 'Tel Aviv');
    insert b;

    b = reload(b.Id);
    System.assertEquals('IL', b.Country__c);
    System.assertEquals('Asia/Jerusalem', b.Time_Zone__c);
    System.assertEquals('ILS', b.Currency_Code__c);
  }

  @IsTest
  static void fuelEconomyFormatFallsBackToUnits() {
    System.assertEquals(
      'km_L',
      CountryProfiles.fuelEconomyFormat('IL', 'km', 'L')
    );
    System.assertEquals(
      'MPG_UK',
      CountryProfiles.fuelEconomyFormat('GB', 'mi', 'L')
    );
    System.assertEquals(
      'MPG_US',
      CountryProfiles.fuelEconomyFormat(null, 'mi', 'gal_US')
    );
    System.assertEquals(
      'MPG_UK',
      CountryProfiles.fuelEconomyFormat('ZZ', 'mi', 'L')
    );
    System.assertEquals(
      'L_100km',
      CountryProfiles.fuelEconomyFormat('', 'km', 'L')
    );
    System.assertEquals(null, CountryProfiles.forCountry('Portugal'));
  }
}
