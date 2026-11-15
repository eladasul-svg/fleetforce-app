import os
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import main  # noqa: E402
from app.matrix import HaversineMatrix  # noqa: E402

TEST_KEY = "test-key-123"
TEST_ORG = "00D000000000001"


@pytest.fixture
def source() -> HaversineMatrix:
    return HaversineMatrix()


@pytest.fixture
def client(monkeypatch) -> TestClient:
    monkeypatch.setenv("FLEETFORCE_API_KEYS", f'{{"{TEST_KEY}": "{TEST_ORG}"}}')
    monkeypatch.delenv("FLEETFORCE_AUTH_DISABLED", raising=False)
    monkeypatch.delenv("OSRM_URL", raising=False)
    monkeypatch.setenv("MATRIX_SOURCE", "haversine")
    main.api_keys.cache_clear()
    main.matrix_source.cache_clear()
    yield TestClient(main.app)
    main.api_keys.cache_clear()
    main.matrix_source.cache_clear()


@pytest.fixture
def headers() -> dict:
    return {"X-FleetForce-Key": TEST_KEY}


os.environ.setdefault("VROOM_THREADS", "2")
