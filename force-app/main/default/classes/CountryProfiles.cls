/**
 * Country Profiles (Country_Profile__mdt, one record per ISO code, DeveloperName = the code) give the regional defaults
 * for a country. A new branch with no Country takes the org default country and time zone; when Country is set or
 * changed, every blank regional field is filled from the profile. A value the user set is never overwritten.
 */
public with sharing class CountryProfiles {
  /** The profile for an ISO code, or null. */
  public static Country_Profile__mdt forCountry(String iso) {
    if (String.isBlank(iso) || !Pattern.matches('[A-Za-z]{2}', iso.trim())) {
      return null;
    }
    return Country_Profile__mdt.getInstance(iso.trim().toUpperCase());
  }

  /** Before insert and update on Fleet_Branch__c. oldMap is null on insert. */
  public static void prefillBranches(
    List<Fleet_Branch__c> branches,
    Map<Id, Fleet_Branch__c> oldMap
  ) {
    Fleet_Display_Setting__c org = Fleet_Display_Setting__c.getInstance();
    for (Fleet_Branch__c b : branches) {
      Fleet_Branch__c old = oldMap == null ? null : oldMap.get(b.Id);
      if (old == null && String.isBlank(b.Country__c) && org != null) {
        b.Country__c = org.Default_Country__c;
      }
      if (old == null || b.Country__c != old.Country__c) {
        Country_Profile__mdt p = forCountry(b.Country__c);
        if (p != null) {
          b.Time_Zone__c = ifBlank(b.Time_Zone__c, p.Default_Time_Zone__c);
          b.Currency_Code__c = ifBlank(
            b.Currency_Code__c,
            p.Default_Currency__c
          );
          b.Distance_Unit__c = ifBlank(b.Distance_Unit__c, p.Distance_Unit__c);
          b.Volume_Unit__c = ifBlank(b.Volume_Unit__c, p.Volume_Unit__c);
          b.Weight_Unit__c = ifBlank(b.Weight_Unit__c, p.Weight_Unit__c);
        }
      }
      if (old == null && String.isBlank(b.Time_Zone__c) && org != null) {
        b.Time_Zone__c = org.Default_Time_Zone__c;
      }
    }
  }

  /**
   * The fuel economy format for a vehicle: the operating country's profile, else derived from the units
   * (miles with US gallons = MPG_US, miles with litres or UK gallons = MPG_UK, otherwise L_100km).
   */
  public static String fuelEconomyFormat(
    String country,
    String distanceUnit,
    String volumeUnit
  ) {
    Country_Profile__mdt p = forCountry(country);
    if (p != null && String.isNotBlank(p.Fuel_Economy_Format__c)) {
      return p.Fuel_Economy_Format__c;
    }
    if (distanceUnit == 'mi') {
      return volumeUnit == 'gal_US' ? 'MPG_US' : 'MPG_UK';
    }
    return 'L_100km';
  }

  private static String ifBlank(String value, String fallback) {
    return String.isBlank(value) ? fallback : value;
  }
}
