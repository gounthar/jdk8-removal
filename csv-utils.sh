#!/usr/bin/env bash
# Source the config.sh script. This script contains the configuration variables for the CSV files.
source ./config.sh

# Function to read a CSV file and return its lines as an array.
# This function reads the CSV file line by line, discards the first line (header),
# and adds each subsequent line to an array. It then prints the array elements,
# which can be captured when calling the function.
read_csv_file() {
  # Initialize an empty array
  local lines=()
  # Open the CSV file for reading and assign it to file descriptor 3
  exec 3< "$script_dir/$csv_file_recipe_list"
  # Read and discard the first line (header) from file descriptor 3
  read -r <&3
  # Read the rest of the CSV file line by line from file descriptor 3
  while IFS=',' read -r recipe_name url commit_message maven_command <&3; do
    # Add the line to the array
    lines+=("$recipe_name,$url,$commit_message,$maven_command")
  done
  # Close file descriptor 3, which releases it for other processes to use
  exec 3<&-
  # Print the array elements, one per line
  printf '%s\n' "${lines[@]}"
}

# Function to format the repository name
# Arguments:
#   repo: The name of the repository
format_repo_name_old() {
  repo=$1
  debug "format_repo_name function called with repo: $repo"
  # Format the repository name
  formatted_repo=$(echo "$repo" | awk -F'/' '{print $2}' | tr '-' ' ' | awk '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1')
    debug "format_repo_name function will then return: $formatted_repo"
  echo "$formatted_repo"
}

format_repo_name() {
  url=$1
  # debug "format_repo_name function called with url: $url"
  # Extract the repository name from the URL
  repo=$(basename "$url" .git)
  # debug "Extracted repo: $repo"
  # Format the repository name
  formatted_repo=$(echo "$repo" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1')
  # debug "format_repo_name function will then return: $formatted_repo"
  echo "$formatted_repo"
}

# Export the read_csv_file function, making it available to subshells and other scripts that source this script
export -f read_csv_file format_repo_name
