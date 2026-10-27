// Removes every data trust sample record (sources, profiles, streams, notices, alerts flagged Sample Data)
// and clears the data health fields on the vehicles that had them. Safe to run twice.
//
// Usage:  sf apex run --file scripts/apex/data_trust_reset.apex --target-org <alias>

DataTrustSampleData.reset();
System.debug(LoggingLevel.ERROR, 'DATA TRUST RESET done');
