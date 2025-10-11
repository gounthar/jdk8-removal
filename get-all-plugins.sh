#!/bin/bash
set -euo pipefail
# This script processes plugin data from 'plugins.json' to generate a list of ALL plugins
# sorted by popularity. The output is saved in 'all-plugins.csv'.

# Generate 'all-plugins.csv' with all plugins sorted by popularity
# The CSV contains two columns: plugin name and popularity
# Ensure the source data file exists
if [[ ! -f plugins.json ]]; then
  echo "Error: plugins.json not found."
  exit 1
fi

echo "Extracting all plugins from plugins.json..."

jq -r '
  .plugins
  | to_entries
  | map(select(.value.popularity != null))                           # Keep entries with a non-null popularity (including 0)
  | map({name: .key, popularity: .value.popularity})                 # Extract plugin name and popularity
  | sort_by(-.popularity)                                            # Sort by popularity in descending order (no limit)
  | "name,popularity", (.[] | "\(.name),\(.popularity)")             # Format as CSV
' plugins.json > all-plugins.csv

# Check if 'all-plugins.csv' is non-empty
# Exit with an error message if the file is empty or missing
[[ ! -s all-plugins.csv ]] && { echo "Error: all-plugins.csv is empty or missing."; exit 1; }

# Count plugins (subtract 1 for header)
plugin_count=$(tail -n +2 all-plugins.csv | wc -l)

if [ "$plugin_count" -le 0 ]; then
  echo "Error: No plugins extracted from plugins.json. Check input and jq filter."
  exit 1
fi

# Print a success message
echo "Generated all-plugins.csv sorted by popularity. Total plugins: $plugin_count"

# Show first 10 plugins as a sample
echo ""
echo "Sample (top 10 plugins):"
head -n 11 all-plugins.csv | column -t -s ','
