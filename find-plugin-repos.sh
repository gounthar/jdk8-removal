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

# Create CSV files and write headers
echo "Plugin,URL" >"$csv_file"
echo "Plugin,URL" >"$csv_file_no_jenkinsfile"
echo "Plugin,URL" >"$csv_file_jdk11"

# Function to check the rate limit status
  check_rate_limit() {
    rate_limit_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/rate_limit")
    remaining=$(echo "$rate_limit_response" | jq '.resources.graphql.remaining')
    reset=$(echo "$rate_limit_response" | jq '.resources.graphql.reset')

    if [ "$remaining" -eq 0 ]; then
      current_time=$(date +%s)
      wait_time=$((reset - current_time))
      end_time=$(date -d "@$reset" +"%H:%M")
      echo "API rate limit exceeded for GraphQL. Please wait $wait_time seconds before retrying. Come back at $end_time."

      # Initialize progress bar
      start_time=$(date +%s)
      while [ $((current_time + wait_time)) -gt $(date +%s) ]; do
        elapsed_time=$(( $(date +%s) - start_time ))
        progress=$(( 100 * elapsed_time / wait_time ))
        printf "\rProgress: [%-50s] %d%%" $(printf "%0.s#" $(seq 1 $(( progress / 2 )))) $progress
        sleep 1
      done
      echo -e "\nWait time completed. Resuming..."
    fi
  }

  # Function to check for Jenkinsfile
  # This function takes a repository name as an argument.
  # It tries to fetch a Jenkinsfile from the default branch of the repository using the GitHub API.
  # If a Jenkinsfile exists, it passes it as a string to the check_java_version_in_jenkinsfile function.
  check_for_jenkinsfile() {
    repo=$1
    if [ -z "$repo" ]; then
      error "Repository name is empty. Skipping."
      return 1
    fi

    # Check the rate limit before making API requests
    check_rate_limit

    default_branch=$(gh repo view "$repo" --json defaultBranchRef --jq '.defaultBranchRef.name')
    if [ -z "$default_branch" ]; then
      error "Failed to retrieve default branch for $repo. Skipping repository."
      return 1
    fi

    # Try to fetch Jenkinsfile from the default branch using the resolved variable
    response=$(curl -s -L -w "\n%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "https://raw.githubusercontent.com/$repo/$default_branch/Jenkinsfile")
    http_code=$(echo "$response" | tail -n1)
    jenkinsfile=$(echo "$response" | sed '$d')

    # Check the HTTP status code
    if [ "$http_code" -eq 200 ]; then
      info "Jenkinsfile found in $repo"
      # Check if the Java version numbers exist in the Jenkinsfile
      check_java_version_in_jenkinsfile "$jenkinsfile" "$repo"
    elif [ "$http_code" -eq 404 ]; then
      # Format the repository name
      formatted_repo=$(format_repo_name "$repo")
      echo "$formatted_repo,https://github.com/$repo" >>"$csv_file_no_jenkinsfile"
    else
      error "Failed to fetch Jenkinsfile for $repo. HTTP status code: $http_code"
    fi

    # Add a delay to avoid hitting the rate limit
    sleep "$RATE_LIMIT_DELAY"
  }


# Export the functions so they can be used by parallel
export -f write_to_csv
export -f write_to_csv_jdk11
export -f check_java_version_in_jenkinsfile
export -f check_for_jenkinsfile
export -f check_rate_limit
export -f download_and_transform_pom
export -f get_java_version_from_pom
export -f get_jenkins_core_version_from_pom
export -f get_jenkins_parent_pom_version_from_pom

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
