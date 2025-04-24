#!/bin/bash
set -euo pipefail

# Default number of plugins to 250 if no argument is provided
NUM_PLUGINS=${1:-250}

# Check if plugins.json exists and is older than one day
if [[ ! -f plugins.json || $(find plugins.json -mtime +0) ]]; then
  echo "Downloading a fresh copy of plugins.json..."
  curl -L https://updates.jenkins.io/current/update-center.actual.json -o plugins.json
fi

# Generate 'top-<NUM_PLUGINS>-plugins.csv' with the top plugins sorted by popularity
jq -r --argjson num "$NUM_PLUGINS" '
  .plugins
  | to_entries
  | map(select(.value.popularity)) # Filter plugins with a "popularity" field
  | map({name: .key, popularity: .value.popularity}) # Extract plugin name and popularity
  | sort_by(-.popularity)[:$num] # Sort by popularity in descending order and limit to top N
  | "name,popularity", (.[] | "\(.name),\(.popularity)") # Format as CSV
' plugins.json > "top-${NUM_PLUGINS}-plugins.csv"
if [ $? -ne 0 ]; then
  echo "Error: jq command failed."
  exit 1
fi

# Extract plugin names from 'top-<NUM_PLUGINS>-plugins.csv' into 'top_plugins.txt'
awk -F',' 'NR > 1 {print $1}' "top-${NUM_PLUGINS}-plugins.csv" > top_plugins.txt

# Generate 'plugins_with_versions.txt' with plugin names and their versions
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
[[ ! -s plugins_with_versions.txt ]] && { echo "Error: plugins_with_versions.txt is empty or missing."; exit 1; }

# Check if 'top-<NUM_PLUGINS>-plugins.csv' is non-empty
[[ ! -s "top-${NUM_PLUGINS}-plugins.csv" ]] && { echo "Error: top-${NUM_PLUGINS}-plugins.csv is empty or missing."; exit 1; }

# Create 'top_plugins_with_versions.txt' by joining 'plugins_with_versions.txt' and 'top-<NUM_PLUGINS>-plugins.csv'
awk -F',' 'NR==FNR {split($1, a, ":"); versions[a[1]]=$1; next} $1 in versions {print versions[$1]}' \
  plugins_with_versions.txt "top-${NUM_PLUGINS}-plugins.csv" > top_plugins_with_versions.txt
# Verify the merged output
[[ ! -s top_plugins_with_versions.txt ]] && { echo "Error: top_plugins_with_versions.txt is empty or missing."; exit 1; }

# Print a success message indicating the output file has been generated
echo "Generated top_plugins_with_versions.txt sorted by popularity. Total plugins: $(wc -l < top_plugins_with_versions.txt)"