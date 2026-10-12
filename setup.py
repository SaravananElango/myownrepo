# Create the GCS bucket and the BigQuery dataset if they do not exist.

from google.cloud import bigquery, storage

from config import BUCKET, DATASET, LOCATION, PROJECT

gcs = storage.Client(project=PROJECT)
bucket = gcs.bucket(BUCKET)
if not bucket.exists():
    gcs.create_bucket(bucket, location=LOCATION)

bq = bigquery.Client(project=PROJECT)
ds = bigquery.Dataset(f"{PROJECT}.{DATASET}")
ds.location = LOCATION
bq.create_dataset(ds, exists_ok=True)
print(f"dataset created: {DATASET}")
