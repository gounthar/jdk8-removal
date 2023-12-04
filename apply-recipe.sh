#!/usr/bin/env bash

# set -x

# TODO: [ERROR] Recipe validation error in org.gounthar.jdk21-prerequisites.recipeList[0] (in file:/tmp/plugins/wsclean-plugin/wsclean-plugin/rewrite.yml): recipe 'org.openrewrite.jenkins.ModernizePluginForJava8' does not exist.

source log-utils.sh

# Source the csv-utils.sh script
source csv-utils.sh

# Ensure parallel is installed
if ! [ -x "$(command -v parallel)" ]; then
  error 'Error: parallel is not installed.' >&2
  exit 1
fi

# Ensure mvn is installed
if ! [ -x "$(command -v mvn)" ]; then
  error 'Error: mvn is not installed.' >&2
  exit 1
fi

# Ensure JAVA_HOME is set
if [ -z "${JAVA_HOME-}" ]; then
  # Print a warning message in yellow
  warning "Warning: JAVA_HOME environment variable is not set." >&2
  # Try to infer JAVA_HOME from java command path
  if command -v java >/dev/null; then
    export JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
    # Print a success message in green
    success "JAVA_HOME set to $JAVA_HOME"
  else
    # Print an error message in red
    error "Error: java command not found. Cannot set JAVA_HOME." >&2
    exit 1
  fi
fi

# Check if the GITHUB_TOKEN environment variable is set
if [ -z "${GITHUB_TOKEN-}" ]; then
  error "Error: GITHUB_TOKEN environment variable is not set." >&2
  exit 1
fi

# Source the config.sh file to import the csv_file variable
source config.sh

# Source the csv-utils.sh script. This script contains utility functions for working with CSV files.
source csv-utils.sh

source git-utils.sh

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

# Function to clone a repo and run the Maven command
apply_recipe() {
  debug "First argument of the apply_recipe function: $1"
  url=$1
  debug "url: $url"
  # This line is using the basename command to extract the repository name from the URL.
  # The basename command in Unix is often used to return the last component in a file path.
  # In this case, it's being used to remove the .git extension from the URL of the Git repository.
  # The result is stored in the repo variable.
  repo=$(basename "$url" .git)
  debug "repo: $repo"
  # Create a subdirectory in /tmp/plugins for the repository
  tmp_dir="/tmp/plugins/$repo"
  debug "tmp_dir: $tmp_dir"
  mkdir -p "$tmp_dir"
  info "Processing $repo in $tmp_dir"
  # Clone the repository
  pull_and_set_upstream "$url" "$repo" "$tmp_dir"

  # Does not work
  # Should try first: mvn -U org.openrewrite.maven:rewrite-maven-plugin:run \
  #  -Drewrite.recipeArtifactCoordinates=org.openrewrite.recipe:rewrite-jenkins:RELEASE \
  #  -Drewrite.activeRecipes=org.openrewrite.jenkins.ModernizePluginForJava8
  #if mvn -U org.openrewrite.maven:rewrite-maven-plugin:run -Drewrite.activeRecipes=org.gounthar.jdk21-prerequisites -Dmaven.test.skip=true; then
  # Call the function and capture the output in an array
  mapfile -t lines < <(read_csv_file)
  # Loop over the recipes array
  for line in "${lines[@]}"; do
    # Split the line on the comma
    IFS=',' read -r -a array <<<"$line"
    # Get the recipe name
    recipe_name=${array[0]}
    # Get the recipe URL
    recipe_url=${array[1]}
    # Get the commit message
    commit_message=${array[2]}
    # Get the Maven command and remove the double quotes
    # ${array[3]//\"/} is a parameter expansion that replaces all occurrences of " in ${array[3]} with nothing, effectively removing the double quotes.
    maven_command=${array[3]//\"/}
    # Print the recipe name in green
    info "Applying $recipe_name"
    info "Its URL is $recipe_url"
    # Print the Maven command in green
    info "Maven command: $maven_command"
    # Print a message in green
    info "Running Maven command in $repo"
    # Run the Maven command
    if eval $maven_command; then
      # Print a message in green
      info "Maven command succeeded"
      info "Will now create the diff"
      apply_patch_and_push "$url" "$repo" "$commit_message"

      info "Writing $repo to CSV file"
      # Write to CSV file
      # Format the repository name
      # It does not work for the time being, as if the function could not be found
      formatted_repo=$(format_repo_name "$url")
      # Get the GitHub username of the current user
      username=$(gh api user | jq -r '.login')
      echo "$formatted_repo,https://github.com/$username/$repo" >>"$script_dir/$csv_file_compiles"
      # echo "$repo,https://github.com/$username/$repo" >>"$script_dir/$csv_file_compiles"
    else
      echo "$formatted_repo,https://github.com/$username/$repo" >>"$script_dir/$csv_file_does_not_compile"
      # echo "$repo,https://github.com/jenkinsci/$repo" >>"$script_dir/$csv_file_does_not_compile"
    fi
  done
  cd ../..
  # Print a message in green
  info "Finished processing $repo"
  rm -fr "$repo"
}

export -f apply_recipe

# Create a CSV file and write the header
echo "Plugin,URL" >"$script_dir/$csv_file_compiles"
echo "Plugin,URL" >"$script_dir/$csv_file_does_not_compile"
# Create a CSV file and write the header
echo "Recipe Name,URL,Commit Message,Maven Command" >recipes.csv

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
tail -n +2 "$csv_file" | grep -v '^$' | cut -d ',' -f 2 | parallel apply_recipe
