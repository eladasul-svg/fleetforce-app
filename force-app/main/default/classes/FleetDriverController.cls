/**
 * Supplies the data behind the fleetDriverCard LWC: the driver assigned to a vehicle (Fleet_Asset__c.Driver__c, a
 * Contact), their branch, contact details, license and qualification warnings. The photo comes from the driver's
 * Related User; a driver without one (or with Salesforce's default silhouette) gets their initials instead.
 */
public with sharing class FleetDriverController {
  public class DriverCard {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String initials;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String photoUrl;
    @AuraEnabled
    public Id branchId;
    @AuraEnabled
    public String branchName;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String mobile;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String licenseNumber;
    @AuraEnabled
    public String licenseClass;
    @AuraEnabled
    public String licenseState;
    @AuraEnabled
    public Date licenseExpiry;
    @AuraEnabled
    public Decimal safetyScore;
    @AuraEnabled
    public Integer qualificationsExpiringSoon = 0;
    @AuraEnabled
    public Integer qualificationsExpired = 0;
  }

  @AuraEnabled(cacheable=true)
  public static DriverCard getDriverCard(Id driverId) {
    if (driverId == null) {
      return null;
    }
    try {
      List<Contact> rows = [
        SELECT
          Id,
          Name,
          FirstName,
          LastName,
          Title,
          Phone,
          MobilePhone,
          Email,
          fleetforce__Driver_Status__c,
          fleetforce__Driver_Branch__c,
          fleetforce__Driver_Branch__r.Name,
          fleetforce__License_Number__c,
          fleetforce__License_Class__c,
          fleetforce__License_State__c,
          fleetforce__License_Expiry__c,
          fleetforce__Safety_Score__c,
          fleetforce__Related_User__r.MediumPhotoUrl
        FROM Contact
        WHERE Id = :driverId
        WITH USER_MODE
        LIMIT 1
      ];
      if (rows.isEmpty()) {
        return null;
      }
      Contact c = rows[0];
      DriverCard d = new DriverCard();
      d.id = c.Id;
      d.name = c.Name;
      d.initials = initials(c.FirstName, c.LastName);
      d.title = c.Title;
      d.status = c.fleetforce__Driver_Status__c;
      d.photoUrl = photoUrl(c.fleetforce__Related_User__r?.MediumPhotoUrl);
      d.branchId = c.fleetforce__Driver_Branch__c;
      d.branchName = c.fleetforce__Driver_Branch__r?.Name;
      d.phone = c.Phone;
      d.mobile = c.MobilePhone;
      d.email = c.Email;
      d.licenseNumber = c.fleetforce__License_Number__c;
      d.licenseClass = c.fleetforce__License_Class__c;
      d.licenseState = c.fleetforce__License_State__c;
      d.licenseExpiry = c.fleetforce__License_Expiry__c;
      d.safetyScore = c.fleetforce__Safety_Score__c;

      for (AggregateResult r : [
        SELECT fleetforce__Status__c status, COUNT(Id) n
        FROM fleetforce__Driver_Qualification__c
        WHERE
          fleetforce__Driver__c = :driverId
          AND fleetforce__Status__c IN ('Expiring Soon', 'Expired')
        WITH USER_MODE
        GROUP BY fleetforce__Status__c
      ]) {
        Integer n = (Integer) r.get('n');
        if ((String) r.get('status') == 'Expired') {
          d.qualificationsExpired = n;
        } else {
          d.qualificationsExpiringSoon = n;
        }
      }
      return d;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  @TestVisible
  private static String initials(String first, String last) {
    String s = '';
    if (String.isNotBlank(first)) {
      s += first.left(1);
    }
    if (String.isNotBlank(last)) {
      s += last.left(1);
    }
    return s.toUpperCase();
  }

  // Salesforce returns a generic silhouette (".../profilephoto/005/M") for users without a photo; initials look better.
  @TestVisible
  private static String photoUrl(String url) {
    if (String.isBlank(url) || url.contains('/profilephoto/005/')) {
      return null;
    }
    return url;
  }
}
