@IsTest
private class MaintenancePlanOverviewControllerTest {
  @TestSetup
  static void setupData() {
    fleetforce__Fleet_Branch__c branch = new fleetforce__Fleet_Branch__c(
      Name = 'San Francisco Depot',
      fleetforce__Country__c = 'US',
      fleetforce__Time_Zone__c = 'America/Los_Angeles'
    );
    insert branch;

    fleetforce__Maintenance_Plan__c plan = new fleetforce__Maintenance_Plan__c(
      Name = 'Sedan 5-Year Gold Program',
      fleetforce__Asset_Type__c = 'Sedan',
      fleetforce__Frequency_Type__c = 'Mileage-Based',
      fleetforce__Interval_Value__c = 60000,
      fleetforce__Calendar_Interval_Months__c = 60,
      fleetforce__Warning_Miles__c = 3000
    );
    insert plan;

    fleetforce__Maintenance_Plan_Line_Item__c m1 = new fleetforce__Maintenance_Plan_Line_Item__c(
      Name = '15,000-Mile Scheduled Service',
      fleetforce__Maintenance_Plan__c = plan.Id,
      fleetforce__Type__c = 'Milestone / Service Package',
      fleetforce__Sequence__c = 1,
      fleetforce__Milestone_Mileage__c = 15000,
      fleetforce__Milestone_Months__c = 12,
      fleetforce__Service_Category__c = 'Comprehensive Service',
      fleetforce__Estimated_Cost__c = 210.00,
      fleetforce__Estimated_Hours__c = 1.8
    );
    insert m1;

    fleetforce__Maintenance_Plan_Line_Item__c c1 = new fleetforce__Maintenance_Plan_Line_Item__c(
      Name = 'Synthetic Engine Oil & Filter Change',
      fleetforce__Maintenance_Plan__c = plan.Id,
      fleetforce__Parent_Line_Item__c = m1.Id,
      fleetforce__Type__c = 'Fluid & Filter Service',
      fleetforce__Sequence__c = 1,
      fleetforce__Service_Category__c = 'Oil & Fluids',
      fleetforce__Estimated_Cost__c = 95.00,
      fleetforce__Estimated_Hours__c = 0.8
    );
    insert c1;

    fleetforce__Fleet_Asset__c asset = new fleetforce__Fleet_Asset__c(
      Name = '2024 Honda Accord · SF-101',
      fleetforce__VIN__c = '1HGCR2F83HA123456',
      fleetforce__Body_Type__c = 'Sedan',
      fleetforce__Make__c = 'Honda',
      fleetforce__Model__c = 'Accord',
      fleetforce__Odometer__c = 14200,
      fleetforce__Branch__c = branch.Id,
      fleetforce__Assigned_Maintenance_Plan__c = plan.Id
    );
    insert asset;

    fleetforce__Fleet_Asset__c unassignedAsset = new fleetforce__Fleet_Asset__c(
      Name = '2023 Toyota Camry · SF-102',
      fleetforce__VIN__c = '4T1B11HK5JU123456',
      fleetforce__Body_Type__c = 'Sedan',
      fleetforce__Make__c = 'Toyota',
      fleetforce__Model__c = 'Camry',
      fleetforce__Odometer__c = 8500,
      fleetforce__Branch__c = branch.Id
    );
    insert unassignedAsset;
  }

  @IsTest
  static void testGetPlanOverview() {
    fleetforce__Maintenance_Plan__c plan = [
      SELECT Id
      FROM fleetforce__Maintenance_Plan__c
      LIMIT 1
    ];

    Test.startTest();
    MaintenancePlanOverviewController.PlanOverviewPayload payload = MaintenancePlanOverviewController.getPlanOverview(
      plan.Id
    );
    Test.stopTest();

    System.assertNotEquals(null, payload);
    System.assertEquals(1, payload.milestones.size());
    System.assertEquals(1, payload.kpis.milestonesCount);
    System.assertEquals(1, payload.kpis.proceduresCount);
    System.assertEquals(1, payload.assignedAssets.size());
    System.assertEquals(
      '15,000-Mile Scheduled Service',
      payload.assignedAssets[0].nextMilestoneName
    );
  }

  @IsTest
  static void testCreateMilestoneAndChildProcedure() {
    fleetforce__Maintenance_Plan__c plan = [
      SELECT Id
      FROM fleetforce__Maintenance_Plan__c
      LIMIT 1
    ];

    Test.startTest();
    Id newMilestoneId = MaintenancePlanOverviewController.createMilestone(
      plan.Id,
      '30,000-Mile Scheduled Service',
      2,
      30000,
      24,
      'Comprehensive Service',
      250,
      2.0,
      'Spark Plugs, Filters',
      'Follow OEM checklist'
    );
    System.assertNotEquals(null, newMilestoneId);

    Id newChildId = MaintenancePlanOverviewController.createChildProcedure(
      plan.Id,
      newMilestoneId,
      'Replace Iridium Spark Plugs',
      'Component / Part Replacement',
      1,
      'Powertrain',
      120,
      1.0,
      '4x Iridium plugs',
      'Torque to spec'
    );
    System.assertNotEquals(null, newChildId);
    Test.stopTest();

    fleetforce__Maintenance_Plan_Line_Item__c childRec = [
      SELECT Id, fleetforce__Parent_Line_Item__c, fleetforce__Type__c
      FROM fleetforce__Maintenance_Plan_Line_Item__c
      WHERE Id = :newChildId
    ];
    System.assertEquals(
      newMilestoneId,
      childRec.fleetforce__Parent_Line_Item__c
    );
    System.assertEquals(
      'Component / Part Replacement',
      childRec.fleetforce__Type__c
    );
  }

  @IsTest
  static void testAssignAndUnassignAssets() {
    fleetforce__Maintenance_Plan__c plan = [
      SELECT Id
      FROM fleetforce__Maintenance_Plan__c
      LIMIT 1
    ];
    fleetforce__Fleet_Asset__c unassigned = [
      SELECT Id
      FROM fleetforce__Fleet_Asset__c
      WHERE fleetforce__Assigned_Maintenance_Plan__c = NULL
      LIMIT 1
    ];

    Test.startTest();
    MaintenancePlanOverviewController.assignAssets(
      plan.Id,
      new List<Id>{ unassigned.Id }
    );
    fleetforce__Fleet_Asset__c assignedCheck = [
      SELECT fleetforce__Assigned_Maintenance_Plan__c
      FROM fleetforce__Fleet_Asset__c
      WHERE Id = :unassigned.Id
    ];
    System.assertEquals(
      plan.Id,
      assignedCheck.fleetforce__Assigned_Maintenance_Plan__c
    );

    MaintenancePlanOverviewController.unassignAsset(unassigned.Id);
    fleetforce__Fleet_Asset__c unassignedCheck = [
      SELECT fleetforce__Assigned_Maintenance_Plan__c
      FROM fleetforce__Fleet_Asset__c
      WHERE Id = :unassigned.Id
    ];
    System.assertEquals(
      null,
      unassignedCheck.fleetforce__Assigned_Maintenance_Plan__c
    );
    Test.stopTest();
  }

  @IsTest
  static void testDeleteLineItem() {
    fleetforce__Maintenance_Plan_Line_Item__c item = [
      SELECT Id
      FROM fleetforce__Maintenance_Plan_Line_Item__c
      WHERE fleetforce__Parent_Line_Item__c != NULL
      LIMIT 1
    ];

    Test.startTest();
    MaintenancePlanOverviewController.deleteLineItem(item.Id);
    Test.stopTest();

    List<fleetforce__Maintenance_Plan_Line_Item__c> remaining = [
      SELECT Id
      FROM fleetforce__Maintenance_Plan_Line_Item__c
      WHERE Id = :item.Id
    ];
    System.assertEquals(0, remaining.size());
  }

  @IsTest
  static void testValidationExceptions() {
    try {
      MaintenancePlanOverviewController.getPlanOverview(null);
      System.assert(false, 'Expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assert(true);
    }

    try {
      MaintenancePlanOverviewController.createMilestone(
        null,
        '',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null
      );
      System.assert(false, 'Expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assert(true);
    }
  }
}
