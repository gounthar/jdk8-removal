#!/usr/bin/env bash
# jenkinsfile_check.sh

# Function to check for Java versions in Jenkinsfile
# This function takes a Jenkinsfile as a string and a repository name as arguments.
# It checks if the Jenkinsfile contains the numbers 11, 17, or 21 (which represent Java versions).
# If these numbers do not exist, it writes the repository name and URL to a CSV file.
check_java_version_in_jenkinsfile() {
  jenkinsfile=$1
  repo=$2
  # Check if the jenkinsfile variable contains a valid Jenkinsfile
  if [[ "$jenkinsfile" != "404: Not Found"* ]] && [[ "$jenkinsfile" == *"buildPlugin("* ]]; then
    if grep -q -E '11|17|21' <<< "$jenkinsfile"; then
      echo "The numbers 11, 17, or 21 were found in the Jenkinsfile"
    else
      echo "The numbers 11, 17, or 21 were not found in the Jenkinsfile"
      # Write to CSV file
      write_to_csv "$repo"
    fi
  fi
}
