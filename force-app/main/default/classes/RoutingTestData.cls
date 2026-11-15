/**
 * Test data for the routing module: a Beer Sheva depot, drivers Dana and Yossi, vans (one EV, one with
 * an open in-shop ticket, one whose driver's licence has expired), a draft plan for tomorrow and jobs
 * around the depot. Coordinates only, no street addresses.
 */
@IsTest
public class RoutingTestData {
  public static final Decimal DEPOT_LAT = 31.2518;
  public static final Decimal DEPOT_LON = 34.7913;
  public static final List<String> PERMISSION_SETS = new List<String>{
    'FleetAdmin',
    'FleetforceAdmin',
    'FleetforceRouting',
    'FleetforceAssistantUser'
  };

  /**
   * Routing objects are only reachable in USER_MODE through these permission sets. As in
   * AssistantServiceTest, an assignment made in @TestSetup is only honoured by USER_MODE checks when
   * the code under test runs inside a fresh System.runAs(self()) block.
   */
  public static void grantAccess() {
    Id userId = UserInfo.getUserId();
    Set<Id> assigned = new Set<Id>();
    for (PermissionSetAssignment a : [
      SELECT PermissionSetId
      FROM PermissionSetAssignment
      WHERE AssigneeId = :userId
    ]) {
      assigned.add(a.PermissionSetId);
    }
    List<PermissionSetAssignment> toAssign = new List<PermissionSetAssignment>();
    for (PermissionSet ps : [
      SELECT Id
      FROM PermissionSet
      WHERE Name IN :PERMISSION_SETS
    ]) {
      if (!assigned.contains(ps.Id)) {
        toAssign.add(
          new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = ps.Id
          )
        );
      }
    }
    if (!toAssign.isEmpty()) {
      System.runAs(self()) {
        insert toAssign;
      }
    }
  }

  public static User self() {
    return new User(Id = UserInfo.getUserId());
  }

  public static Date planDate() {
    return Date.today().addDays(1);
  }

  public static TimeZone tz() {
    return TimeZone.getTimeZone('Asia/Jerusalem');
  }

  public static Datetime local(Integer hour, Integer minute) {
    return RoutePlanService.localToGmt(
      planDate(),
      Time.newInstance(hour, minute, 0, 0),
      tz()
    );
  }

  /** Builds the standard scenario and returns the plan Id. */
  public static Id scenario(Integer drops) {
    Fleet_Branch__c depot = new Fleet_Branch__c(
      Name = 'Beer Sheva Depot',
      Location__Latitude__s = DEPOT_LAT,
      Location__Longitude__s = DEPOT_LON,
      Time_Zone__c = 'Asia/Jerusalem'
    );
    insert depot;

    Contact dana = new Contact(
      FirstName = 'Dana',
      LastName = 'Levi',
      License_Expiry__c = Date.today().addYears(1)
    );
    Contact yossi = new Contact(
      FirstName = 'Yossi',
      LastName = 'Cohen',
      License_Expiry__c = Date.today().addYears(1)
    );
    Contact avi = new Contact(
      FirstName = 'Avi',
      LastName = 'Mizrahi',
      License_Expiry__c = Date.today().addDays(-3)
    );
    insert new List<Contact>{ dana, yossi, avi };
    insert new Driver_Qualification__c(
      Driver__c = yossi.Id,
      Name = 'Hazmat',
      Status__c = 'Valid',
      Valid_Until__c = Date.today().addYears(1)
    );

    Fleet_Asset__c van1 = van('RT-VAN-1', depot.Id, dana.Id);
    van1.Vehicle_Features__c = 'Lift Gate';
    Fleet_Asset__c van2 = van('RT-VAN-2 EV', depot.Id, yossi.Id);
    van2.Fuel_Type__c = 'Electric';
    Fleet_Asset__c van3 = van('RT-VAN-3 IN SHOP', depot.Id, null);
    Fleet_Asset__c van4 = van('RT-VAN-4 EXPIRED', depot.Id, avi.Id);
    insert new List<Fleet_Asset__c>{ van1, van2, van3, van4 };
    insert new Service_Ticket__c(
      Fleet_Asset__c = van3.Id,
      Status__c = 'In-Shop',
      Priority__c = 'High',
      Actual_Start__c = Date.today().addDays(-1)
    );

    Route_Plan__c plan = new Route_Plan__c(
      Name = 'Beer Sheva · tomorrow',
      Plan_Date__c = planDate(),
      Depot_Branch__c = depot.Id,
      Status__c = 'Draft',
      Provider__c = 'FleetForce Routing',
      Objective__c = 'Min Duration'
    );
    insert plan;

    List<Route_Job__c> jobs = new List<Route_Job__c>();
    for (Integer i = 0; i < drops; i++) {
      jobs.add(job('Delivery', depot.Id));
    }
    Route_Job__c relocation = job('Relocation', depot.Id);
    Route_Job__c refrigerated = job('Delivery', depot.Id);
    refrigerated.Required_Skills__c = 'Refrigerated';
    Route_Job__c noLocation = job('Delivery', depot.Id);
    Route_Job__c otherDay = job('Delivery', depot.Id);
    otherDay.Service_Date__c = planDate().addDays(3);
    jobs.addAll(
      new List<Route_Job__c>{ relocation, refrigerated, noLocation, otherDay }
    );
    insert jobs;

    List<Job_Visit__c> visits = new List<Job_Visit__c>();
    for (Integer i = 0; i < drops; i++) {
      visits.add(visit(jobs[i].Id, 'Delivery', i));
    }
    visits.add(visit(relocation.Id, 'Pickup', 20));
    Job_Visit__c drop = visit(relocation.Id, 'Delivery', 21);
    drop.Window_Start__c = null;
    drop.Window_End__c = null;
    visits.add(drop);
    visits.add(visit(refrigerated.Id, 'Delivery', 22));
    Job_Visit__c lost = visit(noLocation.Id, 'Delivery', 23);
    lost.Location__Latitude__s = null;
    lost.Location__Longitude__s = null;
    visits.add(lost);
    visits.add(visit(otherDay.Id, 'Delivery', 24));
    insert visits;
    return plan.Id;
  }

  public static Fleet_Asset__c van(String name, Id branchId, Id driverId) {
    return new Fleet_Asset__c(
      Name = name,
      Branch__c = branchId,
      Driver__c = driverId,
      Status__c = 'Available',
      Is_Active__c = true,
      Fuel_Type__c = 'Diesel',
      Payload_Kg__c = 800,
      Cargo_Volume_M3__c = 6,
      Pallet_Capacity__c = 4
    );
  }

  public static Route_Job__c job(String type, Id branchId) {
    return new Route_Job__c(
      Type__c = type,
      Status__c = 'Ready',
      Service_Date__c = planDate(),
      Branch__c = branchId,
      Priority__c = 10
    );
  }

  /** A visit on a small spiral around the depot, window 08:00-16:00 local. */
  public static Job_Visit__c visit(Id jobId, String role, Integer i) {
    Decimal angle = i * 0.9;
    Decimal radius = 0.004 + 0.0015 * i;
    return new Job_Visit__c(
      Route_Job__c = jobId,
      Role__c = role,
      Location__Latitude__s = (DEPOT_LAT +
        radius * Decimal.valueOf(Math.sin(angle.doubleValue())))
        .setScale(6),
      Location__Longitude__s = (DEPOT_LON +
        radius * Decimal.valueOf(Math.cos(angle.doubleValue())))
        .setScale(6),
      Window_Start__c = local(8, 0),
      Window_End__c = local(16, 0),
      Hard_Window__c = true,
      Service_Minutes__c = 6,
      Load_1__c = 25,
      Load_2__c = 0.2,
      Load_3__c = 0
    );
  }

  public static Map<String, Fleet_Asset__c> assetsByName() {
    Map<String, Fleet_Asset__c> out = new Map<String, Fleet_Asset__c>();
    for (Fleet_Asset__c a : [
      SELECT Id, Name, Driver__c
      FROM Fleet_Asset__c
      WHERE Name LIKE 'RT-VAN-%'
    ]) {
      out.put(a.Name, a);
    }
    return out;
  }

  // ---------------------------------------------------------------------------------------------
  // HTTP mock that answers like the FleetForce Routing Service, from the request itself
  // ---------------------------------------------------------------------------------------------

  /**
   * Echo service: puts every job and shipment of the request onto the first vehicle in request order,
   * 10 minutes apart, except jobs whose skills no vehicle has, which come back unassigned.
   */
  public class EchoService implements HttpCalloutMock {
    public Integer calls = 0;
    public String lastBody;
    public String lastEndpoint;
    public Integer statusCode = 200;
    public String errorBody;

    public HttpResponse respond(HttpRequest req) {
      calls++;
      lastBody = req.getBody();
      lastEndpoint = req.getEndpoint();
      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'application/json');
      res.setStatusCode(statusCode);
      res.setBody(statusCode == 200 ? answer(lastBody) : errorBody);
      return res;
    }
  }

  public static String answer(String requestBody) {
    Map<String, Object> req = (Map<String, Object>) JSON.deserializeUntyped(
      requestBody
    );
    List<Object> vehicles = (List<Object>) req.get('vehicles');
    Map<String, Object> v = (Map<String, Object>) vehicles[0];
    Set<String> skills = new Set<String>();
    for (Object o : vehicles) {
      for (Object sk : (List<Object>) ((Map<String, Object>) o).get('skills')) {
        skills.add((String) sk);
      }
    }
    Datetime t = RoutingDtos.dt(v.get('shift_start'));
    List<Object> steps = new List<Object>{
      step('start', null, v.get('start'), t, false)
    };
    List<Object> unassigned = new List<Object>();
    for (Object o : (List<Object>) req.get('jobs')) {
      Map<String, Object> j = (Map<String, Object>) o;
      Set<String> needed = new Set<String>();
      for (Object sk : (List<Object>) j.get('skills')) {
        needed.add((String) sk);
      }
      if (!skills.containsAll(needed)) {
        unassigned.add(
          new Map<String, Object>{
            'id' => j.get('id'),
            'type' => 'job',
            'reason' => 'skills',
            'detail' => 'No vehicle has the skill(s): ' +
            String.join(new List<String>(needed), ', ') +
            '.'
          }
        );
        continue;
      }
      t = t.addMinutes(10);
      steps.add(step('job', (String) j.get('id'), j.get('location'), t, false));
    }
    for (Object o : (List<Object>) req.get('shipments')) {
      Map<String, Object> s = (Map<String, Object>) o;
      Map<String, Object> p = (Map<String, Object>) s.get('pickup');
      Map<String, Object> d = (Map<String, Object>) s.get('delivery');
      t = t.addMinutes(10);
      steps.add(
        step('pickup', (String) p.get('id'), p.get('location'), t, false)
      );
      t = t.addMinutes(10);
      steps.add(
        step('delivery', (String) d.get('id'), d.get('location'), t, false)
      );
    }
    t = t.addMinutes(10);
    steps.add(step('end', null, v.get('end'), t, false));
    Integer distance = 1000 * (steps.size() - 1);
    Datetime start = RoutingDtos.dt(v.get('shift_start'));
    Integer duration = ((t.getTime() - start.getTime()) / 1000).intValue();
    return JSON.serialize(
      new Map<String, Object>{
        'routes' => new List<Object>{
          new Map<String, Object>{
            'vehicle_id' => v.get('id'),
            'steps' => steps,
            'distance_m' => distance,
            'duration_s' => duration,
            'service_s' => 0,
            'waiting_s' => 0,
            'start_time' => RoutingDtos.iso(start),
            'end_time' => RoutingDtos.iso(t),
            'geometry' => '_p~iF~ps|U_ulLnnqC'
          }
        },
        'unassigned' => unassigned,
        'summary' => new Map<String, Object>{
          'routes' => 1,
          'assigned' => steps.size() - 2,
          'unassigned' => unassigned.size(),
          'distance_m' => distance,
          'duration_s' => duration,
          'service_s' => 0,
          'waiting_s' => 0,
          'cost' => duration,
          'matrix_source' => 'haversine',
          'solve_ms' => 12
        }
      }
    );
  }

  private static Map<String, Object> step(
    String type,
    String id,
    Object location,
    Datetime t,
    Boolean locked
  ) {
    return new Map<String, Object>{
      'type' => type,
      'id' => id,
      'location' => location,
      'arrival' => RoutingDtos.iso(t),
      'departure' => RoutingDtos.iso(
        t.addMinutes(type == 'start' || type == 'end' ? 0 : 6)
      ),
      'service_seconds' => type == 'start' || type == 'end' ? 0 : 360,
      'waiting_seconds' => 0,
      'leg_distance_m' => type == 'start' ? 0 : 1000,
      'leg_duration_s' => type == 'start' ? 0 : 240,
      'load' => new List<Object>{ 0, 0, 0 },
      'locked' => locked,
      'late_seconds' => 0
    };
  }
}
