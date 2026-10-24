/**
 * Backs the Motorpool booking portal (Experience Cloud site). Searches the bookable vehicle pool for a time window,
 * reports per-day availability for a week, and records a booking request as a Pending Reservation.
 *
 * Runs without sharing on purpose: the portal's visitors are guests who cannot see Fleet Assets or Reservations
 * directly, and the data returned is limited to the fields on the booking cards.
 *
 * A vehicle is in the pool when it is active with status Available. For a requested window it is unavailable when it
 * overlaps a Pending / Approved / Active reservation, an availability blackout, or an in-shop service ticket.
 */
public without sharing class MotorpoolBookingController {

    private static final Set<String> BLOCKING_RESERVATION_STATUSES = new Set<String>{ 'Pending', 'Approved', 'Active' };
    private static final Integer HORIZON_DAYS = 7;

    public class DayCell {
        @AuraEnabled public String dayName;
        @AuraEnabled public Integer dayNumber;
        @AuraEnabled public String status;      // free | booked | service
        @AuraEnabled public Boolean inWindow;   // the day is part of the requested window
    }

    public class VehicleOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String bodyType;
        @AuraEnabled public String fuelType;
        @AuraEnabled public String color;
        @AuraEnabled public Decimal seats;
        @AuraEnabled public String branch;
        @AuraEnabled public String plate;
        @AuraEnabled public Boolean epaRated = false;
        @AuraEnabled public Decimal mpgCombined;
        @AuraEnabled public Decimal evRangeMiles;
        @AuraEnabled public Boolean available;
        @AuraEnabled public String reason;
        @AuraEnabled public List<DayCell> days = new List<DayCell>();
    }

    public class SearchResult {
        @AuraEnabled public List<VehicleOption> options = new List<VehicleOption>();
        @AuraEnabled public Integer availableCount = 0;
        @AuraEnabled public Integer unavailableCount = 0;
    }

    public class BookingConfirmation {
        @AuraEnabled public String reference;
        @AuraEnabled public String vehicleName;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Datetime endTime;
        @AuraEnabled public String status;
    }

    /** One blocked span for one vehicle. */
    private class Block {
        Datetime startTime;
        Datetime endTime;
        String kind;    // booked | service
        Block(Datetime s, Datetime e, String k) { startTime = s; endTime = e; kind = k; }
    }

    @AuraEnabled
    public static SearchResult search(Datetime startTime, Datetime endTime, Integer minSeats, String vehicleType, Integer tzOffsetMinutes) {
        try {
            validateWindow(startTime, endTime);
            Integer offset = tzOffsetMinutes == null ? 0 : tzOffsetMinutes;
            Date firstDay = startTime.addMinutes(offset).dateGmt();

            List<fleetforce__Fleet_Asset__c> pool = loadPool(minSeats, vehicleType);
            SearchResult result = new SearchResult();
            if (pool.isEmpty()) {
                return result;
            }

            Datetime horizonStart = dayStartUtc(firstDay, offset);
            Datetime horizonEnd = dayStartUtc(firstDay.addDays(HORIZON_DAYS), offset);
            if (endTime > horizonEnd) {
                horizonEnd = endTime;
            }
            Map<Id, List<Block>> blocks = loadBlocks(pool, horizonStart, horizonEnd);

            for (fleetforce__Fleet_Asset__c a : pool) {
                List<Block> mine = blocks.containsKey(a.Id) ? blocks.get(a.Id) : new List<Block>();
                VehicleOption o = new VehicleOption();
                o.id = a.Id;
                o.name = a.Name;
                o.bodyType = a.fleetforce__Body_Type__c;
                o.fuelType = a.fleetforce__Fuel_Type__c;
                o.color = a.fleetforce__Color__c;
                o.seats = a.fleetforce__Seat_Count__c;
                o.plate = a.fleetforce__License_Plate__c;
                o.branch = a.fleetforce__Branch__r == null ? null : a.fleetforce__Branch__r.Name;

                fleetforce__Vehicle_Model__mdt model = FleetVehicleController.modelFor(a.Name);
                if (model != null && model.fleetforce__MPG_Combined__c != null) {
                    o.epaRated = true;
                    o.mpgCombined = model.fleetforce__MPG_Combined__c;
                    o.evRangeMiles = model.fleetforce__EV_Range_Miles__c;
                }

                Block conflict = firstOverlap(mine, startTime, endTime);
                o.available = conflict == null;
                o.reason = conflict == null ? null : describe(conflict, offset);

                for (Integer d = 0; d < HORIZON_DAYS; d++) {
                    Date day = firstDay.addDays(d);
                    Datetime ds = dayStartUtc(day, offset);
                    Datetime de = dayStartUtc(day.addDays(1), offset);
                    DayCell c = new DayCell();
                    c.dayName = Datetime.newInstanceGmt(day, Time.newInstance(12, 0, 0, 0)).formatGmt('EEE');
                    c.dayNumber = day.day();
                    c.inWindow = startTime < de && endTime > ds;
                    c.status = 'free';
                    for (Block b : mine) {
                        if (b.startTime < de && b.endTime > ds) {
                            if (b.kind == 'service') {
                                c.status = 'service';
                                break;
                            }
                            c.status = 'booked';
                        }
                    }
                    o.days.add(c);
                }
                result.options.add(o);
                if (o.available) {
                    result.availableCount++;
                } else {
                    result.unavailableCount++;
                }
            }
            result.options.sort(new OptionOrder());
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('We could not check availability right now. Please try again.');
        }
    }

    @AuraEnabled
    public static BookingConfirmation book(Id assetId, Datetime startTime, Datetime endTime, String firstName,
                                           String lastName, String email, String phone) {
        try {
            if (assetId == null) {
                throw new AuraHandledException('Please choose a vehicle.');
            }
            validateWindow(startTime, endTime);
            if (String.isBlank(firstName) || String.isBlank(lastName) || String.isBlank(email)) {
                throw new AuraHandledException('Please enter your name and email.');
            }

            List<fleetforce__Fleet_Asset__c> rows = [
                SELECT Id, Name, fleetforce__Seat_Count__c, fleetforce__Branch__c
                FROM fleetforce__Fleet_Asset__c
                WHERE Id = :assetId AND fleetforce__Is_Active__c = true AND fleetforce__Status__c = 'Available'
                LIMIT 1
            ];
            if (rows.isEmpty()) {
                throw new AuraHandledException('That vehicle is no longer available.');
            }
            fleetforce__Fleet_Asset__c asset = rows[0];

            // Re-check at booking time: someone else may have taken it since the search.
            Map<Id, List<Block>> blocks = loadBlocks(rows, startTime.addDays(-1), endTime.addDays(1));
            if (firstOverlap(blocks.containsKey(asset.Id) ? blocks.get(asset.Id) : new List<Block>(), startTime, endTime) != null) {
                throw new AuraHandledException('Sorry, that vehicle was just booked for part of your dates. Please search again.');
            }

            String reference = 'MP-' + String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 90000) + 10000);
            fleetforce__Reservation__c r = new fleetforce__Reservation__c(
                Name = reference,
                fleetforce__Assigned_Asset__c = asset.Id,
                fleetforce__Origin_Branch__c = asset.fleetforce__Branch__c,
                fleetforce__Start_Time__c = startTime,
                fleetforce__End_Time__c = endTime,
                fleetforce__Guest_First_Name__c = firstName.trim(),
                fleetforce__Guest_Last_Name__c = lastName.trim(),
                fleetforce__Guest_Email__c = email.trim(),
                fleetforce__Guest_Phone__c = phone,
                fleetforce__Min_Seats__c = asset.fleetforce__Seat_Count__c,
                fleetforce__Status__c = 'Pending'
            );
            r.OwnerId = bookingOwnerId();
            insert r;

            BookingConfirmation c = new BookingConfirmation();
            c.reference = reference;
            c.vehicleName = asset.Name;
            c.startTime = startTime;
            c.endTime = endTime;
            c.status = 'Pending approval';
            return c;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('We could not complete your booking right now. Please try again.');
        }
    }

    // ------------------------------------------------------------------------------------------------

    /** Guest users cannot own records, so bookings made on the public site are owned by an active administrator. */
    private static Id bookingOwnerId() {
        if (UserInfo.getUserType() != 'Guest') {
            return UserInfo.getUserId();
        }
        List<User> admins = [
            SELECT Id FROM User
            WHERE IsActive = true AND UserType = 'Standard' AND Profile.PermissionsModifyAllData = true
            ORDER BY CreatedDate LIMIT 1
        ];
        return admins.isEmpty() ? null : admins[0].Id;
    }

    private static void validateWindow(Datetime startTime, Datetime endTime) {
        if (startTime == null || endTime == null) {
            throw new AuraHandledException('Please choose pick-up and return times.');
        }
        if (endTime <= startTime) {
            throw new AuraHandledException('The return time must be after the pick-up time.');
        }
        if (startTime < Datetime.now().addMinutes(-5)) {
            throw new AuraHandledException('The pick-up time must be in the future.');
        }
        if (startTime.addDays(60) < endTime) {
            throw new AuraHandledException('Bookings are limited to 60 days.');
        }
    }

    private static List<fleetforce__Fleet_Asset__c> loadPool(Integer minSeats, String vehicleType) {
        Integer seats = minSeats == null ? 0 : minSeats;
        List<fleetforce__Fleet_Asset__c> all = [
            SELECT Id, Name, fleetforce__Body_Type__c, fleetforce__Fuel_Type__c, fleetforce__Color__c,
                   fleetforce__Seat_Count__c, fleetforce__License_Plate__c, fleetforce__Branch__r.Name
            FROM fleetforce__Fleet_Asset__c
            WHERE fleetforce__Is_Active__c = true AND fleetforce__Status__c = 'Available'
            ORDER BY Name
            LIMIT 200
        ];
        String type = String.isBlank(vehicleType) ? 'Any' : vehicleType;
        List<fleetforce__Fleet_Asset__c> out = new List<fleetforce__Fleet_Asset__c>();
        for (fleetforce__Fleet_Asset__c a : all) {
            Decimal s = a.fleetforce__Seat_Count__c == null ? 0 : a.fleetforce__Seat_Count__c;
            if (s < seats) {
                continue;
            }
            if (type == 'Any'
                || (type == 'Electric or hybrid' && (a.fleetforce__Fuel_Type__c == 'Electric' || a.fleetforce__Fuel_Type__c == 'Hybrid'))
                || type == a.fleetforce__Body_Type__c) {
                out.add(a);
            }
        }
        return out;
    }

    private static Map<Id, List<Block>> loadBlocks(List<fleetforce__Fleet_Asset__c> assets, Datetime fromTime, Datetime toTime) {
        Map<Id, List<Block>> out = new Map<Id, List<Block>>();
        Set<Id> ids = new Map<Id, fleetforce__Fleet_Asset__c>(assets).keySet();

        for (fleetforce__Reservation__c r : [
            SELECT fleetforce__Assigned_Asset__c, fleetforce__Start_Time__c, fleetforce__End_Time__c
            FROM fleetforce__Reservation__c
            WHERE fleetforce__Assigned_Asset__c IN :ids
              AND fleetforce__Status__c IN :BLOCKING_RESERVATION_STATUSES
              AND fleetforce__Start_Time__c < :toTime AND fleetforce__End_Time__c > :fromTime
        ]) {
            add(out, r.fleetforce__Assigned_Asset__c, new Block(r.fleetforce__Start_Time__c, r.fleetforce__End_Time__c, 'booked'));
        }
        for (fleetforce__Availability_Blackout__c b : [
            SELECT fleetforce__Fleet_Asset__c, fleetforce__Start_Time__c, fleetforce__End_Time__c
            FROM fleetforce__Availability_Blackout__c
            WHERE fleetforce__Fleet_Asset__c IN :ids
              AND fleetforce__Start_Time__c < :toTime AND fleetforce__End_Time__c > :fromTime
        ]) {
            add(out, b.fleetforce__Fleet_Asset__c, new Block(b.fleetforce__Start_Time__c, b.fleetforce__End_Time__c, 'service'));
        }
        for (fleetforce__Service_Ticket__c t : [
            SELECT fleetforce__Fleet_Asset__c, fleetforce__Scheduled_Start__c, fleetforce__Scheduled_End__c
            FROM fleetforce__Service_Ticket__c
            WHERE fleetforce__Fleet_Asset__c IN :ids AND fleetforce__Status__c = 'In-Shop'
        ]) {
            Datetime s = t.fleetforce__Scheduled_Start__c == null ? Datetime.now().addDays(-1)
                : Datetime.newInstanceGmt(t.fleetforce__Scheduled_Start__c, Time.newInstance(0, 0, 0, 0));
            Datetime e = t.fleetforce__Scheduled_End__c == null ? Datetime.now().addDays(3)
                : Datetime.newInstanceGmt(t.fleetforce__Scheduled_End__c.addDays(1), Time.newInstance(0, 0, 0, 0));
            if (s < toTime && e > fromTime) {
                add(out, t.fleetforce__Fleet_Asset__c, new Block(s, e, 'service'));
            }
        }
        return out;
    }

    private static void add(Map<Id, List<Block>> m, Id assetId, Block b) {
        if (!m.containsKey(assetId)) {
            m.put(assetId, new List<Block>());
        }
        m.get(assetId).add(b);
    }

    private static Block firstOverlap(List<Block> blocks, Datetime startTime, Datetime endTime) {
        Block first;
        for (Block b : blocks) {
            if (b.startTime < endTime && b.endTime > startTime && (first == null || b.startTime < first.startTime)) {
                first = b;
            }
        }
        return first;
    }

    private static String describe(Block b, Integer offset) {
        String firstDay = b.startTime.addMinutes(offset).formatGmt('EEE d MMM');
        String lastDay = b.endTime.addMinutes(offset).formatGmt('EEE d MMM');
        String span = firstDay == lastDay ? firstDay : firstDay + ' – ' + lastDay;
        return b.kind == 'service' ? 'In maintenance ' + span : 'Booked ' + span;
    }

    private static Datetime dayStartUtc(Date day, Integer offsetMinutes) {
        return Datetime.newInstanceGmt(day, Time.newInstance(0, 0, 0, 0)).addMinutes(-offsetMinutes);
    }

    /** Available first, then by name. */
    private class OptionOrder implements System.Comparator<VehicleOption> {
        public Integer compare(VehicleOption a, VehicleOption b) {
            if (a.available != b.available) {
                return a.available ? -1 : 1;
            }
            return a.name.compareTo(b.name);
        }
    }
}
