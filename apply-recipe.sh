#!/usr/bin/env bash

set -x
# TODO: [ERROR] Recipe validation error in org.gounthar.jdk21-prerequisites.recipeList[0] (in file:/tmp/plugins/wsclean-plugin/wsclean-plugin/rewrite.yml): recipe 'org.openrewrite.jenkins.ModernizePluginForJava8' does not exist.

source log-utils.sh

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

# Source the config.sh file to import the csv_file variable
source config.sh

# Source the csv-utils.sh script. This script contains utility functions for working with CSV files.
source csv-utils.sh

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
  url=$1
  repo=$(basename "$url" .git)
  # Create a subdirectory in /tmp/plugins for the repository
  tmp_dir="/tmp/plugins/$repo"
  mkdir -p "$tmp_dir"
  # Print a message in green
  info "Processing $repo in $tmp_dir"
  # Check if the repository directory already exists in /tmp/plugins
  if [ -d "$tmp_dir/$repo" ]; then
    # If it does, navigate into the directory and pull the latest changes
    debug "$repo in $tmp_dir already exists, pulling latest changes"
    cd "$tmp_dir/$repo" || exit
    # Try to pull the latest changes
    if git pull; then
      # If the pull is successful, continue with the script
      info "Successfully pulled the latest changes"
    else
      # If the pull fails, print an error message and handle the error
      error "Cannot pull with rebase because there are unstaged changes. Please commit or stash them."
      # You can choose to exit the script, or you can stash the changes and try pulling again
      git stash
      if git pull; then
        info "Successfully pulled the latest changes after stashing"
      else
        error "Failed to pull the latest changes even after stashing. Exiting the script."
        exit 1
      fi
    fi
  else
    # If it doesn't, navigate into the /tmp/plugins subdirectory, clone the repository and navigate into the repository directory
    cd "$tmp_dir" || exit
    debug "Cloning $url"
    debug "New Cloning would be https://$GITHUB_TOKEN:x-oauth-basic@github.com/$repo"
    # git clone "$url"
    git clone "https://$GITHUB_TOKEN:x-oauth-basic@github.com/$repo"
    cd "$repo" || exit
  fi
  # Copy the rewrite.xml file from the script repository to the target repository
  cp "$script_dir/rewrite.yml" .
  # Does not work
  # Should try first: mvn -U org.openrewrite.maven:rewrite-maven-plugin:run \
  #  -Drewrite.recipeArtifactCoordinates=org.openrewrite.recipe:rewrite-jenkins:RELEASE \
  #  -Drewrite.activeRecipes=org.openrewrite.jenkins.ModernizePluginForJava8
  #if mvn -U org.openrewrite.maven:rewrite-maven-plugin:run -Drewrite.activeRecipes=org.gounthar.jdk21-prerequisites -Dmaven.test.skip=true; then
  # Call the function and capture the output in an array
  mapfile -t lines < <(read_csv_file)
  # Loop over the array
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
      # Print the commit message in green
      info "Commit message: $commit_message"

      # Print a message in green
      info "Committing changes"
      # Commit the changes
      git add .
      git commit -m "$commit_message"
      # Print a message in green
      info "Pushing changes"
      # Push the changes
      git push
      # Print a message in green
      info "Changes pushed"
      # Print a message in green
      info "Writing $repo to CSV file"
      # Write to CSV file
      echo "$repo,https://github.com/$repo" >>"$script_dir/$csv_file_compiles"
    else
      echo "$repo,https://github.com/$repo" >>"$script_dir/$csv_file_does_not_compile"
    fi
  done
  cd ../..
  # Print a message in green
  info "Finished processing $repo"
}

export -f apply_recipe

# Create a CSV file and write the header
echo "Plugin,URL" >"$script_dir/$csv_file_compiles"
echo "Plugin,URL" >"$script_dir/$csv_file_does_not_compile"
# Create a CSV file and write the header
echo "Recipe Name,URL,Commit Message,Maven Command" >recipes.csv

# Read the CSV file and pass each URL to the run_maven_command function
tail -n +2 "$csv_file" | cut -d ',' -f 2 | parallel apply_recipe
