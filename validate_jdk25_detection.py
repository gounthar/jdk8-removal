#!/usr/bin/env python3
"""
Validate JDK 25 detection by comparing automated results with manual spreadsheet.
This script checks:
1. Did we detect all plugins that were manually identified?
2. Did we find the correct PRs?
3. Did we correctly identify merge status?
"""
import json
import pandas as pd
import sys
from datetime import datetime

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 validate_jdk25_detection.py <jdk25-tracking-json-file>")
        print("\nExample:")
        print("  python3 validate_jdk25_detection.py reports/jdk25_tracking_with_prs_2025-10-09.json")
        sys.exit(1)

    automated_file = sys.argv[1]

    print("=" * 80)
    print("JDK 25 Detection Validation Report")
    print(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 80)
    print()

    # Load manual spreadsheet
    try:
        manual_df = pd.read_csv('Java_25_Compatibility_check.csv')
        manual_jdk25 = manual_df[manual_df['Java 25 pull request'].notna()]
        print(f"✓ Loaded manual spreadsheet: {len(manual_jdk25)} plugins with JDK 25")
    except FileNotFoundError:
        print("✗ Error: Java_25_Compatibility_check.csv not found")
        sys.exit(1)

    # Load automated results
    try:
        with open(automated_file) as f:
            automated_data = json.load(f)
        automated_jdk25 = [p for p in automated_data if p['has_jdk25']]
        print(f"✓ Loaded automated results: {len(automated_jdk25)} plugins with JDK 25")
    except FileNotFoundError:
        print(f"✗ Error: {automated_file} not found")
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"✗ Error: Invalid JSON in {automated_file}")
        sys.exit(1)

    print()
    print("-" * 80)
    print("VALIDATION RESULTS")
    print("-" * 80)
    print()

    # Create lookup maps
    manual_map = {}
    for _, row in manual_jdk25.iterrows():
        name = row['Name'].lower().strip()
        manual_map[name] = {
            'pr_url': str(row['Java 25 pull request']),
            'is_merged': row['Is merged?']
        }

    automated_map = {}
    for plugin in automated_jdk25:
        # Try various name formats
        names = [
            plugin['plugin'].lower().strip(),
            plugin['repository'].split('/')[-1].replace('-plugin', '').replace('-', ' '),
            plugin['repository'].split('/')[-1].replace('-plugin', '')
        ]
        for name in names:
            automated_map[name] = plugin

    # Validation checks
    found_count = 0
    missing_count = 0
    pr_match_count = 0
    pr_mismatch_count = 0
    merge_match_count = 0
    merge_mismatch_count = 0

    print("1. CHECKING MANUAL PLUGINS IN AUTOMATED RESULTS")
    print()

    for manual_name, manual_data in manual_map.items():
        # Try to find in automated results
        found = False
        automated_plugin = None

        # Try exact match and variations
        search_names = [
            manual_name,
            manual_name.replace(' ', '-'),
            manual_name.replace('-', ' '),
            manual_name + '-plugin'
        ]

        for search_name in search_names:
            if search_name in automated_map:
                found = True
                automated_plugin = automated_map[search_name]
                break

        if found:
            found_count += 1
            print(f"✓ FOUND: {manual_name}")

            # Check PR URL
            manual_pr = manual_data['pr_url']
            automated_pr = automated_plugin['jdk25_pr']['url']

            if automated_pr:
                if manual_pr in automated_pr or automated_pr in manual_pr:
                    pr_match_count += 1
                    print(f"  ✓ PR matches: {automated_pr}")
                else:
                    pr_mismatch_count += 1
                    print("  ✗ PR mismatch!")
                    print(f"    Manual:    {manual_pr}")
                    print(f"    Automated: {automated_pr}")

                # Check merge status
                manual_merged = manual_data['is_merged']
                automated_merged = automated_plugin['jdk25_pr']['is_merged']

                if str(manual_merged).lower() == str(automated_merged).lower():
                    merge_match_count += 1
                    print(f"  ✓ Merge status matches: {automated_merged}")
                else:
                    merge_mismatch_count += 1
                    print("  ✗ Merge status mismatch!")
                    print(f"    Manual:    {manual_merged}")
                    print(f"    Automated: {automated_merged}")
            else:
                pr_mismatch_count += 1
                print("  ✗ No PR found in automated results")
                print(f"    Expected: {manual_pr}")

            print()
        else:
            missing_count += 1
            print(f"✗ MISSING: {manual_name}")
            print(f"  Expected PR: {manual_data['pr_url']}")
            print()

    print()
    print("-" * 80)
    print("2. ADDITIONAL PLUGINS FOUND BY AUTOMATION")
    print()

    # Find plugins detected by automation but not in manual list
    additional_count = 0
    for plugin in automated_jdk25:
        plugin_names = [
            plugin['plugin'].lower().strip(),
            plugin['repository'].split('/')[-1].replace('-plugin', '').replace('-', ' ')
        ]

        found_in_manual = any(name in manual_map for name in plugin_names)

        if not found_in_manual:
            additional_count += 1
            print(f"+ NEW: {plugin['plugin']}")
            print(f"  Repository: {plugin['repository']}")
            if plugin['jdk25_pr']['url']:
                print(f"  PR: {plugin['jdk25_pr']['url']}")
                print(f"  Merged: {plugin['jdk25_pr']['is_merged']}")
            else:
                print("  No PR found")
            print()

    if additional_count == 0:
        print("No additional plugins found beyond manual list.")
        print()

    # Summary
    print()
    print("=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print()
    print(f"Manual plugins with JDK 25:     {len(manual_map)}")
    print(f"Automated plugins with JDK 25:  {len(automated_jdk25)}")
    print()
    print("Detection Accuracy:")
    if len(manual_map) > 0:
        print(f"  ✓ Found in automation:         {found_count}/{len(manual_map)} ({found_count/len(manual_map)*100:.1f}%)")
        print(f"  ✗ Missing from automation:     {missing_count}/{len(manual_map)}")
    else:
        print("  (Manual spreadsheet lists no JDK 25 plugins)")
    print()
    print("PR Matching:")
    print(f"  ✓ PR matches:                  {pr_match_count}")
    print(f"  ✗ PR mismatches:               {pr_mismatch_count}")
    print()
    print("Merge Status:")
    print(f"  ✓ Merge status matches:        {merge_match_count}")
    print(f"  ✗ Merge status mismatches:     {merge_mismatch_count}")
    print()
    print(f"Additional plugins found:        {additional_count}")
    print()

    # Overall assessment
    if missing_count == 0 and pr_mismatch_count == 0 and merge_mismatch_count == 0:
        print("✓✓✓ VALIDATION PASSED: All checks successful! ✓✓✓")
        return 0
    elif missing_count == 0:
        print("⚠ VALIDATION PARTIAL: All plugins found, but some details don't match")
        return 1
    else:
        print("✗✗✗ VALIDATION FAILED: Some plugins were not detected ✗✗✗")
        return 2

if __name__ == '__main__':
    sys.exit(main())
