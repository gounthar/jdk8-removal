#!/bin/bash

  # Generate a CSV file containing the top 250 plugins sorted by popularity
  # The output file is named 'top-250-plugins.csv' and contains two columns: name and popularity
  jq -r '
    .plugins
    | to_entries
    | map(select(.value | type == "object" and has("popularity"))) # Filter plugins with a "popularity" field
    | map({name: .key, popularity: .value.popularity}) # Extract plugin name and popularity
    | sort_by(-.popularity)[:250] # Sort by popularity in descending order and take the top 250
    | "name,popularity", # Add CSV header
      (.[] | "\(.name),\(.popularity)") # Format each plugin as "name,popularity"
  ' plugins.json > top-250-plugins.csv

  # Extract plugin names from the generated 'top-250-plugins.csv' file
  # The output file is named 'top_plugins.txt' and contains only the plugin names
  top_plugins=$(awk -F',' 'NR > 1 {print $1}' top-250-plugins.csv)

  jq -r --argjson topPlugins "$(printf '%s\n' "$top_plugins" | jq -R -s -c 'split("\n")[:-1]')" '
    .plugins
    | to_entries
    | map(select(.key as $name | $topPlugins | index($name))) # Filter plugins that are in the top 250
    | .[].key # Extract only the plugin names
  ' plugins.json > top_plugins.txt

  # Extract plugin names and their versions from 'plugins.json'
  # The output file is named 'plugins_with_versions.txt' and contains entries in the format "plugin-name:version"
  jq -r '
    .plugins
    | to_entries
    | map(select(.key as $name | $name)) # Ensure all plugins are included
    | map("\(.key):\(.value.version // "unknown")") # Format as "plugin-name:version", defaulting to "unknown" if version is missing
    | .[]
  ' plugins.json > plugins_with_versions.txt

  # Check if 'plugins_with_versions.txt' is non-empty
  # Exit with an error message if the file is empty or missing
  if [[ ! -s plugins_with_versions.txt ]]; then
    echo "Error: plugins_with_versions.txt is empty or missing."
    exit 1
  fi

  # Check if 'top-250-plugins.csv' is non-empty
  # Exit with an error message if the file is empty or missing
  if [[ ! -s top-250-plugins.csv ]]; then
    echo "Error: top-250-plugins.csv is empty or missing."
    exit 1
  fi

  # Join 'top-250-plugins.csv' and 'plugins_with_versions.txt' to create 'top_plugins_with_versions.txt'
  # The output file contains plugins sorted by popularity with their versions appended
  awk -F',' 'NR==FNR {split($1, a, ":"); versions[a[1]]=$1; next} $1 in versions {print versions[$1]}' \
    plugins_with_versions.txt top-250-plugins.csv > top_plugins_with_versions.txt

  # Print a success message indicating the output file has been generated
  echo "Generated top_plugins_with_versions.txt sorted by popularity"