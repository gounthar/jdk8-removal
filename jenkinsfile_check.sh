#!/usr/bin/env bash

# Function to write to JDK11 CSV file
write_to_csv_jdk11() {
  repo=$1
  formatted_repo=$(format_repo_name "$repo")
  info "Writing $formatted_repo to JDK11 CSV file"
  echo "$formatted_repo,https://github.com/$repo" >>"$csv_file_jdk11"
  sync
}

# Function to write to CSV file for no Java version
write_to_csv() {
  repo=$1
  formatted_repo=$(format_repo_name "$repo")
  info "Writing $formatted_repo to CSV file"
  echo "$formatted_repo,https://github.com/$repo" >>"$csv_file"
  sync
}

# Function to check for Java versions in Jenkinsfile
check_java_version_in_jenkinsfile() {
  jenkinsfile=$1
  repo=$2
  if [[ "$jenkinsfile" != "404: Not Found"* ]] && [[ "$jenkinsfile" == *"buildPlugin("* ]]; then
    if grep -q '11' <<< "$jenkinsfile"; then
      echo "JDK 11 was found in the Jenkinsfile"
      # Write to JDK11 CSV file
      write_to_csv_jdk11 "$repo"
    elif ! grep -q -E '11|17|21' <<< "$jenkinsfile"; then
      echo "No Java version found in the Jenkinsfile"
      # Write to CSV file for no Java version
      write_to_csv "$repo"
    fi
  fi
}
