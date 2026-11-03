# FleetForce Routing Service

The solver behind FleetForce Routing (`docs/decisions/routing-module.md`, Section 6). A FastAPI app
that runs [VROOM](https://github.com/VROOM-Project/vroom) in-process through `pyvroom`, over a
travel-time matrix from an OSRM sidecar (or a straight-line `HaversineMatrix` for tests and as a
fallback). Salesforce calls it through the `FleetForce_Routing` named credential.

```
services/routing/
  app/schemas.py      the v1 contract (Pydantic; OpenAPI is generated from it)
  app/solver.py       neutral JSON -> VROOM problem -> neutral result, locked prefixes, unassigned reasons
  app/matrix.py       MatrixSource: OsrmMatrix, HaversineMatrix, FallbackMatrix
  app/main.py         endpoints, X-FleetForce-Key auth, metering log line
  osrm/               OSRM pre-processing script and sidecar image
  Dockerfile          API image
  docker-compose.yml  local OSRM + API
  cloudbuild.yaml     OSRM graph + images + Cloud Run deploy
  service.yaml        Cloud Run multi-container service (API + OSRM sidecar)
  tests/              pytest, all on HaversineMatrix (no network, no Docker)
```

## Run the tests

Needs Python 3.10 or later (the image uses 3.12). On a Mac with only the system Python 3.9, use a
standalone 3.12, for example `~/.local/python3.12/bin/python3 -m venv .venv`.

```bash
cd services/routing
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
python -m pytest -q
```

The scenarios from the work order live in `tests/test_scenarios.py`: (a) 6 vans and 60 drops around
the Beer Sheva depot, (b) the 12-car overnight relocation as pickup→drop shipments, (c) re-optimizing
after a 40-minute delay with the next stop locked, (d) jobs left unassigned with a reason.

## Run locally without a map (fastest)

```bash
cd services/routing
FLEETFORCE_AUTH_DISABLED=1 MATRIX_SOURCE=haversine uvicorn app.main:app --reload --port 8080
# http://localhost:8080/docs for the generated OpenAPI UI
```

## Run locally with OSRM (docker compose)

```bash
cd services/routing
./osrm/prepare.sh                 # downloads the Geofabrik israel-and-palestine extract, builds map.osrm* (MLD, car)
docker compose up --build         # OSRM on :5000, API on :8080 (auth disabled)
curl -s localhost:8080/healthz    # {"status":"ok","solver":"pyvroom","osrm":"up",...}
```

Another region: `./osrm/prepare.sh north-america/us/texas` (OSRM needs about 2x the .pbf size in RAM to
serve and 7x while pre-processing).

## API (v1)

All endpoints except `/healthz` need `X-FleetForce-Key`. Coordinates are `[lon, lat]`, distances
metres, durations seconds, times ISO 8601 (UTC recommended).

| Endpoint            | Purpose                                                                                                                                 |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `POST /v1/optimize` | `vehicles[]`, `jobs[]`, `shipments[]`, `options` (objective, geometry, `fixed[]`) → `routes[]`, `unassigned[]` with `reason`, `summary` |
| `POST /v1/matrix`   | `locations[]` → `durations[][]`, `distances[][]`                                                                                        |
| `POST /v1/route`    | ordered `waypoints[]` (+ optional `departure`) → `legs[]`, totals, geometry                                                             |
| `GET /healthz`      | solver and OSRM status (unauthenticated, used by the Cloud Run startup probe)                                                           |

Notes on the contract:

- **Capacity** has three slots (`Capacity_Dimension__mdt` 1–3). A vehicle without `capacity` is unlimited.
- **Skills** are plain strings; the service maps them to VROOM's integers.
- **Objectives:** `min_duration` (default), `min_distance`, `min_vehicles` (a large fixed cost per
  vehicle used), `balanced` (caps tasks per vehicle at ⌈tasks / vehicles⌉ + 1).
- **`options.fixed[]`** pins a route's next stops: `{vehicle_id, task_ids[]}`. The service plays them
  forward from the vehicle's `start`/`shift_start` in that order (reporting `late_seconds` if a window
  is already missed), then solves the rest from the last locked stop. VROOM's own `vehicles[].steps`
  is only an initial solution hint, not a hard pin, so it is not used for this. If a shipment's pickup
  is locked but its delivery is not, the delivery stays on the same vehicle.
- **Unassigned reasons:** `skills`, `capacity`, `time_window`, `no_room` (eligible vehicles are full or
  out of time). VROOM itself reports only _what_ it could not place; the service works out _why_.
- **Breaks** (`vehicles[].breaks`) come back as `type: "break"` steps; FleetForce uses them for Break and
  Charge waypoints.

## Configuration

| Variable                   | Default                                       | Meaning                                                                                     |
| -------------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `FLEETFORCE_API_KEYS`      | —                                             | JSON `{"<key>": "<subscriber org Id>"}`; on Cloud Run, the `fleetforce-routing-keys` secret |
| `FLEETFORCE_AUTH_DISABLED` | —                                             | `1` skips the key check (local only)                                                        |
| `MATRIX_SOURCE`            | `osrm` if `OSRM_URL` is set, else `haversine` | which matrix to use                                                                         |
| `OSRM_URL`                 | —                                             | e.g. `http://localhost:5000`                                                                |
| `HAVERSINE_SPEED_KMH`      | `40`                                          | average speed assumed by `HaversineMatrix` (with a 1.3 detour factor)                       |
| `VROOM_THREADS`            | `min(4, CPUs)`                                | solver threads                                                                              |

Every request logs one JSON line (`event: routing_request`, `org_id`, `jobs`, `vehicles`, `ms`, ...)
for metering in Cloud Logging.

## Deploy (GCP)

The commands for the first deploy (Artifact Registry repo, secret, service account, Cloud Build) are in
`docs/Code Work Orders/routing-local-next-steps.md`. In short:

```bash
gcloud builds submit services/routing --config services/routing/cloudbuild.yaml \
  --substitutions=_REGION=me-west1,_REPO=fleetforce
```
