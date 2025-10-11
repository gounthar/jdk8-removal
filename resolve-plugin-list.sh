#!/usr/bin/env bash

# resolve-plugin-list.sh
# Shared utility to determine which plugin list to use based on PLUGIN_LIST_MODE
# This script sets the following variables:
#   - PLUGIN_LIST_FILE: Path to the plugin list CSV file
#   - PLUGIN_LIST_NAME: Human-readable name for the plugin list
#   - REQUIRED_SCRIPT: Script needed to generate the plugin list file

# Source log-utils if available
if [ -f "log-utils.sh" ]; then
  source log-utils.sh
fi

# Determine which plugin list to use
# PLUGIN_LIST_MODE can be "top-250" (default) or "all"
PLUGIN_LIST_MODE="${PLUGIN_LIST_MODE:-top-250}"

case "$PLUGIN_LIST_MODE" in
  all)
    PLUGIN_LIST_FILE="all-plugins.csv"
    PLUGIN_LIST_NAME="all plugins"
    REQUIRED_SCRIPT="get-all-plugins.sh"
    ;;
  top-250)
    PLUGIN_LIST_FILE="top-250-plugins.csv"
    PLUGIN_LIST_NAME="top-250 plugins"
    REQUIRED_SCRIPT="get-most-popular-plugins.sh"
    ;;
  *)
    if type error >/dev/null 2>&1; then
      error "Invalid PLUGIN_LIST_MODE: $PLUGIN_LIST_MODE. Must be 'top-250' or 'all'."
    else
      echo "Error: Invalid PLUGIN_LIST_MODE: $PLUGIN_LIST_MODE. Must be 'top-250' or 'all'." >&2
    fi
    exit 1
    ;;
esac

# Export variables for use by calling scripts
export PLUGIN_LIST_FILE
export PLUGIN_LIST_NAME
export REQUIRED_SCRIPT
