#!/usr/bin/env bash
# Builds the OSRM car graph (MLD) for one Geofabrik extract into osrm/data/.
# Local use:   ./osrm/prepare.sh                    (Israel + Palestine, ~0.1-0.2 GB download)
#              ./osrm/prepare.sh north-america/us/texas
# Cloud Build runs the same three osrm-* steps itself (see cloudbuild.yaml).
# Needs Docker. Peak RAM while pre-processing is about 7x the .pbf size.
set -euo pipefail

REGION_PATH="${1:-asia/israel-and-palestine}"
OSRM_IMAGE="${OSRM_IMAGE:-ghcr.io/project-osrm/osrm-backend:v5.27.1}"
NAME="$(basename "$REGION_PATH")"
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="$HERE/data"

mkdir -p "$DATA"
if [ ! -f "$DATA/$NAME-latest.osm.pbf" ]; then
  echo "Downloading $REGION_PATH from Geofabrik..."
  curl -fL --retry 3 -o "$DATA/$NAME-latest.osm.pbf" \
    "https://download.geofabrik.de/$REGION_PATH-latest.osm.pbf"
fi

run() { docker run --rm -t -v "$DATA:/data" "$OSRM_IMAGE" "$@"; }
run osrm-extract -p /opt/car.lua "/data/$NAME-latest.osm.pbf"
run osrm-partition "/data/$NAME-latest.osrm"
run osrm-customize "/data/$NAME-latest.osrm"

# The sidecar image and docker compose expect a fixed base name.
for f in "$DATA/$NAME-latest.osrm"*; do
  mv -f "$f" "$DATA/map.osrm${f#"$DATA/$NAME-latest.osrm"}"
done
echo "OSRM graph ready in $DATA (map.osrm*)."
