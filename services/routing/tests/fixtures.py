"""Demo-shaped problems around the Beer Sheva depot.

Coordinates only (no street addresses), generated from a fixed seed inside the city's bounding box,
so every run sees the same problem.
"""

from __future__ import annotations

import random
from datetime import datetime, timedelta, timezone

DEPOT = [34.7913, 31.2518]  # [lon, lat], Beer Sheva
BBOX = {"lon": (34.745, 34.835), "lat": (31.215, 31.290)}

# 2026-11-04 in Israel (UTC+2): local 07:00 is 05:00Z.
DAY = datetime(2026, 11, 4, tzinfo=timezone.utc)


def local(hour: float) -> datetime:
    """Israel local time on the demo day, as an aware UTC datetime."""
    return DAY + timedelta(hours=hour - 2)


def iso(t: datetime) -> str:
    return t.isoformat().replace("+00:00", "Z")


def point(rng: random.Random) -> list[float]:
    return [round(rng.uniform(*BBOX["lon"]), 6), round(rng.uniform(*BBOX["lat"]), 6)]


def morning_vans(n_vans: int = 6, n_drops: int = 60, seed: int = 4471) -> dict:
    """(a) 6 vans, 60 drops with time windows and capacity. Vans 5 and 6 are EVs with a charge stop."""
    rng = random.Random(seed)
    vehicles = []
    for i in range(1, n_vans + 1):
        ev = i > n_vans - 2
        v = {
            "id": f"van-{i}",
            "start": DEPOT,
            "end": DEPOT,
            "shift_start": iso(local(7)),
            "shift_end": iso(local(17)),
            "capacity": [800, 60, 6],  # kg, volume (0.1 m3), pallets
            "skills": ["lift_gate"] if i % 2 == 0 else [],
        }
        if ev:
            v["breaks"] = [
                {
                    "id": f"charge-{i}",
                    "description": "Charge",
                    "service_seconds": 30 * 60,
                    "time_windows": [{"start": iso(local(11.5)), "end": iso(local(13.5))}],
                }
            ]
        vehicles.append(v)

    slots = [(8, 11), (10, 13), (13, 16), None]
    jobs = []
    for k in range(1, n_drops + 1):
        slot = slots[k % len(slots)]
        job = {
            "id": f"drop-{k:02d}",
            "location": point(rng),
            "service_seconds": rng.choice([300, 360, 420, 480]),
            "delivery": [rng.randint(10, 40), rng.randint(1, 4), 0],
            "priority": rng.choice([0, 0, 10, 50]),
        }
        if slot:
            job["time_windows"] = [{"start": iso(local(slot[0])), "end": iso(local(slot[1]))}]
        if k % 15 == 0:
            job["skills"] = ["lift_gate"]
        jobs.append(job)
    return {"vehicles": vehicles, "jobs": jobs, "options": {"objective": "min_duration"}}


LOTS = {
    "central_station": [34.7983, 31.2430],
    "university": [34.8017, 31.2622],
    "hospital": [34.8010, 31.2580],
}


def overnight_relocation(n_cars: int = 12, n_drivers: int = 3, seed: int = 55) -> dict:
    """(b) 12 cars to rebalance overnight: pickup -> drop shipments, one car per driver at a time."""
    rng = random.Random(seed)
    targets = list(LOTS.values())
    vehicles = [
        {
            "id": f"driver-{i}",
            "start": DEPOT,
            "end": DEPOT,
            "shift_start": iso(local(22)),
            "shift_end": iso(local(30)),  # 06:00 next day
            "capacity": [0, 0, 1],  # slot 3 = seats/cars: the driver drives one car at a time
        }
        for i in range(1, n_drivers + 1)
    ]
    shipments = []
    for k in range(1, n_cars + 1):
        shipments.append(
            {
                "id": f"reloc-{k:02d}",
                "pickup": {"id": f"reloc-{k:02d}-p", "location": point(rng), "service_seconds": 300},
                "delivery": {
                    "id": f"reloc-{k:02d}-d",
                    "location": targets[k % len(targets)],
                    "service_seconds": 180,
                },
                "amount": [0, 0, 1],
            }
        )
    return {"vehicles": vehicles, "shipments": shipments, "options": {"objective": "min_duration"}}


def single_van(n_drops: int = 12, seed: int = 1140) -> dict:
    rng = random.Random(seed)
    return {
        "vehicles": [
            {
                "id": "dana",
                "start": DEPOT,
                "end": DEPOT,
                "shift_start": iso(local(8)),
                "shift_end": iso(local(18)),
                "capacity": [800, 60, 6],
            }
        ],
        "jobs": [
            {
                "id": f"stop-{k:02d}",
                "location": point(rng),
                "service_seconds": 600,
                "delivery": [20, 2, 0],
                "time_windows": [{"start": iso(local(8)), "end": iso(local(17))}],
            }
            for k in range(1, n_drops + 1)
        ],
        "options": {"objective": "min_duration"},
    }
