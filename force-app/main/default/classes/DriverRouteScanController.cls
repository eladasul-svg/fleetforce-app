/**
 * LWC controller for scanning a delivery document on the driver app's Route tab, previewing
 * extracted stop details, persisting the job/visit/attachment, and re-optimizing the active route.
 *
 * Runs without sharing and accepts primitive/JSON parameters so both authenticated drivers and the
 * Motorpool guest demo site can invoke it cleanly. Never annotate callout methods cacheable=true.
 */
public without sharing class DriverRouteScanController {
  @AuraEnabled
  public static DriverRouteScanService.ScanResult scanDocument(
    String base64Data,
    String mimeType,
    String fileName
  ) {
    try {
      return DriverRouteScanService.scanDocument(
        base64Data,
        mimeType,
        fileName
      );
    } catch (DriverRouteScanService.ScanException e) {
      throw auraError(e.getMessage());
    } catch (Exception e) {
      throw auraError('Could not scan document: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static DriverRouteScanService.GeoPoint geocodeAddress(
    String address,
    String city
  ) {
    try {
      return DriverRouteScanService.geocodeAddress(address, city);
    } catch (Exception e) {
      throw auraError('Could not geocode address: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static DriverRouteScanService.CreatedJobResult createScannedJob(
    Id routeId,
    Id driverId,
    String payloadJson,
    String base64Data,
    String mimeType,
    String fileName
  ) {
    try {
      return DriverRouteScanService.createScannedJob(
        routeId,
        driverId,
        payloadJson,
        base64Data,
        mimeType,
        fileName
      );
    } catch (DriverRouteScanService.ScanException e) {
      throw auraError(e.getMessage());
    } catch (Exception e) {
      throw auraError('Could not save scanned stop: ' + e.getMessage());
    }
  }

  @AuraEnabled
  public static DriverRouteScanService.AddVisitResult addVisitToRoute(
    Id routeId,
    Id visitId
  ) {
    try {
      return DriverRouteScanService.addVisitToRoute(routeId, visitId);
    } catch (DriverRouteScanService.ScanException e) {
      throw auraError(e.getMessage());
    } catch (RoutingProviders.RoutingException e) {
      throw auraError(e.getMessage());
    } catch (Exception e) {
      throw auraError('Could not re-optimize route: ' + e.getMessage());
    }
  }

  private static AuraHandledException auraError(String message) {
    AuraHandledException ex = new AuraHandledException(message);
    ex.setMessage(message);
    return ex;
  }
}
