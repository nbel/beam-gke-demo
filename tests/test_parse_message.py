import json
from beam_pipeline.beam_pipeline import ParseMessage


def test_parse_message():
    element = json.dumps(
        {
            "sensor_id": "Sensor-A",
            "temperature": 21.5,
            "humidity": 40,
            "timestamp": "2025-01-01T00:00:00Z",
        }
    ).encode("utf-8")

    fn = ParseMessage()
    result = list(fn.process(element))

    assert result == [
        {
            "sensor_id": "Sensor-A",
            "temperature": 21.5,
            "humidity": 40,
            "timestamp": "2025-01-01T00:00:00Z",
        }
    ]
