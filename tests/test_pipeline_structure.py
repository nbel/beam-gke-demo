import json
import apache_beam as beam
from apache_beam.testing.test_pipeline import (
    TestPipeline as BeamTestPipeline,
)  # remove test prefix for pytest
from apache_beam.testing.util import assert_that, equal_to
from beam_pipeline.beam_pipeline import ParseMessage


def test_pipeline_parse_only():
    input_data = [
        json.dumps(
            {
                "sensor_id": "Sensor-A",
                "temperature": 21.5,
                "humidity": 40.3,
                "timestamp": "2025-01-01T00:00:00Z",
            }
        ).encode("utf-8")
    ]

    expected = [
        {
            "sensor_id": "Sensor-A",
            "temperature": 21.5,
            "humidity": 40.3,
            "timestamp": "2025-01-01T00:00:00Z",
        }
    ]

    with BeamTestPipeline() as p:
        import os

        print("CWD = ", os.getcwd())
        result = p | beam.Create(input_data) | beam.ParDo(ParseMessage())
        assert_that(result, equal_to(expected))
