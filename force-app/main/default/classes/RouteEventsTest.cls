@IsTest
private class RouteEventsTest {
  @TestSetup
  static void makeData() {
    RoutingTestData.grantAccess();
  }

  @IsTest
  static void eventsAreWrittenWithActorAndPayload() {
    Route_Plan__c plan = new Route_Plan__c(Name = 'P', Status__c = 'Draft');
    insert plan;
    Route_Event__c e;
    System.runAs(RoutingTestData.self()) {
      e = RouteEvents.log(
        RouteEvents.event('Delay Reported', 'Driver')
          .forPlan(plan.Id)
          .payload(new Map<String, Object>{ 'minutes' => 40 })
      );
      RouteEvents.log(
        new List<RouteEvents.Builder>{
          RouteEvents.event('Arrived', 'System').forPlan(plan.Id)
        }
      );
    }
    Route_Event__c saved = [
      SELECT Type__c, Actor_Type__c, Actor_User__c, Payload__c, Occurred_At__c
      FROM Route_Event__c
      WHERE Id = :e.Id
    ];
    System.assertEquals('Driver', saved.Actor_Type__c);
    System.assertEquals(UserInfo.getUserId(), saved.Actor_User__c);
    System.assertEquals('{"minutes":40}', saved.Payload__c);
    System.assertNotEquals(null, saved.Occurred_At__c);
    System.assertEquals(2, [SELECT COUNT() FROM Route_Event__c]);
  }

  @IsTest
  static void eventsCannotBeChangedOrDeleted() {
    Route_Event__c e = new Route_Event__c(
      Type__c = 'Arrived',
      Actor_Type__c = 'System'
    );
    insert e;
    e.Type__c = 'Departed';
    try {
      update e;
      System.assert(false, 'expected an exception');
    } catch (DmlException ex) {
      System.assert(ex.getMessage().contains('append-only'), ex.getMessage());
    }
    try {
      delete e;
      System.assert(false, 'expected an exception');
    } catch (DmlException ex) {
      System.assert(ex.getMessage().contains('append-only'), ex.getMessage());
    }
    System.assertEquals(
      'Arrived',
      [SELECT Type__c FROM Route_Event__c WHERE Id = :e.Id].Type__c
    );
  }
}
