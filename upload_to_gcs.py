# Upload the Excel file (archive) and the NDJSON files (landing) to GCS under a load_date folder.

import sys
from datetime import date

from google.cloud import storage

from config import BUCKET, PROJECT, ROOT

LOAD_DATE = f"load_date={date.fromisoformat(sys.argv[1])}"

bucket = storage.Client(project=PROJECT).bucket(BUCKET)

uploads = [(ROOT / "data/raw/Synthetic_ICT_Risk_Case_Dataset.xlsx",
            f"ict_risk/archive/{LOAD_DATE}")]
uploads += [(f, f"ict_risk/landing/{LOAD_DATE}")
            for f in sorted((ROOT / "data/landing").glob("*.ndjson"))]

for local, prefix in uploads:
    blob = bucket.blob(f"{prefix}/{local.name}")
    blob.upload_from_filename(local)
    print(f"uploaded gs://{BUCKET}/{blob.name}")
