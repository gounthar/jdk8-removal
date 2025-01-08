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

# Initialize output file with opening brace
echo "" > $output_file

# Create an associative array to store plugin data
declare -A plugin_map

# Parse JSON file and populate the associative array
while IFS= read -r line; do
  scm=$(echo "$line" | jq -r '.scm')
  name=$(echo "$line" | jq -r '.name')
  version=$(echo "$line" | jq -r '.lastVersion')
  plugin_map["$scm"]="$name:$version"
done < <(jq -c '.plugins[] | {scm: .scm, name: .name, lastVersion: .versions[0].lastVersion}' "$json_file")

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
  repo_url="${repo_url#"${repo_url%%[! ]*}"}"
  repo_url="${repo_url%"${repo_url##*[! ]}"}"

  # Lookup plugin name and version in the associative array
  if [[ -n "${plugin_map[$repo_url]}" ]]; then
    echo "${plugin_map[$repo_url]}" >> $output_file
  fi

done < "$csv_file"

# After the loop, remove the last comma and add closing brace
if [[ ! -s $output_file ]]; then
  echo "Error: No plugins were processed" >&2
  echo "{}" > $output_file
  exit 1
fi

if ! sed -i '$ s/,$/\n}/' $output_file 2>/dev/null; then
  echo "Error: Failed to finalize output file" >&2
  exit 1
fi

# Validate final JSON
if ! jq empty $output_file > /dev/null 2>&1; then
  echo "Error: Generated invalid JSON" >&2
  exit 1
fi

echo "Successfully generated plugins file: $output_file" >&2
