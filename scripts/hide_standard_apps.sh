#!/usr/bin/env bash
# Trims the System Administrator's App Launcher to Fleet Ops + FleetForce Admin.
# Deploys only app visibility (the full Admin profile in unpackaged/ is not deployable on its own).
# In an org where FleetForce is installed as a package (no namespace of its own), the FleetForce apps are named
# fleetforce__FleetOps and fleetforce__FleetForce_Admin, so the names are prefixed in a temporary copy.
# Usage: scripts/hide_standard_apps.sh <org-alias>
set -euo pipefail
ORG="${1:?usage: $0 <org-alias>}"
SRC="$(cd "$(dirname "$0")/launcher" && pwd)"
NS=$(sf data query --target-org "$ORG" --query "SELECT NamespacePrefix FROM Organization" --json \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["result"]["records"][0].get("NamespacePrefix") or "")')
DIR="$SRC"
if [ -z "$NS" ]; then
  DIR="$(mktemp -d)"
  cp -R "$SRC/." "$DIR"
  APPS=$(sf data query --use-tooling-api --target-org "$ORG" --json \
    --query "SELECT DeveloperName FROM CustomApplication WHERE NamespacePrefix = 'fleetforce'" \
    | python3 -c 'import json,sys;print(" ".join(r["DeveloperName"] for r in json.load(sys.stdin)["result"]["records"]))')
  # prefix the FleetForce apps; drop any the installed version does not have yet (older versions lack FleetForce_Admin)
  python3 - "$DIR/profiles/Admin.profile" $APPS <<'PY'
import re, sys
path, installed = sys.argv[1], set(sys.argv[2:])
s = open(path).read()
def fix(m):
    block, name = m.group(0), m.group(1)
    if name not in ('FleetOps', 'FleetForce_Admin'):
        return block
    if name not in installed:
        return ''
    return block.replace('<application>' + name + '<', '<application>fleetforce__' + name + '<')
s = re.sub(r'\s*<applicationVisibilities>\s*<application>(\w+)</application>.*?</applicationVisibilities>', fix, s, flags=re.S)
open(path, 'w').write(s)
PY
fi
sf project deploy start --metadata-dir "$DIR" --target-org "$ORG" --wait 15
