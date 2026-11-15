"""Travel-time and distance matrix sources.

`MatrixSource` is the seam: the solver only ever sees integer seconds and metres. `OsrmMatrix` asks the
OSRM sidecar, `HaversineMatrix` estimates from straight-line distance (tests, and the fallback when
OSRM is down). A `GoogleMatrix` for traffic-aware ETAs would slot in here later.
"""

from __future__ import annotations

import logging
import math
from dataclasses import dataclass
from typing import Protocol, Sequence

import httpx

from .polyline import encode

log = logging.getLogger("fleetforce.routing.matrix")

Coord = Sequence[float]  # [lon, lat]

EARTH_RADIUS_M = 6_371_008.8


@dataclass
class Matrix:
    durations: list[list[int]]
    distances: list[list[int]]
    source: str


class MatrixSource(Protocol):
    name: str

    def table(self, locations: Sequence[Coord]) -> Matrix: ...

    def geometry(self, locations: Sequence[Coord]) -> str | None: ...

    def healthy(self) -> bool: ...


def haversine_m(a: Coord, b: Coord) -> float:
    lon1, lat1, lon2, lat2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(h))


class HaversineMatrix:
    """Straight-line distance times a detour factor, at an assumed average speed.

    Deterministic and offline, so the tests and the fallback path never depend on a road graph.
    """

    name = "haversine"

    def __init__(self, speed_kmh: float = 40.0, detour_factor: float = 1.3):
        if speed_kmh <= 0 or detour_factor < 1:
            raise ValueError("speed must be positive and the detour factor at least 1")
        self.speed_ms = speed_kmh / 3.6
        self.detour_factor = detour_factor

    def table(self, locations: Sequence[Coord]) -> Matrix:
        n = len(locations)
        distances = [[0] * n for _ in range(n)]
        durations = [[0] * n for _ in range(n)]
        for i in range(n):
            for j in range(i + 1, n):
                d = haversine_m(locations[i], locations[j]) * self.detour_factor
                t = d / self.speed_ms
                distances[i][j] = distances[j][i] = round(d)
                durations[i][j] = durations[j][i] = round(t)
        return Matrix(durations=durations, distances=distances, source=self.name)

    def geometry(self, locations: Sequence[Coord]) -> str | None:
        return encode(locations)

    def healthy(self) -> bool:
        return True


class OsrmError(RuntimeError):
    pass


class OsrmMatrix:
    """OSRM `table` and `route` services on the sidecar (car profile, MLD)."""

    name = "osrm"

    def __init__(self, base_url: str, timeout: float = 30.0, client: httpx.Client | None = None):
        self.base_url = base_url.rstrip("/")
        self.client = client or httpx.Client(timeout=timeout)

    @staticmethod
    def _coords(locations: Sequence[Coord]) -> str:
        return ";".join(f"{lon:.6f},{lat:.6f}" for lon, lat in locations)

    def table(self, locations: Sequence[Coord]) -> Matrix:
        if len(locations) == 1:
            return Matrix(durations=[[0]], distances=[[0]], source=self.name)
        url = f"{self.base_url}/table/v1/driving/{self._coords(locations)}"
        data = self._get(url, {"annotations": "duration,distance"})
        durations = [[_int(x) for x in row] for row in data["durations"]]
        distances = [[_int(x) for x in row] for row in data["distances"]]
        return Matrix(durations=durations, distances=distances, source=self.name)

    def geometry(self, locations: Sequence[Coord]) -> str | None:
        if len(locations) < 2:
            return None
        url = f"{self.base_url}/route/v1/driving/{self._coords(locations)}"
        data = self._get(url, {"overview": "full", "geometries": "polyline"})
        return data["routes"][0]["geometry"]

    def healthy(self) -> bool:
        try:
            self.table([[34.7915, 31.2520], [34.80, 31.26]])
            return True
        except Exception:  # noqa: BLE001 - any failure means "down" for the health check
            return False

    def _get(self, url: str, params: dict[str, str]) -> dict:
        try:
            res = self.client.get(url, params=params)
        except httpx.HTTPError as e:
            raise OsrmError(f"OSRM unreachable: {e}") from e
        if res.status_code != 200:
            raise OsrmError(f"OSRM returned {res.status_code}: {res.text[:200]}")
        data = res.json()
        if data.get("code") != "Ok":
            raise OsrmError(f"OSRM error {data.get('code')}: {data.get('message')}")
        return data


def _int(x: float | None) -> int:
    # OSRM returns null for pairs it cannot connect; treat as effectively unreachable.
    return 10_000_000 if x is None else round(x)


class FallbackMatrix:
    """Primary source with a fallback: OSRM first, Haversine if OSRM fails."""

    def __init__(self, primary: MatrixSource, fallback: MatrixSource):
        self.primary = primary
        self.fallback = fallback

    @property
    def name(self) -> str:
        return self.primary.name

    def table(self, locations: Sequence[Coord]) -> Matrix:
        try:
            return self.primary.table(locations)
        except Exception as e:  # noqa: BLE001
            log.warning("matrix source %s failed, falling back: %s", self.primary.name, e)
            m = self.fallback.table(locations)
            m.source = f"{self.fallback.name} (fallback)"
            return m

    def geometry(self, locations: Sequence[Coord]) -> str | None:
        try:
            return self.primary.geometry(locations)
        except Exception:  # noqa: BLE001
            return self.fallback.geometry(locations)

    def healthy(self) -> bool:
        return self.primary.healthy()
