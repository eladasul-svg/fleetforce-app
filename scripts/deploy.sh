#!/bin/bash
# Fleetforce staged deployment script.
# Deploys in dependency order to avoid async schema limits and missing-reference errors.
#
# Usage:  ./scripts/deploy.sh <org-alias>
# Example: ./scripts/deploy.sh fleetforce-dev-6

set -e
ORG="${1:?Usage: $0 <org-alias>}"
echo "🚀 Fleetforce staged deployment → $ORG"

deploy() {
  echo "  → $1"
  shift
  sf project deploy start --target-org "$ORG" --ignore-conflicts "$@"
}

deploy_object() {
  local obj="$1" i="$2" total="$3"
  echo "  [$i/$total] $obj"
  sf project deploy start --target-org "$ORG" \
    --metadata "CustomObject:$obj" --ignore-conflicts
  sleep 5
}

# ── Stage 1: GlobalValueSets ──────────────────────────────────────────────────
echo "── Stage 1: GlobalValueSets ──"
deploy "globalValueSets" --source-dir force-app/main/default/globalValueSets

# ── Stage 2: Objects in dependency order ──────────────────────────────────────
echo "── Stage 2: Objects (sequential, dependency order) ──"
OBJECTS=(
  # Tier 0 — no fleetforce deps
  Fleet_Schedule__c Agreement__c Insurance_Policy__c
  Maintenance_Plan__c Vendor_Rate_Card__c Telemetry_Raw__c Driver_Qualification__c
  # Tier 1 — depends on Tier 0
  Fleet_Branch__c Agreement_Line__c Schedule_Exception__c Schedule_Window__c
  # Tier 2 (Total_Maintenance_Cost__c rollup deployed separately after Service_Ticket__c)
  Fleet_Asset__c
  # Tier 3 — depends on Fleet_Asset__c / Fleet_Branch__c
  Fuel_Card__c Service_Ticket__c Asset_Component__c Asset_Document__c
  Authorized_Driver__c Availability_Blackout__c Branch_Assignment__c
  Telematics_Equipment__c Reservation__c Schedule_Assignment__c
  # Tier 4
  Fuel_Log__c Asset_Insurance_Link__c Telemetry_Violation__c Allocation__c
  # Tier 5
  Carbon_Log__c Citation__c Service_Line_Item__c
)

# Remove rollup summary field before Fleet_Asset__c deploys (circular dep with Service_Ticket__c)
ROLLUP="force-app/main/default/objects/Fleet_Asset__c/fields/Total_Maintenance_Cost__c.field-meta.xml"
ROLLUP_BAK="/tmp/Total_Maintenance_Cost__c.bak.xml"
cp "$ROLLUP" "$ROLLUP_BAK"
rm "$ROLLUP"
trap "cp '$ROLLUP_BAK' '$ROLLUP'" EXIT
TOTAL=${#OBJECTS[@]}
for i in "${!OBJECTS[@]}"; do
  deploy_object "${OBJECTS[$i]}" "$(( i + 1 ))" "$TOTAL"
done

# Restore rollup and deploy it now that Service_Ticket__c exists
cp "$ROLLUP_BAK" "$ROLLUP"
echo "  [rollup] Fleet_Asset__c.Total_Maintenance_Cost__c"
sf project deploy start --target-org "$ORG" \
  --metadata "CustomField:Fleet_Asset__c.Total_Maintenance_Cost__c" --ignore-conflicts
sleep 3

# ── Stage 3: Apex + LWC (needed before FlexiPages) ───────────────────────────
echo "── Stage 3: Apex + LWC ──"
deploy "classes"    --source-dir force-app/main/default/classes
deploy "lwc"        --source-dir force-app/main/default/lwc
deploy "aura"       --source-dir force-app/main/default/aura
deploy "components" --source-dir force-app/main/default/components

# ── Stage 4: FlexiPages (objects + LWC must exist first) ─────────────────────
echo "── Stage 4: FlexiPages ──"
deploy "flexipages" --source-dir force-app/main/default/flexipages

# ── Stage 5: Remaining metadata ───────────────────────────────────────────────
echo "── Stage 5: Remaining metadata ──"
for dir in tabs layouts flows pages remoteSiteSettings staticresources sites applications; do
  [ -d "force-app/main/default/$dir" ] && deploy "$dir" --source-dir "force-app/main/default/$dir"
done

# ── Stage 6: Profiles + Permission Sets (depend on everything) ────────────────
echo "── Stage 6: Profiles & Permission Sets ──"
deploy "profiles"       --source-dir force-app/main/default/profiles
deploy "permissionsets" --source-dir force-app/main/default/permissionsets

echo ""
echo "✅ Deployment complete → $ORG"
echo "   Run: sf org open --target-org $ORG"
