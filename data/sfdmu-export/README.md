# Demo dataset (SFDMU)

The FleetForce demo data: 4 branches, 35 vehicles and about 860 related records (drivers, schedules, bookings, trips,
fuel, service, telematics, documents). It loads into any org that has `force-app` deployed.

| Branch                            | Country | Time zone                                            | Currency | Distance / volume / weight |
| --------------------------------- | ------- | ---------------------------------------------------- | -------- | -------------------------- |
| Lisbon Central HQ (`BR-LIS`)      | PT      | Europe/Lisbon                                        | EUR      | km / L / kg                |
| London Hub (`BR-LON`)             | GB      | Europe/London                                        | GBP      | mi / L / kg                |
| Tel Aviv Satellite (`BR-TLV`)     | IL      | Asia/Jerusalem                                       | ILS      | km / L / kg                |
| Chicago Service Center (`BR-CHI`) | US      | America/Chicago (the US profile default is New York) | USD      | mi / US gal / lb           |

Vehicles leave Registration Country blank and inherit their branch country, except `FA-0102`, a van registered in
Portugal that operates from London (the cross-border example). Vehicles at km branches have their odometers, trip
distances and speeds in km; fuel outside the US is logged in litres at local prices.

## Load

```bash
./scripts/load_demo_data.sh <org-alias>
```

This runs SFDMU on this folder (`export.json`, every object **Upsert** on its external ID, so it can be re-run),
then the Apex seeds in `scripts/apex/` and the data trust sample. For the multi-currency demo org use
`./scripts/demo_multicurrency_setup.sh`, which also adds currencies and gives each money record its branch currency.

`target/` and `reports/` are SFDMU's run output and are not committed.

## History

Exported from the US demo org in August 2026 and converted to the four countries on 31 Oct 2026 by
`scripts/data/regionalise_demo_data.py` (one-time; it does nothing on already converted files).
To export again from an org: `sf sfdmu run --sourceusername <org> --targetusername csvfile --path data/sfdmu-export`.
