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

  @IsTest
  static void approvalRules() {
    Map<String, Object> clean = new Map<String, Object>{
      'lateHardWindows' => new List<Object>(),
      'unassigned' => new List<Object>()
    };
    System.assertEquals('Driver', RoutingPolicy.forReoptimize(clean).approver);
    Map<String, Object> late = new Map<String, Object>{
      'lateHardWindows' => new List<Object>{ 'JOB-1' },
      'unassigned' => new List<Object>{ 'x' }
    };
    RoutingPolicy.Decision d = RoutingPolicy.forReoptimize(late);
    System.assertEquals('Dispatcher', d.approver);
    System.assertEquals(2, d.reasons.size());
    System.assertEquals(
      'Driver',
      RoutingPolicy.forAddWaypoint('Charge').approver
    );
    System.assertEquals(
      'Dispatcher',
      RoutingPolicy.forAddWaypoint('Driver Added').approver
    );
    System.assertEquals('Dispatcher', RoutingPolicy.forSkip().approver);
    System.assertEquals(
      'Dispatcher',
      RoutingPolicy.forWindowChange(new Job_Visit__c(Hard_Window__c = true))
        .approver
    );
    System.assertEquals(
      'Driver',
      RoutingPolicy.forWindowChange(new Job_Visit__c(Hard_Window__c = false))
        .approver
    );

    RoutingPolicy.settingsOverride = new Routing_Policy_Setting__mdt(
      Driver_Approves_Reorder__c = false,
      Driver_Approves_Breaks__c = false
    );
    System.assertEquals(
      'Dispatcher',
      RoutingPolicy.forReoptimize(clean).approver
    );
    System.assertEquals(
      'Dispatcher',
      RoutingPolicy.forAddWaypoint('Break').approver
    );
    RoutingPolicy.settingsOverride = null;
    System.assertNotEquals(null, RoutingPolicy.settings());
    System.assertEquals(
      true,
      RoutingPolicy.forAddWaypoint('Break').toMap().get('allowed')
    );
  }

  @IsTest
  static void driversCannotApproveDispatcherChanges() {
    Contact c = new Contact(
      LastName = 'Driver',
      Related_User__c = UserInfo.getUserId()
    );
    insert c;
    Route__c asDriver = new Route__c(Driver__c = c.Id);
    asDriver.putSObject('Driver__r', c);
    System.assertEquals('Driver', RoutingPolicy.actorRole(asDriver));
    System.assertNotEquals(
      null,
      RoutingPolicy.approvalError('Dispatcher', asDriver)
    );
    System.assertEquals(null, RoutingPolicy.approvalError('Driver', asDriver));
    System.assertEquals('Dispatcher', RoutingPolicy.actorRole(new Route__c()));
    System.assertEquals(
      null,
      RoutingPolicy.approvalError('Dispatcher', new Route__c())
    );
  }

  @IsTest
  static void handoffTargetsMustBeAbleToDrive() {
    Map<String, Fleet_Asset__c> vans = RoutingTestData.assetsByName();
    Fleet_Asset__c expired = vans.get('RT-VAN-4 EXPIRED');
    Fleet_Asset__c ok = vans.get('RT-VAN-2 EV');
    System.runAs(RoutingTestData.self()) {
      RoutingPolicy.Decision d = RoutingPolicy.forHandoff(
        new Route__c(
          Name = 'Avi',
          Fleet_Asset__c = expired.Id,
          Driver__c = expired.Driver__c
        ),
        RoutingTestData.planDate()
      );
      System.assert(!d.allowed);
      d = RoutingPolicy.forHandoff(
        new Route__c(
          Name = 'Yossi',
          Fleet_Asset__c = ok.Id,
          Driver__c = ok.Driver__c
        ),
        RoutingTestData.planDate()
      );
      System.assert(d.allowed);
      System.assertEquals('Dispatcher', d.approver);
    }
  }
}
