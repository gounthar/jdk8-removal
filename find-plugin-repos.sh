#!/usr/bin/env bash

  # TODO: Adds another CSV file for all the repositories that don't have a Jenkinsfile at all...
  mkdir -p ./reports

  # Source the csv-utils.sh script
  source csv-utils.sh

  source log-utils.sh

  # Source the check-env.sh script
  source check-env.sh

  # Source the config.sh file to import the csv_file variable
  source config.sh

  # Check if the file already exists
  if [ -f "/reports/$csv_file" ]; then
      echo "$csv_file already exists. Exiting script."
      exit 0
  fi

  # This file is used as a healthcheck for the docker container.
  rm -f "$repos_retrieved_file"

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

  # Source the jenkinsfile_check.sh file
  source jenkinsfile_check.sh

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

  # Export the functions so they can be used by parallel
  export -f write_to_csv
  export -f write_to_csv_jdk11
  # Export the check_java_version_in_jenkinsfile function
  export -f check_java_version_in_jenkinsfile
  export -f check_for_jenkinsfile
  export -f check_rate_limit

  # Create a CSV file and write the header
  echo "Plugin,URL" >"$csv_file"
  echo "Plugin,URL" >"$csv_file_no_jenkinsfile"
  echo "Plugin,URL" >"$csv_file_jdk11"

  # Fetch all repositories under the jenkinsci organization
  # We use a while loop to handle pagination in the GitHub API.
  # The GitHub API returns a maximum of 100 items per page, so if there are more than 100 repositories, we need to fetch multiple pages.
  page=1
  while :; do
    # Check the rate limit before making API requests
    check_rate_limit

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

  # Step 1: Extract the header and store it
  header=$(head -n 1 "$csv_file")

  # Step 2 and 3: Skip the first line, sort the rest, and store in a temporary file
  tail -n +2 "$csv_file" | sort > temp_file.csv

  # Step 4: Write the header to the original file
  echo "$header" > "$csv_file"

  # Step 5: Append the sorted content to the original file
  cat temp_file.csv >> "$csv_file"

  # Cleanup: Remove the temporary file
  rm temp_file.csv


  # Step 1: Extract the header and store it
  header=$(head -n 1 "$csv_file_no_jenkinsfile")

  # Step 2 and 3: Skip the first line, sort the rest, and store in a temporary file
  tail -n +2 "$csv_file_no_jenkinsfile" | sort > temp_file.csv

  # Step 4: Write the header to the original file
  echo "$header" > "$csv_file_no_jenkinsfile"

  # Step 5: Append the sorted content to the original file
  cat temp_file.csv >> "$csv_file_no_jenkinsfile"

  # Cleanup: Remove the temporary file
  rm temp_file.csv

  # Step 1: Extract the header and store it
  header=$(head -n 1 "$csv_file_jdk11")

  # Step 2 and 3: Skip the first line, sort the rest, and store in a temporary file
  tail -n +2 "$csv_file_jdk11" | sort > temp_file.csv

  # Step 4: Write the header to the original file
  echo "$header" > "$csv_file_jdk11"

  # Step 5: Append the sorted content to the original file
  cat temp_file.csv >> "$csv_file_jdk11"

  # Cleanup: Remove the temporary file
  rm temp_file.csv

  # Flush changes to disk
  sync
  echo "Done!"  > "$repos_retrieved_file"
