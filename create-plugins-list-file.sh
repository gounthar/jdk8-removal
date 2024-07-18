#!/bin/bash

# This script processes a CSV file and a JSON file to generate a list of plugins and their latest versions.
# Usage: ./create-plugins-list-file.sh <csv_file> <json_file>
# The CSV file should contain plugin names and URLs, separated by commas.
# The JSON file should contain plugin data, including names and version information.
# The output is saved in a file named "plugins.txt", listing each plugin's name and its latest version.

if [ $# -ne 2 ]; then
    echo "Usage: $0 <csv_file> <json_file>"
    exit 1
fi

csv_file=$1  # The first argument: path to the CSV file.
json_file=$2  # The second argument: path to the JSON file.
output_file="plugins.txt"  # The output file where the results will be saved.
rm -f "$output_file"  # Remove the output file if it already exists.

#set -x  # Enable debugging to show commands and their arguments as they are executed.

# Function to extract the plugin name from its URL.
# Takes a single argument: the full URL of the plugin's repository.
# Outputs the last part of the URL, which is assumed to be the plugin name.
get_plugin_name() {
    local url=$1
    echo "$url" | sed -n 's#.*/\([^/]*\)$#\1#p'
}

# Main loop to process each line in the CSV file.
# Reads the CSV file line by line, extracting the plugin name and URL.
# Uses the extracted plugin name to find the corresponding plugin in the JSON file and extract its latest version.
# Writes the plugin name and its latest version to the output file.
while IFS=, read -r name url; do
    # Check if the URL contains "plugin"

        plugin_name=$(get_plugin_name "$url")
        if [ -n "$plugin_name" ]; then
            gav=$(jq -r --arg plugin_url "$url" '.plugins[] | select(.scm == $plugin_url) | .gav' "$json_file")
            if [ -n "$gav" ]; then
                # Process the plugin as before
                echo "Found gav $gav for plugin $plugin_name"
                echo "$gav"| rev | cut -d':' -f1,2 | rev >> "$output_file"
                else
                    echo "gav not found for plugin: $plugin_name"
                    jq -r --arg plugin_url "$url" '.plugins[] | select(.scm == $plugin_url)' "$json_file"
            fi
            else
                echo "Plugin name not found for URL: $url"
        fi

done < "$csv_file"

echo "Processing complete. Results saved in $output_file"
