#!/bin/bash

# Source the config.sh script to get the csv_file variable
source /scripts/config.sh

# Check if the file exists
if [ -f "/scripts/$repos_retrieved_file" ]; then
    exit 0
else
    exit 1
fi
