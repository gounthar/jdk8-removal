#!/usr/bin/env python3
import sys
try:
    import pandas as pd
    import openpyxl
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Installing openpyxl...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "openpyxl"])
    import pandas as pd

xlsx_file = 'Java 25 Compatibility check.xlsx'
xl_file = pd.ExcelFile(xlsx_file)
print(f'Sheet names: {xl_file.sheet_names}')
print()

df = pd.read_excel(xlsx_file, sheet_name=0)
print(f'Columns: {list(df.columns)}')
print()
print(f'Shape: {df.shape}')
print()
print('First 10 rows:')
print(df.head(10).to_string())
print()

# Save as CSV for easier processing
csv_file = 'Java_25_Compatibility_check.csv'
df.to_csv(csv_file, index=False)
print(f'Saved to {csv_file}')
