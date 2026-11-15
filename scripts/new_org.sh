#!/bin/bash
# Creates a FleetForce org in one command, so no org is ever precious (docs/project files/environments.md).
#
#   ./scripts/new_org.sh <alias>                          develop: namespaced scratch org, source deploy, demo data
#   ./scripts/new_org.sh <alias> --package <04t id>       test or demo: no namespace, installs that package version
#   options:  --multicurrency   EUR corporate currency plus GBP, USD, ILS (demo only)
#             --no-data         skip the demo data
#             --days <n>        lifetime, default 30
#
# Afterwards: the manual steps in docs/project files/manual-setup-steps.md, and update the "Current orgs" table in
# docs/project files/environments.md.
set -euo pipefail
ALIAS="${1:?Usage: $0 <alias> [--package <04t id>] [--multicurrency] [--no-data] [--days <n>]}"
shift
PACKAGE=""; MC=""; DATA="yes"; DAYS=30
while [ $# -gt 0 ]; do
  case "$1" in
    --package) PACKAGE="${2:?--package needs a 04t id}"; shift 2 ;;
    --multicurrency) MC="yes"; shift ;;
    --no-data) DATA=""; shift ;;
    --days) DAYS="${2:?--days needs a number}"; shift 2 ;;
    *) echo "Unknown option $1"; exit 1 ;;
  esac
done
cd "$(dirname "$0")/.."

if sf org display --target-org "$ALIAS" > /dev/null 2>&1; then
  echo "✖ $ALIAS already exists. Pick a new alias or delete it first."; exit 1
fi

DEF=config/project-scratch-def.json
[ -n "$MC" ] && DEF=config/demo-multicurrency-scratch-def.json
NS_FLAG=""
[ -n "$PACKAGE" ] && NS_FLAG="--no-namespace"   # the package brings the namespace; the org must not have it

echo "── Create $ALIAS ($DAYS days, $DEF${PACKAGE:+, no namespace})"
sf org create scratch -f "$DEF" -a "$ALIAS" -y "$DAYS" --wait 30 -v fleetforcePBO $NS_FLAG > /dev/null

if [ -n "$MC" ]; then
  echo "── Currencies"
  for pair in GBP:0.84 USD:1.08 ILS:4.05; do
    sf data create record --target-org "$ALIAS" --sobject CurrencyType \
      --values "IsoCode=${pair%%:*} ConversionRate=${pair##*:} DecimalPlaces=2 IsActive=true" > /dev/null
  done
fi

if [ -n "$PACKAGE" ]; then
  echo "── Install package $PACKAGE"
  sf package install --package "$PACKAGE" --target-org "$ALIAS" --wait 30 --publish-wait 10 --no-prompt > /dev/null
else
  echo "── Deploy force-app"
  sf project deploy start --source-dir force-app --target-org "$ALIAS" --wait 30 > /dev/null
fi

echo "── Permission sets"
for ps in FleetAdmin FleetforceAdmin FleetforceDataTrust FleetforceAssistantUser FleetforceRouting; do
  sf org assign permset --name "$ps" --target-org "$ALIAS" > /dev/null 2>&1 || echo "   $ps not assigned"
done

echo "── App Launcher"
./scripts/hide_standard_apps.sh "$ALIAS" > /dev/null 2>&1 || echo "   skipped (see scripts/hide_standard_apps.sh)"

if [ -n "$DATA" ]; then
  ./scripts/load_demo_data.sh "$ALIAS"
  if [ -n "$MC" ]; then
    sf apex run --file scripts/apex/demo_currencies.apex --target-org "$ALIAS" | grep USER_DEBUG | sed 's/.*DEBUG|/  /'
  fi
fi

echo "✅ $ALIAS ready: sf org open --target-org $ALIAS"
echo "   Next: manual steps (docs/project files/manual-setup-steps.md) and the Current orgs table (environments.md)."
