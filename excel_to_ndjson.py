# Convert the three Excel sheets to NDJSON files, all values kept as text.

from pathlib import Path
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "data/raw/Synthetic_ICT_Risk_Case_Dataset.xlsx"
OUT = ROOT / "data/landing"
SHEETS = ["Risk_Data", "Risk_Application_Map", "Application_Catalog"]

OUT.mkdir(parents=True, exist_ok=True)
for sheet in SHEETS:
    # dtype=str so pandas does not guess types
    df = pd.read_excel(SRC, sheet_name=sheet, dtype=str)
    df.to_json(OUT / f"{sheet.lower()}.ndjson",
               orient="records", lines=True, force_ascii=False)
    print(f"{sheet}:{len(df)} rows , {len(df.columns)} columns")
