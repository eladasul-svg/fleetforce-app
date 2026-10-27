#!/usr/bin/env bash
# Trims the System Administrator's App Launcher to Fleet Ops + FleetForce Admin.
# Deploys only app visibility (the full Admin profile in unpackaged/ is not deployable on its own).
# Usage: scripts/hide_standard_apps.sh <org-alias>
set -euo pipefail
ORG="${1:?usage: $0 <org-alias>}"
cd "$(dirname "$0")/launcher"
sf project deploy start --metadata-dir . --target-org "$ORG" --wait 15
