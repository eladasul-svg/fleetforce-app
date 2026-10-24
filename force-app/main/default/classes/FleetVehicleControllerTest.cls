@IsTest
private class FleetVehicleControllerTest {

    @TestSetup
    static void makeData() {
        insert new List<fleetforce__Fleet_Asset__c>{
            new fleetforce__Fleet_Asset__c(Name = '2023 Chevrolet Malibu LT', fleetforce__Body_Type__c = 'Sedan',
                fleetforce__Fuel_Type__c = 'Gasoline', fleetforce__Color__c = 'Blue', fleetforce__Seat_Count__c = 5,
                fleetforce__Odometer__c = 12000, fleetforce__License_Plate__c = 'TST-001'),
            new fleetforce__Fleet_Asset__c(Name = '2022 Ford Transit-250 Cargo Van', fleetforce__Body_Type__c = 'Van'),
            new fleetforce__Fleet_Asset__c(Name = '2024 Ford F-150 Lightning Pro EV (On Order)', fleetforce__Body_Type__c = 'Pickup',
                fleetforce__Fuel_Type__c = 'Electric')
        };

        // FleetAdmin grants FLS on Fleet_Asset__c's custom fields; USER_MODE queries need the call itself to
        // run inside a fresh System.runAs(self) block (same pattern as AssistantToolsTest).
        Id userId = UserInfo.getUserId();
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'FleetAdmin' LIMIT 1];
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSetId = :ps.Id] == 0) {
            System.runAs(new User(Id = userId)) {
                insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id);
            }
        }
    }

    private static fleetforce__Fleet_Asset__c asset(String name) {
        return [SELECT Id FROM fleetforce__Fleet_Asset__c WHERE Name = :name LIMIT 1];
    }

    @IsTest
    static void modelKeyStripsYearAndParenthetical() {
        System.assertEquals('ford f-150 lariat 4wd', FleetVehicleController.modelKey('2023 Ford F-150 Lariat 4WD (On Order)'));
        System.assertEquals('chevrolet malibu lt', FleetVehicleController.modelKey('2023 Chevrolet Malibu LT'));
        System.assertEquals('', FleetVehicleController.modelKey(null));
    }

    @IsTest
    static void ratedVehicleGetsFuelEconomy() {
        Id id = asset('2023 Chevrolet Malibu LT').Id;
        FleetVehicleController.VehicleCard c;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            c = FleetVehicleController.getCard(id);
        }
        System.assertEquals('Sedan', c.bodyType);
        System.assertEquals('Blue', c.color);
        System.assertEquals(true, c.epaRated);
        System.assertEquals(30, c.mpgCombined);
        System.assertEquals(null, c.evRangeMiles);
    }

    @IsTest
    static void electricVehicleHasRangeAndSuffixIsIgnored() {
        Id id = asset('2024 Ford F-150 Lightning Pro EV (On Order)').Id;
        FleetVehicleController.VehicleCard c;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            c = FleetVehicleController.getCard(id);
        }
        System.assertEquals(true, c.epaRated);
        System.assertEquals(320, c.evRangeMiles);
    }

    @IsTest
    static void unratedVehicleHasNoFuelEconomy() {
        Id id = asset('2022 Ford Transit-250 Cargo Van').Id;
        FleetVehicleController.VehicleCard c;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            c = FleetVehicleController.getCard(id);
        }
        System.assertEquals('Van', c.bodyType);
        System.assertEquals(false, c.epaRated);
        System.assertEquals(null, c.mpgCombined);
    }
}
