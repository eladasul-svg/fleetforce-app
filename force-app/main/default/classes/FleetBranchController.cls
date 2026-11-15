/**
 * Controller for the fleetBranchHighlights LWC.
 * Supplies branch operational highlights, location/map details, leadership contact info,
 * bay capacity utilization, and live fleet/driver/route metrics.
 */
public with sharing class FleetBranchController {
  public class ManagerInfo {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String firstName;
    @AuraEnabled
    public String lastName;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String mobile;
    @AuraEnabled
    public String initials;
    @AuraEnabled
    public String photoUrl;
  }

  public class BranchHighlightsDTO {
    @AuraEnabled
    public Id branchId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String branchCode;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String locationType;
    @AuraEnabled
    public Decimal capacity;
    @AuraEnabled
    public String street;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String state;
    @AuraEnabled
    public String zipCode;
    @AuraEnabled
    public String country;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public String fullAddress;
    @AuraEnabled
    public String googleMapsUrl;
    @AuraEnabled
    public ManagerInfo manager;

    @AuraEnabled
    public Integer totalVehicles = 0;
    @AuraEnabled
    public Integer activeVehicles = 0;
    @AuraEnabled
    public Integer inShopVehicles = 0;
    @AuraEnabled
    public Integer assignedDrivers = 0;
    @AuraEnabled
    public Integer activeRoutePlans = 0;
    @AuraEnabled
    public Integer openServiceTickets = 0;
    @AuraEnabled
    public Decimal capacityUtilizationPct = 0;
    @AuraEnabled
    public String capacityStatus = 'optimal'; // 'optimal', 'warning', 'critical'
  }

  @AuraEnabled(cacheable=true)
  public static BranchHighlightsDTO getBranchHighlights(Id branchId) {
    if (branchId == null) {
      return null;
    }

    List<fleetforce__Fleet_Branch__c> branches = [
      SELECT
        Id,
        Name,
        fleetforce__Branch_ID__c,
        fleetforce__Status__c,
        fleetforce__Type__c,
        fleetforce__Capacity__c,
        fleetforce__Street__c,
        fleetforce__City__c,
        fleetforce__US_State__c,
        fleetforce__Zip_Code__c,
        fleetforce__Country__c,
        fleetforce__Phone__c,
        fleetforce__Email__c,
        fleetforce__Location__Latitude__s,
        fleetforce__Location__Longitude__s,
        fleetforce__Approving_Manager__c,
        fleetforce__Primary_Contact__c
      FROM fleetforce__Fleet_Branch__c
      WHERE Id = :branchId
      WITH USER_MODE
      LIMIT 1
    ];

    if (branches.isEmpty()) {
      return null;
    }

    fleetforce__Fleet_Branch__c b = branches[0];
    BranchHighlightsDTO dto = new BranchHighlightsDTO();
    dto.branchId = b.Id;
    dto.name = b.Name;
    dto.branchCode = b.fleetforce__Branch_ID__c;
    dto.status = b.fleetforce__Status__c;
    dto.locationType = b.fleetforce__Type__c;
    dto.capacity = b.fleetforce__Capacity__c;
    dto.street = b.fleetforce__Street__c;
    dto.city = b.fleetforce__City__c;
    dto.state = b.fleetforce__US_State__c;
    dto.zipCode = b.fleetforce__Zip_Code__c;
    dto.country = b.fleetforce__Country__c;
    dto.phone = b.fleetforce__Phone__c;
    dto.email = b.fleetforce__Email__c;
    dto.latitude = b.fleetforce__Location__Latitude__s;
    dto.longitude = b.fleetforce__Location__Longitude__s;

    // Address construction
    List<String> addrParts = new List<String>();
    if (String.isNotBlank(dto.street)) {
      addrParts.add(dto.street);
    }
    if (String.isNotBlank(dto.city)) {
      addrParts.add(dto.city);
    }
    if (String.isNotBlank(dto.state)) {
      addrParts.add(dto.state);
    }
    if (String.isNotBlank(dto.zipCode)) {
      addrParts.add(dto.zipCode);
    }
    if (String.isNotBlank(dto.country)) {
      addrParts.add(dto.country);
    }
    dto.fullAddress = String.join(addrParts, ', ');

    // Google Maps link
    if (dto.latitude != null && dto.longitude != null) {
      dto.googleMapsUrl =
        'https://www.google.com/maps/search/?api=1&query=' +
        dto.latitude +
        ',' +
        dto.longitude;
    } else if (String.isNotBlank(dto.fullAddress)) {
      dto.googleMapsUrl =
        'https://www.google.com/maps/search/?api=1&query=' +
        EncodingUtil.urlEncode(dto.fullAddress, 'UTF-8');
    }

    // Manager info
    Id managerContactId = b.fleetforce__Approving_Manager__c != null
      ? b.fleetforce__Approving_Manager__c
      : b.fleetforce__Primary_Contact__c;

    if (managerContactId != null) {
      List<Contact> managers = [
        SELECT
          Id,
          Name,
          FirstName,
          LastName,
          Title,
          Email,
          Phone,
          MobilePhone,
          fleetforce__Photo_Document_Id__c,
          fleetforce__Related_User__r.MediumPhotoUrl
        FROM Contact
        WHERE Id = :managerContactId
        WITH USER_MODE
        LIMIT 1
      ];

      if (!managers.isEmpty()) {
        Contact m = managers[0];
        ManagerInfo mgr = new ManagerInfo();
        mgr.id = m.Id;
        mgr.name = m.Name;
        mgr.firstName = m.FirstName;
        mgr.lastName = m.LastName;
        mgr.title = m.Title;
        mgr.email = m.Email;
        mgr.phone = m.Phone;
        mgr.mobile = m.MobilePhone;
        mgr.initials = calculateInitials(m.FirstName, m.LastName, m.Name);
        mgr.photoUrl = resolvePhotoUrl(
          m.fleetforce__Photo_Document_Id__c,
          m.fleetforce__Related_User__r?.MediumPhotoUrl
        );
        dto.manager = mgr;
      }
    }

    // Vehicle metrics
    dto.totalVehicles = [
      SELECT COUNT()
      FROM fleetforce__Fleet_Asset__c
      WHERE fleetforce__Branch__c = :branchId
      WITH USER_MODE
    ];

    dto.activeVehicles = [
      SELECT COUNT()
      FROM fleetforce__Fleet_Asset__c
      WHERE
        fleetforce__Branch__c = :branchId
        AND fleetforce__Status__c IN ('Available', 'Assigned')
      WITH USER_MODE
    ];

    // In-Shop Vehicles count (distinct assets at this branch with active shop tickets)
    Set<Id> inShopAssetIds = new Set<Id>();
    for (fleetforce__Service_Ticket__c t : [
      SELECT fleetforce__Fleet_Asset__c
      FROM fleetforce__Service_Ticket__c
      WHERE
        fleetforce__Fleet_Asset__r.fleetforce__Branch__c = :branchId
        AND fleetforce__In_Shop__c = TRUE
      WITH USER_MODE
    ]) {
      if (t.fleetforce__Fleet_Asset__c != null) {
        inShopAssetIds.add(t.fleetforce__Fleet_Asset__c);
      }
    }
    dto.inShopVehicles = inShopAssetIds.size();

    // Assigned Drivers count
    dto.assignedDrivers = [
      SELECT COUNT()
      FROM Contact
      WHERE fleetforce__Driver_Branch__c = :branchId
      WITH USER_MODE
    ];

    // Active Route Plans
    dto.activeRoutePlans = [
      SELECT COUNT()
      FROM fleetforce__Route_Plan__c
      WHERE
        fleetforce__Depot_Branch__c = :branchId
        AND fleetforce__Status__c IN (
          'Draft',
          'Optimizing',
          'Optimized',
          'In Progress'
        )
      WITH USER_MODE
    ];

    // Open Service Tickets
    dto.openServiceTickets = [
      SELECT COUNT()
      FROM fleetforce__Service_Ticket__c
      WHERE
        fleetforce__Fleet_Asset__r.fleetforce__Branch__c = :branchId
        AND fleetforce__Status__c != 'Completed'
      WITH USER_MODE
    ];

    // Capacity Utilization %
    if (dto.capacity != null && dto.capacity > 0) {
      Decimal pct = (Decimal.valueOf(dto.totalVehicles) / dto.capacity) * 100;
      dto.capacityUtilizationPct = pct.setScale(1);
      if (dto.capacityUtilizationPct >= 95) {
        dto.capacityStatus = 'critical';
      } else if (dto.capacityUtilizationPct >= 80) {
        dto.capacityStatus = 'warning';
      } else {
        dto.capacityStatus = 'optimal';
      }
    } else {
      dto.capacityUtilizationPct = 0;
      dto.capacityStatus = 'optimal';
    }

    return dto;
  }

  private static String calculateInitials(
    String first,
    String last,
    String fullName
  ) {
    String s = '';
    if (String.isNotBlank(first)) {
      s += first.left(1);
    }
    if (String.isNotBlank(last)) {
      s += last.left(1);
    }
    if (String.isBlank(s) && String.isNotBlank(fullName)) {
      s = fullName.left(2);
    }
    return s.toUpperCase();
  }

  private static String resolvePhotoUrl(
    String documentId,
    String userMediumPhotoUrl
  ) {
    if (String.isNotBlank(documentId) && documentId.startsWith('069')) {
      List<ContentDocument> docs = [
        SELECT LatestPublishedVersionId
        FROM ContentDocument
        WHERE Id = :documentId
        WITH USER_MODE
        LIMIT 1
      ];
      if (!docs.isEmpty()) {
        return '/sfc/servlet.shepherd/version/download/' +
          docs[0].LatestPublishedVersionId;
      }
    }
    if (
      String.isNotBlank(userMediumPhotoUrl) &&
      !userMediumPhotoUrl.contains('/profilephoto/005/')
    ) {
      return userMediumPhotoUrl;
    }
    return null;
  }
}
