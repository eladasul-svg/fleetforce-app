"""The four work-order scenarios (R1 a-d), solved with HaversineMatrix."""

from __future__ import annotations

from datetime import timedelta

from app import schemas as s
from app.solver import optimize

from . import fixtures as fx


def _solve(problem: dict, source) -> s.OptimizeResponse:
    return optimize(s.OptimizeRequest.model_validate(problem), source)


def _task_steps(route: s.Route) -> list[s.Step]:
    return [st for st in route.steps if st.type in ("job", "pickup", "delivery")]


def _windows_by_id(problem: dict) -> dict[str, list[s.TimeWindow]]:
    req = s.OptimizeRequest.model_validate(problem)
    out = {j.id: j.time_windows for j in req.jobs}
    for sh in req.shipments:
        out[sh.pickup.id] = sh.pickup.time_windows
        out[sh.delivery.id] = sh.delivery.time_windows
    return out


def _assert_windows_respected(problem: dict, result: s.OptimizeResponse) -> None:
    windows = _windows_by_id(problem)
    for route in result.routes:
        for st in _task_steps(route):
            ws = windows[st.id]
            if not ws:
                continue
            start_service = st.arrival + timedelta(seconds=st.waiting_seconds)
            assert any(w.start <= start_service <= w.end for w in ws), (
                f"{st.id} served at {start_service} outside {ws}"
            )


# -------------------------------------------------------------------------------------------------
# (a) Morning: 6 vans, 60 drops
# -------------------------------------------------------------------------------------------------


def test_morning_all_drops_assigned_within_windows_and_capacity(source):
    problem = fx.morning_vans()
    result = _solve(problem, source)

    assert result.summary.unassigned == 0, result.unassigned
    assert result.summary.assigned == 60
    served = sorted(st.id for r in result.routes for st in _task_steps(r))
    assert served == sorted(j["id"] for j in problem["jobs"])
    _assert_windows_respected(problem, result)

    capacity = [800, 60, 6]
    for route in result.routes:
        assert route.steps[0].type == "start" and route.steps[-1].type == "end"
        assert route.steps[0].location == fx.DEPOT and route.steps[-1].location == fx.DEPOT
        for st in route.steps:
            assert all(0 <= load <= cap for load, cap in zip(st.load, capacity)), st
        assert route.steps[-1].load == [0, 0, 0]
        assert route.start_time >= fx.local(7) and route.end_time <= fx.local(17)
        # Distance and duration add up.
        assert route.distance_m == sum(st.leg_distance_m for st in route.steps)
        assert route.duration_s > 0


def test_morning_ev_routes_include_the_charge_stop(source):
    result = _solve(fx.morning_vans(), source)
    for route in result.routes:
        breaks = [st for st in route.steps if st.type == "break"]
        if route.vehicle_id in ("van-5", "van-6"):
            assert [b.id for b in breaks] == [f"charge-{route.vehicle_id[-1]}"]
            charge = breaks[0]
            assert charge.service_seconds == 1800
            assert fx.local(11.5) <= charge.arrival + timedelta(seconds=charge.waiting_seconds) <= fx.local(13.5)
        else:
            assert breaks == []


def test_lift_gate_jobs_only_go_to_lift_gate_vans(source):
    result = _solve(fx.morning_vans(), source)
    lift_gate_vans = {"van-2", "van-4", "van-6"}
    for route in result.routes:
        for st in _task_steps(route):
            if int(st.id.split("-")[1]) % 15 == 0:
                assert route.vehicle_id in lift_gate_vans


def test_min_vehicles_uses_fewer_vans(source):
    problem = fx.morning_vans()
    problem["jobs"] = problem["jobs"][:12]
    for j in problem["jobs"]:
        j.pop("time_windows", None)
    problem["options"]["objective"] = "min_vehicles"
    result = _solve(problem, source)
    assert result.summary.unassigned == 0
    assert len(result.routes) <= 2


def test_balanced_spreads_the_work(source):
    problem = fx.morning_vans()
    problem["options"]["objective"] = "balanced"
    result = _solve(problem, source)
    counts = [len(_task_steps(r)) for r in result.routes]
    assert result.summary.unassigned == 0
    assert len(result.routes) == 6
    assert max(counts) <= 60 / 6 + 1


def test_geometry_is_returned_when_asked(source):
    from app.polyline import decode

    problem = fx.single_van(4)
    problem["options"]["geometry"] = True
    result = _solve(problem, source)
    path = decode(result.routes[0].geometry)
    assert len(path) == 6  # start, 4 stops, end
    assert abs(path[0][0] - fx.DEPOT[0]) < 1e-5 and abs(path[0][1] - fx.DEPOT[1]) < 1e-5


# -------------------------------------------------------------------------------------------------
# (b) Overnight relocation: 12 pickup -> drop shipments
# -------------------------------------------------------------------------------------------------


def test_relocation_pairs_each_pickup_with_its_drop(source):
    problem = fx.overnight_relocation()
    result = _solve(problem, source)

    assert result.summary.unassigned == 0, result.unassigned
    assert result.summary.assigned == 24
    seen = set()
    for route in result.routes:
        order = [st.id for st in _task_steps(route)]
        for st in route.steps:
            assert 0 <= st.load[2] <= 1, "a driver moves one car at a time"
        for car in {i.rsplit("-", 1)[0] for i in order}:
            assert order.index(f"{car}-p") < order.index(f"{car}-d"), car
            seen.add(car)
        assert route.start_time >= fx.local(22) and route.end_time <= fx.local(30)
    assert len(seen) == 12


# -------------------------------------------------------------------------------------------------
# (c) 11:40: re-optimize remaining stops after a 40-minute delay, one stop locked
# -------------------------------------------------------------------------------------------------


def test_reoptimize_after_delay_with_locked_next_stop(source):
    morning = fx.single_van(12)
    planned = _solve(morning, source).routes[0]
    planned_order = [st.id for st in _task_steps(planned)]

    # By 11:40 Dana has finished the first 4 stops and is at the 4th; loading is 40 minutes late.
    done = planned_order[:4]
    here = next(st.location for st in planned.steps if st.id == done[-1])
    remaining = [j for j in morning["jobs"] if j["id"] not in done]
    locked_next = planned_order[4]

    replan = fx.single_van(12)
    replan["jobs"] = remaining
    replan["vehicles"][0]["start"] = here
    replan["vehicles"][0]["shift_start"] = fx.iso(fx.local(11 + 40 / 60) + timedelta(minutes=40))
    replan["options"]["fixed"] = [{"vehicle_id": "dana", "task_ids": [locked_next]}]
    result = _solve(replan, source)

    route = result.routes[0]
    tasks = _task_steps(route)
    assert tasks[0].id == locked_next and tasks[0].locked
    assert all(not st.locked for st in tasks[1:])
    assert route.steps[0].location == here
    assert tasks[0].arrival >= fx.local(12 + 20 / 60)
    assigned = {st.id for st in tasks} | {u.id for u in result.unassigned}
    assert assigned == {j["id"] for j in remaining}
    # Locked step's departure is where the solver's part of the route starts.
    assert tasks[1].arrival >= tasks[0].departure
    _assert_windows_respected(replan, result)


def test_late_locked_stop_reports_lateness(source):
    problem = fx.single_van(3)
    problem["jobs"][0]["time_windows"] = [{"start": fx.iso(fx.local(8)), "end": fx.iso(fx.local(8.1))}]
    problem["vehicles"][0]["shift_start"] = fx.iso(fx.local(9))
    problem["options"]["fixed"] = [{"vehicle_id": "dana", "task_ids": [problem["jobs"][0]["id"]]}]
    result = _solve(problem, source)
    first = _task_steps(result.routes[0])[0]
    assert first.locked and first.late_seconds > 3000


def test_locked_pickup_keeps_its_delivery_on_the_same_vehicle(source):
    problem = fx.overnight_relocation(n_cars=4, n_drivers=2)
    problem["options"]["fixed"] = [{"vehicle_id": "driver-2", "task_ids": ["reloc-01-p"]}]
    result = _solve(problem, source)
    route = next(r for r in result.routes if r.vehicle_id == "driver-2")
    order = [st.id for st in _task_steps(route)]
    assert order[0] == "reloc-01-p"
    assert "reloc-01-d" in order
    assert result.summary.unassigned == 0


def test_locked_stops_that_fill_the_shift_leave_the_rest_unassigned(source):
    problem = fx.single_van(3)
    problem["vehicles"][0]["shift_end"] = fx.iso(fx.local(8.2))
    problem["options"]["fixed"] = [{"vehicle_id": "dana", "task_ids": ["stop-01", "stop-02"]}]
    result = _solve(problem, source)
    route = result.routes[0]
    assert [st.id for st in _task_steps(route)] == ["stop-01", "stop-02"]
    assert route.steps[-1].type == "end"
    assert [u.id for u in result.unassigned] == ["stop-03"]


# -------------------------------------------------------------------------------------------------
# (d) Unassigned jobs come back with a reason
# -------------------------------------------------------------------------------------------------


def test_missing_skill_leaves_job_unassigned_with_reason(source):
    problem = fx.morning_vans()
    problem["jobs"][0]["skills"] = ["refrigerated"]
    result = _solve(problem, source)
    assert result.summary.unassigned == 1
    u = result.unassigned[0]
    assert (u.id, u.type, u.reason) == (problem["jobs"][0]["id"], "job", "skills")
    assert "refrigerated" in u.detail


def test_skill_split_across_vehicles_is_reported(source):
    problem = fx.single_van(2)
    problem["vehicles"].append(dict(problem["vehicles"][0], id="yossi", skills=["refrigerated"]))
    problem["vehicles"][0]["skills"] = ["lift_gate"]
    problem["jobs"][0]["skills"] = ["lift_gate", "refrigerated"]
    result = _solve(problem, source)
    assert result.unassigned[0].reason == "skills"
    assert "No single vehicle" in result.unassigned[0].detail


def test_oversized_load_is_a_capacity_reason(source):
    problem = fx.single_van(3)
    problem["jobs"][1]["delivery"] = [900, 1, 0]
    result = _solve(problem, source)
    assert [(u.id, u.reason) for u in result.unassigned] == [("stop-02", "capacity")]


def test_window_outside_shift_is_a_time_window_reason(source):
    problem = fx.single_van(3)
    problem["jobs"][2]["time_windows"] = [{"start": fx.iso(fx.local(19)), "end": fx.iso(fx.local(20))}]
    result = _solve(problem, source)
    assert [(u.id, u.reason) for u in result.unassigned] == [("stop-03", "time_window")]


def test_full_vans_report_no_room(source):
    problem = fx.single_van(6)
    problem["vehicles"][0]["capacity"] = [100, 60, 6]  # 5 drops of 20 kg fit, the 6th does not
    result = _solve(problem, source)
    assert result.summary.assigned == 5
    assert [u.reason for u in result.unassigned] == ["no_room"]


def test_unassigned_shipment_is_reported_once(source):
    problem = fx.overnight_relocation(n_cars=2, n_drivers=1)
    problem["shipments"][0]["skills"] = ["tow_hitch"]
    result = _solve(problem, source)
    assert [(u.id, u.type, u.reason) for u in result.unassigned] == [("reloc-01", "shipment", "skills")]


def test_no_tasks_returns_empty_plan(source):
    problem = fx.single_van(0)
    result = _solve(problem, source)
    assert result.routes == [] and result.unassigned == []
    assert result.summary.matrix_source == "haversine"
