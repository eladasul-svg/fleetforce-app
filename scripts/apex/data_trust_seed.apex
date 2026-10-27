// Seeds the data trust preview on the existing demo fleet: 3 sample sources, Standard + EV batch profiles,
// streams for every active vehicle (8 stale telematics, 5 missing a stream), 2 consistency gaps, 2 sample recalls
// and 2 sample regulations, then scores every vehicle and matches the notices.
// Everything it creates is fictional and flagged Sample Data. Starts with a reset, so it can be re-run any time;
// all dates are offsets from now. Hand-checked reference vehicles: docs/data-trust/seed-README.md.
//
// Usage:  sf apex run --file scripts/apex/data_trust_seed.apex --target-org <alias>

DataTrustSampleData.Summary s = DataTrustSampleData.seed();
System.debug(LoggingLevel.ERROR, 'DATA TRUST SEED ' + s);
