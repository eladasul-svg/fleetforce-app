# Data trust sample data (seed README)

Everything the seed creates is **fictional** and flagged `Is_Sample__c = true` (shown as "Sample Data" and as a banner on both screens). Recall ids are obviously fake (`SAMPLE-RCL-001`, `SAMPLE-RCL-002`), and every URL points at `example.com`.

```bash
sf apex run --file scripts/apex/data_trust_seed.apex  --target-org <alias>   # reset + seed + score + match
sf apex run --file scripts/apex/data_trust_reset.apex --target-org <alias>   # remove all sample records
```

The seed **starts with a reset**, so running it twice gives the same result. It uses the existing demo fleet (active vehicles in name order) and creates no new vehicles. All dates are offsets from the moment it runs. It prints a summary (counts, notice matches and the reference vehicle ids and scores) to the debug log under `DATA TRUST SEED`.

The repo had no reset command before this work. `data_trust_reset.apex` is the new one, and it removes only data trust sample records.

## What it creates

| Seed | Content |
| --- | --- |
| Sources | Telematics vendor (sample), 1 h; FMC maintenance file (sample), 168 h; Fuel card feed (sample), 24 h |
| Profiles | **Standard**: default, priority 100, 8 signals. **EV batch**: Fuel Type = Electric, priority 10, 14 signals |
| Streams | Every active vehicle. Most are healthy. 8 have stale telematics (3 to 9 days; REF-3 is one of them). 5 are missing a required stream (3 without a maintenance plan, REF-3 included, and 2 without a fuel feed) |
| Data gaps | 2 vehicles get a High *consistency* gap: "Maintenance plan active in FMC file, missing on fleet record" (key `DGC:`, not auto-resolved) |
| Notices | `SAMPLE-RCL-001` (High) and `SAMPLE-RCL-002` (Critical). Their make / model / year criteria are picked from the fleet so they match as close to **9** and **4** vehicles as the fleet allows; the run summary shows the actual counts. `SAMPLE-REG-LEZ`: diesel, `PT;ES;FR`, effective in 45 days. `SAMPLE-REG-DOC`: commercial category, `PT;ES;IT`, effective in 90 days. All are Active and Reviewed |
| Vehicle fields | Make, Model, Model Year are parsed from the name ("2023 Ford F-150 Lariat 4WD" → Ford / F-150 / 2023). Country is set to PT, with every 5th vehicle ES and every 7th GB. Fields are filled **only where blank**, and reset leaves them in place |

Standard profile lines: Location (required, 24 h, min 2 signals), Odometer (required, 72 h, min 1), Fuel or charge (required, 72 h, min 1), Maintenance plan (required, 720 h, min 1), Diagnostics (optional, 168 h).
EV batch lines: Location (24 h, min 3), Odometer (72 h), Fuel or charge (24 h, min 4), Diagnostics (72 h, min 3), Maintenance plan (720 h). All are required.

## Reference vehicles (hand-calculated)

The seed picks these from the fleet and prints their ids (REF-1 and REF-2 are the first two non-electric vehicles by name; REF-3 is the first non-electric vehicle `SAMPLE-RCL-001` matches). All three use the **Standard** profile.

Formula: **score = 0.4 × F + 0.4 × C + 0.2 × K**. Each part is rounded to a whole number first, and the total is rounded half-up.

### REF-1: Healthy, 100

| Stream | Age | Signals |
| --- | --- | --- |
| Location / Odometer / Diagnostics (telematics) | 2 h | 2 / 1 / 1 |
| Fuel or charge (fuel card) | 12 h | 2 |
| Maintenance plan (FMC) | 72 h | 2 |

- F = all four required lines are within their max age, so (100 + 100 + 100 + 100) / 4 = **100**
- C = 8 / 8 = **100**
- K = no data gaps = **100**
- Score = 40 + 40 + 20 = **100, Healthy**

### REF-2: Watch, 80

| Stream | Age | Signals |
| --- | --- | --- |
| Location / Odometer (telematics), no Diagnostics stream | 60 h | 2 / 1 |
| Fuel or charge | 12 h | 1 |
| Maintenance plan | 72 h | 2 |

- Location: 60 h against a 24 h max. 100 × (72 − 60) / 48 = 25. Odometer: 60 h is within 72 h, so 100. Fuel 100, Maintenance 100.
- F = (25 + 100 + 100 + 100) / 4 = 81.25, which rounds to **81**
- C = 6 / 8 = **75**
- K = one Medium gap (Location stale, 60 h is under 3 × 24 h) = 100 − 10 = **90**
- Score = 32.4 + 30 + 18 = 80.4, which rounds to **80, Watch**

### REF-3: At risk, 45 (the vehicle for demo step 3)

| Stream | Age | Signals |
| --- | --- | --- |
| Location / Odometer / Diagnostics (telematics) | 216 h (9 days) | 2 / 1 / 1 |
| Fuel or charge | 12 h | 2 |
| Maintenance plan | **missing** | – |

- Location: 216 h is at least 3 × 24 h, so 0. Odometer: 216 h is at least 3 × 72 h, so 0. Fuel 100. Maintenance missing, so 0.
- F = (0 + 0 + 100 + 0) / 4 = **25**
- C = 6 / 8 = **75**
- K = three High gaps (Location stale, Odometer stale, Maintenance missing) = 100 − 75 = **25**
- Score = 10 + 30 + 5 = **45, At risk**
- REF-3 also carries an open `SAMPLE-RCL-001` recall alert ("Possible match, confirm by VIN with the manufacturer"). Recall alerts never change the score.

Scores are calculated when the seed runs. Freshness depends on time, so a vehicle seeded as healthy drifts if nothing new arrives: REF-1's 2 h old telematics is still healthy for 24 h. Re-run the seed before the demo to restore these exact numbers. The Apex tests `DataHealthServiceTest` and `DataTrustSampleDataTest` check all three with a fixed clock.
