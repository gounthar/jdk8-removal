# JDK 25 Spreadsheet Update - Fix Status & Tomorrow's Tasks

**Date:** 2025-10-09
**Branch:** `fix/spreadsheet-preserve-historical-jdk25`
**PR:** https://github.com/gounthar/jdk8-removal/pull/546

## Problem Statement

The JDK 25 spreadsheet update script was:
1. Only inserting newly-found plugins, not maintaining the cumulative historical list
2. Creating duplicate entries due to name format mismatches
3. Showing 23 green plugins when only 22 should be green (artifactdeployer was stale)
4. Incorrect boolean value formatting for conditional formatting

## Current Status

### ✅ Fixes Implemented

1. **Historical Data Merge** (`update_jdk25_spreadsheet_enhanced.py:120-157`)
   - Loads ALL historical `jdk25_tracking_with_prs_*.json` files
   - Merges them with current scan data (current takes priority)
   - Ensures plugins that drop out of top 250 aren't lost

2. **Duplicate Prevention** (`update_jdk25_spreadsheet_enhanced.py:312-318`)
   - Tracks all name format variations when reading spreadsheet
   - Stores: exact name, dashed format, with/without "-plugin" suffix
   - Prevents same plugin being added as "new" under different name

3. **Boolean Formula Values** (`update_jdk25_spreadsheet_enhanced.py:360, 432`)
   - Changed from string `"TRUE"`/`"FALSE"` to formulas `"=TRUE()"` / `"=FALSE()"`
   - Ensures Google Sheets evaluates as actual boolean, not text
   - Should work with checkbox data validation and conditional formatting

4. **Stale Data Cleanup** (`update_jdk25_spreadsheet_enhanced.py:378-387`)
   - NEW: Clears PR URL and merge status for rows not in current scan
   - Fixes artifactdeployer showing as green when it's not in top 250 anymore

### 📊 Test Results

**From GitHub Actions run:** https://github.com/gounthar/jdk8-removal/actions/runs/18388697229

```
Total plugins scanned: 204
Plugins with JDK 25: 37
New plugins added to spreadsheet: 0  ✅ (no duplicates!)
Existing plugins updated: 37
Plugins with JDK 25 PR identified: 37
Plugins with merged JDK 25 PR: 37
Success rate: 100.0%
```

**Actual data in JSON:**
- 22 plugins with JDK 25 and merged PRs
- Script counting shows 37 (includes historical data from previous runs)

**Current spreadsheet status:**
- 23 plugins showing green (should be 22)
- Extra green plugin: **artifactdeployer** (not in current top 250 scan)

## The Discrepancy Explained

### Why 22 vs 37?

The JSON file (`jdk25_tracking_with_prs_2025-10-09.json`) only contains:
- **204 total plugins** (top 250 most popular Jenkins plugins)
- **22 plugins with JDK 25**

The script reports 37 because:
- It loads historical JSON files and merges them
- **15 additional plugins** from history that still have JDK 25
- These 15 are no longer in top 250 but we're preserving their data

### The 22 Plugins with JDK 25

```
ansible
asm-api
authentication-tokens
blueocean
config-file-provider
gson-api
javadoc
jnr-posix-api
joda-time-api
json-api
json-path-api
locale
mailer
nodelabelparameter
oss-symbols-api
pipeline-groovy-lib
pipeline-model-definition
slack
workflow-basic-steps
workflow-multibranch
workflow-scm-step
workflow-support
```

### The 23rd Green Plugin (Should NOT be green)

- **artifactdeployer** - Old stale data, not in current scan, should be cleared

## Tomorrow's Tasks

### 1. Test Latest Fix ⚠️ PRIORITY

```bash
# Set environment variables
export GOOGLE_APPLICATION_CREDENTIALS="concise-complex-344219-062a255ca56f.json"
export JDK25_SPREADSHEET_ID="1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI"

# Run the script
python3 update_jdk25_spreadsheet_enhanced.py reports/jdk25_tracking_with_prs_2025-10-09.json
```

**Expected Result:**
- Exactly **22 plugins** should be green in spreadsheet
- artifactdeployer should have empty "Is merged?" and "Java 25 pull request" cells
- No duplicates should be created

### 2. Verify Boolean Formatting

Check in spreadsheet:
- Are checkboxes showing up correctly?
- Are they checked for merged PRs?
- Is conditional formatting making them green?

If NOT green, check:
1. Format → Conditional formatting → See what the rule checks
2. Click a checkbox cell → Check formula bar shows `TRUE` not `"TRUE"`

### 3. Merge PR if Tests Pass

Once confirmed working:
```bash
# Update PR with test confirmation
gh pr comment 546 --body "✅ Tested locally, all 22 plugins showing correctly"

# Merge PR
gh pr merge 546 --squash
```

### 4. Monitor Next Automated Run

GitHub Actions workflow runs daily at 6:00 AM UTC:
- `.github/workflows/jdk25-tracking.yml`
- Watch next run to ensure it works correctly
- Check spreadsheet after run completes

## File Locations

**Script:** `update_jdk25_spreadsheet_enhanced.py`

**Data files:**
- Current scan: `reports/jdk25_tracking_with_prs_2025-10-09.json`
- Plugins registry: `plugins.json`
- Credentials: `concise-complex-344219-062a255ca56f.json`

**Spreadsheet:**
- ID: `1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI`
- URL: https://docs.google.com/spreadsheets/d/1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI
- Sheet name: "Java 25 compatibility progress"

## Key Code Changes

### Historical Data Loading
```python
# Load and merge ALL historical tracking files
historical_files = sorted(glob.glob("reports/jdk25_tracking_with_prs_*.json"))
for hist_file in historical_files:
    # Merge logic...
```

### Name Variation Tracking
```python
# Track all variations to avoid duplicates
existing_plugin_names.add(plugin_name.lower())
existing_plugin_names.add(plugin_name.lower().replace(' ', '-'))
existing_plugin_names.add(plugin_name.lower().replace(' ', '-') + '-plugin')
```

### Boolean Formula Values
```python
# Use formulas for actual boolean values
row[is_merged_col] = "=TRUE()" if jdk25_entry['jdk25_pr']['is_merged'] else "=FALSE()"
```

### Stale Data Cleanup
```python
else:
    # No match found - clear stale data
    if java25_pr_col != -1:
        row[java25_pr_col] = ""
    if is_merged_col != -1:
        row[is_merged_col] = ""
```

## Questions for Tomorrow

1. After running the updated script, do we see exactly 22 green plugins?
2. Is artifactdeployer cleared (no checkbox, no PR URL)?
3. Are there any other stale entries we need to investigate?
4. Should we add more detailed logging to show which rows are being cleared?

## Commits in This PR

1. `b35b908` - feat: maintain cumulative JDK 25 tracking across all historical scans
2. `8d66eec` - fix: use boolean values instead of string for Is Merged column
3. `5b77b2f` - fix: prevent duplicate plugins by tracking all name variations
4. `73e5794` - fix: use uppercase 'TRUE'/'FALSE' strings for Google Sheets compatibility
5. `338f5b9` - fix: use formulas for boolean values to ensure proper evaluation
6. `ac96b5b` - fix: clear stale JDK 25 data for plugins not in current scan

---

**Good night! Resume here tomorrow. 🌙**
