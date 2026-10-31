#!/bin/bash
# One-time migration of an org that has FleetForce from before the regional settings work (commit 7c99d04 and
# later) and holds data, such as fleetforce-dev-11. For a blank org, or one with the package installed
# (fleetforce-master-tso), reinstall the new package version instead: packaged fields cannot be dropped.
#
# Why fields are dropped: five fields cannot change type in place. Branch Country, Branch Time Zone and Schedule
# Time Zone move from local picklists to global value sets ("Cannot change which global value set this picklist
# uses"); Insurance and Qualification Status move from Number to picklist. The script:
#   1. backs up their values (and every record id) to scripts/migration/backup/<org>-<time>/
#   2. drops the five fields (a destructive deploy; Salesforce keeps deleted fields for 15 days)
#   3. deploys force-app (recreates them with the new definitions, and everything else from the work order)
#   4. restores the values mapped to ISO codes, IANA time zones and the new statuses (regional_map.py);
#      setting a branch Country fills its currency and units from the Country Profile
# Vehicle Country (Text to picklist) and VIN (now unique) change in place and keep their data.
#
# Usage:  ./scripts/migration/migrate_regional.sh <org-alias> [--yes]
#         ./scripts/migration/migrate_regional.sh <org-alias> --restore <backup-dir>   (rerun step 5 only)
# Without --yes it stops after the backup and a check-only run of the destructive deploy, and asks before dropping.
set -euo pipefail
ORG="${1:?Usage: $0 <org-alias> [--yes | --restore <backup-dir>]}"
YES="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

restore() {
  echo "── 5. Restore values"
  for pair in branches:fleetforce__Fleet_Branch__c schedules:fleetforce__Fleet_Schedule__c \
              insurance:fleetforce__Insurance_Policy__c qualifications:fleetforce__Driver_Qualification__c; do
    f="${pair%%:*}"; obj="${pair##*:}"
    if [ "$(wc -l < "$BACKUP/restore_$f.csv")" -gt 1 ]; then
      sf data update bulk --sobject "$obj" --file "$BACKUP/restore_$f.csv" --target-org "$ORG" --wait 10 \
        > "$BACKUP/restore_$f.txt" 2>&1 || { echo "✖ Restore of $f failed (see $BACKUP/restore_$f.txt)"; exit 1; }
      echo "  $obj restored"
    fi
  done
  echo "── 6. Permission sets"
  sf org assign permset --name FleetforceAdmin --target-org "$ORG" > /dev/null 2>&1 || true
  echo "✅ $ORG migrated. Backup and logs: $BACKUP"
}

if [ "$YES" = "--restore" ]; then
  BACKUP="${3:?--restore needs the backup directory}"
  python3 "$HERE/regional_map.py" "$BACKUP"
  restore
  exit 0
fi

BACKUP="$HERE/backup/$ORG-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"

q() {  # q <file> <soql>
  sf data query --target-org "$ORG" --result-format csv --query "$2" > "$BACKUP/$1.csv"
  echo "  $1.csv: $(($(wc -l < "$BACKUP/$1.csv") - 1)) rows"
}

echo "── 1. Back up to $BACKUP"
q branches "SELECT Id, Name, fleetforce__Country__c, fleetforce__Time_Zone__c, fleetforce__US_State__c FROM fleetforce__Fleet_Branch__c"
q schedules "SELECT Id, Name, fleetforce__Time_Zone__c FROM fleetforce__Fleet_Schedule__c"
q insurance "SELECT Id, Name, fleetforce__Status__c, fleetforce__Expiration_Date__c FROM fleetforce__Insurance_Policy__c"
q qualifications "SELECT Id, Name, fleetforce__Status__c, fleetforce__Valid_Until__c FROM fleetforce__Driver_Qualification__c"
q vehicles "SELECT Id, Name, fleetforce__Country__c, fleetforce__VIN__c FROM fleetforce__Fleet_Asset__c"
python3 "$HERE/regional_map.py" "$BACKUP"

DUP=$(python3 -c "
import csv,collections,sys
v=[r['fleetforce__VIN__c'].strip().upper() for r in csv.DictReader(open('$BACKUP/vehicles.csv')) if r['fleetforce__VIN__c'].strip()]
print(', '.join(k for k,n in collections.Counter(v).items() if n>1))")
if [ -n "$DUP" ]; then
  echo "✖ Duplicate VINs (VIN becomes unique): $DUP. Fix them first."; exit 1
fi

echo "── 2. Check the destructive deploy"
sf project deploy start --metadata-dir "$HERE/drop_fields" --target-org "$ORG" --dry-run --wait 20 > "$BACKUP/drop_check.txt" 2>&1 \
  || { echo "✖ The fields cannot be dropped (see $BACKUP/drop_check.txt); something else uses them."; exit 1; }
echo "  OK"

if [ "$YES" != "--yes" ]; then
  read -r -p "Drop the five fields in $ORG and migrate? Backup is in $BACKUP. [y/N] " ok
  [ "$ok" = "y" ] || { echo "Stopped. Nothing changed."; exit 0; }
fi

echo "── 3. Drop the five fields"
sf project deploy start --metadata-dir "$HERE/drop_fields" --target-org "$ORG" --wait 20 > "$BACKUP/drop.txt" 2>&1 \
  || { echo "✖ Drop failed (see $BACKUP/drop.txt). Nothing else changed."; exit 1; }

echo "── 4. Deploy force-app"
sf project deploy start --source-dir force-app --target-org "$ORG" --ignore-conflicts --wait 30 > "$BACKUP/deploy.txt" 2>&1 \
  || { echo "✖ Deploy failed (see $BACKUP/deploy.txt). The fields are dropped; fix and rerun step 4 and 5 by hand:"
       echo "   sf project deploy start --source-dir force-app --target-org $ORG --ignore-conflicts"
       echo "   ./scripts/migration/migrate_regional.sh $ORG --restore $BACKUP"; exit 1; }

restore
