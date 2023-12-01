#!/usr/bin/env bash

# Ensure jq is installed. jq is a command-line JSON processor.
# We use it to parse the JSON response from the GitHub API.
if ! [ -x "$(command -v jq)" ]; then
  echo 'Error: jq is not installed.' >&2
  exit 1
fi

# Ensure parallel is installed. parallel is a shell tool for executing jobs in parallel.
# We use it to process multiple repositories concurrently.
if ! [ -x "$(command -v parallel)" ]; then
  echo 'Error: parallel is not installed.' >&2
  exit 1
fi

# Ensure GITHUB_TOKEN is set. GITHUB_TOKEN is a GitHub Personal Access Token that we use to authenticate with the GitHub API.
# You need to generate this token in your GitHub account settings and set it as an environment variable before running this script.
if [ -z "${GITHUB_TOKEN-}" ]; then
  echo 'Error: the GITHUB_TOKEN env var is not set.' >&2
  exit 1
fi

# Function to check for Java versions in Jenkinsfile
# This function takes a Jenkinsfile as a string and a repository name as arguments.
# It checks if the Jenkinsfile contains the numbers 11, 17, or 21 (which represent Java versions).
# If these numbers do not exist, it writes the repository name and URL to a CSV file.
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
    echo "Jenkinsfile found in $repo"
    # Check if the Java version numbers exist in the Jenkinsfile
    check_java_version_in_jenkinsfile "$jenkinsfile" $repo
  fi
}

# Export the functions so they can be used by parallel
export -f check_java_version_in_jenkinsfile
export -f check_for_jenkinsfile

# Create a CSV file and write the header
echo "Plugin,URL" > plugins_without_java_versions.csv

# Fetch all repositories under the jenkinsci organization
# We use a while loop to handle pagination in the GitHub API.
# The GitHub API returns a maximum of 100 items per page, so if there are more than 100 repositories, we need to fetch multiple pages.
page=1
while : ; do
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