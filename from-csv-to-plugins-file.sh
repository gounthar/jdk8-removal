#!/bin/bash

# Path to the CSV file
csv_file="reports/repos_without_jenkinsfile_2025-01-07.csv"

# Path to the JSON file
json_file="plugins.json"

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
    echo "\"$plugin_name\":\"$version\""
  fi
done < "$csv_file"
