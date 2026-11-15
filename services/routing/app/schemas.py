"""Neutral FleetForce routing contract (v1).

These Pydantic models are the API: FastAPI generates the OpenAPI document from them, and the
Salesforce DTOs (`RoutingDtos.cls`) mirror them field for field. Units are SI throughout:
coordinates are [lon, lat], distances are metres, durations are seconds, times are ISO 8601.
"""

from __future__ import annotations

from datetime import datetime
from enum import Enum
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, Field, model_validator

CAPACITY_DIMENSIONS = 3

Coordinate = Annotated[
    list[float],
    Field(min_length=2, max_length=2, description="[longitude, latitude] in WGS84 degrees"),
    AfterValidator(lambda v: _check_coordinate(v)),
]
Amount = Annotated[
    list[int],
    Field(
        max_length=CAPACITY_DIMENSIONS,
        description="Load per capacity dimension (slots 1-3, see Capacity_Dimension__mdt). "
        "Shorter lists are padded with zeros.",
    ),
]


def _check_coordinate(value: list[float]) -> list[float]:
    lon, lat = value
    if not (-180 <= lon <= 180 and -90 <= lat <= 90):
        raise ValueError(f"coordinate {value} is not [lon, lat]")
    return value


class _Model(BaseModel):
    model_config = ConfigDict(extra="forbid")


class TimeWindow(_Model):
    start: datetime
    end: datetime

    @model_validator(mode="after")
    def _ordered(self) -> "TimeWindow":
        if self.end < self.start:
            raise ValueError("time window end is before its start")
        return self


class Break(_Model):
    id: str
    time_windows: list[TimeWindow] = Field(min_length=1)
    service_seconds: int = Field(ge=0, default=0)
    description: str | None = None


class Vehicle(_Model):
    id: str
    start: Coordinate
    end: Coordinate | None = Field(
        default=None, description="Omit for an open trip that ends at the last stop."
    )
    shift_start: datetime
    shift_end: datetime
    capacity: Amount | None = Field(
        default=None, description="Omit for unlimited capacity in every dimension."
    )
    skills: list[str] = Field(default_factory=list)
    breaks: list[Break] = Field(default_factory=list)
    speed_factor: float = Field(default=1.0, gt=0, le=5)
    max_travel_seconds: int | None = Field(default=None, ge=0)


    @model_validator(mode="after")
    def _shift(self) -> "Vehicle":
        if self.shift_end <= self.shift_start:
            raise ValueError(f"vehicle {self.id}: shift_end must be after shift_start")
        return self


class Job(_Model):
    id: str
    location: Coordinate
    service_seconds: int = Field(ge=0, default=0)
    time_windows: list[TimeWindow] = Field(default_factory=list)
    delivery: Amount = Field(default_factory=list)
    pickup: Amount = Field(default_factory=list)
    skills: list[str] = Field(default_factory=list)
    priority: int = Field(default=0, ge=0, le=100)
    description: str | None = None



class ShipmentStep(_Model):
    id: str
    location: Coordinate
    service_seconds: int = Field(ge=0, default=0)
    time_windows: list[TimeWindow] = Field(default_factory=list)
    description: str | None = None



class Shipment(_Model):
    id: str
    pickup: ShipmentStep
    delivery: ShipmentStep
    amount: Amount = Field(default_factory=list)
    skills: list[str] = Field(default_factory=list)
    priority: int = Field(default=0, ge=0, le=100)


class Objective(str, Enum):
    min_duration = "min_duration"
    min_distance = "min_distance"
    min_vehicles = "min_vehicles"
    balanced = "balanced"


class FixedSteps(_Model):
    """A locked prefix of a vehicle's route (started or promised stops).

    The service plays these steps forward from the vehicle's start and shift_start, in this exact
    order, then lets the solver order everything else from the last locked stop onward.
    """

    vehicle_id: str
    task_ids: list[str] = Field(
        min_length=1, description="Job ids, or shipment pickup/delivery step ids, in order."
    )


class Options(_Model):
    objective: Objective = Objective.min_duration
    geometry: bool = False
    exploration_level: int = Field(default=5, ge=1, le=5)
    timeout_seconds: int | None = Field(default=None, ge=1, le=300)
    fixed: list[FixedSteps] = Field(default_factory=list)


class OptimizeRequest(_Model):
    vehicles: list[Vehicle] = Field(min_length=1)
    jobs: list[Job] = Field(default_factory=list)
    shipments: list[Shipment] = Field(default_factory=list)
    options: Options = Field(default_factory=Options)

    @model_validator(mode="after")
    def _unique_ids(self) -> "OptimizeRequest":
        seen: set[str] = set()
        task_ids = [j.id for j in self.jobs]
        for s in self.shipments:
            task_ids += [s.pickup.id, s.delivery.id]
        for tid in task_ids:
            if tid in seen:
                raise ValueError(f"duplicate task id {tid!r}")
            seen.add(tid)
        vids = [v.id for v in self.vehicles]
        if len(set(vids)) != len(vids):
            raise ValueError("duplicate vehicle id")
        for f in self.options.fixed:
            if f.vehicle_id not in vids:
                raise ValueError(f"fixed steps reference unknown vehicle {f.vehicle_id!r}")
            for tid in f.task_ids:
                if tid not in seen:
                    raise ValueError(f"fixed steps reference unknown task {tid!r}")
        return self


StepType = Literal["start", "job", "pickup", "delivery", "break", "end"]


class Step(_Model):
    type: StepType
    id: str | None = None
    location: Coordinate | None = None
    arrival: datetime
    departure: datetime
    service_seconds: int = 0
    waiting_seconds: int = 0
    leg_distance_m: int = 0
    leg_duration_s: int = 0
    load: list[int] = Field(default_factory=list)
    locked: bool = False
    late_seconds: int = Field(
        default=0, description="How far past its last time window the arrival is (locked stops)."
    )


class Route(_Model):
    vehicle_id: str
    steps: list[Step]
    distance_m: int
    duration_s: int
    service_s: int
    waiting_s: int
    start_time: datetime
    end_time: datetime
    geometry: str | None = Field(default=None, description="Encoded polyline (precision 5)")


UnassignedReason = Literal["skills", "capacity", "time_window", "no_room", "locked_conflict"]


class Unassigned(_Model):
    id: str
    type: Literal["job", "pickup", "delivery", "shipment"]
    reason: UnassignedReason
    detail: str


class Summary(_Model):
    routes: int
    assigned: int
    unassigned: int
    distance_m: int
    duration_s: int
    service_s: int
    waiting_s: int
    cost: int
    matrix_source: str
    solve_ms: int


class OptimizeResponse(_Model):
    routes: list[Route]
    unassigned: list[Unassigned]
    summary: Summary


class MatrixRequest(_Model):
    locations: list[Coordinate] = Field(min_length=1, max_length=2500)


class MatrixResponse(_Model):
    durations: list[list[int]]
    distances: list[list[int]]
    matrix_source: str


class RouteWaypoint(_Model):
    id: str | None = None
    location: Coordinate


class RouteRequest(_Model):
    waypoints: list[RouteWaypoint] = Field(min_length=2)
    departure: datetime | None = None
    geometry: bool = True


class Leg(_Model):
    from_id: str | None
    to_id: str | None
    distance_m: int
    duration_s: int
    arrival: datetime | None = None


class RouteResponse(_Model):
    legs: list[Leg]
    distance_m: int
    duration_s: int
    geometry: str | None = None
    matrix_source: str


class Health(_Model):
    status: Literal["ok", "degraded"]
    solver: str
    osrm: Literal["up", "down", "not_configured"]
    matrix_source: str
    version: str
