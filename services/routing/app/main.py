"""FleetForce Routing Service: FastAPI app.

Run locally:  uvicorn app.main:app --reload --port 8080
Environment:
  FLEETFORCE_API_KEYS      JSON object {"<key>": "<subscriber org Id>"} (mounted from Secret Manager)
  FLEETFORCE_AUTH_DISABLED "1" to skip the key check (local development only)
  MATRIX_SOURCE            "osrm" (default when OSRM_URL is set) or "haversine"
  OSRM_URL                 e.g. http://localhost:5000 (the sidecar)
  HAVERSINE_SPEED_KMH      assumed average speed for HaversineMatrix (default 40)
  VROOM_THREADS            solver threads (default min(4, cpu count))
"""

from __future__ import annotations

import json
import logging
import os
import time
from functools import lru_cache

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse

from . import schemas as s
from .matrix import FallbackMatrix, HaversineMatrix, MatrixSource, OsrmError, OsrmMatrix
from .solver import SolveError, optimize, route

VERSION = "1.0.0"

logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(message)s")
log = logging.getLogger("fleetforce.routing")

app = FastAPI(
    title="FleetForce Routing Service",
    version=VERSION,
    description="Vehicle routing for FleetForce: VROOM solver over an OSRM or Haversine matrix.",
)


# -------------------------------------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------------------------------------


@lru_cache
def api_keys() -> dict[str, str]:
    raw = os.environ.get("FLEETFORCE_API_KEYS", "").strip()
    if not raw:
        return {}
    keys = json.loads(raw)
    if not isinstance(keys, dict):
        raise RuntimeError("FLEETFORCE_API_KEYS must be a JSON object of key -> org Id")
    return {str(k): str(v) for k, v in keys.items()}


@lru_cache
def matrix_source() -> MatrixSource:
    haversine = HaversineMatrix(speed_kmh=float(os.environ.get("HAVERSINE_SPEED_KMH", "40")))
    osrm_url = os.environ.get("OSRM_URL", "").strip()
    choice = os.environ.get("MATRIX_SOURCE", "osrm" if osrm_url else "haversine").lower()
    if choice == "osrm":
        if not osrm_url:
            raise RuntimeError("MATRIX_SOURCE=osrm needs OSRM_URL")
        return FallbackMatrix(OsrmMatrix(osrm_url), haversine)
    return haversine


def get_source() -> MatrixSource:
    return matrix_source()


def require_key(x_fleetforce_key: str | None = Header(default=None)) -> str:
    """Returns the subscriber org Id the key belongs to."""
    if os.environ.get("FLEETFORCE_AUTH_DISABLED") == "1":
        return "local-dev"
    keys = api_keys()
    if not x_fleetforce_key or x_fleetforce_key not in keys:
        raise HTTPException(status_code=401, detail="Missing or unknown X-FleetForce-Key")
    return keys[x_fleetforce_key]


# -------------------------------------------------------------------------------------------------
# Endpoints
# -------------------------------------------------------------------------------------------------


def _meter(org_id: str, endpoint: str, started: float, **fields) -> None:
    # One structured line per request: Cloud Logging parses JSON, so this is the metering record.
    log.info(
        json.dumps(
            {
                "event": "routing_request",
                "endpoint": endpoint,
                "org_id": org_id,
                "ms": round((time.perf_counter() - started) * 1000),
                **fields,
            }
        )
    )


@app.post("/v1/optimize", response_model=s.OptimizeResponse)
def post_optimize(
    req: s.OptimizeRequest,
    org_id: str = Depends(require_key),
    source: MatrixSource = Depends(get_source),
) -> s.OptimizeResponse:
    started = time.perf_counter()
    try:
        result = optimize(req, source)
    except SolveError as e:
        raise HTTPException(status_code=422, detail=str(e)) from e
    _meter(
        org_id,
        "optimize",
        started,
        jobs=len(req.jobs),
        shipments=len(req.shipments),
        vehicles=len(req.vehicles),
        unassigned=result.summary.unassigned,
        matrix=result.summary.matrix_source,
    )
    return result


@app.post("/v1/matrix", response_model=s.MatrixResponse)
def post_matrix(
    req: s.MatrixRequest,
    org_id: str = Depends(require_key),
    source: MatrixSource = Depends(get_source),
) -> s.MatrixResponse:
    started = time.perf_counter()
    m = source.table(req.locations)
    _meter(org_id, "matrix", started, locations=len(req.locations), matrix=m.source)
    return s.MatrixResponse(durations=m.durations, distances=m.distances, matrix_source=m.source)


@app.post("/v1/route", response_model=s.RouteResponse)
def post_route(
    req: s.RouteRequest,
    org_id: str = Depends(require_key),
    source: MatrixSource = Depends(get_source),
) -> s.RouteResponse:
    started = time.perf_counter()
    result = route(req, source)
    _meter(org_id, "route", started, waypoints=len(req.waypoints), matrix=result.matrix_source)
    return result


@app.get("/healthz", response_model=s.Health)
def healthz(source: MatrixSource = Depends(get_source)) -> s.Health:
    if isinstance(source, FallbackMatrix):
        osrm = "up" if source.healthy() else "down"
        active = source.primary.name if osrm == "up" else f"{source.fallback.name} (fallback)"
    else:
        osrm, active = "not_configured", source.name
    try:
        import vroom  # noqa: F401

        solver = "pyvroom"
    except ImportError:  # pragma: no cover - the image always has it
        solver = "missing"
    status = "ok" if solver != "missing" and osrm != "down" else "degraded"
    return s.Health(status=status, solver=solver, osrm=osrm, matrix_source=active, version=VERSION)


@app.exception_handler(OsrmError)
def osrm_error(_: Request, exc: OsrmError) -> JSONResponse:
    return JSONResponse(status_code=502, content={"detail": str(exc)})
