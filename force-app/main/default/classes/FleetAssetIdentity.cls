/**
 * Keeps a vehicle identifiable without a VIN. VIN is unique on its own; when it is blank, Plate_Key__c holds the
 * registration country and the normalised plate (PT|AA00AA), unique too, so imports cannot load the same vehicle twice.
 */
public with sharing class FleetAssetIdentity {
  /** Before insert and update: uppercase the VIN and set or clear the plate key. */
  public static void setKeys(List<Fleet_Asset__c> assets) {
    Set<Id> branchIds = new Set<Id>();
    for (Fleet_Asset__c a : assets) {
      if (
        String.isBlank(a.VIN__c) &&
        String.isBlank(a.Country__c) &&
        a.Branch__c != null
      ) {
        branchIds.add(a.Branch__c);
      }
    }
    Map<Id, Fleet_Branch__c> branches = branchIds.isEmpty()
      ? new Map<Id, Fleet_Branch__c>()
      : new Map<Id, Fleet_Branch__c>(
          [SELECT Country__c FROM Fleet_Branch__c WHERE Id IN :branchIds]
        );
    String orgCountry = Fleet_Display_Setting__c.getInstance()
      ?.Default_Country__c;

    for (Fleet_Asset__c a : assets) {
      if (String.isNotBlank(a.VIN__c)) {
        a.VIN__c = a.VIN__c.trim().toUpperCase();
        a.Plate_Key__c = null;
        continue;
      }
      String plate = normalisePlate(a.License_Plate__c);
      if (plate == null) {
        a.Plate_Key__c = null;
        continue;
      }
      String country = a.Country__c;
      if (String.isBlank(country) && branches.containsKey(a.Branch__c)) {
        country = branches.get(a.Branch__c).Country__c;
      }
      if (String.isBlank(country)) {
        country = orgCountry;
      }
      a.Plate_Key__c =
        (String.isBlank(country) ? '' : country.toUpperCase()) +
        '|' +
        plate;
    }
  }

  /** Capitals, no spaces or hyphens; null when nothing is left. */
  public static String normalisePlate(String plate) {
    if (plate == null) {
      return null;
    }
    String p = plate.toUpperCase().replaceAll('[\\s-]', '');
    return p.length() == 0 ? null : p;
  }
}
