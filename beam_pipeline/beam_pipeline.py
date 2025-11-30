import argparse
import json
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from apache_beam.transforms.window import FixedWindows


class ParseMessage(beam.DoFn):
    def process(self, element):
        message = json.loads(element.decode("utf-8"))
        yield {
            "sensor_id": message.get("sensor_id"),
            "temperature": message.get("temperature"),
            "humidity": message.get("humidity"),
            "timestamp": message.get("timestamp"),
        }


def run(argv=None):
    parser = argparse.ArgumentParser()

    parser.add_argument("--input_subscription", required=True)
    parser.add_argument("--output_table", required=True)
    parser.add_argument("--output_path", required=True)

    known_args, pipeline_args = parser.parse_known_args(argv)

    pipeline_options = PipelineOptions(pipeline_args, save_main_session=True)

    with beam.Pipeline(options=pipeline_options) as p:
        parsed_messages = (
            p
            | "Read"
            >> beam.io.ReadFromPubSub(subscription=known_args.input_subscription)
            | "ParseMessage" >> beam.ParDo(ParseMessage())
        )

        # Write to BigQuery
        parsed_messages | "WriteToBigQuery" >> beam.io.WriteToBigQuery(
            table=known_args.output_table,
            write_disposition=beam.io.BigQueryDisposition.WRITE_APPEND,
            create_disposition=beam.io.BigQueryDisposition.CREATE_IF_NEEDED,
            method=beam.io.WriteToBigQuery.Method.FILE_LOADS,
            triggering_frequency=60,
            with_auto_sharding=True,
        )

        # Write to GCS (windowed)
        (
            parsed_messages
            | "JSONify" >> beam.Map(json.dumps)
            | "WindowTo1Min" >> beam.WindowInto(FixedWindows(60))
            | "WriteToGCS"
            >> beam.io.WriteToText(
                file_path_prefix=known_args.output_path,
                file_name_suffix=".json",
                shard_name_template="-SS-of-NN",  # prevents window -> filename expansion
            )
        )


if __name__ == "__main__":
    run()
