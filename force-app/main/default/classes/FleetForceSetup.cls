/**
 * Setup entry points for scripts and anonymous Apex. In an org where FleetForce is installed as a package, classes
 * that are public are not visible outside the fleetforce namespace, so the setup scripts call these instead:
 *
 *   fleetforce.FleetForceSetup.seedDataTrustSample();
 *
 * Keep this class small: every global method is part of the package's public surface.
 */
global with sharing class FleetForceSetup {
  /** Resets and seeds the data trust sample (docs/data-trust/seed-README.md). Returns the run summary as JSON. */
  global static String seedDataTrustSample() {
    return JSON.serializePretty(DataTrustSampleData.seed());
  }

  /** Removes every data trust sample record. */
  global static void resetDataTrustSample() {
    DataTrustSampleData.reset();
  }

  /** Schedules the nightly data health run at 02:00; returns the job id. */
  global static Id scheduleNightlyDataHealth() {
    return DataTrustJobs.scheduleNightly();
  }
}
