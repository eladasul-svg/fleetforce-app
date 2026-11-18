/**
 * Executive-ready Driver 360 Controller for Salesforce Contact.
 * Aggregates driver operational KPIs, active vehicle & key assignments, telematics behaviour,
 * business vs. private mileage split, and powers quick fleet actions.
 */
public with sharing class FleetDriver360Controller {
  public class Driver360Data {
    @AuraEnabled
    public DriverSummary summary;
    @AuraEnabled
    public ActiveVehicle activeVehicle;
    @AuraEnabled
    public TelematicsInsights telematics;
    @AuraEnabled
    public MileageSplit mileageSplit;
    @AuraEnabled
    public CitationsSummary citations;
    @AuraEnabled
    public List<RecentTrip> recentTrips;
    @AuraEnabled
    public List<RecentViolation> recentViolations;
    @AuraEnabled
    public List<DriverQualificationDTO> qualifications;
    @AuraEnabled
    public Integer qualificationCount = 0;
    @AuraEnabled
    public Integer activeSkillsCount = 0;
  }

  public class DriverSummary {
    @AuraEnabled
    public Id contactId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String title;
    @AuraEnabled
    public String contactType;
    @AuraEnabled
    public String driverStatus;
    @AuraEnabled
    public Decimal safetyScore;
    @AuraEnabled
    public String safetyRating; // Excellent (>=85), Good (70-84), Attention Needed (<70)
    @AuraEnabled
    public Integer totalTrips;
    @AuraEnabled
    public Decimal monthlyMileage;
    @AuraEnabled
    public Decimal lifetimeMileage;
    @AuraEnabled
    public String distanceUnit;
    @AuraEnabled
    public String licenseNumber;
    @AuraEnabled
    public String licenseClass;
    @AuraEnabled
    public String licenseState;
    @AuraEnabled
    public Date licenseExpiry;
    @AuraEnabled
    public Integer licenseDaysRemaining;
    @AuraEnabled
    public String licenseExpiryStatus; // Expired, Expiring Soon (<=60), Valid
    @AuraEnabled
    public Date medicalCertDate;
    @AuraEnabled
    public Integer medicalDaysRemaining;
    @AuraEnabled
    public String medicalExpiryStatus; // Expired, Expiring Soon (<=60), Valid
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String mobile;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String photoUrl;
    @AuraEnabled
    public String branchName;
  }

  public class ActiveVehicle {
    @AuraEnabled
    public Boolean hasVehicle;
    @AuraEnabled
    public Id vehicleId;
    @AuraEnabled
    public String vehicleName;
    @AuraEnabled
    public String make;
    @AuraEnabled
    public String model;
    @AuraEnabled
    public String modelYear;
    @AuraEnabled
    public String licensePlate;
    @AuraEnabled
    public String vin;
    @AuraEnabled
    public String vehicleStatus;
    @AuraEnabled
    public String vehicleClass;
    @AuraEnabled
    public String authorizationLevel; // Primary, Secondary, Occasional, Temporary
    @AuraEnabled
    public Id authorizationId;
    @AuraEnabled
    public Boolean hasKey;
    @AuraEnabled
    public String keyTagId;
    @AuraEnabled
    public Decimal fuelEnergyLevel;
    @AuraEnabled
    public String fuelType;
    @AuraEnabled
    public Decimal odometer;
    @AuraEnabled
    public String distanceUnit;
  }

  public class TelematicsInsights {
    @AuraEnabled
    public Integer harshBrakingCount = 0;
    @AuraEnabled
    public Integer rapidAccelerationCount = 0;
    @AuraEnabled
    public Integer idlingCount = 0;
    @AuraEnabled
    public Integer speedingCount = 0;
    @AuraEnabled
    public Integer otherViolationsCount = 0;
    @AuraEnabled
    public Integer totalViolations = 0;
    @AuraEnabled
    public String riskLevel; // Low Risk, Moderate Risk, High Risk
  }

  public class MileageSplit {
    @AuraEnabled
    public Decimal businessMileage = 0;
    @AuraEnabled
    public Decimal privateMileage = 0;
    @AuraEnabled
    public Decimal commuteMileage = 0;
    @AuraEnabled
    public Decimal totalMileage = 0;
    @AuraEnabled
    public Integer businessPct = 0;
    @AuraEnabled
    public Integer privatePct = 0;
    @AuraEnabled
    public Integer commutePct = 0;
  }

  public class CitationsSummary {
    @AuraEnabled
    public Integer count = 0;
    @AuraEnabled
    public Decimal totalFine = 0;
    @AuraEnabled
    public Integer pendingCount = 0;
  }

  public class RecentTrip {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String vehicleName;
    @AuraEnabled
    public Datetime startTime;
    @AuraEnabled
    public Datetime endTime;
    @AuraEnabled
    public Decimal distance;
    @AuraEnabled
    public String distanceUnit;
    @AuraEnabled
    public String tripType;
    @AuraEnabled
    public String approvalStatus;
  }

  public class RecentViolation {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String severity;
    @AuraEnabled
    public Datetime timestamp;
    @AuraEnabled
    public String vehicleName;
  }

  public class DriverQualificationDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public String proficiency;
    @AuraEnabled
    public Integer proficiencyLevel;
    @AuraEnabled
    public String proficiencyLabel;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Boolean isValid;
    @AuraEnabled
    public Date validFrom;
    @AuraEnabled
    public Date validUntil;
    @AuraEnabled
    public Integer daysRemaining;
    @AuraEnabled
    public String expiryStatus;
    @AuraEnabled
    public String certId;
    @AuraEnabled
    public String authority;
    @AuraEnabled
    public Boolean isMandatory;
    @AuraEnabled
    public Boolean doesExpire;
    @AuraEnabled
    public String verificationUrl;
    @AuraEnabled
    public String typeBadgeClass;
    @AuraEnabled
    public String statusBadgeClass;
  }

  public class VehicleOption {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String make;
    @AuraEnabled
    public String model;
    @AuraEnabled
    public String licensePlate;
    @AuraEnabled
    public Decimal odometer;
  }

  @AuraEnabled(cacheable=true)
  public static Driver360Data getDriver360Data(Id contactId) {
    if (contactId == null) {
      return null;
    }
    try {
      Driver360Data result = new Driver360Data();

      // 1. Contact Summary
      List<Contact> contacts = [
        SELECT
          Id,
          Name,
          FirstName,
          LastName,
          Title,
          Email,
          Phone,
          MobilePhone,
          fleetforce__Contact_Type__c,
          fleetforce__Driver_Status__c,
          fleetforce__Safety_Score__c,
          fleetforce__License_Number__c,
          fleetforce__License_Class__c,
          fleetforce__License_State__c,
          fleetforce__License_Expiry__c,
          fleetforce__Medical_Cert__c,
          fleetforce__Driver_Branch__c,
          fleetforce__Driver_Branch__r.Name,
          fleetforce__Photo_Document_Id__c,
          fleetforce__Related_User__r.MediumPhotoUrl
        FROM Contact
        WHERE Id = :contactId
        WITH USER_MODE
        LIMIT 1
      ];

      if (contacts.isEmpty()) {
        return null;
      }

      Contact c = contacts[0];
      DriverSummary s = new DriverSummary();
      s.contactId = c.Id;
      s.name = c.Name;
      s.title = c.Title;
      s.contactType = c.fleetforce__Contact_Type__c;
      s.driverStatus = String.isNotBlank(c.fleetforce__Driver_Status__c)
        ? c.fleetforce__Driver_Status__c
        : 'Active';
      s.phone = c.Phone;
      s.mobile = c.MobilePhone;
      s.email = c.Email;
      s.branchName = c.fleetforce__Driver_Branch__r != null
        ? c.fleetforce__Driver_Branch__r.Name
        : '';

      // Photo
      s.photoUrl = resolvePhotoUrl(c);

      // License countdown
      s.licenseNumber = c.fleetforce__License_Number__c;
      s.licenseClass = c.fleetforce__License_Class__c;
      s.licenseState = c.fleetforce__License_State__c;
      s.licenseExpiry = c.fleetforce__License_Expiry__c;
      if (s.licenseExpiry != null) {
        s.licenseDaysRemaining = Date.today().daysBetween(s.licenseExpiry);
        if (s.licenseDaysRemaining < 0) {
          s.licenseExpiryStatus = 'Expired';
        } else if (s.licenseDaysRemaining <= 60) {
          s.licenseExpiryStatus = 'Expiring Soon';
        } else {
          s.licenseExpiryStatus = 'Valid';
        }
      } else {
        s.licenseExpiryStatus = 'Not Set';
      }

      // Medical Cert countdown
      s.medicalCertDate = c.fleetforce__Medical_Cert__c;
      if (s.medicalCertDate != null) {
        s.medicalDaysRemaining = Date.today().daysBetween(s.medicalCertDate);
        if (s.medicalDaysRemaining < 0) {
          s.medicalExpiryStatus = 'Expired';
        } else if (s.medicalDaysRemaining <= 60) {
          s.medicalExpiryStatus = 'Expiring Soon';
        } else {
          s.medicalExpiryStatus = 'Valid';
        }
      } else {
        s.medicalExpiryStatus = 'Not Set';
      }

      // Safety Score & Rating
      s.safetyScore = c.fleetforce__Safety_Score__c != null
        ? c.fleetforce__Safety_Score__c
        : 92;
      if (s.safetyScore >= 85) {
        s.safetyRating = 'Excellent';
      } else if (s.safetyScore >= 70) {
        s.safetyRating = 'Good';
      } else {
        s.safetyRating = 'Attention Needed';
      }

      result.summary = s;

      // 2. Active Vehicle & Key Status
      ActiveVehicle v = new ActiveVehicle();
      v.hasVehicle = false;

      // Check Authorized_Driver__c first
      List<fleetforce__Authorized_Driver__c> authDrivers = [
        SELECT
          Id,
          fleetforce__Type__c,
          fleetforce__Has_Key__c,
          fleetforce__Is_Active__c,
          fleetforce__Fleet_Asset__c,
          fleetforce__Fleet_Asset__r.Name,
          fleetforce__Fleet_Asset__r.fleetforce__Make__c,
          fleetforce__Fleet_Asset__r.fleetforce__Model__c,
          fleetforce__Fleet_Asset__r.fleetforce__Model_Year__c,
          fleetforce__Fleet_Asset__r.fleetforce__License_Plate__c,
          fleetforce__Fleet_Asset__r.fleetforce__VIN__c,
          fleetforce__Fleet_Asset__r.fleetforce__Status__c,
          fleetforce__Fleet_Asset__r.fleetforce__Vehicle_Class__c,
          fleetforce__Fleet_Asset__r.fleetforce__Key_Tag_ID__c,
          fleetforce__Fleet_Asset__r.fleetforce__Fuel_Energy_Level__c,
          fleetforce__Fleet_Asset__r.fleetforce__Fuel_Type__c,
          fleetforce__Fleet_Asset__r.fleetforce__Odometer__c,
          fleetforce__Fleet_Asset__r.fleetforce__Effective_Distance_Unit__c
        FROM fleetforce__Authorized_Driver__c
        WHERE
          fleetforce__Driver__c = :contactId
          AND fleetforce__Is_Active__c = TRUE
        ORDER BY fleetforce__Type__c ASC, CreatedDate DESC
        LIMIT 1
      ];

      if (!authDrivers.isEmpty()) {
        fleetforce__Authorized_Driver__c ad = authDrivers[0];
        v.hasVehicle = true;
        v.authorizationId = ad.Id;
        v.authorizationLevel = String.isNotBlank(ad.fleetforce__Type__c)
          ? ad.fleetforce__Type__c
          : 'Primary';
        v.hasKey = ad.fleetforce__Has_Key__c == true;
        if (ad.fleetforce__Fleet_Asset__r != null) {
          populateVehicleFields(v, ad.fleetforce__Fleet_Asset__r);
        }
      } else {
        // Fallback: Check if directly linked on Fleet_Asset__c.Driver__c
        List<fleetforce__Fleet_Asset__c> assets = [
          SELECT
            Id,
            Name,
            fleetforce__Make__c,
            fleetforce__Model__c,
            fleetforce__Model_Year__c,
            fleetforce__License_Plate__c,
            fleetforce__VIN__c,
            fleetforce__Status__c,
            fleetforce__Vehicle_Class__c,
            fleetforce__Key_Tag_ID__c,
            fleetforce__Fuel_Energy_Level__c,
            fleetforce__Fuel_Type__c,
            fleetforce__Odometer__c,
            fleetforce__Effective_Distance_Unit__c
          FROM fleetforce__Fleet_Asset__c
          WHERE fleetforce__Driver__c = :contactId
          LIMIT 1
        ];
        if (!assets.isEmpty()) {
          v.hasVehicle = true;
          v.authorizationLevel = 'Primary';
          v.hasKey = true;
          populateVehicleFields(v, assets[0]);
        }
      }
      result.activeVehicle = v;

      // 3. Trips, Lifetime & Monthly Mileage, Split
      List<fleetforce__Trip__c> trips = [
        SELECT
          Id,
          Name,
          fleetforce__Start_Time__c,
          fleetforce__End_Time__c,
          fleetforce__Distance__c,
          fleetforce__Distance_Unit__c,
          fleetforce__Trip_Type__c,
          fleetforce__Fleet_Asset__c,
          fleetforce__Fleet_Asset__r.Name,
          fleetforce__Approval_Status__c,
          CreatedDate
        FROM fleetforce__Trip__c
        WHERE fleetforce__Driver__c = :contactId
        ORDER BY fleetforce__Start_Time__c DESC NULLS LAST, CreatedDate DESC
        LIMIT 100
      ];

      s.totalTrips = trips.size();
      Decimal totalDist = 0;
      Decimal monthDist = 0;
      Decimal bizDist = 0;
      Decimal privDist = 0;
      Decimal commuteDist = 0;
      Date startOfMonth = Date.today().toStartOfMonth();
      String distUnit = 'mi';

      List<RecentTrip> recentTripsList = new List<RecentTrip>();
      for (fleetforce__Trip__c t : trips) {
        Decimal d = t.fleetforce__Distance__c != null
          ? t.fleetforce__Distance__c
          : 0;
        totalDist += d;

        if (String.isNotBlank(t.fleetforce__Distance_Unit__c)) {
          distUnit = t.fleetforce__Distance_Unit__c;
        }

        if (
          t.fleetforce__Start_Time__c != null &&
          t.fleetforce__Start_Time__c.date() >= startOfMonth
        ) {
          monthDist += d;
        }

        String typeStr = String.isNotBlank(t.fleetforce__Trip_Type__c)
          ? t.fleetforce__Trip_Type__c
          : 'Business';
        if (typeStr == 'Business') {
          bizDist += d;
        } else if (typeStr == 'Private') {
          privDist += d;
        } else if (typeStr == 'Commute') {
          commuteDist += d;
        } else {
          bizDist += d;
        }

        if (recentTripsList.size() < 5) {
          RecentTrip rt = new RecentTrip();
          rt.id = t.Id;
          rt.name = t.Name;
          rt.vehicleName = t.fleetforce__Fleet_Asset__r != null
            ? t.fleetforce__Fleet_Asset__r.Name
            : '';
          rt.startTime = t.fleetforce__Start_Time__c;
          rt.endTime = t.fleetforce__End_Time__c;
          rt.distance = d;
          rt.distanceUnit = t.fleetforce__Distance_Unit__c;
          rt.tripType = typeStr;
          rt.approvalStatus = String.isNotBlank(
              t.fleetforce__Approval_Status__c
            )
            ? t.fleetforce__Approval_Status__c
            : 'Submitted';
          recentTripsList.add(rt);
        }
      }

      s.lifetimeMileage = totalDist.setScale(1);
      s.monthlyMileage = monthDist.setScale(1);
      s.distanceUnit = distUnit;
      result.recentTrips = recentTripsList;

      // Mileage Split calculation
      MileageSplit ms = new MileageSplit();
      ms.businessMileage = bizDist.setScale(1);
      ms.privateMileage = privDist.setScale(1);
      ms.commuteMileage = commuteDist.setScale(1);
      ms.totalMileage = totalDist.setScale(1);
      if (totalDist > 0) {
        ms.businessPct = (Integer) Math.round((bizDist / totalDist) * 100);
        ms.privatePct = (Integer) Math.round((privDist / totalDist) * 100);
        ms.commutePct = 100 - ms.businessPct - ms.privatePct;
        if (ms.commutePct < 0)
          ms.commutePct = 0;
      } else {
        ms.businessPct = 100;
        ms.privatePct = 0;
        ms.commutePct = 0;
      }
      result.mileageSplit = ms;

      // 4. Telematics Behavior Insights
      TelematicsInsights ti = new TelematicsInsights();
      List<fleetforce__Telemetry_Violation__c> violations = [
        SELECT
          Id,
          Name,
          fleetforce__Type__c,
          fleetforce__Severity__c,
          fleetforce__Timestamp__c,
          fleetforce__Fleet_Asset__r.Name
        FROM fleetforce__Telemetry_Violation__c
        WHERE fleetforce__Driver__c = :contactId
        ORDER BY fleetforce__Timestamp__c DESC NULLS LAST, CreatedDate DESC
        LIMIT 50
      ];

      List<RecentViolation> recentViolationsList = new List<RecentViolation>();
      for (fleetforce__Telemetry_Violation__c tv : violations) {
        String vType = tv.fleetforce__Type__c;
        if (vType == 'Harsh Braking') {
          ti.harshBrakingCount++;
        } else if (vType == 'Harsh Acceleration') {
          ti.rapidAccelerationCount++;
        } else if (vType == 'Idling') {
          ti.idlingCount++;
        } else if (vType == 'Speeding') {
          ti.speedingCount++;
        } else {
          ti.otherViolationsCount++;
        }
        ti.totalViolations++;

        if (recentViolationsList.size() < 5) {
          RecentViolation rv = new RecentViolation();
          rv.id = tv.Id;
          rv.name = tv.Name;
          rv.type = vType;
          rv.severity = String.isNotBlank(tv.fleetforce__Severity__c)
            ? tv.fleetforce__Severity__c
            : 'Medium';
          rv.timestamp = tv.fleetforce__Timestamp__c;
          rv.vehicleName = tv.fleetforce__Fleet_Asset__r != null
            ? tv.fleetforce__Fleet_Asset__r.Name
            : '';
          recentViolationsList.add(rv);
        }
      }

      if (ti.totalViolations <= 2) {
        ti.riskLevel = 'Low Risk';
      } else if (ti.totalViolations <= 6) {
        ti.riskLevel = 'Moderate Risk';
      } else {
        ti.riskLevel = 'High Risk';
      }
      result.telematics = ti;
      result.recentViolations = recentViolationsList;

      // 5. Citations Summary
      CitationsSummary cs = new CitationsSummary();
      for (AggregateResult ar : [
        SELECT count(Id) totalCount, sum(fleetforce__Fine_Amount__c) totalFine
        FROM fleetforce__Citation__c
        WHERE fleetforce__Driver__c = :contactId
        WITH USER_MODE
      ]) {
        cs.count = (Integer) ar.get('totalCount');
        Decimal sumFine = (Decimal) ar.get('totalFine');
        cs.totalFine = sumFine != null ? sumFine.setScale(2) : 0;
      }
      result.citations = cs;

      // 6. Driver Qualifications & Skills
      List<fleetforce__Driver_Qualification__c> quals = [
        SELECT
          Id,
          Name,
          fleetforce__Type__c,
          fleetforce__Proficiency__c,
          fleetforce__Status__c,
          fleetforce__Valid_From__c,
          fleetforce__Valid_Until__c,
          fleetforce__Cert_ID__c,
          fleetforce__Authority__c,
          fleetforce__Is_Mandatory__c,
          fleetforce__Does_Expire__c,
          fleetforce__Verification_URL__c
        FROM fleetforce__Driver_Qualification__c
        WHERE fleetforce__Driver__c = :contactId
        ORDER BY
          fleetforce__Type__c ASC,
          fleetforce__Valid_Until__c ASC NULLS LAST
        LIMIT 50
      ];

      List<DriverQualificationDTO> qualList = new List<DriverQualificationDTO>();
      Integer activeSkills = 0;
      for (fleetforce__Driver_Qualification__c q : quals) {
        DriverQualificationDTO dto = new DriverQualificationDTO();
        dto.id = q.Id;
        dto.name = q.Name;
        dto.type = String.isNotBlank(q.fleetforce__Type__c)
          ? q.fleetforce__Type__c
          : 'Internal Skill';
        dto.proficiency = q.fleetforce__Proficiency__c;
        if (dto.proficiency != null && dto.proficiency.startsWith('1')) {
          dto.proficiencyLevel = 1;
          dto.proficiencyLabel = 'Beginner';
        } else if (dto.proficiency != null && dto.proficiency.startsWith('2')) {
          dto.proficiencyLevel = 2;
          dto.proficiencyLabel = 'Intermediate';
        } else if (dto.proficiency != null && dto.proficiency.startsWith('3')) {
          dto.proficiencyLevel = 3;
          dto.proficiencyLabel = 'Expert';
        } else if (dto.proficiency != null && dto.proficiency.startsWith('4')) {
          dto.proficiencyLevel = 4;
          dto.proficiencyLabel = 'Native';
        } else {
          dto.proficiencyLevel = 2;
          dto.proficiencyLabel = 'Intermediate';
        }

        dto.status = String.isNotBlank(q.fleetforce__Status__c)
          ? q.fleetforce__Status__c
          : 'Valid';
        dto.validFrom = q.fleetforce__Valid_From__c;
        dto.validUntil = q.fleetforce__Valid_Until__c;
        dto.certId = q.fleetforce__Cert_ID__c;
        dto.authority = q.fleetforce__Authority__c;
        dto.isMandatory = q.fleetforce__Is_Mandatory__c == true;
        dto.doesExpire = q.fleetforce__Does_Expire__c == true;
        dto.verificationUrl = q.fleetforce__Verification_URL__c;

        if (dto.validUntil != null) {
          dto.daysRemaining = Date.today().daysBetween(dto.validUntil);
          if (dto.daysRemaining < 0) {
            dto.expiryStatus = 'Expired';
            dto.isValid = false;
            dto.statusBadgeClass = 'pill-error';
          } else if (dto.daysRemaining <= 60) {
            dto.expiryStatus = 'Expiring Soon (' + dto.daysRemaining + 'd)';
            dto.isValid = true;
            dto.statusBadgeClass = 'pill-warning';
          } else {
            dto.expiryStatus = 'Valid (' + dto.daysRemaining + 'd)';
            dto.isValid = true;
            dto.statusBadgeClass = 'pill-active';
          }
        } else {
          dto.expiryStatus = 'Permanent';
          dto.isValid = (dto.status == 'Valid');
          dto.statusBadgeClass = dto.isValid ? 'pill-active' : 'pill-neutral';
        }

        if (dto.status == 'Expired' || dto.status == 'Revoked') {
          dto.isValid = false;
          dto.statusBadgeClass = 'pill-error';
        }

        if (dto.isValid) {
          activeSkills++;
        }

        if (dto.type == 'Certification') {
          dto.typeBadgeClass = 'badge-cert';
        } else if (dto.type == 'Internal Skill') {
          dto.typeBadgeClass = 'badge-skill';
        } else if (dto.type.contains('Badge')) {
          dto.typeBadgeClass = 'badge-access';
        } else {
          dto.typeBadgeClass = 'badge-lang';
        }

        qualList.add(dto);
      }
      result.qualifications = qualList;
      result.qualificationCount = qualList.size();
      result.activeSkillsCount = activeSkills;

      return result;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error loading Driver 360 data: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<VehicleOption> getAvailableVehicles() {
    List<VehicleOption> options = new List<VehicleOption>();
    for (fleetforce__Fleet_Asset__c a : [
      SELECT
        Id,
        Name,
        fleetforce__Make__c,
        fleetforce__Model__c,
        fleetforce__License_Plate__c,
        fleetforce__Odometer__c
      FROM fleetforce__Fleet_Asset__c
      WHERE fleetforce__Is_Active__c = TRUE
      ORDER BY fleetforce__Make__c ASC, fleetforce__Model__c ASC
      LIMIT 100
    ]) {
      VehicleOption vo = new VehicleOption();
      vo.id = a.Id;
      vo.name = a.Name;
      vo.make = a.fleetforce__Make__c;
      vo.model = a.fleetforce__Model__c;
      vo.licensePlate = a.fleetforce__License_Plate__c;
      vo.odometer = a.fleetforce__Odometer__c;
      String descStr = a.Name;
      if (
        String.isNotBlank(a.fleetforce__Make__c) ||
        String.isNotBlank(a.fleetforce__Model__c)
      ) {
        descStr +=
          ' (' +
          (a.fleetforce__Make__c != null ? a.fleetforce__Make__c : '') +
          ' ' +
          (a.fleetforce__Model__c != null ? a.fleetforce__Model__c : '');
        if (String.isNotBlank(a.fleetforce__License_Plate__c)) {
          descStr += ' · ' + a.fleetforce__License_Plate__c;
        }
        descStr += ')';
      }
      vo.label = descStr;
      options.add(vo);
    }
    return options;
  }

  @AuraEnabled
  public static void toggleKeyAccess(Id authorizationId, Boolean hasKey) {
    if (authorizationId == null) {
      throw new AuraHandledException('Authorization ID is required.');
    }
    try {
      update as user new fleetforce__Authorized_Driver__c(
        Id = authorizationId,
        fleetforce__Has_Key__c = hasKey
      );
    } catch (Exception e) {
      throw new AuraHandledException(
        'Unable to update key status: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled
  public static Id assignVehicle(
    Id contactId,
    Id vehicleId,
    String authType,
    Boolean issueKey
  ) {
    if (contactId == null || vehicleId == null) {
      throw new AuraHandledException('Driver and Vehicle are required.');
    }
    try {
      String aType = String.isNotBlank(authType) ? authType : 'Primary';
      fleetforce__Authorized_Driver__c ad = new fleetforce__Authorized_Driver__c(
        fleetforce__Driver__c = contactId,
        fleetforce__Fleet_Asset__c = vehicleId,
        fleetforce__Type__c = aType,
        fleetforce__Has_Key__c = issueKey == true,
        fleetforce__Is_Active__c = true,
        fleetforce__Start_Date__c = Date.today()
      );
      insert as user ad;

      if (aType == 'Primary') {
        update as user new fleetforce__Fleet_Asset__c(
          Id = vehicleId,
          fleetforce__Driver__c = contactId
        );
      }
      return ad.Id;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Unable to assign vehicle: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled
  public static Id quickLogTrip(
    Id contactId,
    Id vehicleId,
    String tripType,
    String purpose,
    Datetime startTime,
    Datetime endTime,
    Decimal distance,
    String distanceUnit,
    Decimal startOdo,
    Decimal endOdo,
    String origin,
    String destination
  ) {
    if (contactId == null) {
      throw new AuraHandledException('Driver is required.');
    }
    try {
      Datetime st = startTime != null ? startTime : Datetime.now().addHours(-1);
      Datetime et = endTime != null ? endTime : Datetime.now();
      Decimal dist = distance != null
        ? distance
        : (endOdo != null &&
            startOdo != null &&
            endOdo > startOdo
            ? endOdo - startOdo
            : 0);
      String uom = String.isNotBlank(distanceUnit) ? distanceUnit : 'mi';

      fleetforce__Trip__c trip = new fleetforce__Trip__c(
        fleetforce__Driver__c = contactId,
        fleetforce__Fleet_Asset__c = vehicleId,
        fleetforce__Trip_Type__c = String.isNotBlank(tripType)
          ? tripType
          : 'Business',
        fleetforce__Business_Purpose__c = purpose,
        fleetforce__Start_Time__c = st,
        fleetforce__End_Time__c = et,
        fleetforce__Distance__c = dist,
        fleetforce__Distance_Unit__c = uom,
        fleetforce__Start_Odometer__c = startOdo,
        fleetforce__End_Odometer__c = endOdo,
        fleetforce__Origin_Address__c = origin,
        fleetforce__Destination_Address__c = destination,
        fleetforce__Approval_Status__c = 'Submitted'
      );
      insert as user trip;

      if (vehicleId != null && endOdo != null) {
        update as user new fleetforce__Fleet_Asset__c(
          Id = vehicleId,
          fleetforce__Odometer__c = endOdo
        );
      }
      return trip.Id;
    } catch (Exception e) {
      throw new AuraHandledException('Unable to log trip: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static Id quickLogFuel(
    Id contactId,
    Id vehicleId,
    Date txDate,
    Decimal volume,
    Decimal totalCost,
    Decimal odometer,
    String productType
  ) {
    if (contactId == null) {
      throw new AuraHandledException('Driver is required.');
    }
    try {
      fleetforce__Fuel_Log__c fl = new fleetforce__Fuel_Log__c(
        fleetforce__Driver__c = contactId,
        fleetforce__Fleet_Asset__c = vehicleId,
        fleetforce__Transaction_Date__c = txDate != null
          ? txDate
          : Date.today(),
        fleetforce__Volume__c = volume,
        fleetforce__Total_Cost__c = totalCost,
        fleetforce__Odometer__c = odometer,
        fleetforce__Product_Type__c = String.isNotBlank(productType)
          ? productType
          : 'Diesel'
      );
      insert as user fl;

      if (vehicleId != null && odometer != null) {
        update as user new fleetforce__Fleet_Asset__c(
          Id = vehicleId,
          fleetforce__Odometer__c = odometer
        );
      }
      return fl.Id;
    } catch (Exception e) {
      throw new AuraHandledException('Unable to log fuel: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static Id quickReportCitation(
    Id contactId,
    Id vehicleId,
    Date citationDate,
    String ticketNumber,
    String violationType,
    Decimal fineAmount,
    String issuingAuthority
  ) {
    if (contactId == null) {
      throw new AuraHandledException('Driver is required.');
    }
    try {
      fleetforce__Citation__c cit = new fleetforce__Citation__c(
        fleetforce__Driver__c = contactId,
        fleetforce__Fleet_Asset__c = vehicleId,
        fleetforce__Citation_Date__c = citationDate != null
          ? citationDate
          : Date.today(),
        fleetforce__Ticket_Number__c = ticketNumber,
        fleetforce__Violation_Type__c = String.isNotBlank(violationType)
          ? violationType
          : 'Speeding',
        fleetforce__Fine_Amount__c = fineAmount,
        fleetforce__Issuing_Authority__c = issuingAuthority,
        fleetforce__Status__c = 'New'
      );
      insert as user cit;
      return cit.Id;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Unable to report citation: ' + e.getMessage()
      );
    }
  }

  @AuraEnabled
  public static Id addDriverQualification(
    Id contactId,
    String title,
    String qualType,
    String proficiency,
    Date validUntil,
    String certId,
    String authority
  ) {
    if (contactId == null || String.isBlank(title)) {
      throw new AuraHandledException(
        'Driver and Qualification Title are required.'
      );
    }
    try {
      fleetforce__Driver_Qualification__c dq = new fleetforce__Driver_Qualification__c(
        fleetforce__Driver__c = contactId,
        Name = title.trim(),
        fleetforce__Type__c = String.isNotBlank(qualType)
          ? qualType
          : 'Internal Skill',
        fleetforce__Proficiency__c = String.isNotBlank(proficiency)
          ? proficiency
          : '2 - Intermediate',
        fleetforce__Status__c = 'Valid',
        fleetforce__Valid_From__c = Date.today(),
        fleetforce__Valid_Until__c = validUntil,
        fleetforce__Cert_ID__c = certId,
        fleetforce__Authority__c = authority,
        fleetforce__Does_Expire__c = (validUntil != null)
      );
      insert as user dq;
      return dq.Id;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Unable to add qualification: ' + e.getMessage()
      );
    }
  }

  private static void populateVehicleFields(
    ActiveVehicle v,
    fleetforce__Fleet_Asset__c asset
  ) {
    v.vehicleId = asset.Id;
    v.vehicleName = asset.Name;
    v.make = asset.fleetforce__Make__c;
    v.model = asset.fleetforce__Model__c;
    v.modelYear = asset.fleetforce__Model_Year__c;
    v.licensePlate = asset.fleetforce__License_Plate__c;
    v.vin = asset.fleetforce__VIN__c;
    v.vehicleStatus = asset.fleetforce__Status__c;
    v.vehicleClass = asset.fleetforce__Vehicle_Class__c;
    v.keyTagId = asset.fleetforce__Key_Tag_ID__c;
    v.fuelEnergyLevel = asset.fleetforce__Fuel_Energy_Level__c != null
      ? asset.fleetforce__Fuel_Energy_Level__c
      : 75;
    v.fuelType = asset.fleetforce__Fuel_Type__c;
    v.odometer = asset.fleetforce__Odometer__c;
    v.distanceUnit = String.isNotBlank(
        asset.fleetforce__Effective_Distance_Unit__c
      )
      ? asset.fleetforce__Effective_Distance_Unit__c
      : 'mi';
  }

  private static String resolvePhotoUrl(Contact c) {
    if (
      c.fleetforce__Photo_Document_Id__c != null &&
      String.valueOf(c.fleetforce__Photo_Document_Id__c).startsWith('069')
    ) {
      List<ContentDocument> docs = [
        SELECT LatestPublishedVersionId
        FROM ContentDocument
        WHERE Id = :c.fleetforce__Photo_Document_Id__c
        WITH USER_MODE
        LIMIT 1
      ];
      if (!docs.isEmpty()) {
        return '/sfc/servlet.shepherd/version/download/' +
          docs[0].LatestPublishedVersionId;
      }
    }
    String uPhoto = c.fleetforce__Related_User__r?.MediumPhotoUrl;
    if (String.isNotBlank(uPhoto) && !uPhoto.contains('/profilephoto/005/')) {
      return uPhoto;
    }
    return null;
  }
}
