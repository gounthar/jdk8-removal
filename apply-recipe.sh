#!/usr/bin/env bash

# Ensure parallel is installed
if ! [ -x "$(command -v parallel)" ]; then
  echo 'Error: parallel is not installed.' >&2
  exit 1
fi

# Ensure mvn is installed
if ! [ -x "$(command -v mvn)" ]; then
  echo 'Error: mvn is not installed.' >&2
  exit 1
fi

# Ensure JAVA_HOME is set
if [ -z "${JAVA_HOME-}" ]; then
  # Print a warning message in yellow
  echo -e "\033[0;33mWarning: JAVA_HOME environment variable is not set.\033[0m" >&2
  # Try to infer JAVA_HOME from java command path
  if command -v java > /dev/null; then
    export JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
    # Print a success message in green
    echo -e "\033[0;32mJAVA_HOME set to $JAVA_HOME\033[0m"
  else
    # Print an error message in red
    echo -e "\033[0;31mError: java command not found. Cannot set JAVA_HOME.\033[0m" >&2
    exit 1
  fi
fi

# Source the config.sh file to import the csv_file variable
source config.sh


# Check if the CSV file exists
if ! [ -f "$csv_file" ]; then
  echo "Error: The file $csv_file does not exist." >&2
  exit 1
fi

# Store the full path of the directory of the script in a variable
script_dir=$(realpath "$(dirname "$0")")
# Print the directory of the script in green
echo -e "\033[0;32mThe script is located in $script_dir\033[0m"
export script_dir


# Function to clone a repo and run the Maven command
apply_recipe() {
  url=$1
  repo=$(basename "$url" .git)
  # Create a subdirectory in /tmp/plugins for the repository
  tmp_dir="/tmp/plugins/$repo"
  mkdir -p "$tmp_dir"
  # Print a message in green
  echo -e "\033[0;32mProcessing $repo in $tmp_dir\033[0m"
  # Check if the repository directory already exists in /tmp/plugins
  if [ -d "$tmp_dir/$repo" ]; then
    # If it does, navigate into the directory and pull the latest changes
    cd "$tmp_dir/$repo" || exit
    git pull
  else
    # If it doesn't, navigate into the /tmp/plugins subdirectory, clone the repository and navigate into the repository directory
    cd "$tmp_dir" || exit
    git clone "$url"
    cd "$repo" || exit
  fi
  # Copy the rewrite.xml file from the script repository to the target repository
  cp "$script_dir/rewrite.yml" .
  if mvn -U org.openrewrite.maven:rewrite-maven-plugin:run -Drewrite.activeRecipes=org.gounthar.jdk21-prerequisites -Dmaven.test.skip=true; then
    echo "$repo,https://github.com/$repo" >> "$script_dir/$csv_file_compiles"
  else
    echo "$repo,https://github.com/$repo" >> "$script_dir/$csv_file_does_not_compile"
  fi
  cd ../..
  # Print a message in green
  echo -e "\033[0;32mFinished processing $repo\033[0m"
}

export -f apply_recipe

# Create a CSV file and write the header
echo "Plugin,URL" > "$script_dir/$csv_file_compiles"
echo "Plugin,URL" > "$script_dir/$csv_file_does_not_compile"

# Read the CSV file and pass each URL to the run_maven_command function
tail -n +2 "$csv_file" | cut -d ',' -f 2 | parallel apply_recipe