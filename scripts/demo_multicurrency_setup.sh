#!/bin/bash
# Builds the multi-currency demo org: corporate currency EUR (from "country": "PT" in the scratch definition),
# GBP, USD and ILS at fixed rates, the full demo data, and every money record in its branch's currency.
# The package itself never depends on multi-currency; this org exists to show reports converting to EUR.
#
# Usage:  ./scripts/demo_multicurrency_setup.sh [alias]          (default alias fleetforce-demo-mc)
# Creates the org first when the alias does not exist yet (30 days).
set -e
ORG="${1:-fleetforce-demo-mc}"
cd "$(dirname "$0")/.."

if ! sf org display --target-org "$ORG" > /dev/null 2>&1; then
  echo "── Create $ORG"
  sf org create scratch -f config/demo-multicurrency-scratch-def.json -a "$ORG" -y 30 --wait 20
fi

echo "── Currencies (fixed rates per 1 EUR)"
for pair in GBP:0.84 USD:1.08 ILS:4.05; do
  code="${pair%%:*}"; rate="${pair##*:}"
  if [ "$(sf data query --target-org "$ORG" --query "SELECT COUNT() FROM CurrencyType WHERE IsoCode = '$code'" --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["totalSize"])')" = "0" ]; then
    sf data create record --target-org "$ORG" --sobject CurrencyType \
      --values "IsoCode=$code ConversionRate=$rate DecimalPlaces=2 IsActive=true" > /dev/null
    echo "  $code added at $rate"
  else
    echo "  $code already there"
  fi
done

echo "── Deploy force-app"
sf project deploy start --source-dir force-app --target-org "$ORG" --ignore-conflicts --wait 30 > /dev/null

./scripts/load_demo_data.sh "$ORG"

echo "── Branch currencies on money records"
sf apex run --file scripts/apex/demo_currencies.apex --target-org "$ORG" | grep USER_DEBUG | sed 's/.*DEBUG|/  /'
echo "✅ Multi-currency demo ready: sf org open --target-org $ORG"
