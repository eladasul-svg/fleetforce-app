/**
 * Document scan extraction (Claude Vision), geocoding (Openrouteservice), job/visit creation, and
 * single-stop route re-optimization for the driver app's Route tab.
 *
 * Runs without sharing so the guest-site driver demo works alongside authenticated drivers/dispatchers:
 * when the running user has full USER_MODE routing permissions, addVisitToRoute delegates directly to
 * RouteReplanService; when running as the Motorpool guest user (whose license forbids Delete/Edit
 * in USER_MODE), it uses a system-mode equivalent built on RoutePlanService's public helpers.
 */
public without sharing class DriverRouteScanService {
  public class ScanException extends Exception {
  }

  public class ScanResult {
    @AuraEnabled
    public String docType;
    @AuraEnabled
    public String docNumber;
    @AuraEnabled
    public String bolNumber;
    @AuraEnabled
    public String orderNumber;
    @AuraEnabled
    public String customerName;
    @AuraEnabled
    public String customerCode;
    @AuraEnabled
    public String supplierName;
    @AuraEnabled
    public String origin;
    @AuraEnabled
    public String destinationAddress;
    @AuraEnabled
    public String destinationCity;
    @AuraEnabled
    public String siteCode;
    @AuraEnabled
    public String contactName;
    @AuraEnabled
    public String contactPhone;
    @AuraEnabled
    public String truckPlate;
    @AuraEnabled
    public String serviceDate;
    @AuraEnabled
    public String cargoSummary;
    @AuraEnabled
    public Decimal weightKg;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public String geocodedLabel;
    @AuraEnabled
    public String geocodeWarning;
  }

  public class GeoPoint {
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String warning;
  }

  public class CreatedJobResult {
    @AuraEnabled
    public Id jobId;
    @AuraEnabled
    public Id visitId;
    @AuraEnabled
    public Id contentVersionId;
  }

  public class AddVisitResult {
    @AuraEnabled
    public Id routeId;
    @AuraEnabled
    public Id routePlanId;
    @AuraEnabled
    public Boolean assigned;
    @AuraEnabled
    public String unassignedReason;
    @AuraEnabled
    public Decimal revision;
    @AuraEnabled
    public Integer movedStops;
    @AuraEnabled
    public Decimal distanceKm;
    @AuraEnabled
    public String plannedEnd;
  }

  private static final Integer CLAUDE_MAX_TOKENS = 2048;
  private static final Integer DEFAULT_SCAN_SERVICE_MINUTES = 10;
  private static final Set<String> SUPPORTED_IMAGE_TYPES = new Set<String>{
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp'
  };

  private static final String EXTRACTION_SYSTEM_PROMPT =
    'You are a logistics document extraction assistant for FleetForce. ' +
    'Read printed and handwritten Hebrew and English delivery notes, bills of lading (שטר מטען), and dispatch slips across all pages. ' +
    'Return ONLY a single valid JSON object (no markdown fences, no commentary) with these exact keys (use null when absent): ' +
    'docType (string, e.g. "Delivery Note" or "Bill of Lading"), ' +
    'docNumber (string, delivery note number such as SH26011985), ' +
    'bolNumber (string, bill of lading number such as 7998), ' +
    'orderNumber (string, order number such as SO26007097), ' +
    'customerName (string, recipient company name), ' +
    'customerCode (string, customer ID), ' +
    'supplierName (string, supplier/sender company name), ' +
    'origin (string, origin city/warehouse), ' +
    'destinationAddress (string, full destination address/neighborhood/site if given), ' +
    'destinationCity (string, destination city/locality name alone for geocoding), ' +
    'siteCode (string, site code/number if given), ' +
    'contactName (string, site contact person), ' +
    'contactPhone (string, best phone/mobile number), ' +
    'truckPlate (string, vehicle/truck number), ' +
    'serviceDate (string, YYYY-MM-DD if clear, otherwise null), ' +
    'cargoSummary (string, concise item/quantity summary), ' +
    'weightKg (number, total numeric weight in kg, or null).';

  // ---------------------------------------------------------------------------------------------
  // 1. Vision extraction + geocoding (callout only, no DML)
  // ---------------------------------------------------------------------------------------------

  public static ScanResult scanDocument(
    String base64Data,
    String mimeType,
    String fileName
  ) {
    if (String.isBlank(base64Data)) {
      throw new ScanException('Please choose an image or PDF to scan.');
    }

    String normalizedMime = normalizeMimeType(mimeType, fileName);
    Map<String, Object> mediaBlock = buildMediaBlock(
      base64Data,
      normalizedMime
    );
    Map<String, Object> requestBody = new Map<String, Object>{
      'model' => AssistantClaudeClient.getModel(),
      'max_tokens' => CLAUDE_MAX_TOKENS,
      'system' => EXTRACTION_SYSTEM_PROMPT,
      'messages' => new List<Object>{
        new Map<String, Object>{
          'role' => 'user',
          'content' => new List<Object>{
            mediaBlock,
            new Map<String, Object>{
              'type' => 'text',
              'text' => 'Extract the delivery destination, recipient, contact, vehicle, cargo, and document identifiers as JSON.'
            }
          }
        }
      }
    };

    Map<String, Object> response;
    try {
      response = AssistantClaudeClient.send(requestBody);
    } catch (AssistantClaudeClient.ClaudeException e) {
      throw new ScanException(e.getMessage());
    }

    String jsonText = extractTextContent(response);
    ScanResult res = parseScanResult(jsonText);

    GeoPoint geo = geocodeAddress(res.destinationAddress, res.destinationCity);
    res.latitude = geo.latitude;
    res.longitude = geo.longitude;
    res.geocodedLabel = geo.label;
    res.geocodeWarning = geo.warning;
    return res;
  }

  public static GeoPoint geocodeAddress(String address, String city) {
    GeoPoint out = new GeoPoint();
    List<String> candidates = buildGeocodeCandidates(address, city);
    if (candidates.isEmpty()) {
      out.warning = 'No destination address was extracted; enter coordinates or city.';
      return out;
    }

    String nc =
      'callout:' +
      RoutingProviders.namedCredential(OrsRoutingProvider.NAMED_CREDENTIAL);
    String lastError;
    for (Integer i = 0; i < candidates.size(); i++) {
      String query = candidates[i];
      String url =
        nc +
        '/geocode/search?text=' +
        EncodingUtil.urlEncode(query, 'UTF-8') +
        '&boundary.country=IL&size=1';
      try {
        String body = RoutingProviders.send(url, null, null);
        GeoPoint hit = parseGeoJson(body);
        if (hit != null) {
          if (i > 0 && String.isNotBlank(address) && query != address.trim()) {
            hit.warning =
              'Matched broader location "' +
              query +
              '". Verify pin before adding.';
          }
          return hit;
        }
      } catch (Exception e) {
        lastError = e.getMessage();
      }
    }

    out.warning = String.isNotBlank(lastError)
      ? 'Geocoding failed: ' + lastError
      : 'Could not geocode "' +
        candidates[0] +
        '". Adjust the destination or enter coordinates.';
    return out;
  }

  // ---------------------------------------------------------------------------------------------
  // 2. Job, Visit & Attachment persistence (DML only)
  // ---------------------------------------------------------------------------------------------

  public static CreatedJobResult createScannedJob(
    Id routeId,
    Id driverId,
    String payloadJson,
    String base64Data,
    String mimeType,
    String fileName
  ) {
    if (routeId == null) {
      throw new ScanException('No active route was found for this driver.');
    }
    if (String.isBlank(payloadJson)) {
      throw new ScanException('Stop details are required.');
    }

    Map<String, Object> payload;
    try {
      payload = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
    } catch (Exception e) {
      throw new ScanException('Invalid stop payload.');
    }

    List<Route__c> routes = [
      SELECT
        Id,
        Route_Plan__c,
        Route_Plan__r.Plan_Date__c,
        Route_Plan__r.Depot_Branch__c
      FROM Route__c
      WHERE Id = :routeId
      LIMIT 1
    ];
    if (routes.isEmpty()) {
      throw new ScanException('Active route could not be loaded.');
    }
    Route__c route = routes[0];

    String address = str(payload.get('destinationAddress'));
    Decimal lat = dec(payload.get('latitude'));
    Decimal lon = dec(payload.get('longitude'));
    if (String.isBlank(address)) {
      throw new ScanException('Destination address is required.');
    }
    if (lat == null || lon == null) {
      throw new ScanException(
        'Coordinates are required before adding to the route.'
      );
    }

    String docNumber = str(payload.get('docNumber'));
    String bolNumber = str(payload.get('bolNumber'));
    String extId = uniqueExternalId(
      String.isNotBlank(docNumber) ? docNumber : bolNumber
    );

    Route_Job__c job = new Route_Job__c(
      Type__c = 'Delivery',
      Status__c = 'Ready',
      Service_Date__c = route.Route_Plan__r != null &&
        route.Route_Plan__r.Plan_Date__c != null
        ? route.Route_Plan__r.Plan_Date__c
        : Date.today(),
      Branch__c = route.Route_Plan__r == null
        ? null
        : route.Route_Plan__r.Depot_Branch__c,
      Planned_Route__c = route.Id,
      External_Id__c = extId,
      Notes__c = buildJobNotes(payload)
    );
    insert job;

    Decimal loadKg = dec(payload.get('loadKg'));
    Decimal svcMin = dec(payload.get('serviceMinutes'));
    Job_Visit__c visit = new Job_Visit__c(
      Route_Job__c = job.Id,
      Role__c = 'Delivery',
      Status__c = 'Pending',
      Address__c = address.abbreviate(255),
      Location__Latitude__s = lat,
      Location__Longitude__s = lon,
      Load_1__c = loadKg != null && loadKg > 0 ? loadKg : null,
      Service_Minutes__c = svcMin != null &&
        svcMin > 0
        ? svcMin
        : DEFAULT_SCAN_SERVICE_MINUTES,
      Access_Notes__c = buildAccessNotes(payload)
    );
    insert visit;

    Id cvId;
    if (String.isNotBlank(base64Data)) {
      String normalizedMime = normalizeMimeType(mimeType, fileName);
      String safeName = safeAttachmentName(fileName, docNumber, normalizedMime);
      ContentVersion cv = new ContentVersion(
        Title = safeName.substringBeforeLast('.'),
        PathOnClient = safeName,
        VersionData = EncodingUtil.base64Decode(base64Data),
        FirstPublishLocationId = job.Id
      );
      insert cv;
      cvId = cv.Id;
    }

    CreatedJobResult out = new CreatedJobResult();
    out.jobId = job.Id;
    out.visitId = visit.Id;
    out.contentVersionId = cvId;
    return out;
  }

  // ---------------------------------------------------------------------------------------------
  // 3. Re-optimize route with the new visit (callout first, then DML)
  // ---------------------------------------------------------------------------------------------

  public static AddVisitResult addVisitToRoute(Id routeId, Id visitId) {
    if (routeId == null || visitId == null) {
      throw new ScanException('Route Id and Visit Id are required.');
    }

    Boolean useUserMode = hasRoutingUserModeAccess();
    RouteReplanService.RouteContext ctx = useUserMode
      ? RouteReplanService.buildRequest(
          routeId,
          null,
          0,
          new Set<Id>{ visitId },
          null
        )
      : buildContextSystem(routeId, visitId);

    String providerName = ctx.route.Route_Plan__r != null &&
      String.isNotBlank(ctx.route.Route_Plan__r.Provider__c)
      ? ctx.route.Route_Plan__r.Provider__c
      : 'Openrouteservice';

    // ORS rejects locked/fixed prefixes; clear fixed steps when solving via ORS or Mock.
    if (providerName == 'Openrouteservice' || providerName == 'Mock') {
      ctx.request.fixed.clear();
    }

    // RouteReplanService falls back to +1h if Shift_End__c has already passed; extend for ad-hoc scans.
    if (!ctx.request.vehicles.isEmpty()) {
      RoutingDtos.Vehicle v = ctx.request.vehicles[0];
      if (
        ctx.route.Shift_End__c == null ||
        ctx.route.Shift_End__c <= ctx.startTime
      ) {
        v.shiftEnd = ctx.startTime.addHours(12);
      }
    }

    RoutingDtos.OptimizeResult result = RoutingProviders.forName(providerName)
      .optimize(ctx.request);

    if (useUserMode) {
      RouteReplanService.apply(ctx, result, null, 'Driver');
    } else {
      applySystem(ctx, result);
    }

    Job_Visit__c addedVisit = ctx.visits.get(visitId);
    RoutingDtos.Unassigned unassignedMatch = findUnassigned(
      result,
      visitId,
      addedVisit == null ? null : addedVisit.Route_Job__c
    );
    Boolean assigned = unassignedMatch == null;

    if (assigned && addedVisit != null && addedVisit.Route_Job__c != null) {
      update new Route_Job__c(
        Id = addedVisit.Route_Job__c,
        Status__c = 'Planned',
        Planned_Route__c = routeId,
        Unassigned_Reason__c = null
      );
    }

    Map<String, Object> diff = RouteReplanService.diff(ctx, result);
    logScanEvents(ctx, visitId, assigned, diff, useUserMode);

    if (ctx.route.Route_Plan__c != null) {
      RoutePlanOptimizeJob.publish(
        ctx.route.Route_Plan__c,
        'Optimized',
        ctx.route.Revision__c,
        assigned
          ? 'Stop added from driver scan'
          : 'Scanned stop could not be assigned'
      );
    }

    AddVisitResult out = new AddVisitResult();
    out.routeId = routeId;
    out.routePlanId = ctx.route.Route_Plan__c;
    out.assigned = assigned;
    out.unassignedReason = unassignedMatch == null
      ? null
      : (unassignedMatch.reason +
        (String.isBlank(unassignedMatch.detail)
          ? ''
          : ': ' + unassignedMatch.detail));
    out.revision = ctx.route.Revision__c;
    out.movedStops = (Integer) diff.get('movedStops');
    out.distanceKm = (Decimal) diff.get('distanceKm');
    out.plannedEnd = (String) diff.get('plannedEnd');
    return out;
  }

  // ---------------------------------------------------------------------------------------------
  // Vision & geocoding helpers
  // ---------------------------------------------------------------------------------------------

  @TestVisible
  private static String normalizeMimeType(String mimeType, String fileName) {
    String m = String.isBlank(mimeType) ? '' : mimeType.trim().toLowerCase();
    String f = String.isBlank(fileName) ? '' : fileName.trim().toLowerCase();
    if (m == 'application/pdf' || f.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (m == 'image/jpg') {
      return 'image/jpeg';
    }
    if (SUPPORTED_IMAGE_TYPES.contains(m)) {
      return m;
    }
    if (f.endsWith('.png')) {
      return 'image/png';
    }
    if (f.endsWith('.webp')) {
      return 'image/webp';
    }
    if (f.endsWith('.gif')) {
      return 'image/gif';
    }
    return 'image/jpeg';
  }

  private static Map<String, Object> buildMediaBlock(
    String base64Data,
    String mediaType
  ) {
    String blockType = mediaType == 'application/pdf' ? 'document' : 'image';
    return new Map<String, Object>{
      'type' => blockType,
      'source' => new Map<String, Object>{
        'type' => 'base64',
        'media_type' => mediaType,
        'data' => base64Data
      }
    };
  }

  @TestVisible
  private static String extractTextContent(Map<String, Object> response) {
    if (response == null) {
      throw new ScanException('Empty response from Claude.');
    }
    List<Object> blocks = (List<Object>) response.get('content');
    if (blocks == null) {
      throw new ScanException('Claude returned no content blocks.');
    }
    for (Object o : blocks) {
      Map<String, Object> block = (Map<String, Object>) o;
      if (block != null && block.get('type') == 'text') {
        String txt = (String) block.get('text');
        if (String.isNotBlank(txt)) {
          return txt;
        }
      }
    }
    throw new ScanException('Claude did not return extracted text.');
  }

  @TestVisible
  private static ScanResult parseScanResult(String rawText) {
    String cleaned = stripJsonFences(rawText);
    Map<String, Object> m;
    try {
      m = (Map<String, Object>) JSON.deserializeUntyped(cleaned);
    } catch (Exception e) {
      throw new ScanException('Could not parse extracted document JSON.');
    }
    ScanResult r = new ScanResult();
    r.docType = str(m.get('docType'));
    r.docNumber = str(m.get('docNumber'));
    r.bolNumber = str(m.get('bolNumber'));
    r.orderNumber = str(m.get('orderNumber'));
    r.customerName = str(m.get('customerName'));
    r.customerCode = str(m.get('customerCode'));
    r.supplierName = str(m.get('supplierName'));
    r.origin = str(m.get('origin'));
    r.destinationAddress = str(m.get('destinationAddress'));
    r.destinationCity = str(m.get('destinationCity'));
    r.siteCode = str(m.get('siteCode'));
    r.contactName = str(m.get('contactName'));
    r.contactPhone = str(m.get('contactPhone'));
    r.truckPlate = str(m.get('truckPlate'));
    r.serviceDate = str(m.get('serviceDate'));
    r.cargoSummary = str(m.get('cargoSummary'));
    r.weightKg = dec(m.get('weightKg'));
    if (
      String.isBlank(r.destinationAddress) &&
      String.isNotBlank(r.destinationCity)
    ) {
      r.destinationAddress = r.destinationCity;
    }
    return r;
  }

  private static String stripJsonFences(String raw) {
    if (String.isBlank(raw)) {
      return '';
    }
    String s = raw.trim();
    if (s.startsWith('```')) {
      Integer firstNewline = s.indexOf('\n');
      if (firstNewline > -1) {
        s = s.substring(firstNewline + 1);
      }
      if (s.endsWith('```')) {
        s = s.substring(0, s.length() - 3);
      }
    }
    s = s.trim();
    Integer startBrace = s.indexOf('{');
    Integer endBrace = s.lastIndexOf('}');
    if (startBrace >= 0 && endBrace > startBrace) {
      s = s.substring(startBrace, endBrace + 1);
    }
    return s;
  }

  @TestVisible
  private static List<String> buildGeocodeCandidates(
    String address,
    String city
  ) {
    List<String> candidates = new List<String>();
    Set<String> seen = new Set<String>();
    if (String.isNotBlank(address)) {
      addCandidate(candidates, seen, address);
      String noParens = address.replaceAll('\\([^)]*\\)', ' ')
        .replaceAll('\\s+', ' ')
        .trim();
      addCandidate(candidates, seen, noParens);
    }
    if (String.isNotBlank(city)) {
      addCandidate(candidates, seen, city);
    }
    return candidates;
  }

  private static void addCandidate(
    List<String> listOut,
    Set<String> seen,
    String value
  ) {
    if (String.isBlank(value)) {
      return;
    }
    String trimmed = value.trim();
    if (seen.add(trimmed)) {
      listOut.add(trimmed);
    }
  }

  private static GeoPoint parseGeoJson(String body) {
    if (String.isBlank(body)) {
      return null;
    }
    Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
    List<Object> features = (List<Object>) m.get('features');
    if (features == null || features.isEmpty()) {
      return null;
    }
    Map<String, Object> f = (Map<String, Object>) features[0];
    Map<String, Object> geom = (Map<String, Object>) f.get('geometry');
    List<Object> coords = geom == null
      ? null
      : (List<Object>) geom.get('coordinates');
    if (coords == null || coords.size() < 2) {
      return null;
    }
    GeoPoint pt = new GeoPoint();
    pt.longitude = dec(coords[0]);
    pt.latitude = dec(coords[1]);
    Map<String, Object> props = (Map<String, Object>) f.get('properties');
    pt.label = props == null ? null : str(props.get('label'));
    return pt;
  }

  // ---------------------------------------------------------------------------------------------
  // Persistence & formatting helpers
  // ---------------------------------------------------------------------------------------------

  private static String uniqueExternalId(String baseId) {
    String clean = String.isBlank(baseId)
      ? 'SCAN-' + String.valueOf(Datetime.now().getTime())
      : baseId.trim().abbreviate(220);
    List<Route_Job__c> existing = [
      SELECT Id
      FROM Route_Job__c
      WHERE External_Id__c = :clean
      LIMIT 1
    ];
    if (existing.isEmpty()) {
      return clean;
    }
    return (clean +
      '-' +
      String.valueOf(Datetime.now().getTime()).right(6))
      .abbreviate(255);
  }

  private static String buildJobNotes(Map<String, Object> payload) {
    List<String> parts = new List<String>();
    addPart(parts, str(payload.get('customerName')));
    String orderNo = str(payload.get('orderNumber'));
    if (String.isNotBlank(orderNo)) {
      parts.add('Order ' + orderNo);
    }
    addPart(parts, str(payload.get('cargoSummary')));
    Decimal extWeight = dec(payload.get('extractedWeightKg'));
    if (extWeight != null && extWeight > 0) {
      parts.add(extWeight.format() + ' kg');
    }
    String extra = str(payload.get('notes'));
    addPart(parts, extra);
    return String.join(parts, ' · ').abbreviate(32768);
  }

  private static String buildAccessNotes(Map<String, Object> payload) {
    List<String> parts = new List<String>();
    String contact = str(payload.get('contactName'));
    if (String.isNotBlank(contact)) {
      parts.add(contact);
    }
    addPart(parts, str(payload.get('contactPhone')));
    String docNo = str(payload.get('docNumber'));
    if (String.isNotBlank(docNo)) {
      parts.add('Doc ' + docNo);
    }
    String bolNo = str(payload.get('bolNumber'));
    if (String.isNotBlank(bolNo)) {
      parts.add('BOL ' + bolNo);
    }
    return parts.isEmpty() ? null : String.join(parts, ' · ');
  }

  private static void addPart(List<String> parts, String value) {
    if (String.isNotBlank(value)) {
      parts.add(value.trim());
    }
  }

  private static String safeAttachmentName(
    String fileName,
    String docNumber,
    String mimeType
  ) {
    String ext = mimeType == 'application/pdf'
      ? '.pdf'
      : (mimeType == 'image/png' ? '.png' : '.jpg');
    String base = String.isNotBlank(fileName)
      ? fileName.trim()
      : (String.isNotBlank(docNumber) ? 'scan-' + docNumber.trim() : 'scan');
    if (base.contains('.')) {
      base = base.substringBeforeLast('.');
    }
    if (String.isBlank(base)) {
      base = 'scan';
    }
    return base.abbreviate(80) + ext;
  }

  private static String str(Object v) {
    if (v == null) {
      return null;
    }
    String s = String.valueOf(v).trim();
    return String.isBlank(s) ? null : s;
  }

  private static Decimal dec(Object v) {
    if (v == null) {
      return null;
    }
    if (v instanceof Decimal) {
      return (Decimal) v;
    }
    if (v instanceof Integer) {
      return Decimal.valueOf((Integer) v);
    }
    if (v instanceof Long) {
      return Decimal.valueOf((Long) v);
    }
    if (v instanceof Double) {
      return Decimal.valueOf((Double) v);
    }
    String s = String.valueOf(v).replaceAll('[^0-9.-]', '');
    if (String.isBlank(s)) {
      return null;
    }
    try {
      return Decimal.valueOf(s);
    } catch (Exception e) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------------------------
  // System-mode fallback for Motorpool guest-site demo (where Guest license forbids USER_MODE Delete)
  // ---------------------------------------------------------------------------------------------

  @TestVisible
  private static Boolean forceSystemModeForTest = false;

  private static Boolean hasRoutingUserModeAccess() {
    return !forceSystemModeForTest &&
      UserInfo.getUserType() != 'Guest' &&
      Schema.sObjectType.Waypoint__c.isDeletable() &&
      Schema.sObjectType.Waypoint__c.isCreateable() &&
      Schema.sObjectType.Route_Job__c.isUpdateable() &&
      Schema.sObjectType.Route_Event__c.isCreateable();
  }

  private static RouteReplanService.RouteContext buildContextSystem(
    Id routeId,
    Id addVisitId
  ) {
    RouteReplanService.RouteContext ctx = new RouteReplanService.RouteContext();
    List<Route__c> routeRows = [
      SELECT
        Id,
        Name,
        Status__c,
        Revision__c,
        Route_Plan__c,
        Route_Plan__r.Name,
        Route_Plan__r.Plan_Date__c,
        Route_Plan__r.Provider__c,
        Route_Plan__r.Status__c,
        Route_Plan__r.Depot_Branch__c,
        Fleet_Asset__c,
        Fleet_Asset__r.Name,
        Fleet_Asset__r.Vehicle_Features__c,
        Fleet_Asset__r.Fuel_Type__c,
        Fleet_Asset__r.Payload_Kg__c,
        Fleet_Asset__r.Cargo_Volume_M3__c,
        Fleet_Asset__r.Pallet_Capacity__c,
        Fleet_Asset__r.Last_Location__Latitude__s,
        Fleet_Asset__r.Last_Location__Longitude__s,
        Driver__c,
        Driver__r.Name,
        Driver__r.Related_User__c,
        Start_Location__Latitude__s,
        Start_Location__Longitude__s,
        End_Location__Latitude__s,
        End_Location__Longitude__s,
        Shift_Start__c,
        Shift_End__c,
        Planned_Start__c,
        Planned_End__c,
        Planned_Distance_Km__c,
        Planned_Duration_Min__c
      FROM Route__c
      WHERE Id = :routeId
      LIMIT 1
    ];
    if (routeRows.isEmpty()) {
      throw new ScanException('Route ' + routeId + ' was not found.');
    }
    ctx.route = routeRows[0];
    if (
      ctx.route.Status__c == 'Completed' ||
      ctx.route.Status__c == 'Cancelled'
    ) {
      throw new ScanException(
        'A ' + ctx.route.Status__c + ' route cannot be re-planned.'
      );
    }

    for (Waypoint__c w : [
      SELECT
        Id,
        Name,
        Sequence__c,
        Type__c,
        Status__c,
        Locked__c,
        Location__Latitude__s,
        Location__Longitude__s,
        Planned_Arrival__c,
        Planned_Departure__c,
        ETA__c,
        Actual_Arrival__c,
        Actual_Departure__c,
        Service_Minutes__c,
        Leg_Distance_Km__c,
        Reason__c,
        Solver_Step_Id__c
      FROM Waypoint__c
      WHERE Route__c = :routeId
      ORDER BY Sequence__c
      LIMIT 1000
    ]) {
      if (
        RouteReplanService.DONE_STATUSES.contains(w.Status__c) ||
        w.Type__c == 'Start'
      ) {
        ctx.done.add(w);
      } else {
        ctx.remaining.add(w);
      }
    }

    ctx.visits = new Map<Id, Job_Visit__c>(
      [
        SELECT
          Id,
          Name,
          Role__c,
          Status__c,
          Waypoint__c,
          Waypoint__r.Route__c,
          Location__Latitude__s,
          Location__Longitude__s,
          Window_Start__c,
          Window_End__c,
          Hard_Window__c,
          Service_Minutes__c,
          Load_1__c,
          Load_2__c,
          Load_3__c,
          Address__c,
          Access_Notes__c,
          Route_Job__c,
          Route_Job__r.Name,
          Route_Job__r.Priority__c,
          Route_Job__r.Required_Skills__c,
          Route_Job__r.Status__c
        FROM Job_Visit__c
        WHERE Waypoint__r.Route__c = :routeId OR Id = :addVisitId
        LIMIT 2000
      ]
    );

    Integer delay = 0;
    for (Route_Event__c e : [
      SELECT Type__c, Payload__c
      FROM Route_Event__c
      WHERE Route__c = :routeId AND Type__c IN ('Delay Reported', 'Reoptimized')
      ORDER BY Occurred_At__c DESC, Name DESC
      LIMIT 200
    ]) {
      if (e.Type__c == 'Reoptimized') {
        break;
      }
      delay += RouteReplanService.delayOf(e.Payload__c);
    }
    ctx.delayMinutes = delay;

    Datetime lastDeparture;
    Location lastPlace;
    for (Waypoint__c w : ctx.done) {
      Datetime dep = w.Actual_Departure__c != null
        ? w.Actual_Departure__c
        : w.Planned_Departure__c;
      if (dep != null && (lastDeparture == null || dep > lastDeparture)) {
        lastDeparture = dep;
      }
      if (w.Location__Latitude__s != null) {
        lastPlace = Location.newInstance(
          w.Location__Latitude__s,
          w.Location__Longitude__s
        );
      }
    }
    Datetime now = System.now();
    Datetime base = lastDeparture != null &&
      lastDeparture > now
      ? lastDeparture
      : now;
    if (ctx.route.Shift_Start__c != null && ctx.route.Shift_Start__c > base) {
      base = ctx.route.Shift_Start__c;
    }
    ctx.startTime = base.addMinutes(ctx.delayMinutes);
    if (
      ctx.route.Fleet_Asset__r != null &&
      ctx.route.Fleet_Asset__r.Last_Location__Latitude__s != null
    ) {
      ctx.startLocation = Location.newInstance(
        ctx.route.Fleet_Asset__r.Last_Location__Latitude__s,
        ctx.route.Fleet_Asset__r.Last_Location__Longitude__s
      );
    } else if (lastPlace != null) {
      ctx.startLocation = lastPlace;
    } else {
      ctx.startLocation = Location.newInstance(
        ctx.route.Start_Location__Latitude__s,
        ctx.route.Start_Location__Longitude__s
      );
    }

    RoutingDtos.Vehicle v = new RoutingDtos.Vehicle();
    v.id = ctx.route.Id;
    v.startLocation = ctx.startLocation;
    if (ctx.route.End_Location__Latitude__s != null) {
      v.endLocation = Location.newInstance(
        ctx.route.End_Location__Latitude__s,
        ctx.route.End_Location__Longitude__s
      );
    }
    v.shiftStart = ctx.startTime;
    v.shiftEnd = ctx.route.Shift_End__c != null &&
      ctx.route.Shift_End__c > ctx.startTime
      ? ctx.route.Shift_End__c
      : ctx.startTime.addHours(12);
    if (ctx.route.Fleet_Asset__r != null) {
      v.capacity = RoutePlanService.capacity(
        ctx.route.Fleet_Asset__r,
        RoutePlanService.capacityDimensions()
      );
      v.skills = RoutePlanService.splitMulti(
        ctx.route.Fleet_Asset__r.Vehicle_Features__c
      );
    }

    for (Waypoint__c w : ctx.remaining) {
      if (
        (w.Type__c == 'Break' || w.Type__c == 'Charge') &&
        w.Planned_Arrival__c != null
      ) {
        RoutingDtos.BreakSpec b = new RoutingDtos.BreakSpec();
        b.id =
          (w.Type__c == 'Charge' ? RoutePlanService.CHARGE_BREAK_ID : 'break') +
          '-' +
          w.Id;
        b.description = w.Type__c;
        b.serviceSeconds =
          (w.Service_Minutes__c == null ? 0 : w.Service_Minutes__c.intValue()) *
          60;
        Datetime windowFrom = w.Planned_Arrival__c.addMinutes(
          -RouteReplanService.BREAK_WINDOW_MINUTES
        );
        b.windows.add(
          new RoutingDtos.TimeWindow(
            windowFrom < ctx.startTime ? ctx.startTime : windowFrom,
            w.Planned_Arrival__c.addMinutes(
              RouteReplanService.BREAK_WINDOW_MINUTES + ctx.delayMinutes
            )
          )
        );
        if (b.windows[0].endTime > b.windows[0].startTime) {
          v.breaks.add(b);
        }
      }
    }
    ctx.request.vehicles.add(v);

    Map<Id, List<Job_Visit__c>> visitsByWaypoint = new Map<Id, List<Job_Visit__c>>();
    List<Job_Visit__c> added = new List<Job_Visit__c>();
    for (Job_Visit__c jv : ctx.visits.values()) {
      if (jv.Status__c == 'Done' || jv.Status__c == 'Failed') {
        continue;
      }
      if (jv.Waypoint__c != null && jv.Waypoint__r.Route__c == routeId) {
        if (!visitsByWaypoint.containsKey(jv.Waypoint__c)) {
          visitsByWaypoint.put(jv.Waypoint__c, new List<Job_Visit__c>());
        }
        visitsByWaypoint.get(jv.Waypoint__c).add(jv);
      } else {
        added.add(jv);
      }
    }

    List<Job_Visit__c> ordered = new List<Job_Visit__c>();
    for (Waypoint__c w : ctx.remaining) {
      if (!visitsByWaypoint.containsKey(w.Id)) {
        continue;
      }
      for (Job_Visit__c jv : visitsByWaypoint.get(w.Id)) {
        ordered.add(jv);
        ctx.beforeOrder.add(jv.Id);
        ctx.beforeEta.put(
          jv.Id,
          w.ETA__c != null ? w.ETA__c : w.Planned_Arrival__c
        );
      }
    }
    ordered.addAll(added);
    populateTasks(ctx, ordered);
    return ctx;
  }

  private static void populateTasks(
    RouteReplanService.RouteContext ctx,
    List<Job_Visit__c> ordered
  ) {
    List<Capacity_Dimension__mdt> dims = RoutePlanService.capacityDimensions();
    Map<Id, Job_Visit__c> pickupByJob = new Map<Id, Job_Visit__c>();
    Map<Id, Job_Visit__c> deliveryByJob = new Map<Id, Job_Visit__c>();
    for (Job_Visit__c jv : ordered) {
      if (jv.Role__c == 'Pickup') {
        pickupByJob.put(jv.Route_Job__c, jv);
      } else if (jv.Role__c == 'Delivery') {
        deliveryByJob.put(jv.Route_Job__c, jv);
      }
    }
    Datetime dayStart = ctx.startTime.addHours(-24);
    Set<Id> shipped = new Set<Id>();
    for (Job_Visit__c jv : ordered) {
      if (jv.Location__Latitude__s == null) {
        ctx.request.skippedJobs.put(
          jv.Route_Job__c,
          'A visit has no location.'
        );
        continue;
      }
      List<String> skills = RoutePlanService.splitMulti(
        jv.Route_Job__r.Required_Skills__c
      );
      Integer priority = jv.Route_Job__r.Priority__c == null
        ? 0
        : jv.Route_Job__r.Priority__c.intValue();
      Job_Visit__c p = pickupByJob.get(jv.Route_Job__c);
      Job_Visit__c d = deliveryByJob.get(jv.Route_Job__c);
      if (p != null && d != null) {
        if (shipped.add(jv.Route_Job__c)) {
          RoutingDtos.Shipment s = new RoutingDtos.Shipment();
          s.id = jv.Route_Job__c;
          s.pickup = RoutePlanService.shipmentStep(p, dayStart);
          s.delivery = RoutePlanService.shipmentStep(d, dayStart);
          s.amount = RoutePlanService.loads(p, dims);
          s.skills = skills;
          s.priority = priority;
          ctx.request.shipments.add(s);
        }
        continue;
      }
      RoutingDtos.Job job = new RoutingDtos.Job();
      job.id = jv.Id;
      job.location = Location.newInstance(
        jv.Location__Latitude__s,
        jv.Location__Longitude__s
      );
      job.serviceSeconds = RoutePlanService.serviceSeconds(jv);
      job.windows = RoutePlanService.windows(jv, dayStart);
      if (jv.Role__c == 'Pickup') {
        job.pickup = RoutePlanService.loads(jv, dims);
      } else {
        job.delivery = RoutePlanService.loads(jv, dims);
      }
      job.skills = skills;
      job.priority = priority;
      job.description = jv.Route_Job__r.Name;
      ctx.request.jobs.add(job);
    }
  }

  private static void applySystem(
    RouteReplanService.RouteContext ctx,
    RoutingDtos.OptimizeResult result
  ) {
    Route__c route = ctx.route;
    Integer revision =
      (route.Revision__c == null ? 0 : route.Revision__c.intValue()) + 1;
    if (!ctx.remaining.isEmpty()) {
      delete ctx.remaining;
    }
    Integer nextSeq = 1;
    for (Waypoint__c w : ctx.done) {
      if (w.Sequence__c != null && w.Sequence__c.intValue() >= nextSeq) {
        nextSeq = w.Sequence__c.intValue() + 1;
      }
    }
    RoutingDtos.Route solved = result.routeFor(route.Id);
    RoutingDtos.Route r = new RoutingDtos.Route();
    if (solved != null) {
      for (RoutingDtos.Step s : solved.steps) {
        if (s.stepType != 'start') {
          r.steps.add(s);
        }
      }
    }
    RoutePlanService.WaypointBuild built = new RoutePlanService.WaypointBuild();
    RoutePlanService.buildWaypoints(
      route,
      r,
      route.Route_Plan__r.Depot_Branch__c,
      built,
      nextSeq
    );
    insert built.waypoints;

    List<Job_Visit__c> visitUpdates = new List<Job_Visit__c>();
    Map<Id, Route_Job__c> jobUpdates = new Map<Id, Route_Job__c>();
    for (Integer i = 0; i < built.waypoints.size(); i++) {
      for (String visitId : built.visitsByIndex.get(i)) {
        Job_Visit__c jv = ctx.visits.get((Id) visitId);
        visitUpdates.add(
          new Job_Visit__c(
            Id = (Id) visitId,
            Waypoint__c = built.waypoints[i].Id
          )
        );
        if (jv != null) {
          jobUpdates.put(
            jv.Route_Job__c,
            new Route_Job__c(
              Id = jv.Route_Job__c,
              Planned_Route__c = route.Id,
              Unassigned_Reason__c = null
            )
          );
        }
      }
    }
    for (RoutingDtos.Unassigned u : result.unassigned) {
      Id jobId = u.taskType == 'shipment'
        ? (Id) u.id
        : (ctx.visits.containsKey((Id) u.id)
            ? ctx.visits.get((Id) u.id).Route_Job__c
            : null);
      if (jobId != null) {
        jobUpdates.put(
          jobId,
          new Route_Job__c(
            Id = jobId,
            Status__c = 'Ready',
            Planned_Route__c = null,
            Unassigned_Reason__c = (u.reason +
              ': ' +
              (u.detail == null ? '' : u.detail))
              .abbreviate(255)
          )
        );
      }
    }
    if (!visitUpdates.isEmpty()) {
      update visitUpdates;
    }
    if (!jobUpdates.isEmpty()) {
      update jobUpdates.values();
    }

    Decimal doneKm = 0;
    for (Waypoint__c w : ctx.done) {
      doneKm += w.Leg_Distance_Km__c == null ? 0 : w.Leg_Distance_Km__c;
    }
    Route__c upd = new Route__c(Id = route.Id, Revision__c = revision);
    if (solved != null) {
      upd.Planned_End__c = solved.endTime;
      upd.Planned_Distance_Km__c = (doneKm +
        Decimal.valueOf(solved.distanceM) / 1000)
        .setScale(2);
      upd.Geometry__c = solved.geometry == null
        ? null
        : solved.geometry.abbreviate(131072);
    }
    update upd;
    route.Revision__c = revision;
  }

  private static RoutingDtos.Unassigned findUnassigned(
    RoutingDtos.OptimizeResult result,
    Id visitId,
    Id jobId
  ) {
    if (result == null || result.unassigned == null) {
      return null;
    }
    for (RoutingDtos.Unassigned u : result.unassigned) {
      if (
        u.id == String.valueOf(visitId) ||
        (jobId != null &&
        u.id == String.valueOf(jobId))
      ) {
        return u;
      }
    }
    return null;
  }

  private static void logScanEvents(
    RouteReplanService.RouteContext ctx,
    Id visitId,
    Boolean assigned,
    Map<String, Object> diff,
    Boolean useUserMode
  ) {
    RouteEvents.Builder stopAdded = RouteEvents.event('Stop Added', 'Driver')
      .forPlan(ctx.route.Route_Plan__c)
      .forRoute(ctx.route.Id)
      .payload(
        new Map<String, Object>{
          'visitId' => visitId,
          'assigned' => assigned,
          'source' => 'document_scan'
        }
      );
    RouteEvents.Builder reoptimized = RouteEvents.event('Reoptimized', 'Driver')
      .forPlan(ctx.route.Route_Plan__c)
      .forRoute(ctx.route.Id)
      .payload(diff);
    List<RouteEvents.Builder> builders = new List<RouteEvents.Builder>{
      stopAdded,
      reoptimized
    };
    if (useUserMode) {
      RouteEvents.log(builders);
    } else {
      insert new List<Route_Event__c>{ stopAdded.record, reoptimized.record };
    }
  }
}
