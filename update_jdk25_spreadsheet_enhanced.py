#!/usr/bin/env python3
"""
Update Google Spreadsheet with JDK 25 detection results including PR tracking.
This script reads the JSON output from check-jdk25-with-pr.sh and updates the
Java 25 Compatibility check spreadsheet with the exact columns from the existing sheet:
- Name
- Installation Count (from plugins.json or preserved from spreadsheet)
- Java 25 pull request (populated)
- Is merged? (populated)

The script maintains a cumulative list of all plugins that have ever had JDK 25:
- Updates existing rows with latest PR tracking data
- Adds NEW rows for plugins with JDK 25 that aren't in the spreadsheet yet
- Preserves historical data for plugins not in the current scan
"""

import gspread
import gspread.exceptions
from google.oauth2.service_account import Credentials
from gspread.utils import rowcol_to_a1
import json
import logging
import sys
import time
from datetime import datetime
import os
import re
from urllib.parse import urlparse

# Set up logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logging.info("Starting JDK 25 spreadsheet update script...")

def retry_with_backoff(func, max_retries=5, initial_delay=5):
    """Retry a function with exponential backoff."""
    delay = initial_delay
    for attempt in range(max_retries):
        try:
            return func()
        except gspread.exceptions.APIError as e:
            # Check for rate limit errors (429) or quota exceeded errors (403)
            error_code = getattr(e.response, 'status_code', None) if hasattr(e, 'response') else None
            if error_code in (429, 403) or "429" in str(e) or "quota" in str(e).lower():
                if attempt == max_retries - 1:
                    raise
                logging.warning(f"Rate limit hit. Waiting {delay} seconds before retry {attempt + 1}/{max_retries}")
                time.sleep(delay)
                delay *= 2  # Exponential backoff
            else:
                raise

def update_sheet_with_retry(sheet, data, range_name="A1", value_input_option="USER_ENTERED"):
    """Update a sheet with retry logic and rate limiting."""
    def update():
        sheet.update(range_name=range_name, values=data, value_input_option=value_input_option)
        time.sleep(2)  # Add delay between operations
    retry_with_backoff(update)

def format_sheet_with_retry(sheet, range_name, format_dict):
    """Format a sheet with retry logic and rate limiting."""
    def format_func():
        sheet.format(range_name, format_dict)
        time.sleep(2)  # Add delay between operations
    retry_with_backoff(format_func)

# Check command line arguments
if len(sys.argv) < 2:
    print("Usage: python3 update_jdk25_spreadsheet_enhanced.py <jdk25-tracking-json-file> [open-prs-json-file] [spreadsheet-id-or-url]")
    print("\nExample:")
    print("  python3 update_jdk25_spreadsheet_enhanced.py reports/jdk25_tracking_with_prs_2025-10-09.json")
    print("  python3 update_jdk25_spreadsheet_enhanced.py reports/jdk25_tracking_with_prs_2025-10-09.json reports/jdk25_open_prs_tracking_2025-10-10.json")
    print("  python3 update_jdk25_spreadsheet_enhanced.py reports/jdk25_tracking_with_prs_2025-10-09.json reports/jdk25_open_prs_tracking_2025-10-10.json '1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI'")
    print("\nOr set SPREADSHEET_ID in .env file")
    sys.exit(1)

JDK25_TRACKING_FILE = sys.argv[1]

# Check for optional open PRs JSON file
OPEN_PRS_FILE = None
if len(sys.argv) > 2 and sys.argv[2].endswith('.json'):
    OPEN_PRS_FILE = sys.argv[2]
    logging.info(f"Open PRs file specified: {OPEN_PRS_FILE}")

# Get spreadsheet ID from command line, environment variable, or default
SPREADSHEET_ID = None
# Adjust index based on whether open PRs file was provided
spreadsheet_arg_index = 3 if OPEN_PRS_FILE else 2

if len(sys.argv) > spreadsheet_arg_index:
    SPREADSHEET_ID = sys.argv[spreadsheet_arg_index]
    logging.info(f"Using spreadsheet ID from command line: {SPREADSHEET_ID}")
elif os.getenv('SPREADSHEET_ID'):
    SPREADSHEET_ID = os.getenv('SPREADSHEET_ID')
    logging.info(f"Using spreadsheet ID from environment: {SPREADSHEET_ID}")
elif os.getenv('JDK25_SPREADSHEET_ID'):
    SPREADSHEET_ID = os.getenv('JDK25_SPREADSHEET_ID')
    logging.info(f"Using spreadsheet ID from JDK25_SPREADSHEET_ID environment: {SPREADSHEET_ID}")

# Define the scope
scope = ["https://spreadsheets.google.com/feeds", "https://www.googleapis.com/auth/drive"]

# Get credentials filename from environment variable or use default
credentials_file = os.getenv('GOOGLE_APPLICATION_CREDENTIALS', 'google-credentials.json')

# Add your service account credentials
try:
    creds = Credentials.from_service_account_file(credentials_file, scopes=scope)
    logging.info(f"Successfully loaded service account credentials from {credentials_file}")
except FileNotFoundError:
    logging.exception(f"Service account credentials file not found: {credentials_file}")
    logging.error("Set GOOGLE_APPLICATION_CREDENTIALS environment variable or ensure google-credentials.json exists")
    sys.exit(1)

# Authorize the client
client = gspread.authorize(creds)

# Load the JDK 25 tracking JSON file
try:
    with open(JDK25_TRACKING_FILE) as f:
        jdk25_data = json.load(f)
    logging.info(f"Successfully loaded JDK 25 tracking data from {JDK25_TRACKING_FILE}")
    logging.info(f"Found {len(jdk25_data)} plugins in the current scan")
except FileNotFoundError:
    logging.exception(f"File {JDK25_TRACKING_FILE} not found.")
    sys.exit(1)
except json.JSONDecodeError:
    logging.exception(f"Error decoding {JDK25_TRACKING_FILE}.")
    sys.exit(1)

# Load and merge ALL historical tracking files to maintain cumulative data
# This ensures we don't lose plugins that drop out of the top 250
import glob
historical_files = sorted(glob.glob("reports/jdk25_tracking_with_prs_*.json"))
logging.info(f"Found {len(historical_files)} historical tracking files")

# Create a map keyed by repository to track all historical data
historical_plugins = {}
for hist_file in historical_files:
    if hist_file == JDK25_TRACKING_FILE:
        continue  # Skip current file, we already loaded it
    try:
        with open(hist_file) as f:
            hist_data = json.load(f)
        for entry in hist_data:
            repo = entry['repository']
            # Keep the entry with JDK 25 if we find one
            if entry.get('has_jdk25', False):
                # If we don't have this repo yet, or if this entry has JDK 25, store it
                if repo not in historical_plugins or not historical_plugins[repo].get('has_jdk25', False):
                    historical_plugins[repo] = entry
    except Exception as e:
        logging.warning(f"Could not load historical file {hist_file}: {e}")

logging.info(f"Loaded {len(historical_plugins)} plugins from historical data")

# Merge historical data with current data
# Priority: current data overwrites historical data for the same repository
current_repos = {entry['repository'] for entry in jdk25_data}
for repo, hist_entry in historical_plugins.items():
    if repo not in current_repos and hist_entry.get('has_jdk25', False):
        # This plugin is not in current scan but had JDK 25 historically
        jdk25_data.append(hist_entry)

logging.info(f"After merging with historical data: {len(jdk25_data)} total plugins to process")
plugins_from_history = len(jdk25_data) - len(current_repos)
if plugins_from_history > 0:
    logging.info(f"  Including {plugins_from_history} plugins from historical scans")

# Load Jenkins plugins data for installation counts
plugins_data = {}
plugins_json_file = "plugins.json"
if os.path.exists(plugins_json_file):
    try:
        with open(plugins_json_file) as f:
            plugins_registry = json.load(f)
        if 'plugins' in plugins_registry:
            for plugin_name, plugin_info in plugins_registry['plugins'].items():
                plugins_data[plugin_name.lower()] = {
                    'name': plugin_name,
                    'title': plugin_info.get('title', ''),
                    'popularity': plugin_info.get('popularity', 0)
                }
            logging.info(f"Loaded installation data for {len(plugins_data)} plugins")
    except Exception:
        logging.exception(f"Could not load {plugins_json_file}, installation counts will not be available")
else:
    logging.warning(f"{plugins_json_file} not found, installation counts will not be populated for new entries")

# Create a mapping from plugin name/repo to JDK 25 data
jdk25_map = {}
for entry in jdk25_data:
    plugin_name = entry['plugin']
    repo_name = entry['repository']
    # Store by both plugin name and repo name for flexible matching
    jdk25_map[plugin_name.lower()] = entry
    jdk25_map[repo_name.lower()] = entry
    # Also try without -plugin suffix
    if plugin_name.lower().endswith(' plugin'):
        jdk25_map[plugin_name.lower()[:-7]] = entry
    # Also try with various naming conventions
    simple_name = plugin_name.lower().replace(' ', '-')
    jdk25_map[simple_name] = entry
    jdk25_map[f"jenkinsci/{simple_name}"] = entry

logging.info(f"Created JDK 25 tracking map with {len(jdk25_map)} entries")

# Open the Google Sheet
if SPREADSHEET_ID:
    # Extract ID from URL if a URL was provided
    # Use proper URL parsing to prevent URL injection attacks
    if SPREADSHEET_ID.startswith('http://') or SPREADSHEET_ID.startswith('https://'):
        parsed = urlparse(SPREADSHEET_ID)
        # Only accept URLs from docs.google.com domain
        if parsed.netloc == 'docs.google.com':
            match = re.search(r'/d/([a-zA-Z0-9-_]+)', parsed.path)
            if match:
                SPREADSHEET_ID = match.group(1)
            else:
                logging.error(f"Could not extract spreadsheet ID from URL: {SPREADSHEET_ID}")
                sys.exit(1)
        else:
            logging.error(f"Invalid spreadsheet URL - must be from docs.google.com domain, got: {parsed.netloc}")
            sys.exit(1)

    try:
        spreadsheet = client.open_by_key(SPREADSHEET_ID)
        logging.info(f"Opened spreadsheet by ID: {SPREADSHEET_ID}")
    except gspread.exceptions.SpreadsheetNotFound:
        logging.exception(f"Spreadsheet with ID '{SPREADSHEET_ID}' not found.")
        sys.exit(1)
else:
    logging.error("No spreadsheet ID or URL provided. Please provide it as the second argument.")
    print("\nTo find your spreadsheet ID:")
    print("1. Open the spreadsheet in your browser")
    print("2. Look at the URL: https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit")
    print("3. Copy the SPREADSHEET_ID part")
    sys.exit(1)

# Get the worksheet (try different possible names)
worksheet = None
possible_sheet_names = [
    "Java 25 compatibility progress",
    "Java 25 Compatibility Progress",
    "Java 25 Compatibility progress",
    "Sheet1"
]

for sheet_name in possible_sheet_names:
    try:
        worksheet = spreadsheet.worksheet(sheet_name)
        logging.info(f"Found worksheet: '{sheet_name}'")
        break
    except gspread.exceptions.WorksheetNotFound:
        continue

if worksheet is None:
    logging.error("Could not find the worksheet. Available sheets:")
    for sheet in spreadsheet.worksheets():
        logging.error(f"  - {sheet.title}")
    sys.exit(1)

# Read existing data from the spreadsheet
try:
    existing_data = worksheet.get_all_values()
    logging.info(f"Read {len(existing_data)} rows from existing spreadsheet")
except Exception:
    logging.exception("Could not read existing data")
    sys.exit(1)

if not existing_data or len(existing_data) == 0:
    logging.error("Spreadsheet appears to be empty")
    sys.exit(1)

# Get headers
headers = existing_data[0]
logging.info(f"Existing headers: {headers}")

# Update the Installation Count header to reflect current month
current_month_year = datetime.now().strftime("%B %Y")
for i, header in enumerate(headers):
    if "installation count" in header.lower():
        headers[i] = f"Installation Count ({current_month_year})"
        logging.info(f"Updated header to: {headers[i]}")
        break

existing_data[0] = headers

# Find column indices
def find_column_index(headers, possible_names):
    for name in possible_names:
        for i, header in enumerate(headers):
            if name.lower() in header.lower():
                return i
    return -1

name_col = find_column_index(headers, ["Name", "Plugin"])
installation_count_col = find_column_index(headers, ["Installation Count", "Installations", "Install Count"])
java25_pr_col = find_column_index(headers, ["Java 25 pull request", "Java 25 PR", "JDK 25 PR", "Pull Request"])
is_merged_col = find_column_index(headers, ["Is merged", "Merged", "Is Merged?"])

logging.info(f"Column indices: Name={name_col}, Installation Count={installation_count_col}, Java 25 PR={java25_pr_col}, Is Merged={is_merged_col}")

if name_col == -1:
    logging.error("Could not find 'Name' column in the spreadsheet")
    sys.exit(1)

# Update rows with JDK 25 PR data
updated_count = 0
plugins_with_jdk25 = 0
plugins_with_pr = 0
plugins_with_merged_pr = 0
existing_plugin_names = set()  # Track plugins already in spreadsheet

for i, row in enumerate(existing_data[1:], start=2):  # Start from row 2 (skip header)
    if name_col >= len(row):
        continue

    plugin_name = row[name_col].strip()
    if not plugin_name:
        continue

    # Track this plugin as existing in the spreadsheet with ALL variations
    # to avoid duplicate detection later
    existing_plugin_names.add(plugin_name.lower())
    existing_plugin_names.add(plugin_name.lower().replace(' ', '-'))
    existing_plugin_names.add(plugin_name.lower().replace(' ', '-') + '-plugin')
    if plugin_name.lower().endswith(' plugin'):
        existing_plugin_names.add(plugin_name.lower()[:-7].strip())

    # Try to find this plugin in our JDK 25 data
    jdk25_entry = None
    # Try various formats
    lookup_keys = [
        plugin_name.lower(),
        plugin_name.lower().replace(' ', '-'),
        plugin_name.lower().replace(' ', '-') + '-plugin',
        f"jenkinsci/{plugin_name.lower().replace(' ', '-')}",
        f"jenkinsci/{plugin_name.lower().replace(' ', '-')}-plugin"
    ]

    for key in lookup_keys:
        if key in jdk25_map:
            jdk25_entry = jdk25_map[key]
            break

    if jdk25_entry:
        # Extend row if needed to accommodate all columns
        while len(row) <= max(java25_pr_col, is_merged_col):
            row.append("")

        # Only update if JDK 25 is present
        if jdk25_entry['has_jdk25']:
            plugins_with_jdk25 += 1

            # Update Java 25 PR column
            if java25_pr_col != -1 and jdk25_entry['jdk25_pr']['url']:
                pr_url = jdk25_entry['jdk25_pr']['url']
                pr_number = jdk25_entry['jdk25_pr']['number']
                # Create a hyperlink - just use the plain URL, let Google Sheets auto-detect
                # This avoids formula parsing issues with quotes
                row[java25_pr_col] = pr_url
                plugins_with_pr += 1
            elif java25_pr_col != -1:
                row[java25_pr_col] = ""

            # Update Is Merged column
            if is_merged_col != -1:
                if jdk25_entry['jdk25_pr']['url']:
                    # Use formulas to create actual boolean values
                    row[is_merged_col] = "=TRUE()" if jdk25_entry['jdk25_pr']['is_merged'] else "=FALSE()"
                    if jdk25_entry['jdk25_pr']['is_merged']:
                        plugins_with_merged_pr += 1
                else:
                    row[is_merged_col] = ""

            existing_data[i-1] = row
            updated_count += 1

            if updated_count % 25 == 0:
                logging.info(f"Updated {updated_count} rows...")
        else:
            # Clear JDK 25 PR data if JDK 25 is not present
            if java25_pr_col != -1:
                row[java25_pr_col] = ""
            if is_merged_col != -1:
                row[is_merged_col] = ""
            existing_data[i-1] = row
    else:
        # No match found - this plugin is not in our current scan
        # Clear JDK 25 PR data to avoid stale entries
        while len(row) <= max(java25_pr_col, is_merged_col):
            row.append("")
        if java25_pr_col != -1:
            row[java25_pr_col] = ""
        if is_merged_col != -1:
            row[is_merged_col] = ""
        existing_data[i-1] = row

logging.info(f"Updated {updated_count} rows with JDK 25 PR data")

# Now add NEW plugins with JDK 25 that aren't in the spreadsheet yet
new_plugins_added = 0
logging.info("Checking for new plugins with JDK 25 to add...")

for entry in jdk25_data:
    if not entry['has_jdk25']:
        continue  # Skip plugins without JDK 25

    plugin_name = entry['plugin']
    repo_name = entry['repository']

    # Check if this plugin is already in the spreadsheet
    is_existing = False
    lookup_keys = [
        plugin_name.lower(),
        repo_name.lower().replace('jenkinsci/', ''),
        plugin_name.lower().replace(' ', '-'),
        plugin_name.lower().replace(' plugin', ''),
    ]

    for key in lookup_keys:
        if key in existing_plugin_names:
            is_existing = True
            break

    if is_existing:
        continue  # Already in spreadsheet

    # This is a new plugin with JDK 25 - add it!
    new_row = [""] * max(len(headers), max(name_col, installation_count_col, java25_pr_col, is_merged_col) + 1)

    # Set plugin name
    new_row[name_col] = plugin_name

    # Set installation count if available
    if installation_count_col != -1:
        # Try to find installation count from plugins.json
        plugin_key = repo_name.replace('jenkinsci/', '').lower()
        if plugin_key in plugins_data:
            new_row[installation_count_col] = plugins_data[plugin_key]['popularity']
        else:
            new_row[installation_count_col] = 0

    # Set JDK 25 PR URL
    if java25_pr_col != -1 and entry['jdk25_pr']['url']:
        new_row[java25_pr_col] = entry['jdk25_pr']['url']

    # Set merge status
    if is_merged_col != -1:
        if entry['jdk25_pr']['url']:
            # Use formulas to create actual boolean values
            new_row[is_merged_col] = "=TRUE()" if entry['jdk25_pr']['is_merged'] else "=FALSE()"
            if entry['jdk25_pr']['is_merged']:
                plugins_with_merged_pr += 1
        else:
            new_row[is_merged_col] = ""

    existing_data.append(new_row)
    new_plugins_added += 1
    plugins_with_jdk25 += 1

    if entry['jdk25_pr']['url']:
        plugins_with_pr += 1

    # Track this plugin to avoid duplicates
    existing_plugin_names.add(plugin_name.lower())

    if new_plugins_added % 10 == 0:
        logging.info(f"Added {new_plugins_added} new plugins...")

logging.info(f"Added {new_plugins_added} new plugins with JDK 25 to spreadsheet")
logging.info(f"Writing {len(existing_data)} rows to spreadsheet...")
update_sheet_with_retry(worksheet, existing_data, "A1")

# Format the header row
logging.info("Formatting header row...")
last_cell = rowcol_to_a1(1, len(headers))
header_range = f"A1:{last_cell}"
format_sheet_with_retry(worksheet, header_range, {
    "textFormat": {
        "bold": True,
        "fontSize": 11
    },
    "backgroundColor": {
        "red": 0.2,
        "green": 0.5,
        "blue": 0.8
    },
    "horizontalAlignment": "CENTER"
})

# Freeze the header row
worksheet.freeze(rows=1)

# Update or create a statistics sheet
try:
    stats_sheet = spreadsheet.worksheet("Statistics")
    logging.info("Updating existing Statistics sheet...")
except gspread.exceptions.WorksheetNotFound:
    logging.info("Creating Statistics sheet...")
    stats_sheet = spreadsheet.add_worksheet(title="Statistics", rows=50, cols=5)

# Calculate statistics
total_plugins_scanned = len(jdk25_data)
stats_data = [
    ["Metric", "Count", "Percentage", "", ""],
    ["Total Plugins Scanned", total_plugins_scanned, "100.00%", "", ""],
    ["", "", "", "", ""],
    ["JDK 25 Statistics", "", "", "", ""],
    ["Plugins with JDK 25", plugins_with_jdk25, f"{plugins_with_jdk25/total_plugins_scanned*100:.2f}%" if total_plugins_scanned > 0 else "0.00%", "", ""],
    ["Plugins with JDK 25 PR Identified", plugins_with_pr, f"{plugins_with_pr/plugins_with_jdk25*100:.2f}%" if plugins_with_jdk25 > 0 else "0.00%", "", ""],
    ["Plugins with Merged JDK 25 PR", plugins_with_merged_pr, f"{plugins_with_merged_pr/plugins_with_jdk25*100:.2f}%" if plugins_with_jdk25 > 0 else "0.00%", "", ""],
    ["", "", "", "", ""],
    ["Last Updated", datetime.now().strftime("%Y-%m-%d %H:%M:%S"), "", "", ""]
]

update_sheet_with_retry(stats_sheet, stats_data, "A1")

# Format statistics sheet
format_sheet_with_retry(stats_sheet, "A1:C1", {
    "textFormat": {
        "bold": True
    },
    "backgroundColor": {
        "red": 0.2,
        "green": 0.5,
        "blue": 0.8
    },
    "horizontalAlignment": "CENTER"
})

logging.info("Spreadsheet update complete!")
logging.info(f"Spreadsheet URL: {spreadsheet.url}")
logging.info("\nSummary:")
logging.info(f"  Total plugins scanned: {total_plugins_scanned}")
logging.info(f"  Plugins with JDK 25: {plugins_with_jdk25}")
logging.info(f"  New plugins added to spreadsheet: {new_plugins_added}")
logging.info(f"  Existing plugins updated: {updated_count}")
logging.info(f"  Plugins with JDK 25 PR identified: {plugins_with_pr}")
logging.info(f"  Plugins with merged JDK 25 PR: {plugins_with_merged_pr}")
logging.info(f"  Success rate: {plugins_with_pr/plugins_with_jdk25*100:.1f}% of JDK 25 plugins have PR identified" if plugins_with_jdk25 > 0 else "  No JDK 25 plugins found")

# Handle open PRs data if provided
if OPEN_PRS_FILE:
    logging.info(f"\nProcessing open PRs data from {OPEN_PRS_FILE}...")
    try:
        with open(OPEN_PRS_FILE) as f:
            open_prs_data = json.load(f)
        logging.info(f"Loaded {len(open_prs_data)} plugins from open PRs file")

        # Collect all open PRs
        all_open_prs = []
        for entry in open_prs_data:
            if entry.get('has_open_jdk25_prs', False) and entry.get('open_jdk25_prs'):
                plugin_name = entry['plugin']
                repository = entry['repository']
                for pr in entry['open_jdk25_prs']:
                    # Calculate days open
                    if pr.get('createdAt'):
                        created_date = datetime.fromisoformat(pr['createdAt'].replace('Z', '+00:00'))
                        days_open = (datetime.now(created_date.tzinfo) - created_date).days
                    else:
                        days_open = 0

                    all_open_prs.append({
                        'plugin': plugin_name,
                        'repository': repository,
                        'pr_number': pr.get('number', ''),
                        'pr_url': pr.get('url', ''),
                        'title': pr.get('title', ''),
                        'is_draft': pr.get('isDraft', False),
                        'author': pr.get('author', {}).get('login', ''),
                        'created': pr.get('createdAt', '').split('T')[0] if pr.get('createdAt') else '',
                        'days_open': days_open
                    })

        logging.info(f"Found {len(all_open_prs)} open PRs that add JDK 25")

        if all_open_prs:
            # Create or update "Open JDK 25 PRs" sheet
            try:
                open_prs_sheet = spreadsheet.worksheet("Open JDK 25 PRs")
                logging.info("Updating existing 'Open JDK 25 PRs' sheet...")
                # Clear existing content except header
                open_prs_sheet.clear()
            except gspread.exceptions.WorksheetNotFound:
                logging.info("Creating 'Open JDK 25 PRs' sheet...")
                open_prs_sheet = spreadsheet.add_worksheet(title="Open JDK 25 PRs", rows=len(all_open_prs) + 50, cols=9)

            # Prepare data
            headers = ["Plugin Name", "Repository", "PR Number", "PR URL", "Title", "Is Draft?", "Author", "Created", "Days Open"]
            rows_data = [headers]

            for pr in all_open_prs:
                rows_data.append([
                    pr['plugin'],
                    pr['repository'],
                    pr['pr_number'],
                    pr['pr_url'],
                    pr['title'],
                    "Yes" if pr['is_draft'] else "No",
                    pr['author'],
                    pr['created'],
                    pr['days_open']
                ])

            # Write data
            logging.info(f"Writing {len(rows_data)} rows to 'Open JDK 25 PRs' sheet...")
            update_sheet_with_retry(open_prs_sheet, rows_data, "A1")

            # Format header
            last_col = rowcol_to_a1(1, len(headers))
            header_range = f"A1:{last_col}"
            format_sheet_with_retry(open_prs_sheet, header_range, {
                "textFormat": {
                    "bold": True,
                    "fontSize": 11
                },
                "backgroundColor": {
                    "red": 0.2,
                    "green": 0.5,
                    "blue": 0.8
                },
                "horizontalAlignment": "CENTER"
            })

            # Freeze header row
            open_prs_sheet.freeze(rows=1)

            # Apply row coloring based on draft status
            for i, pr in enumerate(all_open_prs, start=2):  # Start from row 2 (after header)
                row_range = f"A{i}:{last_col}{i}"
                if pr['is_draft']:
                    # Dark orange for draft PRs (#FF8C00 = rgb(1.0, 0.55, 0.0))
                    bg_color = {"red": 1.0, "green": 0.55, "blue": 0.0}
                else:
                    # Light orange for regular PRs (#FFD580 = rgb(1.0, 0.84, 0.5))
                    bg_color = {"red": 1.0, "green": 0.84, "blue": 0.5}

                format_sheet_with_retry(open_prs_sheet, row_range, {
                    "backgroundColor": bg_color
                })

                if i % 10 == 0:
                    logging.info(f"Formatted {i-1}/{len(all_open_prs)} rows...")

            logging.info(f"'Open JDK 25 PRs' sheet updated successfully!")
            logging.info(f"  Total open PRs: {len(all_open_prs)}")
            draft_count = sum(1 for pr in all_open_prs if pr['is_draft'])
            logging.info(f"  Draft PRs: {draft_count}")
            logging.info(f"  Regular PRs: {len(all_open_prs) - draft_count}")
        else:
            logging.info("No open JDK 25 PRs found to display")

    except FileNotFoundError:
        logging.warning(f"Open PRs file not found: {OPEN_PRS_FILE}")
    except json.JSONDecodeError:
        logging.exception(f"Error decoding {OPEN_PRS_FILE}")
    except Exception:
        logging.exception("Error processing open PRs data")
else:
    logging.info("\nNo open PRs file provided, skipping open PRs sheet update")
