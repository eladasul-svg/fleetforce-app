"""Translates the neutral FleetForce contract into a VROOM problem, solves it, and maps it back.

VROOM works in integer seconds and integer ids against a matrix indexed by location. Everything
FleetForce-specific (string ids, datetimes, skill names, locked prefixes, reasons for unassigned jobs)
is handled here, so the VROOM problem itself stays the plain JSON that vroom-express and
openrouteservice also accept.
"""

from __future__ import annotations

import json
import math
import os
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Iterable

import vroom

from . import schemas as s
from .matrix import Matrix, MatrixSource

UNLIMITED = 1_000_000_000
MIN_VEHICLES_FIXED_COST = 10_000_000
VEHICLE_SKILL_PREFIX = "__vehicle:"


class SolveError(RuntimeError):
    pass


# -------------------------------------------------------------------------------------------------
# Internal task model
# -------------------------------------------------------------------------------------------------


@dataclass
class Task:
    """One thing a vehicle stops for: a job, or one end of a shipment."""

    id: str
    kind: str  # job | pickup | delivery
    location: list[float]
    service: int
    windows: list[s.TimeWindow]
    skills: list[str]
    priority: int
    delivery: list[int] = field(default_factory=lambda: [0, 0, 0])  # jobs
    pickup: list[int] = field(default_factory=lambda: [0, 0, 0])  # jobs
    amount: list[int] = field(default_factory=lambda: [0, 0, 0])  # shipment ends
    shipment_id: str | None = None
    partner_id: str | None = None  # the other end of a shipment


def _pad(amount: Iterable[int] | None, fill: int = 0) -> list[int]:
    values = list(amount or [])
    return values + [fill] * (s.CAPACITY_DIMENSIONS - len(values))


def _tasks(req: s.OptimizeRequest) -> dict[str, Task]:
    out: dict[str, Task] = {}
    for j in req.jobs:
        out[j.id] = Task(
            id=j.id,
            kind="job",
            location=j.location,
            service=j.service_seconds,
            windows=j.time_windows,
            skills=j.skills,
            priority=j.priority,
            delivery=_pad(j.delivery),
            pickup=_pad(j.pickup),
        )
    for sh in req.shipments:
        for kind, step, partner in (
            ("pickup", sh.pickup, sh.delivery.id),
            ("delivery", sh.delivery, sh.pickup.id),
        ):
            out[step.id] = Task(
                id=step.id,
                kind=kind,
                location=step.location,
                service=step.service_seconds,
                windows=step.time_windows,
                skills=sh.skills,
                priority=sh.priority,
                amount=_pad(sh.amount),
                shipment_id=sh.id,
                partner_id=partner,
            )
    return out


# -------------------------------------------------------------------------------------------------
# Clock and locations
# -------------------------------------------------------------------------------------------------


class Clock:
    """Maps datetimes to integer seconds from the earliest instant in the request."""

    def __init__(self, instants: Iterable[datetime]):
        normalised = [_aware(t) for t in instants]
        self.epoch = min(normalised) if normalised else datetime.now(timezone.utc)

    def sec(self, t: datetime) -> int:
        return max(0, int((_aware(t) - self.epoch).total_seconds()))

    def dt(self, seconds: int | float) -> datetime:
        return self.epoch + timedelta(seconds=int(seconds))


def _aware(t: datetime) -> datetime:
    return t if t.tzinfo else t.replace(tzinfo=timezone.utc)


def _instants(req: s.OptimizeRequest) -> list[datetime]:
    out: list[datetime] = []
    for v in req.vehicles:
        out += [v.shift_start, v.shift_end]
        for b in v.breaks:
            out += [w.start for w in b.time_windows]
    for j in req.jobs:
        out += [w.start for w in j.time_windows]
    for sh in req.shipments:
        out += [w.start for w in sh.pickup.time_windows + sh.delivery.time_windows]
    return out


class Locations:
    def __init__(self) -> None:
        self.coords: list[list[float]] = []
        self._index: dict[tuple[float, float], int] = {}

    def add(self, coord: list[float]) -> int:
        key = (round(coord[0], 6), round(coord[1], 6))
        if key not in self._index:
            self._index[key] = len(self.coords)
            self.coords.append([coord[0], coord[1]])
        return self._index[key]


# -------------------------------------------------------------------------------------------------
# Locked prefixes
# -------------------------------------------------------------------------------------------------


@dataclass
class LockedPrefix:
    steps: list[dict]  # partially built output steps (seconds, location index)
    end_index: int
    end_time: int


def _travel(m: Matrix, a: int, b: int, speed_factor: float) -> int:
    return round(m.durations[a][b] / speed_factor)


def _play_locked(
    vehicle: s.Vehicle,
    task_ids: list[str],
    tasks: dict[str, Task],
    locs: Locations,
    m: Matrix,
    clock: Clock,
) -> LockedPrefix:
    t = clock.sec(vehicle.shift_start)
    at = locs.add(vehicle.start)
    steps = []
    for tid in task_ids:
        task = tasks[tid]
        idx = locs.add(task.location)
        arrival = t + _travel(m, at, idx, vehicle.speed_factor)
        wait, late = 0, 0
        if task.windows:
            windows = sorted(task.windows, key=lambda w: w.start)
            open_window = next((w for w in windows if clock.sec(w.end) >= arrival), None)
            if open_window is None:
                late = arrival - clock.sec(windows[-1].end)
            else:
                wait = max(0, clock.sec(open_window.start) - arrival)
        departure = arrival + wait + task.service
        steps.append(
            {
                "type": task.kind,
                "task": task,
                "index": idx,
                "arrival": arrival,
                "waiting": wait,
                "service": task.service,
                "locked": True,
                "late": late,
            }
        )
        t, at = departure, idx
    return LockedPrefix(steps=steps, end_index=at, end_time=t)


# -------------------------------------------------------------------------------------------------
# The solve
# -------------------------------------------------------------------------------------------------


def _costs(objective: s.Objective) -> dict[str, int]:
    if objective == s.Objective.min_distance:
        return {"per_hour": 1, "per_km": 3600}
    if objective == s.Objective.min_vehicles:
        return {"per_hour": 3600, "fixed": MIN_VEHICLES_FIXED_COST}
    if objective == s.Objective.balanced:
        return {"per_hour": 3600, "per_km": 1800}
    return {"per_hour": 3600}


def _windows(windows: list[s.TimeWindow], clock: Clock) -> list[list[int]]:
    return [[clock.sec(w.start), clock.sec(w.end)] for w in windows]


def optimize(req: s.OptimizeRequest, source: MatrixSource) -> s.OptimizeResponse:
    started = time.perf_counter()
    tasks = _tasks(req)
    clock = Clock(_instants(req))

    locs = Locations()
    for v in req.vehicles:
        locs.add(v.start)
        if v.end is not None:
            locs.add(v.end)
    for t in tasks.values():
        locs.add(t.location)
    m = source.table(locs.coords)

    # Locked prefixes: played forward here, removed from what the solver sees.
    locked: dict[str, LockedPrefix] = {}
    locked_ids: set[str] = set()
    for f in req.options.fixed:
        vehicle = next(v for v in req.vehicles if v.id == f.vehicle_id)
        locked[f.vehicle_id] = _play_locked(vehicle, f.task_ids, tasks, locs, m, clock)
        locked_ids.update(f.task_ids)

    # A shipment whose pickup is locked but whose delivery is not becomes a plain delivery job
    # pinned (through a vehicle-only skill) to the vehicle already carrying it.
    pinned_vehicle: dict[str, str] = {}
    for vid, prefix in locked.items():
        for step in prefix.steps:
            task: Task = step["task"]
            if task.kind == "pickup" and task.partner_id not in locked_ids:
                pinned_vehicle[task.partner_id] = vid

    skill_names = sorted(
        {sk for v in req.vehicles for sk in v.skills}
        | {sk for t in tasks.values() for sk in t.skills}
        | {VEHICLE_SKILL_PREFIX + v.id for v in req.vehicles}
    )
    skill_id = {name: i + 1 for i, name in enumerate(skill_names)}

    vroom_ids: dict[int, Task] = {}
    next_id = iter(range(1, 10_000_000))
    vehicle_ids: dict[int, s.Vehicle] = {}
    break_ids: dict[int, s.Break] = {}

    open_tasks = [t for t in tasks.values() if t.id not in locked_ids]
    vroom_vehicles = []
    for i, v in enumerate(req.vehicles, start=1):
        start_index, start_time = locs.add(v.start), clock.sec(v.shift_start)
        if v.id in locked:
            start_index, start_time = locked[v.id].end_index, locked[v.id].end_time
        end_time = clock.sec(v.shift_end)
        vehicle_ids[i] = v
        if start_time >= end_time:
            continue  # the locked stops already use up the shift
        entry: dict = {
            "id": i,
            "profile": "car",
            "start_index": start_index,
            "capacity": _pad(v.capacity, UNLIMITED) if v.capacity is not None else [UNLIMITED] * 3,
            "skills": [skill_id[sk] for sk in v.skills] + [skill_id[VEHICLE_SKILL_PREFIX + v.id]],
            "time_window": [start_time, end_time],
            "costs": _costs(req.options.objective),
        }
        if v.end is not None:
            entry["end_index"] = locs.add(v.end)
        if v.speed_factor != 1.0:
            entry["speed_factor"] = v.speed_factor
        if v.max_travel_seconds is not None:
            entry["max_travel_time"] = v.max_travel_seconds
        breaks = []
        for b in v.breaks:
            windows = [w for w in _windows(b.time_windows, clock) if w[1] >= start_time]
            if not windows:
                continue
            bid = next(next_id)
            break_ids[bid] = b
            breaks.append({"id": bid, "time_windows": windows, "service": b.service_seconds})
        if breaks:
            entry["breaks"] = breaks
        vroom_vehicles.append(entry)

    if req.options.objective == s.Objective.balanced and vroom_vehicles:
        per_vehicle = math.ceil(len(open_tasks) / len(vroom_vehicles)) + 1
        for entry in vroom_vehicles:
            entry["max_tasks"] = per_vehicle

    vroom_jobs, vroom_shipments = [], []
    task_vroom_id: dict[str, int] = {}
    for t in open_tasks:
        task_vroom_id[t.id] = next(next_id)
        vroom_ids[task_vroom_id[t.id]] = t

    def task_skills(t: Task) -> list[int]:
        ids = [skill_id[sk] for sk in t.skills]
        if t.id in pinned_vehicle:
            ids.append(skill_id[VEHICLE_SKILL_PREFIX + pinned_vehicle[t.id]])
        return ids

    def step_json(t: Task) -> dict:
        out: dict = {
            "id": task_vroom_id[t.id],
            "location_index": locs.add(t.location),
            "service": t.service,
        }
        if t.windows:
            out["time_windows"] = _windows(t.windows, clock)
        return out

    for t in open_tasks:
        if t.kind == "job":
            job = step_json(t) | {"delivery": t.delivery, "pickup": t.pickup, "priority": t.priority}
            if t.skills or t.id in pinned_vehicle:
                job["skills"] = task_skills(t)
            vroom_jobs.append(job)
        elif t.kind == "delivery" and t.id in pinned_vehicle:
            job = step_json(t) | {"delivery": t.amount, "priority": t.priority}
            job["skills"] = task_skills(t)
            vroom_jobs.append(job)
        elif t.kind == "pickup":
            partner = tasks[t.partner_id]
            if partner.id in locked_ids:
                continue  # delivery locked without its pickup: nothing left to plan
            shipment = {
                "pickup": step_json(t),
                "delivery": step_json(partner),
                "amount": t.amount,
                "priority": t.priority,
            }
            if t.skills:
                shipment["skills"] = task_skills(t)
            vroom_shipments.append(shipment)

    solution: dict = {"routes": [], "unassigned": [], "summary": {"cost": 0}}
    if vroom_vehicles and (vroom_jobs or vroom_shipments):
        problem = {
            "vehicles": vroom_vehicles,
            "jobs": vroom_jobs,
            "shipments": vroom_shipments,
            "matrices": {"car": {"durations": m.durations, "distances": m.distances}},
        }
        solution = _run_vroom(problem, req.options)
    else:
        # Nothing to solve with (no vehicle has shift time left): every open task is unassigned.
        solution["unassigned"] = [
            {"id": vid}
            for vid, t in vroom_ids.items()
            if not (t.kind == "pickup" and t.partner_id in locked_ids)
        ]

    routes = _build_routes(req, solution, locked, vehicle_ids, vroom_ids, break_ids, tasks, locs, m, clock, source)
    unassigned = _unassigned(req, solution, vroom_ids, tasks, locs, m, clock, locked)

    assigned = sum(1 for r in routes for st in r.steps if st.type in ("job", "pickup", "delivery"))
    summary = s.Summary(
        routes=len(routes),
        assigned=assigned,
        unassigned=len(unassigned),
        distance_m=sum(r.distance_m for r in routes),
        duration_s=sum(r.duration_s for r in routes),
        service_s=sum(r.service_s for r in routes),
        waiting_s=sum(r.waiting_s for r in routes),
        cost=int(solution.get("summary", {}).get("cost", 0)),
        matrix_source=m.source,
        solve_ms=round((time.perf_counter() - started) * 1000),
    )
    return s.OptimizeResponse(routes=routes, unassigned=unassigned, summary=summary)


def _run_vroom(problem: dict, options: s.Options) -> dict:
    problem_input = vroom.Input()
    try:
        # pyvroom's JSON loader takes exactly the vroom-express / ORS problem format.
        problem_input._from_json(json.dumps(problem), False)
        timeout = timedelta(seconds=options.timeout_seconds) if options.timeout_seconds else None
        threads = int(os.environ.get("VROOM_THREADS", min(4, os.cpu_count() or 1)))
        result = problem_input.solve(
            exploration_level=options.exploration_level, nb_threads=threads, timeout=timeout
        )
    except Exception as e:  # noqa: BLE001 - pyvroom raises its own exception types
        raise SolveError(f"VROOM could not solve the problem: {e}") from e
    return result.to_dict()


# -------------------------------------------------------------------------------------------------
# Mapping the solution back
# -------------------------------------------------------------------------------------------------


def _build_routes(req, solution, locked, vehicle_ids, vroom_ids, break_ids, tasks, locs, m, clock, source):
    solved = {r["vehicle"]: r for r in solution.get("routes", [])}
    routes: list[s.Route] = []
    for vid_int, vehicle in vehicle_ids.items():
        prefix = locked.get(vehicle.id)
        vroom_route = solved.get(vid_int)
        if prefix is None and vroom_route is None:
            continue

        raw: list[dict] = [
            {
                "type": "start",
                "index": locs.add(vehicle.start),
                "arrival": clock.sec(vehicle.shift_start),
                "waiting": 0,
                "service": 0,
            }
        ]
        if prefix:
            raw += prefix.steps
        if vroom_route:
            prev_index = raw[-1]["index"]
            for st in vroom_route["steps"]:
                if st["type"] == "start":
                    continue
                entry = {
                    "type": st["type"],
                    "arrival": st["arrival"],
                    "waiting": st.get("waiting_time", 0),
                    "service": st.get("service", 0) + st.get("setup", 0),
                }
                if st["type"] == "break":
                    entry["break"] = break_ids[st["id"]]
                    entry["index"] = prev_index
                elif st["type"] == "end":
                    entry["index"] = st.get("location_index", prev_index)
                else:
                    entry["task"] = vroom_ids[st["id"]]
                    entry["index"] = st["location_index"]
                    # A pinned delivery was sent to VROOM as a plain job.
                    entry["type"] = entry["task"].kind
                prev_index = entry["index"]
                raw.append(entry)
        else:
            last = raw[-1]
            end_index = locs.add(vehicle.end) if vehicle.end is not None else last["index"]
            departure = last["arrival"] + last["waiting"] + last["service"]
            raw.append(
                {
                    "type": "end",
                    "index": end_index,
                    "arrival": departure + _travel(m, last["index"], end_index, vehicle.speed_factor),
                    "waiting": 0,
                    "service": 0,
                }
            )

        steps: list[s.Step] = []
        load = _start_load(raw, tasks)
        prev = None
        for entry in raw:
            task: Task | None = entry.get("task")
            if task is not None:
                if task.kind == "job":
                    load = [a - d + p for a, d, p in zip(load, task.delivery, task.pickup)]
                elif task.kind == "pickup":
                    load = [a + b for a, b in zip(load, task.amount)]
                else:
                    load = [a - b for a, b in zip(load, task.amount)]
            leg_d = leg_t = 0
            if prev is not None and entry["type"] != "break":
                leg_d = m.distances[prev["index"]][entry["index"]]
                leg_t = _travel(m, prev["index"], entry["index"], vehicle.speed_factor)
            step_id = task.id if task else (entry["break"].id if "break" in entry else None)
            steps.append(
                s.Step(
                    type=entry["type"],
                    id=step_id,
                    location=locs.coords[entry["index"]],
                    arrival=clock.dt(entry["arrival"]),
                    departure=clock.dt(entry["arrival"] + entry["waiting"] + entry["service"]),
                    service_seconds=entry["service"],
                    waiting_seconds=entry["waiting"],
                    leg_distance_m=leg_d,
                    leg_duration_s=leg_t,
                    load=list(load),
                    locked=entry.get("locked", False),
                    late_seconds=entry.get("late", 0),
                )
            )
            if entry["type"] != "break":
                prev = entry

        geometry = None
        if req.options.geometry:
            path = [st.location for st in steps if st.type != "break"]
            geometry = source.geometry(path)
        routes.append(
            s.Route(
                vehicle_id=vehicle.id,
                steps=steps,
                distance_m=sum(st.leg_distance_m for st in steps),
                duration_s=int((steps[-1].arrival - steps[0].departure).total_seconds()),
                service_s=sum(st.service_seconds for st in steps),
                waiting_s=sum(st.waiting_seconds for st in steps),
                start_time=steps[0].departure,
                end_time=steps[-1].arrival,
                geometry=geometry,
            )
        )
    return routes


def _start_load(raw: list[dict], tasks: dict[str, Task]) -> list[int]:
    """What the vehicle carries out of the depot: its deliveries, plus shipments already on board."""
    load = [0, 0, 0]
    on_route = {e["task"].id for e in raw if "task" in e}
    for e in raw:
        task: Task | None = e.get("task")
        if task is None:
            continue
        if task.kind == "job":
            load = [a + b for a, b in zip(load, task.delivery)]
        elif task.kind == "delivery" and task.partner_id not in on_route:
            load = [a + b for a, b in zip(load, task.amount)]
    return load


def _unassigned(req, solution, vroom_ids, tasks, locs, m, clock, locked) -> list[s.Unassigned]:
    out: list[s.Unassigned] = []
    seen_shipments: set[str] = set()
    for u in solution.get("unassigned", []):
        task = vroom_ids[u["id"]]
        locked_ids = {st["task"].id for p in locked.values() for st in p.steps}
        if task.shipment_id and task.partner_id in locked_ids:
            kind = task.kind  # the other end is already on a vehicle
        elif task.shipment_id:
            if task.shipment_id in seen_shipments:
                continue
            seen_shipments.add(task.shipment_id)
            kind = "shipment"
        else:
            kind = "job"
        reason, detail = _diagnose(req, task, tasks, locs, m, clock, locked)
        out.append(
            s.Unassigned(
                id=task.shipment_id if kind == "shipment" else task.id,
                type=kind,
                reason=reason,
                detail=detail,
            )
        )
    return out


def _diagnose(req, task: Task, tasks, locs, m, clock, locked) -> tuple[str, str]:
    """VROOM reports what it could not place, not why. Check the usual reasons in order."""
    needed = set(task.skills)
    by_skills = [v for v in req.vehicles if needed <= set(v.skills)]
    if not by_skills:
        missing = sorted(needed - set().union(*(set(v.skills) for v in req.vehicles)))
        if missing:
            return "skills", f"No vehicle has the skill(s): {', '.join(missing)}."
        return "skills", f"No single vehicle has all of: {', '.join(sorted(needed))}."

    if task.kind == "job":
        demand = [max(d, p) for d, p in zip(task.delivery, task.pickup)]
    else:
        demand = task.amount
    by_capacity = [
        v
        for v in by_skills
        if v.capacity is None or all(d <= c for d, c in zip(demand, _pad(v.capacity, UNLIMITED)))
    ]
    if not by_capacity:
        return "capacity", f"The load {demand} is larger than any eligible vehicle's capacity."

    ends = [task] if task.kind != "pickup" else [task, tasks[task.partner_id]]
    for v in by_capacity:
        if all(_reachable(v, t, locs, m, clock, locked) for t in ends):
            return "no_room", (
                "The solver could not fit this stop: every eligible vehicle is full or out of shift time."
            )
    return "time_window", "No eligible vehicle can reach this stop inside its time window and shift."


def _reachable(v: s.Vehicle, task: Task, locs, m, clock, locked) -> bool:
    start_index, start_time = locs.add(v.start), clock.sec(v.shift_start)
    if v.id in locked:
        start_index, start_time = locked[v.id].end_index, locked[v.id].end_time
    idx = locs.add(task.location)
    earliest = start_time + _travel(m, start_index, idx, v.speed_factor)
    end_index = locs.add(v.end) if v.end is not None else idx
    shift_end = clock.sec(v.shift_end)
    windows = task.windows or [s.TimeWindow(start=clock.dt(0), end=clock.dt(shift_end))]
    for w in windows:
        arrive = max(earliest, clock.sec(w.start))
        if arrive <= clock.sec(w.end) and arrive + task.service + _travel(m, idx, end_index, v.speed_factor) <= shift_end:
            return True
    return False


# -------------------------------------------------------------------------------------------------
# /v1/route
# -------------------------------------------------------------------------------------------------


def route(req: s.RouteRequest, source: MatrixSource) -> s.RouteResponse:
    coords = [w.location for w in req.waypoints]
    m = source.table(coords)
    legs, t = [], _aware(req.departure) if req.departure else None
    for i in range(1, len(coords)):
        d, dur = m.distances[i - 1][i], m.durations[i - 1][i]
        if t is not None:
            t = t + timedelta(seconds=dur)
        legs.append(
            s.Leg(
                from_id=req.waypoints[i - 1].id,
                to_id=req.waypoints[i].id,
                distance_m=d,
                duration_s=dur,
                arrival=t,
            )
        )
    return s.RouteResponse(
        legs=legs,
        distance_m=sum(leg.distance_m for leg in legs),
        duration_s=sum(leg.duration_s for leg in legs),
        geometry=source.geometry(coords) if req.geometry else None,
        matrix_source=m.source,
    )
