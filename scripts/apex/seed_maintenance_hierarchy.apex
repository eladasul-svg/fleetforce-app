// 1. Update PM-007 record to represent a comprehensive broad Maintenance Plan
fleetforce__Maintenance_Plan__c sedansPlan = [
    SELECT Id, Name, fleetforce__Asset_Type__c, fleetforce__Calendar_Interval_Months__c, 
           fleetforce__Interval_Value__c, fleetforce__Warning_Miles__c
    FROM fleetforce__Maintenance_Plan__c
    WHERE Id = 'a0RWm000001otLpMAI'
    LIMIT 1
];

sedansPlan.Name = 'Kia Sedona & Passenger Fleet 5-Year Gold Plan';
sedansPlan.fleetforce__Asset_Type__c = 'Sedan';
sedansPlan.fleetforce__Calendar_Interval_Months__c = 60;
sedansPlan.fleetforce__Interval_Value__c = 60000;
sedansPlan.fleetforce__Warning_Miles__c = 3000;
sedansPlan.fleetforce__SOP_Checklist__c = 'Manufacturer recommended 5-Year / 60,000-Mile Scheduled Maintenance Program for passenger sedans and minivans.';
update sedansPlan;

// 2. Clear old line items on this plan if any
delete [SELECT Id FROM fleetforce__Maintenance_Plan_Line_Item__c WHERE fleetforce__Maintenance_Plan__c = :sedansPlan.Id];

// 3. Create Milestone Line Items for Sedona Gold Plan
fleetforce__Maintenance_Plan_Line_Item__c m15 = new fleetforce__Maintenance_Plan_Line_Item__c(
    Name = '15,000-Mile Scheduled Service',
    fleetforce__Maintenance_Plan__c = sedansPlan.Id,
    fleetforce__Type__c = 'Milestone / Service Package',
    fleetforce__Sequence__c = 1,
    fleetforce__Milestone_Mileage__c = 15000,
    fleetforce__Milestone_Months__c = 12,
    fleetforce__Service_Category__c = 'Comprehensive Service',
    fleetforce__Estimated_Cost__c = 210.00,
    fleetforce__Estimated_Hours__c = 1.8,
    fleetforce__Components_Serviced__c = 'Engine Oil, Oil Filter, Tire Rotation, Brake Inspection'
);

fleetforce__Maintenance_Plan_Line_Item__c m30 = new fleetforce__Maintenance_Plan_Line_Item__c(
    Name = '30,000-Mile Scheduled Service',
    fleetforce__Maintenance_Plan__c = sedansPlan.Id,
    fleetforce__Type__c = 'Milestone / Service Package',
    fleetforce__Sequence__c = 2,
    fleetforce__Milestone_Mileage__c = 30000,
    fleetforce__Milestone_Months__c = 24,
    fleetforce__Service_Category__c = 'Comprehensive Service',
    fleetforce__Estimated_Cost__c = 270.00,
    fleetforce__Estimated_Hours__c = 1.9,
    fleetforce__Components_Serviced__c = 'Engine Air Filter, Cabin Filter, Brake Fluid Exchange'
);

fleetforce__Maintenance_Plan_Line_Item__c m60 = new fleetforce__Maintenance_Plan_Line_Item__c(
    Name = '60,000-Mile Major Powertrain & Ignition Service',
    fleetforce__Maintenance_Plan__c = sedansPlan.Id,
    fleetforce__Type__c = 'Milestone / Service Package',
    fleetforce__Sequence__c = 3,
    fleetforce__Milestone_Mileage__c = 60000,
    fleetforce__Milestone_Months__c = 48,
    fleetforce__Service_Category__c = 'Powertrain',
    fleetforce__Estimated_Cost__c = 810.00,
    fleetforce__Estimated_Hours__c = 5.0,
    fleetforce__Components_Serviced__c = 'Spark Plugs, Fuel Flush, Transmission Fluid, Coolant Flush'
);

insert new List<fleetforce__Maintenance_Plan_Line_Item__c>{ m15, m30, m60 };

// 4. Create Child Line Items under the Milestones
List<fleetforce__Maintenance_Plan_Line_Item__c> children = new List<fleetforce__Maintenance_Plan_Line_Item__c>{
    // Children of 15k
    new fleetforce__Maintenance_Plan_Line_Item__c(
        Name = 'Synthetic Engine Oil & Filter Change',
        fleetforce__Maintenance_Plan__c = sedansPlan.Id,
        fleetforce__Parent_Line_Item__c = m15.Id,
        fleetforce__Type__c = 'Fluid & Filter Service',
        fleetforce__Sequence__c = 1,
        fleetforce__Service_Category__c = 'Oil & Fluids',
        fleetforce__Estimated_Cost__c = 95.00,
        fleetforce__Estimated_Hours__c = 0.8,
        fleetforce__Components_Serviced__c = '0W-20 Full Synthetic Oil, OEM Oil Filter'
    ),
    new fleetforce__Maintenance_Plan_Line_Item__c(
        Name = 'Radial Tire Rotation & Tread Depth Check',
        fleetforce__Maintenance_Plan__c = sedansPlan.Id,
        fleetforce__Parent_Line_Item__c = m15.Id,
        fleetforce__Type__c = 'Tire & Brake Service',
        fleetforce__Sequence__c = 2,
        fleetforce__Service_Category__c = 'Tires & Brakes',
        fleetforce__Estimated_Cost__c = 65.00,
        fleetforce__Estimated_Hours__c = 0.5,
        fleetforce__Components_Serviced__c = 'Tire Rotation, Pressure Check, Tread Gauge'
    ),
    new fleetforce__Maintenance_Plan_Line_Item__c(
        Name = 'Multi-Point Chassis & Brake Safety Inspection',
        fleetforce__Maintenance_Plan__c = sedansPlan.Id,
        fleetforce__Parent_Line_Item__c = m15.Id,
        fleetforce__Type__c = 'Inspection / Diagnostic',
        fleetforce__Sequence__c = 3,
        fleetforce__Service_Category__c = 'Annual Inspection',
        fleetforce__Estimated_Cost__c = 50.00,
        fleetforce__Estimated_Hours__c = 0.5,
        fleetforce__Components_Serviced__c = 'Pads, Rotors, Calipers, Steering, Suspension'
    ),

    // Children of 30k
    new fleetforce__Maintenance_Plan_Line_Item__c(
        Name = 'Engine & Cabin Micro-Air Filter Replacement',
        fleetforce__Maintenance_Plan__c = sedansPlan.Id,
        fleetforce__Parent_Line_Item__c = m30.Id,
        fleetforce__Type__c = 'Component / Part Replacement',
        fleetforce__Sequence__c = 1,
        fleetforce__Service_Category__c = 'Comprehensive Service',
        fleetforce__Estimated_Cost__c = 85.00,
        fleetforce__Estimated_Hours__c = 0.5,
        fleetforce__Components_Serviced__c = 'Engine Air Filter, HEPA Cabin Filter'
    ),
    new fleetforce__Maintenance_Plan_Line_Item__c(
        Name = 'DOT 4 Brake Fluid Exchange & Bleed',
        fleetforce__Maintenance_Plan__c = sedansPlan.Id,
        fleetforce__Parent_Line_Item__c = m30.Id,
        fleetforce__Type__c = 'Fluid & Filter Service',
        fleetforce__Sequence__c = 2,
        fleetforce__Service_Category__c = 'Tires & Brakes',
        fleetforce__Estimated_Cost__c = 140.00,
        fleetforce__Estimated_Hours__c = 1.0,
        fleetforce__Components_Serviced__c = 'Brake Fluid System Flush'
    ),

    // Children of 60k
    new fleetforce__Maintenance_Plan_Line_Item__c(
        Name = 'OEM Iridium Spark Plug Set Replacement',
        fleetforce__Maintenance_Plan__c = sedansPlan.Id,
        fleetforce__Parent_Line_Item__c = m60.Id,
        fleetforce__Type__c = 'Component / Part Replacement',
        fleetforce__Sequence__c = 1,
        fleetforce__Service_Category__c = 'Powertrain',
        fleetforce__Estimated_Cost__c = 220.00,
        fleetforce__Estimated_Hours__c = 1.5,
        fleetforce__Components_Serviced__c = '6x Iridium Spark Plugs, Ignition Boot Inspection'
    ),
    new fleetforce__Maintenance_Plan_Line_Item__c(
        Name = 'Fuel Induction & Injection System Flush',
        fleetforce__Maintenance_Plan__c = sedansPlan.Id,
        fleetforce__Parent_Line_Item__c = m60.Id,
        fleetforce__Type__c = 'Fluid & Filter Service',
        fleetforce__Sequence__c = 2,
        fleetforce__Service_Category__c = 'Powertrain',
        fleetforce__Estimated_Cost__c = 180.00,
        fleetforce__Estimated_Hours__c = 1.0,
        fleetforce__Components_Serviced__c = 'Throttle Body Cleaner, Fuel Injector Detergent'
    ),
    new fleetforce__Maintenance_Plan_Line_Item__c(
        Name = 'Automatic Transmission Fluid Flush & Exchange',
        fleetforce__Maintenance_Plan__c = sedansPlan.Id,
        fleetforce__Parent_Line_Item__c = m60.Id,
        fleetforce__Type__c = 'Fluid & Filter Service',
        fleetforce__Sequence__c = 3,
        fleetforce__Service_Category__c = 'Powertrain',
        fleetforce__Estimated_Cost__c = 260.00,
        fleetforce__Estimated_Hours__c = 1.5,
        fleetforce__Components_Serviced__c = 'ATF Synthetic Fluid, Pan Gasket'
    ),
    new fleetforce__Maintenance_Plan_Line_Item__c(
        Name = 'Engine Cooling System Drain & Antifreeze Refill',
        fleetforce__Maintenance_Plan__c = sedansPlan.Id,
        fleetforce__Parent_Line_Item__c = m60.Id,
        fleetforce__Type__c = 'Fluid & Filter Service',
        fleetforce__Sequence__c = 4,
        fleetforce__Service_Category__c = 'Oil & Fluids',
        fleetforce__Estimated_Cost__c = 150.00,
        fleetforce__Estimated_Hours__c = 1.0,
        fleetforce__Components_Serviced__c = '50/50 OAT Coolant, Radiator Pressure Test'
    )
};

insert children;

// 5. Update F-150 Plan Line Items to have Type = 'Milestone / Service Package'
List<fleetforce__Maintenance_Plan_Line_Item__c> f150Items = [
    SELECT Id, Name, fleetforce__Type__c, fleetforce__Parent_Line_Item__c 
    FROM fleetforce__Maintenance_Plan_Line_Item__c 
    WHERE fleetforce__Maintenance_Plan__r.Name LIKE '%Ford F-150%'
];
for (fleetforce__Maintenance_Plan_Line_Item__c item : f150Items) {
    item.fleetforce__Type__c = 'Milestone / Service Package';
}
update f150Items;

System.debug('Maintenance Plan Hierarchy seeding completed successfully!');
