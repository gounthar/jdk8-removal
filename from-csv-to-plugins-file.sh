#!/usr/bin/env bash
# Input formats:
# CSV: "Plugin Name,Repository URL"
# JSON: { "versions": [{ "scm": "repo_url", "lastVersion": "version" }] }
#
# Output format:
# "plugin-name": "version"
#
# Exit codes:
# 0: Success
# 1: Input file not found or invalid JSON
# Usage: ./from-csv-to-plugins-file.sh [csv_file] [json_file] [output_file]

# Source additional scripts required for this script to function.
source csv-utils.sh  # Utility functions for processing CSV files.
source log-utils.sh  # Logging utility functions.
source check-env.sh  # Environment check functions.
source config.sh     # Configuration variables, including csv_file.

# Path to the CSV file
csv_file="${1:-reports/repos_without_jenkinsfile_2025-01-07.csv}"
# Path to the JSON file
json_file="${2:-plugins.json}"

if [[ ! -f "$csv_file" ]]; then
    echo "Error: CSV file not found: $csv_file" >&2
    exit 1
fi
echo "I will use $csv_file as input file"

if [[ ! -f "$json_file" ]]; then
    echo "Error: JSON file not found: $json_file" >&2
    exit 1
fi
echo "I will use $json_file as second input file"

# Default output file
output_file="${3:-plugins-output.txt}"
echo "I will use $output_file as output file"

# Error file
error_file="${4:-plugins-rejected.txt}"
echo "I will use $error_file as error file"
echo -n "" > "$error_file"

# Cleanup function
cleanup() {
  if [[ $? -ne 0 && -f "$output_file" ]]; then
    rm -f "$output_file"
  fi
}

# Register cleanup
trap cleanup EXIT

# Validate JSON file
if ! error=$(jq empty "$json_file" 2>&1); then
  echo "Invalid JSON file: $json_file - $error" >&2
  exit 1
fi

# Initialize output file
echo -n "" > $output_file

# Create associative arrays to store plugin data
declare -A plugin_name_map
declare -A plugin_version_map

# Parse JSON file and populate the associative arrays
while IFS= read -r line; do
  scm=$(echo "$line" | jq -r '.scm')
  name=$(echo "$line" | jq -r '.name')
  version=$(echo "$line" | jq -r '.lastVersion')
  # echo "$line"
  plugin_name_map["$scm"]="$name"
  plugin_version_map["$scm"]="$version"
done < <(jq -c '.plugins[] | {scm: .scm, name: .name, lastVersion: .version}' "$json_file")

# Output the contents of array1
# echo "Contents of plugin_version_map:"
# for key in "${!plugin_version_map[@]}"; do
  # echo "$key: ${plugin_version_map[$key]}"
# done

# Output the contents of array2
# echo "Contents of plugin_name_map:"
# for key in "${!plugin_name_map[@]}"; do
  # echo "$key: ${plugin_name_map[$key]}"
# done

# Read and process CSV file
line_num=0
while IFS=, read -r plugin_name repo_url remainder || [[ -n "$plugin_name" ]]; do
  ((line_num++))

  # Skip header line
  if [[ $line_num -eq 1 && "$plugin_name" == "Plugin Name" ]]; then
    continue
  fi

  # Validate line format
  if [[ -z "$plugin_name" || -z "$repo_url" || -n "$remainder" ]]; then
    echo "Error: Invalid CSV format at line $line_num" >&2
    continue
  fi

  # Trim whitespace
  plugin_name="${plugin_name#"${plugin_name%%[! ]*}"}"
  plugin_name="${plugin_name%"${plugin_name##*[! ]}"}"
  # echo "$repo_url" >> $output_file
  repo_url="${repo_url#"${repo_url%%[! ]*}"}"
  # echo "Trim lead $repo_url" >> $output_file
  repo_url="${repo_url%"${repo_url##*[! ]}"}"
  # echo "Trim suffix $repo_url" >> $output_file

  # Lookup plugin name and version in the associative arrays
if [[ -n "${plugin_name_map[$repo_url]}" && -n "${plugin_version_map[$repo_url]}" ]]; then
  echo "${plugin_name_map[$repo_url]}:${plugin_version_map[$repo_url]}" >> $output_file
else
  echo "$repo_url was not found in $json_file"
  echo "$repo_url" >> $error_file
fi

done < "$csv_file"

echo "Successfully generated plugins file: $output_file" >&2
