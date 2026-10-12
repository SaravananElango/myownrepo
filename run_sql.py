# Run sql/00 to sql/05 in order and stop at the first error (e.g. a failed assert).

import sys

from google.cloud import bigquery

from config import DATASET, LOCATION, PROJECT, ROOT

PLACEHOLDER = "{{DATASET}}"

bq = bigquery.Client(project=PROJECT, location=LOCATION)
job_config = bigquery.QueryJobConfig(default_dataset=f"{PROJECT}.{DATASET}")

for path in sorted((ROOT / "sql").glob("0[0-5]_*.sql")):
    print(f">> {path.name}")
    sql = path.read_text()
    if f"set @@dataset_id = '{PLACEHOLDER}'" not in sql:
        sys.exit(f"FAILED in {path.name}: missing \"set @@dataset_id = '{PLACEHOLDER}';\"")

    # dataset name comes from config.py
    sql = sql.replace(PLACEHOLDER, DATASET)
    try:
        bq.query(sql, job_config=job_config).result()
    except Exception as e:
        sys.exit(f"FAILED in {path.name}: {getattr(e, 'message', e)}")

print(f"All scripts succeeded -> {PROJECT}.{DATASET}")
