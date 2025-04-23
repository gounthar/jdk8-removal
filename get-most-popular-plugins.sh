#!/bin/bash

  # Generate 'top-250-plugins.csv' with the top 250 plugins sorted by popularity
  jq -r '
    .plugins
    | to_entries
    | map(select(.value.popularity)) # Filter plugins with a "popularity" field
    | map({name: .key, popularity: .value.popularity})
    | sort_by(-.popularity)[:250] # Sort and limit to top 250
    | "name,popularity", (.[] | "\(.name),\(.popularity)")
  ' plugins.json > top-250-plugins.csv

  # Extract plugin names from 'top-250-plugins.csv' into 'top_plugins.txt'
  awk -F',' 'NR > 1 {print $1}' top-250-plugins.csv > top_plugins.txt

  # Generate 'plugins_with_versions.txt' with plugin names and versions
  jq -r '
    .plugins
    | to_entries
    | map("\(.key):\(.value.version // "unknown")") # Default version to "unknown" if missing
    | .[]
  ' plugins.json > plugins_with_versions.txt

  # Exit if required files are missing or empty
  [[ ! -s plugins_with_versions.txt ]] && { echo "Error: plugins_with_versions.txt is empty or missing."; exit 1; }
  [[ ! -s top-250-plugins.csv ]] && { echo "Error: top-250-plugins.csv is empty or missing."; exit 1; }

  # Create 'top_plugins_with_versions.txt' by joining files and preserving order
  awk -F',' 'NR==FNR {split($1, a, ":"); versions[a[1]]=$1; next} $1 in versions {print versions[$1]}' \
    plugins_with_versions.txt top-250-plugins.csv > top_plugins_with_versions.txt

  # Success message
  echo "Generated top_plugins_with_versions.txt sorted by popularity"