#!/bin/bash
set -euo pipefail
# This script processes plugin data from 'plugins.json' to generate a list of the top 250 plugins
# sorted by popularity, along with their versions. The output is saved in 'top_plugins_with_versions.txt'.

# Generate 'top-250-plugins.csv' with the top 250 plugins sorted by popularity
# The CSV contains two columns: plugin name and popularity
# Ensure the source data file exists
if [[ ! -f plugins.json ]]; then
  echo "Error: plugins.json not found."
  exit 1
fi

jq -r '
  .plugins
  | to_entries
  | map(select(.value.popularity)) # Filter plugins with a "popularity" field
  | map({name: .key, popularity: .value.popularity}) # Extract plugin name and popularity
  | sort_by(-.popularity)[:250] # Sort by popularity in descending order and limit to top 250
  | "name,popularity", (.[] | "\(.name),\(.popularity)") # Format as CSV
' plugins.json > top-250-plugins.csv
if [ $? -ne 0 ]; then
  echo "Error: jq command failed."
  exit 1
fi

# Extract plugin names from 'top-250-plugins.csv' into 'top_plugins.txt'
# This file contains only the names of the top 250 plugins
awk -F',' 'NR > 1 {print $1}' top-250-plugins.csv > top_plugins.txt

# Generate 'plugins_with_versions.txt' with plugin names and their versions
# Each line is formatted as "plugin-name:version". If the version is missing, it defaults to "unknown".
jq -r '
  .plugins
  | to_entries
  | map("\(.key):\(.value.version // "unknown")") # Format as "plugin-name:version"
  | .[]
' plugins.json > plugins_with_versions.txt
  if [ $? -ne 0 ]; then
    echo "Error: jq command failed."
    exit 1
  fi

# Check if 'plugins_with_versions.txt' is non-empty
# Exit with an error message if the file is empty or missing
[[ ! -s plugins_with_versions.txt ]] && { echo "Error: plugins_with_versions.txt is empty or missing."; exit 1; }

# Check if 'top-250-plugins.csv' is non-empty
# Exit with an error message if the file is empty or missing
[[ ! -s top-250-plugins.csv ]] && { echo "Error: top-250-plugins.csv is empty or missing."; exit 1; }

# Create 'top_plugins_with_versions.txt' by joining 'plugins_with_versions.txt' and 'top-250-plugins.csv'
# The output file contains plugins sorted by popularity with their versions appended
awk -F',' 'NR==FNR {split($1, a, ":"); versions[a[1]]=$1; next} $1 in versions {print versions[$1]}' \
  plugins_with_versions.txt top-250-plugins.csv > top_plugins_with_versions.txt
# Verify the merged output
[[ ! -s top_plugins_with_versions.txt ]] && { echo "Error: top_plugins_with_versions.txt is empty or missing."; exit 1; }

# Print a success message indicating the output file has been generated
echo "Generated top_plugins_with_versions.txt sorted by popularity. Total plugins: $(wc -l < top_plugins_with_versions.txt)"
