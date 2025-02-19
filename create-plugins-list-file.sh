#!/bin/bash

# This script processes a CSV file and a JSON file to generate a list of plugins and their latest versions.
# Usage: ./create-plugins-list-file.sh <csv_file> <json_file>
# The CSV file should contain plugin names and URLs, separated by commas.
# The JSON file should contain plugin data, including names and version information.
# The output is saved in a file named "plugins.txt", listing each plugin's name and its latest version.

# Check if the correct number of arguments are passed; if not, print usage and exit.
if [ $# -ne 2 ]; then
    echo "Usage: $0 <csv_file> <json_file>"
    exit 1
fi

# Source additional scripts required for this script to function.
source csv-utils.sh  # Utility functions for processing CSV files.
source log-utils.sh  # Logging utility functions.
source check-env.sh  # Environment check functions.
source config.sh     # Configuration variables, including csv_file.

# Assign command line arguments to variables for easier reference.
csv_file=$1  # The first argument: path to the CSV file.
json_file=$2  # The second argument: path to the JSON file.

# Set default output file if not set
: "${plugins_list_output_file:=plugins.txt}"

# Remove the output file if it already exists to start fresh.
rm -f "$plugins_list_output_file"

# Function to extract the plugin name from its URL.
# Takes a single argument: the full URL of the plugin's repository.
# Outputs the last part of the URL, which is assumed to be the plugin name.
get_plugin_name() {
    local url=$1
    echo "$url" | sed -n 's#.*/\([^/]*\)$#\1#p'
}

# Function to extract Java version from pom.xml
get_java_version_from_pom() {
    local pom_file=$1
    local java_version=$(xmllint --xpath "string(//properties/maven.compiler.source)" "$pom_file")
    if [ -z "$java_version" ]; then
        java_version=$(xmllint --xpath "string(//properties/maven.compiler.target)" "$pom_file")
    fi
    if [ -z "$java_version" ]; then
        java_version=$(xmllint --xpath "string(//plugin[artifactId='maven-compiler-plugin']/configuration/source)" "$pom_file")
    fi
    if [ -z "$java_version" ]; then
        java_version=$(xmllint --xpath "string(//plugin[artifactId='maven-compiler-plugin']/configuration/target)" "$pom_file")
    fi
    echo "$java_version"
}

# Function to extract Jenkins core version from pom.xml
# Function to extract Jenkins core version from pom.xml
get_jenkins_core_version_from_pom() {
    local pom_file=$1
    local jenkins_core_version=$(xmllint --xpath "string($pom_xml_jenkins_core_version_xpath)" "$pom_file")
    echo "$jenkins_core_version"
}

# Main processing loop: reads each line from the CSV file, extracts plugin name and URL,
# finds the corresponding plugin in the JSON file, and extracts its latest version.
# The plugin name and its latest version are then written to the output file.
while IFS=, read -r name url; do
    # Extract the plugin name from the URL.
    plugin_name=$(get_plugin_name "$url")
    if [ -n "$plugin_name" ]; then
        # Query the JSON file for the plugin's GroupId, ArtifactId, and Version (GAV).
        gav=$(jq -r --arg plugin_url "$url" '.plugins[] | select(.scm == $plugin_url) | .gav' "$json_file")
        if [ -n "$gav" ]; then
            # If GAV is found, process and save the artifactId:version to the output file.
            echo "Found gav $gav for plugin $plugin_name"
            echo "$gav" | rev | cut -d':' -f1,2 | rev >> "$plugins_list_output_file"
        else
            # If GAV is not found, log the missing GAV for the plugin.
            echo "gav not found for plugin: $plugin_name with name: $name"
            # Additionally, print the plugin's JSON data for debugging.
            jq -r --arg plugin_url "$url" '.plugins[] | select(.scm == $plugin_url)' "$json_file"
        fi
    else
        # Log an error if the plugin name could not be extracted from the URL.
        echo "Plugin name not found for URL: $url"
    fi
done < "$csv_file"

# Sort the output file alphabetically
sort "$plugins_list_output_file" -o "$plugins_list_output_file"
# Final log statement indicating the script has completed processing.
echo "Processing complete. Results saved in $plugins_list_output_file"

# Process the new CSV file for plugins using JDK 11
if [ "$csv_file" == "$csv_file_jdk11" ]; then
    : "${plugins_list_jdk11_output_file:=plugins_jdk11.txt}"
    rm -f "$plugins_list_jdk11_output_file"
    while IFS=, read -r name url; do
        plugin_name=$(get_plugin_name "$url")
        if [ -n "$plugin_name" ]; then
            gav=$(jq -r --arg plugin_url "$url" '.plugins[] | select(.scm == $plugin_url) | .gav' "$json_file")
            if [ -n "$gav" ]; then
                echo "Found gav $gav for plugin $plugin_name"
                echo "$gav" | rev | cut -d':' -f1,2 | rev >> "$plugins_list_jdk11_output_file"
            else
                echo "gav not found for plugin: $plugin_name with name: $name"
                jq -r --arg plugin_url "$url" '.plugins[] | select(.scm == $plugin_url)' "$json_file"
            fi
        else
            echo "Plugin name not found for URL: $url"
        fi
    done < "$csv_file"
    sort "$plugins_list_jdk11_output_file" -o "$plugins_list_jdk11_output_file"
    echo "Processing complete. Results saved in $plugins_list_jdk11_output_file"
    cp "$plugins_list_jdk11_output_file" "$plugins_list_jdk11_main_output_file"
fi
