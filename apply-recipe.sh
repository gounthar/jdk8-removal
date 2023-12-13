#!/usr/bin/env bash

set -x

# TODO: [ERROR] Recipe validation error in org.gounthar.jdk21-prerequisites.recipeList[0] (in file:/tmp/plugins/wsclean-plugin/wsclean-plugin/rewrite.yml): recipe 'org.openrewrite.jenkins.ModernizePluginForJava8' does not exist.

source log-utils.sh

# Source the csv-utils.sh script
source csv-utils.sh

# Source the config.sh file to import the csv_file variable
source config.sh

# Source the csv-utils.sh script. This script contains utility functions for working with CSV files.
source csv-utils.sh

source git-utils.sh

# Source the check-env.sh script
source check-env.sh

# Check if the CSV file exists
if ! [ -f "$csv_file" ]; then
  error "Error: The file $csv_file does not exist." >&2
  exit 1
fi

# Store the full path of the directory of the script in a variable
script_dir=$(realpath "$(dirname "$0")")
# Print the directory of the script in green
info "The script is located in $script_dir"
export script_dir

write_to_csv_file() {
  url=$1
  debug "url: $url"
  repo=$2
  csv_file=$3
  formatted_repo=$(format_repo_name "$url")
  debug "repo: $repo, repo dir: $tmp_dir/$repo"
  debug "formatted_repo: $formatted_repo"
  username=$(gh api user | jq -r '.login')
  debug "username: $username"
  echo "$formatted_repo,https://github.com/$username/$repo" >>"$script_dir/$csv_file"
}

# Function to clone a repository and set up the upstream
# This function takes three arguments: the URL of the repository, the name of the repository, and the path to a temporary directory.
#
# Args:
#   url: The URL of the repository to clone.
#   repo: The name of the repository to clone.
#   tmp_dir: The path to the temporary directory where the repository will be cloned.
#
# The function first creates the temporary directory if it does not already exist.
# It then prints an informational message about the repository it is processing.
# Finally, it calls the `pull_and_set_upstream` function to clone the repository and set up the upstream.
clone_and_setup_repo() {
  url=$1
  repo=$2
  tmp_dir=$3
  mkdir -p "$tmp_dir"
  info "Processing $repo in $tmp_dir"
  pull_and_set_upstream "$url" "$repo" "$tmp_dir"
}

# Function to run a Maven command on a repository
# This function takes five arguments: the name of the recipe, the URL of the recipe, the Maven command to run, the URL of the repository, and the name of the repository.
#
# Args:
#   recipe_name: The name of the recipe to apply.
#   recipe_url: The URL of the recipe to apply.
#   maven_command: The Maven command to run.
#   url: The URL of the repository to process.
#   repo: The name of the repository to process.
#
# The function first prints some information about the operation it is about to perform.
# It then runs the Maven command. If the command succeeds, it applies a patch and pushes the changes to the repository, and writes the repository information to a CSV file.
# If the command fails, it writes the repository information to a different CSV file.
run_maven_command() {
  # Store the arguments in variables
  recipe_name=$1
  recipe_url=$2
  maven_command=$3
  url=$4
  repo=$5
  csv_file=$6

  # Print some information about the operation
  info "Applying $recipe_name"
  info "Its URL is $recipe_url"
  info "Maven command: $maven_command"
  info "Running Maven command in $repo"

  # Get the current date in YYYY-MM-DD format
  # The `date` command is used with the `+"%Y-%m-%d"` option to format the date.
  current_date=$(date +"%Y-%m-%d")

  # Run the Maven command
  if eval $maven_command; then
    # If the command succeeds, print a success message, apply a patch, push the changes, and write to a CSV file
    info "Maven command succeeded"
    info "Will now create the diff"
    apply_patch_and_push "$url" "$repo" "$commit_message"
    write_to_csv_file "$url" "$repo" "$csv_file_compiles"
    patch_exists="false"
    # Check if the modifications.patch file exists and is not empty
    if [ -s "../modifications.patch" ]; then
      # If the file exists and is not empty, set the variable to "true"
      patch_exists="true"
    fi
    echo "$recipe_name,$current_date,$patch_exists" >>"$repo_log_file"
  else
    # If the command fails, write to a different CSV file
    write_to_csv_file "$url" "$repo" "$csv_file_does_not_compile"
  fi
}

# Function to process a CSV file
# This function reads a CSV file line by line, splits each line into an array of fields, and then runs a Maven command on a repository.
#
# The function first calls the `read_csv_file` function to read the CSV file and store the lines in an array.
# It then loops over each line in the array. For each line, it splits the line into an array of fields using the comma as the delimiter.
# It stores the first four fields in the `recipe_name`, `recipe_url`, `commit_message`, and `maven_command` variables, respectively.
# It then calls the `run_maven_command` function, passing the `recipe_name`, `recipe_url`, `maven_command`, `url`, and `repo` variables as arguments.
process_csv_file() {
  # Read the CSV file and store the lines in an array
  mapfile -t lines < <(read_csv_file)
  num_lines=${#lines[@]}
  debug "Found $num_lines recipes"

  # Now let's tackle the log creation for the current recipe
  # Create a CSV file and write the header
  repo_log_dir="$script_dir/reports/recipes"
  mkdir -p "$repo_log_dir"
  repo_log_file="$repo_log_dir/$repo.csv"
  # Check if the file exists
  if [ ! -f "$repo_log_file" ]; then
    # If the file does not exist, create it and write the header
    echo "Recipe,Date,Change" >"$repo_log_file"
  fi
  # Loop over each line in the array
  for line in "${lines[@]}"; do
    # Split the line into an array of fields using the comma as the delimiter
    IFS=',' read -r -a array <<<"$line"

    # Store the first four fields in the `recipe_name`, `recipe_url`, `commit_message`, and `maven_command` variables, respectively
    recipe_name=${array[0]}
    recipe_url=${array[1]}
    commit_message=${array[2]}
    maven_command=${array[3]//\"/}

    # Call the `run_maven_command` function, passing the `recipe_name`, `recipe_url`, `maven_command`, `url`, and `repo` variables as arguments
    info "Processing $recipe_name"
    run_maven_command "$recipe_name recipe" "$recipe_url" "$maven_command" "$url" "$repo" "$repo_log_file"
    info "Finished processing $recipe_name recipe"
  done
}

# Function to clone a repo and run the Maven command
# This function takes a URL as an argument, clones the repository at that URL,
# and then applies a recipe to it.
#
# Args:
#   url: The URL of the repository to clone and process.
#
# The function first extracts the repository name from the URL and creates a temporary directory for it.
# It then calls the `clone_and_setup_repo` function to clone the repository and set up the upstream.
# After that, it calls the `process_csv_file` function to read and process the CSV file.
# Once the processing is done, it changes the directory back to the parent directory and removes the temporary directory.
apply_recipe() {
  # Print a debug message with the first argument of the function
  debug "First argument of the apply_recipe function: $1"

  # Store the first argument in the `url` variable
  url=$1

  # Print a debug message with the URL
  debug "url: $url"

  # Extract the repository name from the URL and store it in the `repo` variable
  repo=$(basename "$url" .git)

  # Print a debug message with the repository name
  debug "repo: $repo"

  # Create a temporary directory for the repository and store its path in the `tmp_dir` variable
  tmp_dir="/tmp/plugins/$repo"

  # Print a debug message with the path of the temporary directory
  debug "tmp_dir: $tmp_dir"

  # Call the `clone_and_setup_repo` function to clone the repository and set up the upstream
  clone_and_setup_repo "$url" "$repo" "$tmp_dir"

  # Call the `process_csv_file` function to read and process the CSV file
  process_csv_file

  # Change the directory back to the parent directory
  cd ../..

  # Print an info message indicating that the processing of the repository is finished
  info "Finished processing $repo"

  # Remove the temporary directory
  rm -fr "$repo"
}

export -f apply_recipe clone_and_setup_repo process_csv_file run_maven_command write_to_csv_file

# Create a CSV file and write the header
echo "Plugin,URL" >"$script_dir/$csv_file_compiles"
echo "Plugin,URL" >"$script_dir/$csv_file_does_not_compile"
# Create a CSV file and write the header
echo "Recipe Name,URL,Commit Message,Maven Command" >"$script_dir/recipes.csv"

mkdir -p "/tmp/plugins"

# Read the CSV file and pass each URL to the run_maven_command function
# The tail -n +2 "$csv_file" command reads the CSV file specified by the csv_file variable, skipping the first line.
# This is typically used to skip the header line in a CSV file.
# The grep -v '^$' command filters out empty lines.
# The '^$' is a regular expression that matches lines that start (^) and end ($) with nothing in between, i.e., empty lines.
# The -v option inverts the match, so grep -v '^$' will output only the lines that are not empty.
# The cut -d ',' -f 2 command extracts the second field from each line.
# The -d ',' option specifies the field delimiter, which is a comma in a CSV file.
# The -f 2 option specifies the field number to extract.
# The parallel apply_recipe command runs the apply_recipe function for each line of input.
# The apply_recipe function is defined elsewhere in the script and performs the actual operations on the Git repository.
# In summary, this line of code reads a CSV file, skips the header line, filters out empty lines, extracts the second field from each line, and applies a function to each extracted field in parallel.
# tail -n +2 "$csv_file" | grep -v '^$' | cut -d ',' -f 2 | parallel apply_recipe
tail -n +2 "$csv_file" | grep -v '^$' | cut -d ',' -f 2 | while read -r url; do apply_recipe "$url"; done