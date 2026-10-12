# Load the NDJSON files from GCS into the raw BigQuery tables, every column as STRING.

import json
import sys
from datetime import date

from google.cloud import bigquery

from config import BUCKET, DATASET, PROJECT, ROOT

LOAD_DATE = f"load_date={date.fromisoformat(sys.argv[1])}"
PREFIX = f"ict_risk/landing/{LOAD_DATE}"

TABLES = {
    "risk_data.ndjson": "raw_risk_data",
    "risk_application_map.ndjson": "raw_risk_application_map",
    "application_catalog.ndjson": "raw_application_catalog",
}

bq = bigquery.Client(project=PROJECT)
for file, table in TABLES.items():
    with (ROOT / "data/landing" / file).open() as fh:
        columns = json.loads(fh.readline()).keys()

    # schema from the file header, all STRING, table replaced on each load
    cfg = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
        schema=[bigquery.SchemaField(name, "STRING") for name in columns],
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )
    uri = f"gs://{BUCKET}/{PREFIX}/{file}"
    table_id = f"{PROJECT}.{DATASET}.{table}"
    print(f"Loading {uri} -> {table_id}")
    job = bq.load_table_from_uri(uri, table_id, job_config=cfg)
    job.result()
    print(f"{table_id}: {bq.get_table(table_id).num_rows} rows loaded ({job.job_id})")
