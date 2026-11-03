@IsTest
private class RoutingPolicyTest {
  @TestSetup
  static void makeData() {
    RoutingTestData.grantAccess();
    RoutingTestData.scenario(1);
  }

  @IsTest
  static void inShopAssetsAreFound() {
    Map<String, Fleet_Asset__c> vans = RoutingTestData.assetsByName();
    Set<Id> inShop;
    System.runAs(RoutingTestData.self()) {
      inShop = RoutingPolicy.assetsInShop(
        new Map<Id, Fleet_Asset__c>(vans.values()).keySet()
      );
      System.assert(RoutingPolicy.assetsInShop(new Set<Id>()).isEmpty());
    }
    System.assertEquals(new Set<Id>{ vans.get('RT-VAN-3 IN SHOP').Id }, inShop);
  }

  @IsTest
  static void driversWithExpiredLicencesOrMandatoryQualificationsAreBlocked() {
    Map<String, Fleet_Asset__c> vans = RoutingTestData.assetsByName();
    Id dana = vans.get('RT-VAN-1').Driver__c;
    Id yossi = vans.get('RT-VAN-2 EV').Driver__c;
    Id avi = vans.get('RT-VAN-4 EXPIRED').Driver__c;
    insert new Driver_Qualification__c(
      Driver__c = dana,
      Name = 'Forklift',
      Status__c = 'Expired',
      Is_Mandatory__c = true
    );
    Map<Id, RoutingPolicy.DriverStatus> status;
    System.runAs(RoutingTestData.self()) {
      status = RoutingPolicy.driverStatus(
        new Set<Id>{ dana, yossi, avi },
        RoutingTestData.planDate()
      );
      System.assert(RoutingPolicy.driverStatus(null, Date.today()).isEmpty());
    }
    System.assert(!status.get(avi).eligible);
    System.assert(status.get(avi).reason.contains('licence expired'));
    System.assert(!status.get(dana).eligible);
    System.assert(status.get(dana).reason.contains('Forklift'));
    System.assert(status.get(yossi).eligible);
    System.assertEquals(new List<String>{ 'Hazmat' }, status.get(yossi).skills);
  }

  @IsTest
  static void allocationConflictsAreReported() {
    Fleet_Asset__c van1 = RoutingTestData.assetsByName().get('RT-VAN-1');
    insert new Allocation__c(
      Name = 'Booking',
      Fleet_Asset__c = van1.Id,
      Status__c = 'Confirmed',
      Scheduled_Start__c = RoutingTestData.local(9, 0),
      Scheduled_End__c = RoutingTestData.local(10, 0)
    );
    List<Route__c> routes = new List<Route__c>{
      new Route__c(
        Name = 'Overlaps',
        Fleet_Asset__c = van1.Id,
        Planned_Start__c = RoutingTestData.local(8, 0),
        Planned_End__c = RoutingTestData.local(12, 0)
      ),
      new Route__c(
        Name = 'Later',
        Fleet_Asset__c = van1.Id,
        Planned_Start__c = RoutingTestData.local(11, 0),
        Planned_End__c = RoutingTestData.local(12, 0)
      ),
      new Route__c(Name = 'No times', Fleet_Asset__c = van1.Id)
    };
    List<String> conflicts;
    System.runAs(RoutingTestData.self()) {
      conflicts = RoutingPolicy.allocationConflicts(routes);
      System.assert(
        RoutingPolicy.allocationConflicts(
            new List<Route__c>{ new Route__c(Name = 'x') }
          )
          .isEmpty()
      );
    }
    System.assertEquals(1, conflicts.size());
    System.assert(conflicts[0].startsWith('Overlaps'));
  }
}
