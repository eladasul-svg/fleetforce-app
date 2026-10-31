#!/bin/bash
# Loads the multi-country demo into an org that already has force-app deployed: the SFDMU dataset
# (data/sfdmu-export: 4 branches in Lisbon, London, Tel Aviv and Chicago, 35 vehicles and their records), then the
# re-runnable Apex seeds (locations around each branch, tasks, events, bookings, driver app) and the data trust sample.
# Every step can be re-run: SFDMU upserts on external IDs and the seeds delete and recreate their own records.
#
# Usage:  ./scripts/load_demo_data.sh <org-alias>
# The org needs the FleetAdmin, FleetforceAdmin and FleetforceDataTrust permission sets on the running user.
set -e
ORG="${1:?Usage: $0 <org-alias>}"
cd "$(dirname "$0")/.."

echo "── Permission sets"
for ps in FleetAdmin FleetforceAdmin FleetforceDataTrust; do
  sf org assign permset --name "$ps" --target-org "$ORG" > /dev/null 2>&1 || true
done

echo "── Demo dataset (SFDMU)"
rm -rf data/sfdmu-export/target data/sfdmu-export/reports
sf sfdmu run --sourceusername csvfile --targetusername "$ORG" --path data/sfdmu-export --noprompt --silent \
  || { echo "SFDMU failed; see data/sfdmu-export/reports and target/"; exit 1; }
if grep -q "," data/sfdmu-export/reports/MissingParentRecordsReport.csv 2>/dev/null \
   && [ "$(wc -l < data/sfdmu-export/reports/MissingParentRecordsReport.csv)" -gt 1 ]; then
  echo "   ⚠ some lookups could not be resolved: data/sfdmu-export/reports/MissingParentRecordsReport.csv"
fi

for s in seed_branch_locations seed_tasks seed_events seed_motorpool_bookings seed_driver_app; do
  echo "── $s"
  sf apex run --file "scripts/apex/$s.apex" --target-org "$ORG" | grep -E "USER_DEBUG|Error|error" | sed 's/.*DEBUG|//' || true
done

echo "── Data trust sample"
sf apex run --file scripts/apex/data_trust_seed.apex --target-org "$ORG" \
  | awk '/DATA TRUST SEED/{p=1} /CUMULATIVE_LIMIT_USAGE/{p=0} p' | sed 's/.*ERROR|//' || true

echo "✅ Demo data loaded into $ORG"
