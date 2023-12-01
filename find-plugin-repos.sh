#!/usr/bin/env bash

# Ensure jq is installed
if ! [ -x "$(command -v jq)" ]; then
  echo 'Error: jq is not installed.' >&2
  exit 1
fi

# Ensure parallel is installed
if ! [ -x "$(command -v parallel)" ]; then
  echo 'Error: parallel is not installed.' >&2
  exit 1
fi

# Ensure GITHUB_TOKEN is set
if [ -z "${GITHUB_TOKEN-}" ]; then
  echo 'Error: the GITHUB_TOKEN env var is not set.' >&2
  exit 1
fi

# Function to check for Java versions in Jenkinsfile
check_java_version_in_jenkinsfile() {
  jenkinsfile=$1
  repo=$2
  # Check if the jenkinsfile variable contains a valid Jenkinsfile
  if [[ "$jenkinsfile" != "404: Not Found"* ]] && [[ "$jenkinsfile" == *"buildPlugin("* ]]; then
    if echo "$jenkinsfile" | grep -q -E '11|17|21'; then
      echo "The numbers 11, 17, or 21 were found in the Jenkinsfile"
    else
      echo "The numbers 11, 17, or 21 were not found in the Jenkinsfile"
      # Write to CSV file
      echo "$repo,https://github.com/$repo" >> plugins_without_java_versions.csv
      # Flush changes to disk
      sync
    fi
  fi
}

# Function to check for Jenkinsfile
check_for_jenkinsfile() {
  repo=$1
  # Try to fetch Jenkinsfile from the main branch
  jenkinsfile=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://raw.githubusercontent.com/$repo/main/Jenkinsfile")

  # If Jenkinsfile does not exist in the main branch, try the master branch
  if [[ "$jenkinsfile" == "404: Not Found"* ]]; then
    jenkinsfile=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://raw.githubusercontent.com/$repo/master/Jenkinsfile")
  fi

  # Check if the curl command was successful
  if [[ "$jenkinsfile" != "404: Not Found"* ]]; then
    echo "Jenkinsfile found in $repo"
    # Check if the Java version numbers exist in the Jenkinsfile
    check_java_version_in_jenkinsfile "$jenkinsfile" $repo
  fi
}

export -f check_java_version_in_jenkinsfile
export -f check_for_jenkinsfile

# Create CSV file and write the header
echo "Plugin,URL" > plugins_without_java_versions.csv

# Fetch all repositories under the jenkinsci organization
page=1
while : ; do
  response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/orgs/jenkinsci/repos?per_page=100&page=$page")
  repos=$(echo "$response" | jq -r '.[].full_name')
  echo "$repos" | parallel check_for_jenkinsfile

  # If the response is empty, break the loop
  [ -z "$repos" ] && break

  ((page++))
done