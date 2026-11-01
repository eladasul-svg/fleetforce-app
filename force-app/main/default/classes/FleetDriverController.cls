/**
 * Supplies the data behind the fleetDriverCard LWC: the driver assigned to a vehicle (Fleet_Asset__c.Driver__c, a
 * Contact), their branch, contact details, license and qualification warnings.
 *
 * The photo is an image file in the contact's Files, chosen or uploaded from the card; Contact.Photo_Document_Id__c
 * holds its ContentDocument Id, so a new version of the same file shows automatically. Without one the photo comes
 * from the driver's Related User, and without that (or with Salesforce's default silhouette) the card shows initials.
 */
public with sharing class FleetDriverController {
  private static final Set<String> IMAGE_TYPES = new Set<String>{
    'JPG',
    'JPEG',
    'PNG',
    'GIF',
    'WEBP',
    'BMP'
  };

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
    public Id photoDocumentId;
    @AuraEnabled
    public Boolean canEditPhoto = false;
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

  public class DriverPhoto {
    @AuraEnabled
    public Id documentId;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String url;
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
          fleetforce__Related_User__r.MediumPhotoUrl,
          fleetforce__Photo_Document_Id__c
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
      d.photoUrl = fileUrl(c.fleetforce__Photo_Document_Id__c);
      if (d.photoUrl != null) {
        d.photoDocumentId = c.fleetforce__Photo_Document_Id__c;
      } else {
        d.photoUrl = photoUrl(c.fleetforce__Related_User__r?.MediumPhotoUrl);
      }
      d.canEditPhoto = canEditPhoto(c.Id);
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

  /** Image files in the driver's Files, newest first, for the photo picker. */
  @AuraEnabled
  public static List<DriverPhoto> getDriverPhotos(Id driverId) {
    try {
      List<DriverPhoto> out = new List<DriverPhoto>();
      for (ContentDocumentLink l : [
        SELECT
          ContentDocumentId,
          ContentDocument.Title,
          ContentDocument.FileType,
          ContentDocument.LatestPublishedVersionId
        FROM ContentDocumentLink
        WHERE LinkedEntityId = :driverId
        WITH USER_MODE
        ORDER BY ContentDocument.CreatedDate DESC
      ]) {
        if (!IMAGE_TYPES.contains(l.ContentDocument.FileType)) {
          continue;
        }
        DriverPhoto p = new DriverPhoto();
        p.documentId = l.ContentDocumentId;
        p.title = l.ContentDocument.Title;
        p.url = versionUrl(l.ContentDocument.LatestPublishedVersionId);
        out.add(p);
      }
      return out;
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  /**
   * Makes an image file in the driver's Files their photo, or clears the photo when documentId is null (the file
   * itself stays in Files). Files uploaded from the card are linked to the contact by lightning-file-upload.
   */
  @AuraEnabled
  public static void setDriverPhoto(Id driverId, Id documentId) {
    try {
      if (documentId != null) {
        List<ContentDocumentLink> links = [
          SELECT ContentDocument.FileType
          FROM ContentDocumentLink
          WHERE LinkedEntityId = :driverId AND ContentDocumentId = :documentId
          WITH USER_MODE
        ];
        if (links.isEmpty()) {
          throw new PhotoException('That file is not in the driver\'s Files.');
        }
        if (!IMAGE_TYPES.contains(links[0].ContentDocument.FileType)) {
          throw new PhotoException(
            'Choose an image file (JPG, PNG, GIF or WEBP).'
          );
        }
      }
      update as user new Contact(
        Id = driverId,
        fleetforce__Photo_Document_Id__c = documentId
      );
    } catch (Exception e) {
      throw new AuraHandledException(e.getMessage());
    }
  }

  public class PhotoException extends Exception {
  }

  private static Boolean canEditPhoto(Id driverId) {
    if (
      !Schema.SObjectType.Contact.fields.fleetforce__Photo_Document_Id__c.isUpdateable()
    ) {
      return false;
    }
    List<UserRecordAccess> access = [
      SELECT RecordId, HasEditAccess
      FROM UserRecordAccess
      WHERE UserId = :UserInfo.getUserId() AND RecordId = :driverId
    ];
    return !access.isEmpty() && access[0].HasEditAccess;
  }

  // The photo file's latest version, if the file still exists and the user can see it.
  private static String fileUrl(String documentId) {
    // ContentDocument Ids start with 069; anything else typed into the field is ignored.
    if (String.isBlank(documentId) || !documentId.startsWith('069')) {
      return null;
    }
    List<ContentDocument> docs = [
      SELECT LatestPublishedVersionId
      FROM ContentDocument
      WHERE Id = :documentId
      WITH USER_MODE
    ];
    return docs.isEmpty() ? null : versionUrl(docs[0].LatestPublishedVersionId);
  }

  private static String versionUrl(Id versionId) {
    return '/sfc/servlet.shepherd/version/download/' + versionId;
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
