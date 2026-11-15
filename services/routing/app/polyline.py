"""Google encoded polyline (precision 5), the format OSRM returns and map libraries decode."""

from __future__ import annotations

from typing import Sequence


def _encode_value(value: int) -> str:
    value = ~(value << 1) if value < 0 else value << 1
    out = []
    while value >= 0x20:
        out.append(chr((0x20 | (value & 0x1F)) + 63))
        value >>= 5
    out.append(chr(value + 63))
    return "".join(out)


def encode(locations: Sequence[Sequence[float]], precision: int = 5) -> str:
    """Encode [lon, lat] pairs. The polyline format itself stores lat before lon."""
    factor = 10**precision
    prev_lat = prev_lon = 0
    parts = []
    for lon, lat in locations:
        lat_i, lon_i = round(lat * factor), round(lon * factor)
        parts.append(_encode_value(lat_i - prev_lat))
        parts.append(_encode_value(lon_i - prev_lon))
        prev_lat, prev_lon = lat_i, lon_i
    return "".join(parts)


def decode(encoded: str, precision: int = 5) -> list[list[float]]:
    """Decode to [lon, lat] pairs."""
    factor = 10**precision
    coords, index, lat, lon = [], 0, 0, 0
    while index < len(encoded):
        deltas = []
        for _ in range(2):
            shift = result = 0
            while True:
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            deltas.append(~(result >> 1) if result & 1 else result >> 1)
        lat += deltas[0]
        lon += deltas[1]
        coords.append([lon / factor, lat / factor])
    return coords
