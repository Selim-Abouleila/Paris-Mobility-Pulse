"""
Unit tests for the Dataflow pipeline's core transform functions.

These test the pure business logic (no GCP dependencies, no Beam runner).
"""

import json

from pipelines.dataflow.pmp_streaming.main import (
    _epoch_to_rfc3339,
    _extract_bike_types,
    _to_int,
    velib_snapshot_to_station_rows,
)

# ---------------------------------------------------------------------------
# Fixtures: sample events matching the real Vélib GBFS envelope
# ---------------------------------------------------------------------------

VALID_EVENT = {
    "ingest_ts": "2026-01-24T16:00:00Z",
    "event_ts": "2026-01-24T16:00:00Z",
    "source": "velib",
    "event_type": "station_status_snapshot",
    "key": "velib:station_status_snapshot",
    "payload": {
        "data": {
            "stations": [
                {
                    "station_id": 123,
                    "stationCode": "16107",
                    "is_installed": 1,
                    "is_renting": 1,
                    "is_returning": 1,
                    "last_reported": 1737734400,
                    "num_bikes_available": 7,
                    "num_docks_available": 13,
                    "num_bikes_available_types": [
                        {"mechanical": 3},
                        {"ebike": 4},
                    ],
                },
                {
                    "station_id": 456,
                    "stationCode": "10042",
                    "is_installed": 0,
                    "is_renting": 0,
                    "is_returning": 0,
                    "last_reported": 1737734400,
                    "num_bikes_available": 0,
                    "num_docks_available": 20,
                    "num_bikes_available_types": [
                        {"mechanical": 0},
                        {"ebike": 0},
                    ],
                },
            ]
        }
    },
}


# ---------------------------------------------------------------------------
# velib_snapshot_to_station_rows
# ---------------------------------------------------------------------------


class TestVelibSnapshotToStationRows:
    """Core transform: envelope → one curated row per station."""

    def test_yields_one_row_per_station(self):
        rows = list(velib_snapshot_to_station_rows(VALID_EVENT))
        assert len(rows) == 2

    def test_row_fields_correct(self):
        rows = list(velib_snapshot_to_station_rows(VALID_EVENT))
        row = rows[0]

        assert row["station_id"] == "123"
        assert row["station_code"] == "16107"
        assert row["ingest_ts"] == "2026-01-24T16:00:00Z"
        assert row["event_ts"] == "2026-01-24T16:00:00Z"
        assert row["is_installed"] == 1
        assert row["is_renting"] == 1
        assert row["is_returning"] == 1
        assert row["num_bikes_available"] == 7
        assert row["num_docks_available"] == 13
        assert row["mechanical_available"] == 3
        assert row["ebike_available"] == 4

    def test_raw_station_json_preserved(self):
        rows = list(velib_snapshot_to_station_rows(VALID_EVENT))
        raw = json.loads(rows[0]["raw_station_json"])
        assert raw["station_id"] == 123

    def test_empty_stations_yields_nothing(self):
        evt = {**VALID_EVENT, "payload": {"data": {"stations": []}}}
        rows = list(velib_snapshot_to_station_rows(evt))
        assert rows == []

    def test_stations_not_a_list_yields_nothing(self):
        evt = {**VALID_EVENT, "payload": {"data": {"stations": "NOT_A_LIST"}}}
        rows = list(velib_snapshot_to_station_rows(evt))
        assert rows == []

    def test_missing_payload_yields_nothing(self):
        evt = {"ingest_ts": "2026-01-01T00:00:00Z"}
        rows = list(velib_snapshot_to_station_rows(evt))
        assert rows == []

    def test_station_without_id_is_skipped(self):
        evt = {
            **VALID_EVENT,
            "payload": {"data": {"stations": [{"num_bikes_available": 5}]}},
        }
        rows = list(velib_snapshot_to_station_rows(evt))
        assert rows == []


# ---------------------------------------------------------------------------
# _extract_bike_types
# ---------------------------------------------------------------------------


class TestExtractBikeTypes:
    """Parses Vélib and alternate GBFS bike type formats."""

    def test_velib_format(self):
        st = {"num_bikes_available_types": [{"mechanical": 3}, {"ebike": 4}]}
        mech, ebike = _extract_bike_types(st)
        assert mech == 3
        assert ebike == 4

    def test_alternate_gbfs_format(self):
        st = {
            "num_bikes_available_types": [
                {"bike_type": "mechanical", "count": 10},
                {"bike_type": "ebike", "count": 5},
            ]
        }
        mech, ebike = _extract_bike_types(st)
        assert mech == 10
        assert ebike == 5

    def test_missing_types_returns_none(self):
        mech, ebike = _extract_bike_types({})
        assert mech is None
        assert ebike is None

    def test_empty_list_returns_none(self):
        mech, ebike = _extract_bike_types({"num_bikes_available_types": []})
        assert mech is None
        assert ebike is None


# ---------------------------------------------------------------------------
# _to_int  /  _epoch_to_rfc3339
# ---------------------------------------------------------------------------


class TestHelpers:
    """Low-level type conversion helpers."""

    def test_to_int_normal(self):
        assert _to_int(5) == 5

    def test_to_int_string(self):
        assert _to_int("42") == 42

    def test_to_int_none(self):
        assert _to_int(None) is None

    def test_to_int_garbage(self):
        assert _to_int("not_a_number") is None

    def test_epoch_to_rfc3339(self):
        # 1737734400 = 2025-01-24T16:00:00Z
        result = _epoch_to_rfc3339(1737734400)
        assert result == "2025-01-24T16:00:00Z"

    def test_epoch_to_rfc3339_none(self):
        assert _epoch_to_rfc3339(None) is None

    def test_epoch_to_rfc3339_garbage(self):
        assert _epoch_to_rfc3339("not_an_epoch") is None
