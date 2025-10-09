#!/usr/bin/env python3
"""
Check which plugins are already identified with JDK 25 in the manual spreadsheet
"""
import pandas as pd
import sys

# Read the CSV
try:
    df = pd.read_csv('Java_25_Compatibility_check.csv')
    print("=== Plugins with JDK 25 in Manual Spreadsheet ===\n")

    # Filter rows where Java 25 pull request column has a value
    jdk25_plugins = df[df['Java 25 pull request'].notna()]

    print(f"Total plugins with JDK 25 PR: {len(jdk25_plugins)}\n")

    if len(jdk25_plugins) > 0:
        print("Plugin Name | PR URL | Is Merged")
        print("-" * 80)
        for idx, row in jdk25_plugins.iterrows():
            name = row['Name']
            pr = row['Java 25 pull request']
            merged = row['Is merged?']
            print(f"{name} | {pr} | {merged}")

        # Save list for comparison
        plugin_names = jdk25_plugins['Name'].tolist()
        print(f"\n=== Plugin names for comparison ===")
        for name in plugin_names:
            print(name)

        # Save to file for easy comparison
        with open('manual_jdk25_plugins.txt', 'w') as f:
            for name in plugin_names:
                f.write(f"{name}\n")
        print(f"\nSaved plugin names to: manual_jdk25_plugins.txt")
    else:
        print("No plugins with JDK 25 PRs found in manual spreadsheet.")

except FileNotFoundError:
    print("Error: Java_25_Compatibility_check.csv not found")
    sys.exit(1)
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
