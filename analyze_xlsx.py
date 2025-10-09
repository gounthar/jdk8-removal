#!/usr/bin/env python3
"""
Analyze Excel files and convert them to CSV format.

Usage:
    python3 analyze_xlsx.py <excel-file.xlsx>

Example:
    python3 analyze_xlsx.py "Java 25 Compatibility check.xlsx"
"""

import sys
import pandas as pd
import openpyxl

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 analyze_xlsx.py <excel-file.xlsx>")
        print("\nExample:")
        print('  python3 analyze_xlsx.py "Java 25 Compatibility check.xlsx"')
        sys.exit(1)

    xlsx_file = sys.argv[1]

    try:
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
        csv_file = xlsx_file.rsplit('.', 1)[0] + '.csv'
        df.to_csv(csv_file, index=False)
        print(f'Saved to {csv_file}')

    except FileNotFoundError:
        print(f"Error: File '{xlsx_file}' not found")
        sys.exit(1)
    except Exception as e:
        print(f"Error processing file: {e}")
        sys.exit(1)
