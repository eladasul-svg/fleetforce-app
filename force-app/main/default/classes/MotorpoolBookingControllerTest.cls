@IsTest
private class MotorpoolBookingControllerTest {

    private static Datetime pickup() {
        return Datetime.newInstanceGmt(Date.today().addDays(3), Time.newInstance(9, 0, 0, 0));
    }

    private static Datetime dropoff() {
        return Datetime.newInstanceGmt(Date.today().addDays(4), Time.newInstance(17, 0, 0, 0));
    }

    private static fleetforce__Fleet_Asset__c asset(String name, String body, String fuel, Decimal seats, String status) {
        return new fleetforce__Fleet_Asset__c(
            Name = name, fleetforce__Body_Type__c = body, fleetforce__Fuel_Type__c = fuel,
            fleetforce__Seat_Count__c = seats, fleetforce__Status__c = status, fleetforce__Is_Active__c = true
        );
    }

    @TestSetup
    static void makeData() {
        insert new List<fleetforce__Fleet_Asset__c>{
            asset('2023 Chevrolet Malibu LT', 'Sedan', 'Gasoline', 5, 'Available'),     // free
            asset('2023 Ford Explorer XLT', 'SUV', 'Gasoline', 7, 'Available'),           // booked in the window
            asset('2024 Toyota Camry Hybrid LE', 'Sedan', 'Hybrid', 5, 'Available'),      // blackout in the window
            asset('2022 Ford Transit-350 Extended Van', 'Van', 'Gasoline', 2, 'Available'), // in the shop
            asset('2023 Ford F-150 Lariat 4WD', 'Pickup', 'Gasoline', 5, 'Assigned')       // not in the pool
        };
    }

    private static Id idOf(String name) {
        return [SELECT Id FROM fleetforce__Fleet_Asset__c WHERE Name = :name LIMIT 1].Id;
    }

    private static void addBlockers() {
        insert new fleetforce__Reservation__c(
            fleetforce__Assigned_Asset__c = idOf('2023 Ford Explorer XLT'),
            fleetforce__Start_Time__c = pickup().addHours(2), fleetforce__End_Time__c = pickup().addHours(30),
            fleetforce__Status__c = 'Approved'
        );
        insert new fleetforce__Availability_Blackout__c(
            fleetforce__Fleet_Asset__c = idOf('2024 Toyota Camry Hybrid LE'),
            fleetforce__Start_Time__c = pickup().addDays(-1), fleetforce__End_Time__c = pickup().addDays(1)
        );
        insert new fleetforce__Service_Ticket__c(
            fleetforce__Fleet_Asset__c = idOf('2022 Ford Transit-350 Extended Van'),
            fleetforce__Status__c = 'In-Shop', fleetforce__Actual_Start__c = Date.today(),
            fleetforce__Scheduled_Start__c = Date.today(), fleetforce__Scheduled_End__c = Date.today().addDays(10)
        );
    }

    private static MotorpoolBookingController.VehicleOption find(MotorpoolBookingController.SearchResult r, String name) {
        for (MotorpoolBookingController.VehicleOption o : r.options) {
            if (o.name == name) {
                return o;
            }
        }
        return null;
    }

    @IsTest
    static void everyPoolVehicleIsAvailableWhenNothingIsBooked() {
        MotorpoolBookingController.SearchResult r = MotorpoolBookingController.search(pickup(), dropoff(), 1, 'Any', 0);
        System.assertEquals(4, r.availableCount, 'Assigned vehicles are not part of the pool');
        System.assertEquals(0, r.unavailableCount);
    }

    @IsTest
    static void reservationsBlackoutsAndShopTicketsMakeVehiclesUnavailable() {
        addBlockers();
        MotorpoolBookingController.SearchResult r = MotorpoolBookingController.search(pickup(), dropoff(), 1, 'Any', 0);
        System.assertEquals(1, r.availableCount);
        System.assertEquals(3, r.unavailableCount);
        System.assertEquals(true, find(r, '2023 Chevrolet Malibu LT').available);
        System.assert(find(r, '2023 Ford Explorer XLT').reason.startsWith('Booked'));
        System.assert(find(r, '2024 Toyota Camry Hybrid LE').reason.startsWith('In maintenance'));
        System.assert(find(r, '2022 Ford Transit-350 Extended Van').reason.startsWith('In maintenance'));
        System.assertEquals('2023 Chevrolet Malibu LT', r.options[0].name, 'Available vehicles sort first');
    }

    @IsTest
    static void seatAndTypeFiltersNarrowThePool() {
        System.assertEquals(1, MotorpoolBookingController.search(pickup(), dropoff(), 6, 'Any', 0).options.size());
        System.assertEquals(2, MotorpoolBookingController.search(pickup(), dropoff(), 1, 'Sedan', 0).options.size());
        System.assertEquals(1, MotorpoolBookingController.search(pickup(), dropoff(), 1, 'Electric or hybrid', 0).options.size());
    }

    @IsTest
    static void weekStripCoversSevenDaysAndMarksBookedDays() {
        addBlockers();
        MotorpoolBookingController.VehicleOption o =
            find(MotorpoolBookingController.search(pickup(), dropoff(), 1, 'Any', 0), '2023 Ford Explorer XLT');
        System.assertEquals(7, o.days.size());
        System.assertEquals('booked', o.days[0].status);
        System.assertEquals(true, o.days[0].inWindow);
        System.assertEquals(false, o.days[6].inWindow);
    }

    @IsTest
    static void bookingCreatesAPendingReservationAndBlocksTheVehicle() {
        Id assetId = idOf('2023 Chevrolet Malibu LT');
        MotorpoolBookingController.BookingConfirmation c =
            MotorpoolBookingController.book(assetId, pickup(), dropoff(), 'Jane', 'Smith', 'jane@example.com', null);
        System.assert(c.reference.startsWith('MP-'));
        System.assertEquals('Pending approval', c.status);

        fleetforce__Reservation__c saved = [
            SELECT Name, fleetforce__Status__c, fleetforce__Assigned_Asset__c, fleetforce__Guest_Last_Name__c
            FROM fleetforce__Reservation__c WHERE Name = :c.reference
        ];
        System.assertEquals('Pending', saved.fleetforce__Status__c);
        System.assertEquals(assetId, saved.fleetforce__Assigned_Asset__c);
        System.assertEquals('Smith', saved.fleetforce__Guest_Last_Name__c);

        try {
            MotorpoolBookingController.book(assetId, pickup(), dropoff(), 'Jane', 'Smith', 'jane@example.com', null);
            System.assert(false, 'A second booking for the same window must be refused');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        System.assertEquals(false, find(MotorpoolBookingController.search(pickup(), dropoff(), 1, 'Any', 0), '2023 Chevrolet Malibu LT').available);
    }

    @IsTest
    static void invalidRequestsAreRejected() {
        try {
            MotorpoolBookingController.search(dropoff(), pickup(), 1, 'Any', 0);
            System.assert(false, 'return before pick-up');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            MotorpoolBookingController.search(Datetime.now().addDays(-2), Datetime.now().addDays(-1), 1, 'Any', 0);
            System.assert(false, 'pick-up in the past');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Id malibu = idOf('2023 Chevrolet Malibu LT');
        try {
            MotorpoolBookingController.book(malibu, pickup(), dropoff(), null, null, null, null);
            System.assert(false, 'missing contact details');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            MotorpoolBookingController.book(idOf('2023 Ford F-150 Lariat 4WD'), pickup(), dropoff(), 'A', 'B', 'a@example.com', null);
            System.assert(false, 'vehicle not in the pool');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
