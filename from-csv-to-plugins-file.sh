#!/bin/bash
# Generates a plugins file ("plugin-name:plugin-version") by matching plugin
# names from a CSV file with versions from a JSON file
# Usage: ./from-csv-to-plugins-file.sh [csv_file] [json_file]

# Path to the CSV file
csv_file="${1:-reports/repos_without_jenkinsfile_2025-01-07.csv}"
# Path to the JSON file
json_file="${2:-plugins.json}"

if [[ ! -f "$csv_file" ]]; then
    echo "Error: CSV file not found: $csv_file" >&2
    exit 1
fi

if [[ ! -f "$json_file" ]]; then
    echo "Error: JSON file not found: $json_file" >&2
    exit 1
fi

# Validate JSON file
if ! jq empty "$json_file" > /dev/null 2>&1; then
  echo "Invalid JSON file: $json_file"
  exit 1
fi

# Initialize output file with opening brace
echo "" > output.txt
# Read the CSV file line by line
while IFS=, read -r plugin_name repo_url; do
  # Skip the header line if present
  if [[ "$plugin_name" == "Plugin Name" ]]; then
    continue
  fi

  # Extract the plugin name and version from the JSON data using jq
  version=$(jq -r --arg repo_url "$repo_url" '
    .versions[] | select(.scm == $repo_url) | .lastVersion' "$json_file")

  # Print the plugin name and version in the desired format
  if [[ -n "$version" ]]; then
    echo "\"$plugin_name\":\"$version\"," >> output.txt
  fi

done < "$csv_file"

# After the loop, remove the last comma and add closing brace
sed -i '$ s/,$/\n}/' output.txt
