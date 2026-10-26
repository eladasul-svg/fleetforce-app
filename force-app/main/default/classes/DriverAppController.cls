/**
 * Backs the mobile driver app (a page on the Experience Cloud site). For a chosen driver it assembles everything the
 * app shows (current vehicle and trip, authorized vehicles, reservations, service tickets, documents, violations,
 * citations, qualifications, fuel card and a derived notification list) and records what the driver does: start /
 * end a trip with a pre-trip check, report an issue, log fuel, attach photos.
 *
 * Runs without sharing and takes the driver as a parameter: this is the demo build, with a driver picker and no
 * login. A real deployment must resolve the driver from the logged-in user instead of trusting a parameter.
 * All @AuraEnabled methods take simple parameters on purpose (custom-class parameters fail for the guest user).
 */
public without sharing class DriverAppController {

    public class DriverOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String vehicle;
    }

    public class DriverInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String firstName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String status;
        @AuraEnabled public String licenseClass;
        @AuraEnabled public String licenseNumber;
        @AuraEnabled public String licenseState;
        @AuraEnabled public Date licenseExpiry;
        @AuraEnabled public Integer licenseDaysLeft;
        @AuraEnabled public Date medicalCert;
        @AuraEnabled public Integer medicalDaysLeft;
        @AuraEnabled public Decimal safetyScore;
        @AuraEnabled public String branch;
    }

    public class VehicleInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String plate;
        @AuraEnabled public String bodyType;
        @AuraEnabled public String fuelType;
        @AuraEnabled public String color;
        @AuraEnabled public Decimal seats;
        @AuraEnabled public Decimal odometer;
        @AuraEnabled public Decimal energyLevel;
        @AuraEnabled public String status;
        @AuraEnabled public String branch;
        @AuraEnabled public Decimal latitude;
        @AuraEnabled public Decimal longitude;
        @AuraEnabled public Boolean epaRated = false;
        @AuraEnabled public Decimal mpgCombined;
        @AuraEnabled public Decimal evRangeMiles;
        @AuraEnabled public String authorizationType;
    }

    public class TripInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Datetime checkOut;
        @AuraEnabled public Datetime checkIn;
        @AuraEnabled public Decimal odometerStart;
        @AuraEnabled public Decimal odometerEnd;
        @AuraEnabled public Decimal distance;
        @AuraEnabled public String vehicle;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean newDamage;
    }

    public class ReservationInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String vehicle;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime endTime;
        @AuraEnabled public String status;
        @AuraEnabled public String branch;
    }

    public class TicketInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String summary;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public String category;
        @AuraEnabled public Date scheduledStart;
        @AuraEnabled public Date dueDate;
    }

    public class DocInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String docType;
        @AuraEnabled public String docNumber;
        @AuraEnabled public Date validUntil;
        @AuraEnabled public Integer daysLeft;
        @AuraEnabled public String status;
        @AuraEnabled public String link;
    }

    public class ViolationInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String violationType;
        @AuraEnabled public String severity;
        @AuraEnabled public Datetime occurredAt;
        @AuraEnabled public String value;
        @AuraEnabled public String vehicle;
    }

    public class CitationInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String ticketNumber;
        @AuraEnabled public String violationType;
        @AuraEnabled public Datetime citationDate;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String status;
        @AuraEnabled public String liability;
        @AuraEnabled public Date courtDate;
        @AuraEnabled public String vehicle;
    }

    public class QualificationInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String qualType;
        @AuraEnabled public String authority;
        @AuraEnabled public Date validUntil;
        @AuraEnabled public Integer daysLeft;
        @AuraEnabled public Boolean mandatory;
    }

    public class AuthorizedInfo {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String name;
        @AuraEnabled public String plate;
        @AuraEnabled public String authType;
        @AuraEnabled public Boolean hasKey;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Boolean isCurrent;
    }

    public class FuelCardInfo {
        @AuraEnabled public String provider;
        @AuraEnabled public String lastDigits;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal dailyLimit;
        @AuraEnabled public Date expiry;
        @AuraEnabled public String allowed;
    }

    public class Notice {
        @AuraEnabled public String kind;      // license | medical | document | citation | violation | reservation | service
        @AuraEnabled public String level;     // bad | warn | info
        @AuraEnabled public String title;
        @AuraEnabled public String detail;
        @AuraEnabled public Integer rank;
    }

    public class Dashboard {
        @AuraEnabled public DriverInfo driver;
        @AuraEnabled public VehicleInfo vehicle;
        @AuraEnabled public TripInfo openTrip;
        @AuraEnabled public List<TripInfo> recentTrips = new List<TripInfo>();
        @AuraEnabled public List<ReservationInfo> reservations = new List<ReservationInfo>();
        @AuraEnabled public List<TicketInfo> tickets = new List<TicketInfo>();
        @AuraEnabled public List<DocInfo> documents = new List<DocInfo>();
        @AuraEnabled public List<ViolationInfo> violations = new List<ViolationInfo>();
        @AuraEnabled public List<CitationInfo> citations = new List<CitationInfo>();
        @AuraEnabled public List<QualificationInfo> qualifications = new List<QualificationInfo>();
        @AuraEnabled public List<AuthorizedInfo> authorized = new List<AuthorizedInfo>();
        @AuraEnabled public FuelCardInfo fuelCard;
        @AuraEnabled public List<Notice> notices = new List<Notice>();
    }

    // ------------------------------------------------------------------------------------------------------------

    @AuraEnabled
    public static List<DriverOption> getDrivers() {
        try {
            List<Contact> drivers = [
                SELECT Id, Name, fleetforce__Driver_Status__c
                FROM Contact WHERE fleetforce__Contact_Type__c = 'Driver' ORDER BY Name LIMIT 100
            ];
            Map<Id, String> vehicleByDriver = new Map<Id, String>();
            for (fleetforce__Fleet_Asset__c a : [
                SELECT Name, fleetforce__Driver__c FROM fleetforce__Fleet_Asset__c
                WHERE fleetforce__Driver__c IN :drivers AND fleetforce__Is_Active__c = true ORDER BY Name
            ]) {
                if (!vehicleByDriver.containsKey(a.fleetforce__Driver__c)) {
                    vehicleByDriver.put(a.fleetforce__Driver__c, a.Name);
                }
            }
            List<DriverOption> withVehicle = new List<DriverOption>();
            List<DriverOption> without = new List<DriverOption>();
            for (Contact c : drivers) {
                DriverOption o = new DriverOption();
                o.id = c.Id;
                o.name = c.Name;
                o.status = c.fleetforce__Driver_Status__c;
                o.vehicle = vehicleByDriver.get(c.Id);
                (o.vehicle == null ? without : withVehicle).add(o);
            }
            withVehicle.addAll(without);
            return withVehicle;
        } catch (Exception e) {
            throw new AuraHandledException('Could not load drivers.');
        }
    }

    @AuraEnabled
    public static Dashboard getDashboard(Id driverId) {
        try {
            Contact c = [
                SELECT Id, Name, FirstName, Email, Phone, MobilePhone, fleetforce__Driver_Status__c,
                       fleetforce__License_Class__c, fleetforce__License_Number__c, fleetforce__License_State__c,
                       fleetforce__License_Expiry__c, fleetforce__Medical_Cert__c, fleetforce__Safety_Score__c,
                       fleetforce__Driver_Branch__r.Name
                FROM Contact WHERE Id = :driverId LIMIT 1
            ];
            Dashboard d = new Dashboard();
            Date today = Date.today();

            DriverInfo di = new DriverInfo();
            di.id = c.Id;
            di.name = c.Name;
            di.firstName = c.FirstName;
            di.email = c.Email;
            di.phone = c.MobilePhone != null ? c.MobilePhone : c.Phone;
            di.status = c.fleetforce__Driver_Status__c;
            di.licenseClass = c.fleetforce__License_Class__c;
            di.licenseNumber = c.fleetforce__License_Number__c;
            di.licenseState = c.fleetforce__License_State__c;
            di.licenseExpiry = c.fleetforce__License_Expiry__c;
            di.licenseDaysLeft = c.fleetforce__License_Expiry__c == null ? null : today.daysBetween(c.fleetforce__License_Expiry__c);
            di.medicalCert = c.fleetforce__Medical_Cert__c;
            di.medicalDaysLeft = c.fleetforce__Medical_Cert__c == null ? null : today.daysBetween(c.fleetforce__Medical_Cert__c);
            di.safetyScore = c.fleetforce__Safety_Score__c;
            di.branch = c.fleetforce__Driver_Branch__r == null ? null : c.fleetforce__Driver_Branch__r.Name;
            d.driver = di;

            // authorized vehicles
            Map<Id, String> authType = new Map<Id, String>();
            for (fleetforce__Authorized_Driver__c a : [
                SELECT fleetforce__Fleet_Asset__c, fleetforce__Fleet_Asset__r.Name, fleetforce__Fleet_Asset__r.fleetforce__License_Plate__c,
                       fleetforce__Type__c, fleetforce__Has_Key__c, fleetforce__End_Date__c
                FROM fleetforce__Authorized_Driver__c
                WHERE fleetforce__Driver__c = :driverId AND fleetforce__Is_Active__c = true
                ORDER BY fleetforce__Fleet_Asset__r.Name
            ]) {
                AuthorizedInfo ai = new AuthorizedInfo();
                ai.assetId = a.fleetforce__Fleet_Asset__c;
                ai.name = a.fleetforce__Fleet_Asset__r.Name;
                ai.plate = a.fleetforce__Fleet_Asset__r.fleetforce__License_Plate__c;
                ai.authType = a.fleetforce__Type__c;
                ai.hasKey = a.fleetforce__Has_Key__c;
                ai.endDate = a.fleetforce__End_Date__c;
                ai.isCurrent = false;
                d.authorized.add(ai);
                authType.put(a.fleetforce__Fleet_Asset__c, a.fleetforce__Type__c);
            }

            // open trip (checked out, not yet checked in); one left open for weeks is stale data, not a current trip
            Datetime staleBefore = Datetime.now().addDays(-14);
            List<fleetforce__Allocation__c> openTrips = [
                SELECT Id, Name, fleetforce__Actual_Check_Out__c, fleetforce__Odometer_Start__c, fleetforce__Status__c,
                       fleetforce__Fleet_Asset__c, fleetforce__Fleet_Asset__r.Name, fleetforce__Has_New_Damage__c
                FROM fleetforce__Allocation__c
                WHERE fleetforce__Driver__c = :driverId AND fleetforce__Actual_Check_Out__c != null
                  AND fleetforce__Actual_Check_Out__c >= :staleBefore
                  AND fleetforce__Actual_Check_In__c = null AND fleetforce__Status__c = 'Active'
                ORDER BY fleetforce__Actual_Check_Out__c DESC LIMIT 1
            ];
            Id openTripAsset;
            if (!openTrips.isEmpty()) {
                fleetforce__Allocation__c t = openTrips[0];
                d.openTrip = tripOf(t);
                openTripAsset = t.fleetforce__Fleet_Asset__c;
            }

            // current vehicle: the one on the open trip, else the one assigned to the driver
            fleetforce__Fleet_Asset__c asset;
            if (openTripAsset != null) {
                asset = assetById(openTripAsset);
            } else {
                List<fleetforce__Fleet_Asset__c> mine = [
                    SELECT Id FROM fleetforce__Fleet_Asset__c
                    WHERE fleetforce__Driver__c = :driverId AND fleetforce__Is_Active__c = true ORDER BY Name LIMIT 1
                ];
                if (!mine.isEmpty()) {
                    asset = assetById(mine[0].Id);
                }
            }
            if (asset != null) {
                d.vehicle = vehicleOf(asset, authType.get(asset.Id));
                for (AuthorizedInfo ai : d.authorized) {
                    ai.isCurrent = ai.assetId == asset.Id;
                }
            }

            // recent trips
            for (fleetforce__Allocation__c t : [
                SELECT Id, Name, fleetforce__Actual_Check_Out__c, fleetforce__Actual_Check_In__c, fleetforce__Odometer_Start__c,
                       fleetforce__Odometer_End__c, fleetforce__Distance_Driven__c, fleetforce__Status__c,
                       fleetforce__Fleet_Asset__r.Name, fleetforce__Has_New_Damage__c
                FROM fleetforce__Allocation__c
                WHERE fleetforce__Driver__c = :driverId AND fleetforce__Actual_Check_In__c != null
                ORDER BY fleetforce__Actual_Check_Out__c DESC LIMIT 5
            ]) {
                d.recentTrips.add(tripOf(t));
            }

            // reservations: current and upcoming first, then the most recent past ones
            Datetime now = Datetime.now();
            for (fleetforce__Reservation__c r : [
                SELECT Id, Name, fleetforce__Start_Time__c, fleetforce__End_Time__c, fleetforce__Status__c,
                       fleetforce__Assigned_Asset__r.Name, fleetforce__Origin_Branch__r.Name
                FROM fleetforce__Reservation__c
                WHERE fleetforce__Requestor_Contact__c = :driverId
                  AND fleetforce__Status__c IN ('Pending', 'Approved', 'Active')
                  AND fleetforce__End_Time__c >= :now
                ORDER BY fleetforce__Start_Time__c LIMIT 8
            ]) {
                d.reservations.add(reservationOf(r));
            }

            if (asset != null) {
                for (fleetforce__Service_Ticket__c t : [
                    SELECT Id, Name, fleetforce__Summary__c, fleetforce__Status__c, fleetforce__Priority__c, fleetforce__Category__c,
                           fleetforce__Scheduled_Start__c, fleetforce__Due_Date__c
                    FROM fleetforce__Service_Ticket__c
                    WHERE fleetforce__Fleet_Asset__c = :asset.Id AND fleetforce__Status__c IN ('Draft', 'In-Shop')
                    ORDER BY fleetforce__Date_Reported__c DESC NULLS LAST LIMIT 6
                ]) {
                    TicketInfo ti = new TicketInfo();
                    ti.id = t.Id;
                    ti.name = t.Name;
                    ti.summary = t.fleetforce__Summary__c;
                    ti.status = t.fleetforce__Status__c;
                    ti.priority = t.fleetforce__Priority__c;
                    ti.category = t.fleetforce__Category__c;
                    ti.scheduledStart = t.fleetforce__Scheduled_Start__c;
                    ti.dueDate = t.fleetforce__Due_Date__c;
                    d.tickets.add(ti);
                }
                for (fleetforce__Asset_Document__c doc : [
                    SELECT Id, fleetforce__Doc_Type__c, fleetforce__Doc_Number__c, fleetforce__Valid_Until__c, fleetforce__Status__c, fleetforce__Doc_Link__c
                    FROM fleetforce__Asset_Document__c WHERE fleetforce__Fleet_Asset__c = :asset.Id
                    ORDER BY fleetforce__Valid_Until__c NULLS LAST LIMIT 10
                ]) {
                    DocInfo di2 = new DocInfo();
                    di2.id = doc.Id;
                    di2.docType = doc.fleetforce__Doc_Type__c;
                    di2.docNumber = doc.fleetforce__Doc_Number__c;
                    di2.validUntil = doc.fleetforce__Valid_Until__c;
                    di2.daysLeft = doc.fleetforce__Valid_Until__c == null ? null : today.daysBetween(doc.fleetforce__Valid_Until__c);
                    di2.status = doc.fleetforce__Status__c;
                    di2.link = doc.fleetforce__Doc_Link__c;
                    d.documents.add(di2);
                }
                for (fleetforce__Fuel_Card__c fc : [
                    SELECT fleetforce__Provider__c, fleetforce__Full_Card_Number__c, fleetforce__Status__c, fleetforce__Daily_Limit__c,
                           fleetforce__Expiration_Date__c, fleetforce__Fuel_Type_Allowed__c
                    FROM fleetforce__Fuel_Card__c
                    WHERE fleetforce__Assigned_Driver__c = :driverId OR fleetforce__Assigned_Asset__c = :asset.Id
                    ORDER BY fleetforce__Assigned_Driver__c NULLS LAST LIMIT 1
                ]) {
                    FuelCardInfo f = new FuelCardInfo();
                    f.provider = fc.fleetforce__Provider__c;
                    String num = fc.fleetforce__Full_Card_Number__c;
                    f.lastDigits = String.isBlank(num) ? null : num.right(4);
                    f.status = fc.fleetforce__Status__c;
                    f.dailyLimit = fc.fleetforce__Daily_Limit__c;
                    f.expiry = fc.fleetforce__Expiration_Date__c;
                    f.allowed = fc.fleetforce__Fuel_Type_Allowed__c;
                    d.fuelCard = f;
                }
            }

            for (fleetforce__Telemetry_Violation__c v : [
                SELECT Id, fleetforce__Type__c, fleetforce__Severity__c, fleetforce__Timestamp__c, fleetforce__Value__c, fleetforce__Fleet_Asset__r.Name
                FROM fleetforce__Telemetry_Violation__c WHERE fleetforce__Driver__c = :driverId
                ORDER BY fleetforce__Timestamp__c DESC NULLS LAST LIMIT 8
            ]) {
                ViolationInfo vi = new ViolationInfo();
                vi.id = v.Id;
                vi.violationType = v.fleetforce__Type__c;
                vi.severity = v.fleetforce__Severity__c;
                vi.occurredAt = v.fleetforce__Timestamp__c;
                vi.value = v.fleetforce__Value__c;
                vi.vehicle = v.fleetforce__Fleet_Asset__r == null ? null : v.fleetforce__Fleet_Asset__r.Name;
                d.violations.add(vi);
            }
            for (fleetforce__Citation__c ct : [
                SELECT Id, fleetforce__Ticket_Number__c, fleetforce__Violation_Type__c, fleetforce__Citation_Date__c, fleetforce__Total_Amount__c,
                       fleetforce__Fine_Amount__c, fleetforce__Status__c, fleetforce__Liability_Status__c, fleetforce__Court_Date__c,
                       fleetforce__Fleet_Asset__r.Name
                FROM fleetforce__Citation__c WHERE fleetforce__Driver__c = :driverId
                ORDER BY fleetforce__Citation_Date__c DESC NULLS LAST LIMIT 8
            ]) {
                CitationInfo ci = new CitationInfo();
                ci.id = ct.Id;
                ci.ticketNumber = ct.fleetforce__Ticket_Number__c;
                ci.violationType = ct.fleetforce__Violation_Type__c;
                ci.citationDate = ct.fleetforce__Citation_Date__c;
                ci.amount = ct.fleetforce__Total_Amount__c != null ? ct.fleetforce__Total_Amount__c : ct.fleetforce__Fine_Amount__c;
                ci.status = ct.fleetforce__Status__c;
                ci.liability = ct.fleetforce__Liability_Status__c;
                ci.courtDate = ct.fleetforce__Court_Date__c;
                ci.vehicle = ct.fleetforce__Fleet_Asset__r == null ? null : ct.fleetforce__Fleet_Asset__r.Name;
                d.citations.add(ci);
            }
            for (fleetforce__Driver_Qualification__c q : [
                SELECT Id, fleetforce__Type__c, fleetforce__Authority__c, fleetforce__Valid_Until__c, fleetforce__Is_Mandatory__c
                FROM fleetforce__Driver_Qualification__c WHERE fleetforce__Driver__c = :driverId
                ORDER BY fleetforce__Type__c, fleetforce__Valid_Until__c NULLS LAST LIMIT 12
            ]) {
                QualificationInfo qi = new QualificationInfo();
                qi.id = q.Id;
                qi.qualType = q.fleetforce__Type__c;
                qi.authority = q.fleetforce__Authority__c;
                qi.validUntil = q.fleetforce__Valid_Until__c;
                qi.daysLeft = q.fleetforce__Valid_Until__c == null ? null : today.daysBetween(q.fleetforce__Valid_Until__c);
                qi.mandatory = q.fleetforce__Is_Mandatory__c;
                d.qualifications.add(qi);
            }

            buildNotices(d, today);
            return d;
        } catch (Exception e) {
            throw new AuraHandledException('We could not load your driver information.');
        }
    }

    // ------------------------------------------------------------------------------------------------------------
    // Actions

    @AuraEnabled
    public static Id startTrip(Id driverId, Id assetId, Decimal odometer, Decimal energyPercent, String conditionNotes, Boolean newDamage) {
        try {
            if (driverId == null || assetId == null) {
                throw new AuraHandledException('Please choose a driver and vehicle.');
            }
            fleetforce__Fleet_Asset__c a = [
                SELECT Id, Name, fleetforce__Branch__c, fleetforce__Odometer__c FROM fleetforce__Fleet_Asset__c WHERE Id = :assetId LIMIT 1
            ];
            fleetforce__Allocation__c t = new fleetforce__Allocation__c(
                Name = 'TRIP-' + String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 90000) + 10000),
                fleetforce__Driver__c = driverId,
                fleetforce__Fleet_Asset__c = assetId,
                fleetforce__Origin_Branch__c = a.fleetforce__Branch__c,
                fleetforce__Status__c = 'Active',
                fleetforce__Actual_Check_Out__c = Datetime.now(),
                fleetforce__Odometer_Start__c = odometer,
                fleetforce__Fuel_Level_Out__c = energyPercent,
                fleetforce__Condition_Out__c = conditionNotes,
                fleetforce__Has_New_Damage__c = newDamage == true
            );
            insert t;
            a.fleetforce__Odometer__c = odometer != null ? odometer : a.fleetforce__Odometer__c;
            a.fleetforce__Fuel_Energy_Level__c = energyPercent;
            update a;
            if (newDamage == true) {
                createTicket(driverId, assetId, 'Corrective Repair', 'Medium', 'Damage found at pre-trip check',
                    String.isBlank(conditionNotes) ? 'Driver reported new damage during the pre-trip check.' : conditionNotes);
            }
            return t.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('We could not start your trip. Please try again.');
        }
    }

    @AuraEnabled
    public static void endTrip(Id allocationId, Decimal odometer, Decimal energyPercent, String conditionNotes, Boolean newDamage) {
        try {
            fleetforce__Allocation__c t = [
                SELECT Id, fleetforce__Driver__c, fleetforce__Fleet_Asset__c, fleetforce__Odometer_Start__c, fleetforce__Has_New_Damage__c
                FROM fleetforce__Allocation__c WHERE Id = :allocationId LIMIT 1
            ];
            t.fleetforce__Status__c = 'Completed';
            t.fleetforce__Actual_Check_In__c = Datetime.now();
            t.fleetforce__Odometer_End__c = odometer;
            t.fleetforce__Fuel_Level_In__c = energyPercent;
            t.fleetforce__Condition_In__c = conditionNotes;
            if (odometer != null && t.fleetforce__Odometer_Start__c != null) {
                t.fleetforce__Distance_Driven__c = Math.max(0, odometer - t.fleetforce__Odometer_Start__c);
            }
            t.fleetforce__Has_New_Damage__c = t.fleetforce__Has_New_Damage__c == true || newDamage == true;
            update t;
            fleetforce__Fleet_Asset__c a = new fleetforce__Fleet_Asset__c(Id = t.fleetforce__Fleet_Asset__c);
            if (odometer != null) {
                a.fleetforce__Odometer__c = odometer;
            }
            a.fleetforce__Fuel_Energy_Level__c = energyPercent;
            update a;
            if (newDamage == true) {
                createTicket(t.fleetforce__Driver__c, t.fleetforce__Fleet_Asset__c, 'Corrective Repair', 'Medium',
                    'Damage found when ending a trip',
                    String.isBlank(conditionNotes) ? 'Driver reported new damage at the end of a trip.' : conditionNotes);
            }
        } catch (Exception e) {
            throw new AuraHandledException('We could not end your trip. Please try again.');
        }
    }

    @AuraEnabled
    public static Id reportIssue(Id driverId, Id assetId, String category, String priority, String description) {
        try {
            if (assetId == null || String.isBlank(description)) {
                throw new AuraHandledException('Please describe the issue.');
            }
            return createTicket(driverId, assetId, String.isBlank(category) ? 'Other' : category,
                String.isBlank(priority) ? 'Medium' : priority, description.abbreviate(120), description);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('We could not send your report. Please try again.');
        }
    }

    @AuraEnabled
    public static void logFuel(Id driverId, Id assetId, Decimal volume, String unit, Decimal totalCost, Decimal odometer,
                               Boolean fullTank, String stationName) {
        try {
            if (assetId == null || volume == null || volume <= 0) {
                throw new AuraHandledException('Please enter how much you added.');
            }
            String uom = String.isBlank(unit) ? 'Gallons (US)' : unit;
            String product = uom == 'kWh' ? 'Electric Charge' : 'Petrol';
            Id cardId;
            for (fleetforce__Fuel_Card__c fc : [
                SELECT Id FROM fleetforce__Fuel_Card__c
                WHERE fleetforce__Assigned_Driver__c = :driverId OR fleetforce__Assigned_Asset__c = :assetId LIMIT 1
            ]) {
                cardId = fc.Id;
            }
            insert new fleetforce__Fuel_Log__c(
                Name = 'FUEL-' + String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 90000) + 10000),
                fleetforce__Fleet_Asset__c = assetId,
                fleetforce__Driver__c = driverId,
                fleetforce__Fuel_Card__c = cardId,
                fleetforce__Transaction_Date__c = Datetime.now(),
                fleetforce__Volume__c = volume,
                fleetforce__UOM__c = uom,
                fleetforce__Product_Type__c = product,
                fleetforce__Total_Cost__c = totalCost,
                fleetforce__Unit_Cost__c = totalCost != null ? (totalCost / volume).setScale(3) : null,
                fleetforce__Odometer__c = odometer,
                fleetforce__Full_Tank__c = fullTank == true,
                fleetforce__Vendor_Name__c = stationName
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('We could not save your fuel entry. Please try again.');
        }
    }

    /** Attaches a (client-resized) photo to a trip or a ticket. base64 is the file content without the data: prefix. */
    @AuraEnabled
    public static Id attachPhoto(Id parentId, String fileName, String base64) {
        try {
            if (parentId == null || String.isBlank(base64)) {
                throw new AuraHandledException('There is no photo to upload.');
            }
            ContentVersion cv = new ContentVersion(
                Title = String.isBlank(fileName) ? 'Driver photo' : fileName,
                PathOnClient = (String.isBlank(fileName) ? 'photo' : fileName) + '.jpg',
                VersionData = EncodingUtil.base64Decode(base64),
                FirstPublishLocationId = parentId
            );
            insert cv;
            return cv.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('We could not upload the photo.');
        }
    }

    // ------------------------------------------------------------------------------------------------------------
    // Helpers

    private static Id createTicket(Id driverId, Id assetId, String category, String priority, String summary, String description) {
        fleetforce__Service_Ticket__c t = new fleetforce__Service_Ticket__c(
            fleetforce__Fleet_Asset__c = assetId,
            fleetforce__Reported_By__c = driverId,
            fleetforce__Category__c = category,
            fleetforce__Priority__c = priority,
            fleetforce__Status__c = 'Draft',
            fleetforce__Date_Reported__c = Datetime.now(),
            fleetforce__Summary__c = summary,
            fleetforce__Description__c = description
        );
        insert t;
        return t.Id;
    }

    private static fleetforce__Fleet_Asset__c assetById(Id assetId) {
        return [
            SELECT Id, Name, fleetforce__License_Plate__c, fleetforce__Body_Type__c, fleetforce__Fuel_Type__c, fleetforce__Color__c,
                   fleetforce__Seat_Count__c, fleetforce__Odometer__c, fleetforce__Fuel_Energy_Level__c, fleetforce__Status__c,
                   fleetforce__Branch__r.Name, fleetforce__Last_Location__Latitude__s, fleetforce__Last_Location__Longitude__s
            FROM fleetforce__Fleet_Asset__c WHERE Id = :assetId LIMIT 1
        ];
    }

    private static VehicleInfo vehicleOf(fleetforce__Fleet_Asset__c a, String authorizationType) {
        VehicleInfo v = new VehicleInfo();
        v.id = a.Id;
        v.name = a.Name;
        v.plate = a.fleetforce__License_Plate__c;
        v.bodyType = a.fleetforce__Body_Type__c;
        v.fuelType = a.fleetforce__Fuel_Type__c;
        v.color = a.fleetforce__Color__c;
        v.seats = a.fleetforce__Seat_Count__c;
        v.odometer = a.fleetforce__Odometer__c;
        v.energyLevel = a.fleetforce__Fuel_Energy_Level__c;
        v.status = a.fleetforce__Status__c;
        v.branch = a.fleetforce__Branch__r == null ? null : a.fleetforce__Branch__r.Name;
        v.latitude = a.fleetforce__Last_Location__Latitude__s;
        v.longitude = a.fleetforce__Last_Location__Longitude__s;
        v.authorizationType = authorizationType;
        fleetforce__Vehicle_Model__mdt m = FleetVehicleController.modelFor(a.Name);
        if (m != null && m.fleetforce__MPG_Combined__c != null) {
            v.epaRated = true;
            v.mpgCombined = m.fleetforce__MPG_Combined__c;
            v.evRangeMiles = m.fleetforce__EV_Range_Miles__c;
        }
        return v;
    }

    private static TripInfo tripOf(fleetforce__Allocation__c t) {
        TripInfo ti = new TripInfo();
        ti.id = t.Id;
        ti.name = t.Name;
        ti.checkOut = t.fleetforce__Actual_Check_Out__c;
        ti.odometerStart = t.fleetforce__Odometer_Start__c;
        ti.status = t.fleetforce__Status__c;
        ti.newDamage = t.fleetforce__Has_New_Damage__c;
        ti.vehicle = t.fleetforce__Fleet_Asset__r == null ? null : t.fleetforce__Fleet_Asset__r.Name;
        try {
            ti.checkIn = t.fleetforce__Actual_Check_In__c;
            ti.odometerEnd = t.fleetforce__Odometer_End__c;
            ti.distance = t.fleetforce__Distance_Driven__c;
        } catch (SObjectException e) {
            // fields not selected for this query (open trip): leave empty
        }
        return ti;
    }

    private static ReservationInfo reservationOf(fleetforce__Reservation__c r) {
        ReservationInfo ri = new ReservationInfo();
        ri.id = r.Id;
        ri.name = r.Name;
        ri.vehicle = r.fleetforce__Assigned_Asset__r == null ? null : r.fleetforce__Assigned_Asset__r.Name;
        ri.startTime = r.fleetforce__Start_Time__c;
        ri.endTime = r.fleetforce__End_Time__c;
        ri.status = r.fleetforce__Status__c;
        ri.branch = r.fleetforce__Origin_Branch__r == null ? null : r.fleetforce__Origin_Branch__r.Name;
        return ri;
    }

    private static void addNotice(Dashboard d, String kind, String level, String title, String detail) {
        Notice n = new Notice();
        n.kind = kind;
        n.level = level;
        n.title = title;
        n.detail = detail;
        n.rank = level == 'bad' ? 0 : level == 'warn' ? 1 : 2;
        d.notices.add(n);
    }

    private static String inDays(Integer days) {
        return days < 0 ? 'expired ' + (-days) + ' days ago' : days == 0 ? 'expires today' : 'expires in ' + days + ' days';
    }

    private static void buildNotices(Dashboard d, Date today) {
        DriverInfo di = d.driver;
        if (di.licenseDaysLeft != null && di.licenseDaysLeft <= 60) {
            addNotice(d, 'license', di.licenseDaysLeft < 0 ? 'bad' : 'warn', 'Your driver license ' + inDays(di.licenseDaysLeft),
                'Renew it to stay authorized to drive company vehicles.');
        }
        if (di.medicalDaysLeft != null && di.medicalDaysLeft <= 60) {
            addNotice(d, 'medical', di.medicalDaysLeft < 0 ? 'bad' : 'warn', 'Your medical certificate ' + inDays(di.medicalDaysLeft),
                'Book your medical check before it lapses.');
        }
        for (DocInfo doc : d.documents) {
            if (doc.daysLeft != null && doc.daysLeft <= 30) {
                addNotice(d, 'document', doc.daysLeft < 0 ? 'bad' : 'warn', doc.docType + ' for your vehicle ' + inDays(doc.daysLeft),
                    d.vehicle == null ? null : d.vehicle.name);
            }
        }
        for (CitationInfo c : d.citations) {
            if (c.status == 'New') {
                addNotice(d, 'citation', 'bad', c.violationType == null ? 'New citation' : 'New citation: ' + c.violationType,
                    (c.amount == null ? '' : '$' + c.amount.setScale(2) + ' · ') + (c.courtDate == null ? 'Action needed' : 'Court date ' + c.courtDate.format()));
            }
        }
        Datetime weekAgo = Datetime.now().addDays(-7);
        for (ViolationInfo v : d.violations) {
            if (v.occurredAt != null && v.occurredAt >= weekAgo) {
                addNotice(d, 'violation', v.severity == 'High' || v.severity == 'Critical' ? 'bad' : 'warn',
                    v.violationType + ' detected', v.vehicle);
            }
        }
        for (ReservationInfo r : d.reservations) {
            if (r.startTime != null && r.startTime <= Datetime.now().addDays(2)) {
                addNotice(d, 'reservation', 'info', 'Upcoming booking: ' + r.vehicle, 'Starts ' + r.startTime.format('EEE d MMM, HH:mm'));
            }
        }
        for (TicketInfo t : d.tickets) {
            if (t.status == 'In-Shop') {
                addNotice(d, 'service', 'info', 'Your vehicle is in the workshop', t.summary);
            }
        }
        d.notices.sort(new NoticeOrder());
    }

    private class NoticeOrder implements System.Comparator<Notice> {
        public Integer compare(Notice a, Notice b) {
            return a.rank - b.rank;
        }
    }
}
