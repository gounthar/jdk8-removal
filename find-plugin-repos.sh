#!/usr/bin/env bash

# Enable debug mode if DEBUG_MODE is set to true
if [ "$DEBUG_MODE" = "true" ]; then
  set -x
fi

# Source the required scripts
source csv-utils.sh
source log-utils.sh
source check-env.sh
source config.sh
source jenkinsfile_check.sh

# Export the functions so they can be used by parallel
export -f write_to_csv
export -f write_to_csv_jdk11
export -f check_java_version_in_jenkinsfile
export -f check_for_jenkinsfile
export -f check_rate_limit
export -f get_java_version_from_pom
export -f get_jenkins_core_version_from_pom
export -f get_jenkins_parent_pom_version_from_pom

# Create CSV files and write headers
echo "Plugin,URL" >"$csv_file"
echo "Plugin,URL" >"$csv_file_no_jenkinsfile"
echo "Plugin,URL" >"$csv_file_jdk11"

# Fetch all repositories under the jenkinsci organization
page=1
while :; do
  echo "Fetching page $page of repositories..."
  check_rate_limit

  response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/orgs/jenkinsci/repos?per_page=100&page=$page")
  repos=$(echo "$response" | jq -r '.[].full_name')

  if [ -z "$repos" ]; then
    echo "No more repositories found. Exiting loop."
    break
  fi

  echo "Processing repositories..."
  echo "$repos" | parallel check_for_jenkinsfile
  echo "$repos" | parallel get_java_version_from_pom
  echo "$repos" | parallel get_jenkins_core_version_from_pom
  echo "$repos" | parallel get_jenkins_parent_pom_version_from_pom

  ((page++))
done

# Sort and finalize CSV files
for file in "$csv_file" "$csv_file_no_jenkinsfile" "$csv_file_jdk11"; do
  header=$(head -n 1 "$file")
  tail -n +2 "$file" | sort > temp_file.csv
  echo "$header" > "$file"
  cat temp_file.csv >> "$file"
  rm temp_file.csv
done

sync
echo "Done!" > "$repos_retrieved_file"
