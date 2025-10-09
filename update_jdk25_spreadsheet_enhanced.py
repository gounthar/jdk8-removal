#!/usr/bin/env python3
"""
Update Google Spreadsheet with JDK 25 detection results including PR tracking.
This script reads the JSON output from check-jdk25-with-pr.sh and updates the
Java 25 Compatibility check spreadsheet with the exact columns from the existing sheet:
- Name
- Installation Count (preserved)
- Java 25 pull request (populated)
- Is merged? (populated)
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
            if "429" in str(e):  # Rate limit error
                if attempt == max_retries - 1:
                    raise
                logging.warning(f"Rate limit hit. Waiting {delay} seconds before retry {attempt + 1}/{max_retries}")
                time.sleep(delay)
                delay *= 2  # Exponential backoff
            else:
                raise
    return None

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
    print("Usage: python3 update_jdk25_spreadsheet_enhanced.py <jdk25-tracking-json-file> [spreadsheet-id-or-url]")
    print("\nExample:")
    print("  python3 update_jdk25_spreadsheet_enhanced.py reports/jdk25_tracking_with_prs_2025-10-09.json")
    print("  python3 update_jdk25_spreadsheet_enhanced.py reports/jdk25_tracking_with_prs_2025-10-09.json '1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI'")
    print("\nOr set SPREADSHEET_ID in .env file")
    sys.exit(1)

JDK25_TRACKING_FILE = sys.argv[1]

# Get spreadsheet ID from command line, environment variable, or default
SPREADSHEET_ID = None
if len(sys.argv) > 2:
    SPREADSHEET_ID = sys.argv[2]
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
    logging.info(f"Found {len(jdk25_data)} plugins in the data")
except FileNotFoundError:
    logging.exception(f"File {JDK25_TRACKING_FILE} not found.")
    sys.exit(1)
except json.JSONDecodeError:
    logging.exception(f"Error decoding {JDK25_TRACKING_FILE}.")
    sys.exit(1)

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
except Exception as e:
    logging.exception(f"Could not read existing data: {e}")
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

for i, row in enumerate(existing_data[1:], start=2):  # Start from row 2 (skip header)
    if name_col >= len(row):
        continue

    plugin_name = row[name_col].strip()
    if not plugin_name:
        continue

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
                is_merged = jdk25_entry['jdk25_pr']['is_merged']
                if is_merged:
                    row[is_merged_col] = "TRUE"
                    plugins_with_merged_pr += 1
                else:
                    row[is_merged_col] = "FALSE" if jdk25_entry['jdk25_pr']['url'] else ""

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

logging.info(f"Updated {updated_count} rows with JDK 25 PR data")
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
logging.info(f"\nSummary:")
logging.info(f"  Total plugins scanned: {total_plugins_scanned}")
logging.info(f"  Plugins with JDK 25: {plugins_with_jdk25}")
logging.info(f"  Plugins with JDK 25 PR identified: {plugins_with_pr}")
logging.info(f"  Plugins with merged JDK 25 PR: {plugins_with_merged_pr}")
logging.info(f"  Success rate: {plugins_with_pr/plugins_with_jdk25*100:.1f}% of JDK 25 plugins have PR identified" if plugins_with_jdk25 > 0 else "  No JDK 25 plugins found")
