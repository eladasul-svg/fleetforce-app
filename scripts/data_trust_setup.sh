#!/bin/bash
# Deploys the data trust layer to an org that already has the FleetForce demo fleet, grants access, seeds the
# sample data and schedules the nightly data health run.
#
# Usage:  ./scripts/data_trust_setup.sh <org-alias>
# New scratch org first?  sf org create scratch -f config/project-scratch-def.json -a <alias> --duration-days 30
set -e
ORG="${1:?Usage: $0 <org-alias>}"

echo "── Deploy force-app → $ORG"
sf project deploy start --source-dir force-app --target-org "$ORG" --ignore-conflicts

echo "── Assign FleetforceDataTrust"
sf org assign permset --name FleetforceDataTrust --target-org "$ORG" || echo "   (already assigned)"

echo "── Seed sample data"
sf apex run --file scripts/apex/data_trust_seed.apex --target-org "$ORG" | grep -A40 "DATA TRUST SEED" || true

echo "── Schedule the nightly data health run"
echo "DataTrustJobs.scheduleNightly();" | sf apex run --target-org "$ORG" > /dev/null

echo "✅ Data trust preview ready. Open Fleet Ops → Fleet Exposure:  sf org open --target-org $ORG"
