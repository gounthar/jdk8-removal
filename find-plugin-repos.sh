#!/usr/bin/env bash

# TODO: Adds another CSV file for all the repositories that don't have a Jenkinsfile at all...

# Source the csv-utils.sh script
source csv-utils.sh

source log-utils.sh

# Check if the DEBUG_MODE environment variable is set
if [ "$DEBUG_MODE" = "true" ]; then
  # If DEBUG_MODE is set to true, print a debug message
  debug "Debug mode is on."
else
  # If DEBUG_MODE is not set to true, print an info message
  info "Debug mode is off. To turn it on, set the DEBUG_MODE environment variable to true."
fi
# set -x -o errexit -o nounset -o pipefail

# Ensure jq is installed. jq is a command-line JSON processor.
# We use it to parse the JSON response from the GitHub API.
if ! [ -x "$(command -v jq)" ]; then
  error 'jq is not installed.'
  exit 1
fi

# Ensure parallel is installed. parallel is a shell tool for executing jobs in parallel.
# We use it to process multiple repositories concurrently.
if ! [ -x "$(command -v parallel)" ]; then
  error 'parallel is not installed.'
  exit 1
fi

# Ensure GITHUB_TOKEN is set. GITHUB_TOKEN is a GitHub Personal Access Token that we use to authenticate with the GitHub API.
# You need to generate this token in your GitHub account settings and set it as an environment variable before running this script.
if [ -z "${GITHUB_TOKEN-}" ]; then
  error 'The GITHUB_TOKEN env var is not set.'
  exit 1
fi

# Function to write to the CSV file
write_to_csv() {
  repo=$1
  # Format the repository name
  formatted_repo=$(format_repo_name "$repo")
  info "Writing $formatted_repo to CSV file"
  # Write to CSV file
  echo "$formatted_repo,https://github.com/$repo" >>"$csv_file"
  # Flush changes to disk
  sync
}

# Source the config.sh file to import the csv_file variable
source config.sh
# Source the jenkinsfile_check.sh file
source jenkinsfile_check.sh

# Function to check for Jenkinsfile
# This function takes a repository name as an argument.
# It tries to fetch a Jenkinsfile from the main or master branch of the repository using the GitHub API.
# If a Jenkinsfile exists, it passes it as a string to the check_java_version_in_jenkinsfile function.
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
    info "Jenkinsfile found in $repo"
    # Check if the Java version numbers exist in the Jenkinsfile
    check_java_version_in_jenkinsfile "$jenkinsfile" "$repo"
  else
    # Format the repository name
    formatted_repo=$(format_repo_name "$repo")
    echo "$formatted_repo,https://github.com/$repo" >>"$csv_file_no_jenkinsfile"
  fi
}

# Export the functions so they can be used by parallel
export -f write_to_csv
# Export the check_java_version_in_jenkinsfile function
export -f check_java_version_in_jenkinsfile
export -f check_for_jenkinsfile

# Create a CSV file and write the header
echo "Plugin,URL" >"$csv_file"
echo "Plugin,URL" >"$csv_file_no_jenkinsfile"

# Fetch all repositories under the jenkinsci organization
# We use a while loop to handle pagination in the GitHub API.
# The GitHub API returns a maximum of 100 items per page, so if there are more than 100 repositories, we need to fetch multiple pages.
page=1
while :; do
  # Fetch a page of repositories from the GitHub API
  response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/orgs/jenkinsci/repos?per_page=100&page=$page")
  # Parse the JSON response to get the full names of the repositories
  repos=$(echo "$response" | jq -r '.[].full_name')
  # Use parallel to process each repository
  echo "$repos" | parallel check_for_jenkinsfile

  # If the response is empty, break the loop
  [ -z "$repos" ] && break

  # Increment the page number for the next iteration
  ((page++))
done
