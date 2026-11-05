from __future__ import annotations

import json
import logging

import httpx
import pytest

from app import main
from app.matrix import FallbackMatrix, HaversineMatrix, OsrmError, OsrmMatrix, haversine_m
from app.polyline import decode, encode

from . import fixtures as fx
from .conftest import TEST_ORG


# -------------------------------------------------------------------------------------------------
# Auth and endpoints
# -------------------------------------------------------------------------------------------------


def test_optimize_requires_a_known_key(client):
    body = fx.single_van(2)
    assert client.post("/v1/optimize", json=body).status_code == 401
    assert client.post("/v1/optimize", json=body, headers={"X-FleetForce-Key": "nope"}).status_code == 401


def test_auth_can_be_disabled_for_local_dev(client, monkeypatch):
    monkeypatch.setenv("FLEETFORCE_AUTH_DISABLED", "1")
    assert client.post("/v1/matrix", json={"locations": [fx.DEPOT]}).status_code == 200


def test_optimize_returns_routes_and_logs_metering(client, headers, caplog):
    caplog.set_level(logging.INFO, logger="fleetforce.routing")
    res = client.post("/v1/optimize", json=fx.morning_vans(), headers=headers)
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["summary"]["assigned"] == 60
    assert data["routes"][0]["steps"][0]["arrival"].endswith("Z")
    record = next(json.loads(r.message) for r in caplog.records if "routing_request" in r.message)
    assert record["org_id"] == TEST_ORG
    assert (record["jobs"], record["vehicles"], record["endpoint"]) == (60, 6, "optimize")
    assert record["ms"] >= 0


def test_optimize_rejects_bad_input(client, headers):
    body = fx.single_van(2)
    body["jobs"][1]["id"] = body["jobs"][0]["id"]
    res = client.post("/v1/optimize", json=body, headers=headers)
    assert res.status_code == 422
    assert "duplicate task id" in res.text

    body = fx.single_van(1)
    body["jobs"][0]["location"] = [31.25, 134.79]  # lat/lon swapped and out of range
    assert client.post("/v1/optimize", json=body, headers=headers).status_code == 422

    body = fx.single_van(1)
    body["options"]["fixed"] = [{"vehicle_id": "ghost", "task_ids": ["stop-01"]}]
    assert "unknown vehicle" in client.post("/v1/optimize", json=body, headers=headers).text

    body = fx.single_van(1)
    body["vehicles"][0]["shift_end"] = body["vehicles"][0]["shift_start"]
    assert client.post("/v1/optimize", json=body, headers=headers).status_code == 422


def test_matrix_endpoint(client, headers):
    res = client.post("/v1/matrix", json={"locations": [fx.DEPOT, fx.LOTS["university"]]}, headers=headers)
    data = res.json()
    assert data["matrix_source"] == "haversine"
    assert data["durations"][0][0] == 0 and data["durations"][0][1] == data["durations"][1][0] > 0
    assert data["distances"][0][1] > 1000


def test_route_endpoint_keeps_the_given_order(client, headers):
    waypoints = [
        {"id": "start", "location": fx.DEPOT},
        {"id": "b", "location": fx.LOTS["university"]},
        {"id": "a", "location": fx.LOTS["central_station"]},
    ]
    res = client.post(
        "/v1/route",
        json={"waypoints": waypoints, "departure": fx.iso(fx.local(9))},
        headers=headers,
    )
    data = res.json()
    assert [(leg["from_id"], leg["to_id"]) for leg in data["legs"]] == [("start", "b"), ("b", "a")]
    assert data["distance_m"] == sum(leg["distance_m"] for leg in data["legs"])
    assert len(decode(data["geometry"])) == 3
    assert data["legs"][1]["arrival"] > data["legs"][0]["arrival"]


def test_healthz_without_osrm(client):
    data = client.get("/healthz").json()
    assert data == {
        "status": "ok",
        "solver": "pyvroom",
        "osrm": "not_configured",
        "matrix_source": "haversine",
        "version": main.VERSION,
    }


def test_healthz_reports_osrm_down_and_fallback(client, monkeypatch):
    dead = OsrmMatrix("http://osrm", client=httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(503))))
    main.app.dependency_overrides[main.get_source] = lambda: FallbackMatrix(dead, HaversineMatrix())
    try:
        data = client.get("/healthz").json()
    finally:
        main.app.dependency_overrides.clear()
    assert (data["status"], data["osrm"], data["matrix_source"]) == ("degraded", "down", "haversine (fallback)")


def test_openapi_is_generated_from_the_schemas(client):
    spec = client.get("/openapi.json").json()
    assert {"/v1/optimize", "/v1/matrix", "/v1/route", "/healthz"} <= set(spec["paths"])
    assert "OptimizeRequest" in spec["components"]["schemas"]


def test_osrm_source_requires_url(monkeypatch):
    monkeypatch.setenv("MATRIX_SOURCE", "osrm")
    monkeypatch.delenv("OSRM_URL", raising=False)
    main.matrix_source.cache_clear()
    with pytest.raises(RuntimeError):
        main.matrix_source()
    monkeypatch.setenv("OSRM_URL", "http://localhost:5000")
    main.matrix_source.cache_clear()
    assert isinstance(main.matrix_source(), FallbackMatrix)
    main.matrix_source.cache_clear()


# -------------------------------------------------------------------------------------------------
# Matrix sources
# -------------------------------------------------------------------------------------------------


def test_haversine_is_symmetric_and_scaled():
    m = HaversineMatrix(speed_kmh=36, detour_factor=1.0).table([fx.DEPOT, fx.LOTS["university"], fx.DEPOT])
    straight = haversine_m(fx.DEPOT, fx.LOTS["university"])
    assert m.distances[0][1] == m.distances[1][0] == round(straight)
    assert m.durations[0][1] == round(straight / 10)  # 36 km/h = 10 m/s
    assert m.distances[0][2] == 0


def test_haversine_rejects_nonsense_settings():
    with pytest.raises(ValueError):
        HaversineMatrix(speed_kmh=0)


def _osrm_transport(calls: list):
    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        if "/table/" in request.url.path:
            return httpx.Response(
                200,
                json={"code": "Ok", "durations": [[0, 61.4], [59.6, 0]], "distances": [[0, 812.2], [790.0, None]]},
            )
        return httpx.Response(200, json={"code": "Ok", "routes": [{"geometry": "abc"}]})

    return httpx.MockTransport(handler)


def test_osrm_table_and_route_parsing():
    calls: list = []
    osrm = OsrmMatrix("http://osrm:5000/", client=httpx.Client(transport=_osrm_transport(calls)))
    m = osrm.table([fx.DEPOT, fx.LOTS["university"]])
    assert m.durations == [[0, 61], [60, 0]]
    assert m.distances[1][1] == 10_000_000  # unreachable pair
    assert calls[0].url.path == "/table/v1/driving/34.791300,31.251800;34.801700,31.262200"
    assert calls[0].url.params["annotations"] == "duration,distance"
    assert osrm.geometry([fx.DEPOT, fx.LOTS["university"]]) == "abc"
    assert osrm.table([fx.DEPOT]).durations == [[0]]
    assert osrm.geometry([fx.DEPOT]) is None
    assert osrm.healthy()


def test_osrm_errors_raise():
    bad = OsrmMatrix(
        "http://osrm",
        client=httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"code": "NoTable"}))),
    )
    with pytest.raises(OsrmError):
        bad.table([fx.DEPOT, fx.LOTS["university"]])

    def boom(request):
        raise httpx.ConnectError("refused")

    down = OsrmMatrix("http://osrm", client=httpx.Client(transport=httpx.MockTransport(boom)))
    with pytest.raises(OsrmError):
        down.table([fx.DEPOT, fx.LOTS["university"]])
    assert not down.healthy()


def test_fallback_uses_haversine_when_osrm_fails(source):
    def boom(request):
        raise httpx.ConnectError("refused")

    down = OsrmMatrix("http://osrm", client=httpx.Client(transport=httpx.MockTransport(boom)))
    fb = FallbackMatrix(down, source)
    m = fb.table([fx.DEPOT, fx.LOTS["university"]])
    assert m.source == "haversine (fallback)"
    assert fb.geometry([fx.DEPOT, fx.LOTS["university"]]) == source.geometry([fx.DEPOT, fx.LOTS["university"]])
    assert fb.name == "osrm"


def test_optimize_with_osrm_matrix_end_to_end(client, headers):
    """The solver consumes an OSRM-shaped matrix the same way it consumes Haversine."""

    def handler(request: httpx.Request) -> httpx.Response:
        n = len(request.url.path.split("/")[-1].split(";"))
        return httpx.Response(
            200,
            json={
                "code": "Ok",
                "durations": [[0 if i == j else 300 for j in range(n)] for i in range(n)],
                "distances": [[0 if i == j else 3000 for j in range(n)] for i in range(n)],
            },
        )

    osrm = OsrmMatrix("http://osrm", client=httpx.Client(transport=httpx.MockTransport(handler)))
    main.app.dependency_overrides[main.get_source] = lambda: osrm
    try:
        res = client.post("/v1/optimize", json=fx.single_van(3), headers=headers)
    finally:
        main.app.dependency_overrides.clear()
    data = res.json()
    assert data["summary"]["matrix_source"] == "osrm"
    assert data["summary"]["distance_m"] == 4 * 3000


# -------------------------------------------------------------------------------------------------
# Polyline
# -------------------------------------------------------------------------------------------------


def test_polyline_matches_the_reference_example():
    # Google's documented example: (38.5,-120.2), (40.7,-120.95), (43.252,-126.453)
    pts = [[-120.2, 38.5], [-120.95, 40.7], [-126.453, 43.252]]
    assert encode(pts) == "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
    assert decode(encode(pts)) == pts
