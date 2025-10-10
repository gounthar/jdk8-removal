# JDK 25 Compatibility Tracking

This document describes the automated workflow for tracking JDK 25 compatibility across Jenkins plugins.

## Overview

The JDK 25 tracking system automates the process of:
1. Scanning Jenkins plugin Jenkinsfiles to detect which JDK versions they're building with
2. Generating reports in CSV and JSON formats
3. Updating a Google Spreadsheet with the detection results

This replaces the manual process of checking each plugin and updating the spreadsheet.

## Components

### 1a. check-jdk25-with-pr-incremental.sh (RECOMMENDED FOR REGULAR RUNS)

**Incremental version** that skips already-validated JDK 25 plugins for faster execution.

**What it does:**
- Loads a list of previously validated plugins (those with merged JDK 25 PRs)
- Skips those plugins during processing to save time
- Only checks new or unvalidated plugins
- Everything else same as `check-jdk25-with-pr.sh`

**Usage:**
```bash
# First run (no previous results)
./check-jdk25-with-pr-incremental.sh

# Subsequent runs (using previous results to skip validated plugins)
./check-jdk25-with-pr-incremental.sh reports/jdk25_tracking_with_prs_2025-10-09.json
```

**Benefits:**
- ✅ Much faster for subsequent runs (only checks new/changed plugins)
- ✅ Maintains a `validated_jdk25_plugins.txt` file with confirmed plugins
- ✅ Perfect for weekly/monthly tracking

**Latest Results (2025-10-09):**
- Total repositories scanned: 250
- Repositories with Jenkinsfile: 245
- Repositories building with JDK 25: 45
- Success rate: 100% PR detection for JDK 25 plugins

### 1b. check-jdk25-with-pr.sh (FULL SCAN)

**Enhanced** bash script that not only detects JDK 25 but also tracks the PR that added it.

**What it does:**
- Reads the top-250 most popular Jenkins plugins from `top-250-plugins.csv`
- Maps plugin names to repository URLs using `plugins.json`
- Fetches the Jenkinsfile from each repository's default branch (root directory)
- Detects JDK 25 using pattern matching
- **Clones the repository and searches git history to find the commit that added JDK 25**
- **Uses GitHub API to find the PR associated with that commit**
- **Checks if the PR is merged**
- Generates output in both CSV and JSON formats with PR tracking information

**Use this script** for the first full scan or when you want to re-check all plugins.

### 1d. check-jdk25-open-prs.sh (OPEN PRS DETECTION)

**NEW** bash script that detects open PRs (including drafts) that are adding JDK 25 to Jenkins plugins.

**What it does:**
- Reads the top-250 most popular Jenkins plugins from `top-250-plugins.csv`
- Maps plugin names to repository URLs using `plugins.json`
- For each repository:
  - **Optimization:** Skips repositories that already have JDK 25 merged (saves ~10% of API calls)
  - Fetches all open PRs (including drafts)
  - Checks if the PR modifies the Jenkinsfile
  - Compares Jenkinsfile content between PR head and base branches
  - Identifies PRs that are **adding** JDK 25 (not just modifying existing JDK 25)
  - Tracks draft status, author, creation date
- Generates output in both CSV and JSON formats

**Use this script** to monitor in-progress JDK 25 adoption efforts.

**Output files:**
- `reports/jdk25_open_prs_tracking_YYYY-MM-DD.csv` - CSV report
- `reports/jdk25_open_prs_tracking_YYYY-MM-DD.json` - JSON report
- `logs/jdk25_open_prs_YYYY-MM-DD.log` - Detailed execution log

**JSON structure:**
```json
{
  "plugin": "Plugin Name",
  "repository": "jenkinsci/plugin-name",
  "url": "https://github.com/jenkinsci/plugin-name",
  "has_open_jdk25_prs": true,
  "open_jdk25_prs": [
    {
      "number": 123,
      "url": "https://github.com/jenkinsci/plugin-name/pull/123",
      "title": "Add JDK 25 to test matrix",
      "isDraft": false,
      "author": {
        "login": "username"
      },
      "createdAt": "2025-10-01T10:30:00Z",
      "headRefName": "feature/jdk25",
      "baseRefName": "main"
    }
  ],
  "has_jenkinsfile": true
}
```

**Change Tracking:**
The script automatically compares with the most recent previous run and reports:
- 📈 New PRs opened
- 📉 PRs closed/merged
- ✅ Draft → Ready for review transitions
- ⏸️  Ready → Draft transitions

**Benefits:**
- ✅ Monitors ongoing JDK 25 adoption efforts
- ✅ Distinguishes between draft and regular PRs
- ✅ Tracks changes between runs automatically
- ✅ Helps identify PRs that need review or assistance
- ✅ Complements merged PR tracking for complete visibility

### 1c. check-jdk-versions.sh (Basic version)

Bash script that scans Jenkins plugin repositories to detect JDK versions in their Jenkinsfiles.

**What it does:**
- Reads the top-250 most popular Jenkins plugins from `top-250-plugins.csv`
- Maps plugin names to repository URLs using `plugins.json`
- Fetches the Jenkinsfile from each repository's default branch
- Detects JDK versions (8, 11, 17, 21, 25) using pattern matching
- Generates output in both CSV and JSON formats

**Note:** This version only detects JDK versions but doesn't track PRs. Use `check-jdk25-with-pr.sh` for full automation.

**Output files:**
- `reports/jdk_versions_in_jenkinsfiles_YYYY-MM-DD.csv` - CSV report
- `reports/jdk_versions_in_jenkinsfiles_YYYY-MM-DD.json` - JSON report (used by the update script)

**CSV columns:**
- Plugin - Formatted plugin name
- Repository - GitHub repository path (e.g., jenkinsci/script-security-plugin)
- URL - Full GitHub URL
- JDK_8, JDK_11, JDK_17, JDK_21, JDK_25 - Boolean flags (true/false)
- Jenkinsfile_URL - Direct link to the Jenkinsfile
- Has_Jenkinsfile - Whether a Jenkinsfile was found

### 2. update_jdk25_spreadsheet_enhanced.py (RECOMMENDED)

**Enhanced** Python script that updates the existing Google Spreadsheet with JDK 25 PR tracking.

**What it does:**
- Reads the JSON output from `check-jdk25-with-pr.sh`
- **Optionally** reads the JSON output from `check-jdk25-open-prs.sh`
- Connects to your existing Google Spreadsheet using service account credentials
- Updates the exact columns from the existing spreadsheet:
  - **Name** - Plugin name (preserved)
  - **Installation Count** - Number of installations (preserved from existing)
  - **Java 25 pull request** - Populated with the PR URL we found automatically
  - **Is merged?** - Populated with the merge status we found automatically
- Generates a statistics sheet with summary metrics
- Creates clickable hyperlinks for PRs
- **If open PRs data is provided:**
  - Creates/updates "Open JDK 25 PRs" sheet
  - Lists all open PRs that are adding JDK 25
  - Color-codes rows: dark orange (#FF8C00) for draft PRs, light orange (#FFD580) for regular PRs
  - Includes columns: Plugin Name, Repository, PR Number, PR URL, Title, Is Draft?, Author, Created, Days Open

**This is the recommended script** as it works with your existing spreadsheet structure.

**Usage with open PRs:**
```bash
# Update with both merged and open PRs data
./update_jdk25_spreadsheet_enhanced.py \
  reports/jdk25_tracking_with_prs_2025-10-10.json \
  reports/jdk25_open_prs_tracking_2025-10-10.json

# Or just merged PRs (without open PRs)
./update_jdk25_spreadsheet_enhanced.py \
  reports/jdk25_tracking_with_prs_2025-10-10.json
```

### 2b. update_jdk25_spreadsheet.py (Basic version)

Python script that updates a Google Spreadsheet with JDK version detection results.

**What it does:**
- Reads the JSON output from `check-jdk-versions.sh`
- Connects to Google Sheets using service account credentials
- Creates a new spreadsheet or updates an existing one with JDK version data
- Adds columns for each JDK version (8, 11, 17, 21, 25)
- Generates a statistics sheet with summary metrics

**Note:** This version creates more columns than needed. Use `update_jdk25_spreadsheet_enhanced.py` to work with the existing spreadsheet format.

**Features:**
- Automatic column detection and creation
- Retry logic with exponential backoff for API rate limits
- Flexible plugin name matching (handles various formats)
- Timestamp tracking for updates
- Creates clickable hyperlinks for Jenkinsfiles

### 3. Validation Scripts

#### check_existing_jdk25_plugins.py

Extracts plugins with JDK 25 from the manual Excel spreadsheet for comparison.

**Usage:**
```bash
python3 check_existing_jdk25_plugins.py
```

**What it does:**
- Reads `Java_25_Compatibility_check.csv` (manual spreadsheet export)
- Extracts all plugins that have JDK 25 PR information
- Saves the list to `manual_jdk25_plugins.txt`
- Displays PR URLs and merge status

#### validate_jdk25_detection.py

Validates automated detection results against manual spreadsheet entries.

**Usage:**
```bash
python3 validate_jdk25_detection.py reports/jdk25_tracking_with_prs_2025-10-09.json
```

**What it does:**
1. Loads manual spreadsheet (CSV format)
2. Loads automated detection results (JSON format)
3. Compares both datasets:
   - Checks if all manual plugins were detected
   - Verifies PR URLs match
   - Verifies merge status matches
4. Reports additional plugins found by automation
5. Generates comprehensive validation report

**Exit codes:**
- 0: All checks passed
- 1: Partial success (all plugins found, but some details don't match)
- 2: Validation failed (some plugins not detected)

**Example output:**
```text
✓ FOUND: mailer
  ✓ PR matches: https://github.com/jenkinsci/mailer-plugin/pull/381
  ✓ Merge status matches: True

✗ MISSING: s3
  Expected PR: https://github.com/jenkinsci/s3-plugin/pull/352
```

### 4. analyze_xlsx.py

Helper script to analyze Excel files and convert them to CSV.

**What it does:**
- Reads Excel files (.xlsx format)
- Displays structure (sheets, columns, dimensions)
- Converts to CSV for easier processing

## Plugin List Modes

The JDK 25 tracking scripts support two plugin list modes, controlled by the `PLUGIN_LIST_MODE` environment variable:

### Top-250 Mode (Default)
- **Value:** `PLUGIN_LIST_MODE=top-250` (or unset)
- **Plugin List:** `top-250-plugins.csv` (generated by `get-most-popular-plugins.sh`)
- **Plugin Count:** 250 most popular plugins
- **Execution Time:** ~20-30 minutes for merged PRs, ~15-25 minutes for open PRs
- **Best for:** Daily/weekly monitoring, faster iterations, development testing

### All-Plugins Mode
- **Value:** `PLUGIN_LIST_MODE=all`
- **Plugin List:** `all-plugins.csv` (generated by `get-all-plugins.sh`)
- **Plugin Count:** ~2,036 total plugins in the Jenkins registry
- **Execution Time:** ~2-4 hours for merged PRs, ~1.5-3 hours for open PRs
- **Best for:** Comprehensive audits, monthly reports, complete ecosystem analysis

### Switching Between Modes

**Use top-250 mode (default):**
```bash
# Don't set PLUGIN_LIST_MODE, or explicitly set it
export PLUGIN_LIST_MODE=top-250
./check-jdk25-with-pr-incremental.sh
./check-jdk25-open-prs.sh
```

**Use all-plugins mode:**
```bash
# First, generate the all-plugins list
./get-all-plugins.sh

# Then run scripts with all-plugins mode
export PLUGIN_LIST_MODE=all
./check-jdk25-with-pr-incremental.sh
./check-jdk25-open-prs.sh
```

**Workflow Recommendation:**
1. Use **top-250 mode** for daily/weekly automated runs to track the most popular plugins
2. Use **all-plugins mode** monthly or quarterly for comprehensive ecosystem reports
3. Both modes are fully compatible - output files use the same format

### Benefits of All-Plugins Mode
- ✅ Complete visibility into JDK 25 adoption across entire ecosystem
- ✅ Discover JDK 25 adoption in less popular but important plugins
- ✅ More accurate ecosystem-wide statistics
- ✅ Identifies outliers and edge cases

### Tradeoffs
- ⚠️ Longer execution time (~8x more plugins to scan)
- ⚠️ Higher API usage (but incremental mode helps mitigate this)
- ⚠️ Larger output files

## Prerequisites

### Required Tools
- **Bash** - Shell scripting environment
- **Git** & **GitHub CLI (`gh`)** - For repository operations
- **jq** - JSON processing
- **parallel** (GNU parallel) - Concurrent execution
- **curl** - HTTP requests
- **Python 3** - For Google Sheets integration

### Required Files
- `plugins.json` - Jenkins plugin registry data (download from https://updates.jenkins.io/current/update-center.actual.json)
- `concise-complex-344219-062a255ca56f.json` - Google service account credentials

**Plugin Lists (choose one based on mode):**
- `top-250-plugins.csv` - Top 250 most popular Jenkins plugins (generated by `get-most-popular-plugins.sh`)
- `all-plugins.csv` - All ~2,036 Jenkins plugins (generated by `get-all-plugins.sh`)

### Environment Variables
```bash
export GITHUB_TOKEN=your_github_token_here
export PLUGIN_LIST_MODE=top-250  # Mode: "top-250" (default) or "all"
export RATE_LIMIT_DELAY=2  # Delay between API calls in seconds (optional)
export DEBUG_MODE=false     # Enable debug output (optional)
export JDK25_SPREADSHEET_ID=1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI  # Default automated spreadsheet
export LOG_FILE=logs/custom_log.log  # Custom log file path (optional)
```

**Recommended:** Create a `.env` file in the project root (see `.env.example` for template)

### Logging

All scripts automatically create detailed log files in the `logs/` directory with timestamps. Log files include:
- All console output (info, warnings, errors)
- Debug messages (when DEBUG_MODE=true)
- Timestamps for each log entry
- Summary of execution

Default log file locations:
- JDK 25 tracking: `logs/jdk25_tracking_YYYY-MM-DD.log`
- JDK version detection: `logs/jdk_versions_YYYY-MM-DD.log`

You can override the log file location with the `LOG_FILE` environment variable.

### Python Dependencies
```bash
pip install gspread google-auth pandas openpyxl
```

## Usage

### Step 1: Generate Plugin List

First, download the latest Jenkins update center data:

```bash
curl -o plugins.json https://updates.jenkins.io/current/update-center.actual.json
```

Then generate the plugin list based on your needs:

**Option A: Top-250 Mode (recommended for daily/weekly runs)**
```bash
./get-most-popular-plugins.sh
```

This creates:
- `top-250-plugins.csv` - Top 250 plugins with popularity scores
- `top_plugins.txt` - Just the plugin names
- `top_plugins_with_versions.txt` - Plugin names with version numbers

**Option B: All-Plugins Mode (for comprehensive audits)**
```bash
./get-all-plugins.sh
```

This creates:
- `all-plugins.csv` - All ~2,036 plugins with popularity scores sorted by popularity

**You can generate both lists** and switch between them using the `PLUGIN_LIST_MODE` environment variable.

### Step 2: Scan Jenkinsfiles for JDK 25 and Find Associated PRs

Run the **enhanced** detection script with PR tracking:

```bash
./check-jdk25-with-pr.sh
```

**What happens:**
1. Reads top-250 plugins from CSV
2. Maps plugin names to repository URLs
3. Fetches Jenkinsfile from each repository
4. Detects JDK 25 using pattern matching
5. **For each plugin with JDK 25:**
   - Clones the repository
   - Searches git history to find the commit that added JDK 25
   - Uses GitHub API to find the PR containing that commit
   - Checks if the PR is merged
6. Generates CSV and JSON reports with complete PR tracking

**Duration:** Approximately 20-30 minutes for 250 plugins (due to git cloning and API calls)

**Alternative:** If you only want to detect JDK versions without PR tracking (faster):
```bash
./check-jdk-versions.sh  # Takes 5-10 minutes
```

**Output:**
```
Starting JDK 25 detection with PR tracking in Jenkins plugin Jenkinsfiles...
Output will be written to: reports/jdk25_tracking_with_prs_2025-10-09.csv and reports/jdk25_tracking_with_prs_2025-10-09.json
Reading top-250 plugins list...
Found 250 repositories to check
Processing repositories...
Jenkinsfile found in jenkinsci/script-security-plugin
JDK 25 not found in jenkinsci/script-security-plugin
...
Jenkinsfile found in jenkinsci/mailer-plugin
JDK 25 detected in jenkinsci/mailer-plugin
Searching for commit that added JDK 25 to jenkinsci/mailer-plugin...
Found commit: a1b2c3d4e5f6
Commit date: 2025-09-15T10:30:00Z
Searching for PR associated with commit a1b2c3d4e5f6...
Found PR #381: https://github.com/jenkinsci/mailer-plugin/pull/381 (merged: true)
...
Done! Results saved to:
  CSV: reports/jdk25_tracking_with_prs_2025-10-09.csv
  JSON: reports/jdk25_tracking_with_prs_2025-10-09.json
  Log: logs/jdk25_tracking_2025-10-09.log

Summary:
  Total repositories scanned: 250
  Repositories with Jenkinsfile: 237
  Repositories building with JDK 25: 12
  Repositories with JDK 25 PR identified: 11
  Repositories with merged JDK 25 PR: 10

[SUCCESS] Log file saved to: logs/jdk25_tracking_2025-10-09.log
```

**Tip:** You can monitor the log file in real-time while the script runs:
```bash
tail -f logs/jdk25_tracking_2025-10-09.log
```

### Step 2b: Detect Open PRs Adding JDK 25 (Optional)

If you want to track in-progress JDK 25 adoption efforts, run the open PRs detection script:

```bash
./check-jdk25-open-prs.sh
```

**What happens:**
1. Reads top-250 plugins from CSV
2. Maps plugin names to repository URLs
3. For each repository:
   - Skips if JDK 25 already merged (optimization)
   - Fetches all open PRs (including drafts)
   - Checks if PR modifies Jenkinsfile
   - Compares head vs base branches for JDK 25 presence
   - Identifies PRs that are **adding** JDK 25
4. Generates CSV and JSON reports with PR details

**Duration:** Approximately 15-25 minutes for 250 plugins (GitHub API calls for PR listing and file fetching)

**Output:**
```
Starting JDK 25 open PRs detection in Jenkins plugin repositories...
Output will be written to: reports/jdk25_open_prs_tracking_2025-10-10.csv and reports/jdk25_open_prs_tracking_2025-10-10.json
Reading top-250 plugins list...
Found 250 repositories to check
After deduplication: 204 unique repositories to check
Processing repositories...
Processing jenkinsci/mailer-plugin...
Skipping jenkinsci/mailer-plugin - already has JDK 25 on default branch
Processing jenkinsci/foo-plugin...
Found PR #123 that adds JDK 25 to jenkinsci/foo-plugin
...
Done! Results saved to:
  CSV: reports/jdk25_open_prs_tracking_2025-10-10.csv
  JSON: reports/jdk25_open_prs_tracking_2025-10-10.json
  Log: logs/jdk25_open_prs_2025-10-10.log

Summary:
  Total repositories scanned: 204
  Repositories with open JDK 25 PRs: 3
  Total open PRs adding JDK 25: 4
```

**Example output with change tracking:**
```
Summary:
  Total repositories scanned: 204
  Repositories with open JDK 25 PRs: 3
  Total open PRs adding JDK 25: 4

Checking for changes since last run...
Comparing with previous run from 2025-10-09

Changes since 2025-10-09:
  📈 New PRs opened: 1
  📉 PRs closed/merged: 2
  ✅ Draft → Ready: 1
  ⏸️  Ready → Draft: 0

New PRs:
  • jenkinsci/foo-plugin #456 - https://github.com/jenkinsci/foo-plugin/pull/456

Closed/Merged PRs:
  • jenkinsci/bar-plugin #123 - https://github.com/jenkinsci/bar-plugin/pull/123
  • jenkinsci/baz-plugin #789 - https://github.com/jenkinsci/baz-plugin/pull/789
```

**Benefits:**
- Monitor in-progress JDK 25 adoption
- Identify PRs that may need review or help
- Track draft vs regular PRs
- Understand community adoption velocity
- Automatically see what changed since last run

### Step 3: Update Google Spreadsheet

Run the **enhanced** update script. The spreadsheet ID can be provided in three ways:

**Option 1: Use environment variable (Recommended)**
```bash
# Set in .env file or export
export JDK25_SPREADSHEET_ID=1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI

# Then run without specifying spreadsheet ID
./update_jdk25_spreadsheet_enhanced.py reports/jdk25_tracking_with_prs_2025-10-09.json
```

**Option 2: Provide spreadsheet ID as argument**
```bash
./update_jdk25_spreadsheet_enhanced.py reports/jdk25_tracking_with_prs_2025-10-09.json '1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI'
```

**Option 3: Use the full URL**
```bash
./update_jdk25_spreadsheet_enhanced.py reports/jdk25_tracking_with_prs_2025-10-09.json 'https://docs.google.com/spreadsheets/d/1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI/edit'
```

**Default Automated Spreadsheet:**
- URL: https://docs.google.com/spreadsheets/d/1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI/edit
- ID: `1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI`
- This is the automated spreadsheet (separate from the manual one)

**What happens:**
1. Loads JDK 25 tracking data (including PR information) from JSON
2. Connects to Google Sheets using service account
3. Opens your existing spreadsheet by ID
4. Finds the worksheet (tries multiple possible names)
5. **Updates only the relevant columns:**
   - Populates "Java 25 pull request" with clickable PR links
   - Populates "Is merged?" with TRUE/FALSE
   - Preserves "Installation Count" and other existing data
6. Generates/updates statistics sheet
7. Formats headers

**Output:**
```
Starting JDK 25 spreadsheet update script...
Successfully loaded service account credentials
Successfully loaded JDK 25 tracking data from reports/jdk25_tracking_with_prs_2025-10-09.json
Found 250 plugins in the data
Opened spreadsheet by ID: 1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI
Found worksheet: 'Java 25 compatibility progress'
Read 2235 rows from existing spreadsheet
Existing headers: ['Name', 'Installation Count (June 2025)', 'Java 25 pull request', 'Is merged?']
Column indices: Name=0, Installation Count=1, Java 25 PR=2, Is Merged=3
Updated 12 rows with JDK 25 PR data
Writing 2235 rows to spreadsheet...
Formatting header row...
Updating existing Statistics sheet...
Spreadsheet update complete!
Spreadsheet URL: https://docs.google.com/spreadsheets/d/1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI/edit

Summary:
  Total plugins scanned: 250
  Plugins with JDK 25: 12
  Plugins with JDK 25 PR identified: 11
  Plugins with merged JDK 25 PR: 10
  Success rate: 91.7% of JDK 25 plugins have PR identified
```

## Spreadsheet Structure

### Main Sheet: "Java 25 Compatibility Progress"

| Column | Description |
|--------|-------------|
| Name | Plugin name (formatted) |
| Installation Count | Number of installations (preserved from existing data) |
| Repository URL | GitHub repository URL |
| Has Jenkinsfile | Yes/No - Whether a Jenkinsfile exists |
| Jenkinsfile URL | Clickable link to the Jenkinsfile (if exists) |
| JDK 8 | Yes/No - Builds with JDK 8 |
| JDK 11 | Yes/No - Builds with JDK 11 |
| JDK 17 | Yes/No - Builds with JDK 17 |
| JDK 21 | Yes/No - Builds with JDK 21 |
| JDK 25 | Yes/No - Builds with JDK 25 |
| Java 25 PR | PR URL (preserved from existing data) |
| Is Merged? | Merge status (preserved from existing data) |
| Last Updated | Timestamp of last scan |

### Statistics Sheet

Shows summary metrics:
- Total plugins analyzed
- Plugins with/without Jenkinsfile
- Count and percentage of plugins building with each JDK version

## Automation

To run this automatically on a schedule, you can:

### GitHub Actions

Create `.github/workflows/jdk25-tracking.yml`:

```yaml
name: JDK 25 Compatibility Tracking

on:
  schedule:
    - cron: '0 6 * * *'  # Run daily at 6:00 AM UTC
  workflow_dispatch:  # Allow manual triggers

jobs:
  track-jdk25:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq parallel gh
          pip install -r requirements.txt

      - name: Download plugins data
        run: |
          curl -o plugins.json https://updates.jenkins.io/current/update-center.actual.json
          ./get-most-popular-plugins.sh

      - name: Scan Jenkinsfiles (incremental)
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: ./check-jdk25-with-pr-incremental.sh

      - name: Update Spreadsheet
        env:
          GOOGLE_CREDENTIALS: ${{ secrets.GOOGLE_CREDENTIALS }}
          JDK25_SPREADSHEET_ID: ${{ secrets.JDK25_SPREADSHEET_ID }}
        run: |
          echo "$GOOGLE_CREDENTIALS" > google-credentials.json
          ./update_jdk25_spreadsheet_enhanced.py reports/jdk25_tracking_with_prs_$(date +%Y-%m-%d).json

      - name: Commit results
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add reports/
          git commit -m "Update JDK 25 tracking - $(date +%Y-%m-%d)" || true
          git push
```

### Cron Job

```bash
# Edit crontab
crontab -e

# Add this line to run daily at 6:00 AM UTC
0 6 * * * cd /path/to/your-project-root && ./check-jdk25-with-pr-incremental.sh && ./update_jdk25_spreadsheet_enhanced.py reports/jdk25_tracking_with_prs_$(date +\%Y-\%m-\%d).json
```

## Troubleshooting

### Rate Limiting

If you hit GitHub API rate limits:

```bash
# Increase the delay between API calls
export RATE_LIMIT_DELAY=5

# Or reduce parallelism in check-jdk-versions.sh
# Edit line: parallel -j 5  -> parallel -j 2
```

### Plugin Not Found

If a plugin isn't detected:
1. Check that it's in `top-250-plugins.csv`
2. Verify the repository URL in `plugins.json`
3. Check that the repository has a Jenkinsfile in its default branch (root directory)

**Note:** The scripts currently only detect Jenkinsfiles in the root directory of repositories, not in subdirectories. Based on analysis of the top-250 plugins:
- 245 out of 250 (98%) have Jenkinsfiles in the root directory
- Only 5 plugins genuinely don't have Jenkinsfiles anywhere
- This detection method captures the vast majority of Jenkins plugins

### Spreadsheet Access Denied

Ensure your service account has been granted Editor access to the spreadsheet:
1. Open the spreadsheet
2. Click "Share"
3. Add the service account email (found in the JSON credentials file)
4. Grant "Editor" permissions

### Pattern Not Matching

If JDK versions aren't being detected:
1. Check the Jenkinsfile format manually
2. The patterns look for: `jdk: '25'`, `java: 25`, `openjdk-25`, etc.
3. You may need to add new patterns to the `check_jdk_versions_in_jenkinsfile()` function

## Customization

### Adding New JDK Versions

To track a new JDK version (e.g., JDK 26):

1. **Update check-jdk-versions.sh:**
```bash
# Add detection flag
has_jdk26="false"

# Add pattern matching
if echo "$jenkinsfile" | grep -qiE "(jdk['\": ]+['\"]?26['\"]?|java['\": ]+['\"]?26['\"]?|openjdk-?26)"; then
  has_jdk26="true"
  info "JDK 26 detected in $repo"
fi

# Update CSV output
echo "...,JDK_26,..." >> "$output_csv"

# Update JSON output
cat >> "$output_json" <<EOF
  "jdk26": $has_jdk26
EOF
```

2. **Update update_jdk25_spreadsheet.py:**
```python
# Add column
"JDK 26",

# Add data
entry['jdk_versions']['jdk26']

# Add statistics
plugins_with_jdk26 = sum(1 for entry in jdk_data if entry['jdk_versions']['jdk26'])
```

### Changing the Plugin List

The scripts now support two built-in modes via the `PLUGIN_LIST_MODE` environment variable:

**Switch to all-plugins mode:**
```bash
# Generate the all-plugins list if you haven't already
./get-all-plugins.sh

# Set the mode
export PLUGIN_LIST_MODE=all

# Run the scripts
./check-jdk25-with-pr-incremental.sh
./check-jdk25-open-prs.sh
```

**Switch back to top-250 mode:**
```bash
export PLUGIN_LIST_MODE=top-250
# or simply unset it (top-250 is the default)
unset PLUGIN_LIST_MODE
```

**For custom plugin lists:**
If you need a completely custom list, you can:
1. Create a CSV file with format: `name,popularity` (with header row)
2. Modify the scripts to read from your custom file
3. Or create a wrapper script that sets the appropriate file path

## Maintenance

### Regular Updates

Run the tracking workflow:
- **Weekly**: For active development periods
- **Monthly**: For stable monitoring
- **Before releases**: When planning Jenkins LTS releases

### Monitoring

Check the Statistics sheet for trends:
- Increase in JDK 25 adoption over time
- Plugins still on older JDK versions
- Plugins without Jenkinsfiles (may need manual checking)

## Related Files

- `README.md` - Main project documentation
- `CLAUDE.md` - Development guidelines for AI assistants
- `find-plugin-repos.sh` - Related script for broader plugin analysis
- `upload_to_sheets.py` - Related script for PR tracking
- `get-most-popular-plugins.sh` - Generates top plugin lists

## License

This project follows the same license as the parent Jenkins plugin modernization project.
