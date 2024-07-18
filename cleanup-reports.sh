#!/bin/bash

# Source required scripts
source csv-utils.sh
source log-utils.sh
source check-env.sh
source config.sh

# Function to extract the date from a report filename
extract_date_from_report() {
    echo "$1" | grep -oP '\d{4}-\d{2}-\d{2}'
}

find_previous_report() {
    local current_report=$1
    local current_date=$(extract_date_from_report "$current_report")
    local report_directory=$(dirname "$current_report")
    local file_extension="${current_report##*.}"
    local base_pattern=$(basename "$current_report" | sed -e "s/[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\..*$//" )

    if [ ! -d "$report_directory" ]; then
        debug "Report directory does not exist: $report_directory" >&2
        return
    fi

    debug "Current date: $current_date" >&2
    debug "Base pattern: $base_pattern" >&2
    debug "Looking for reports in directory: $report_directory" >&2

    local search_pattern="${base_pattern}[0-9]{4}-[0-9]{2}-[0-9]{2}.$file_extension"
    local matching_reports=$(find "$report_directory" -maxdepth 1 -type f -regextype posix-extended -regex ".*/${search_pattern}" | grep -v "$current_date" | sort)

    debug "All reports matching pattern before excluding current date:" >&2
    echo "$matching_reports" | while read line; do debug "$line"; done >&2

    if [ -z "$matching_reports" ]; then
        debug "No matching reports found." >&2
        return
    fi

    local previous_report=$(echo "$matching_reports" | tail -n 1)

    if [ -n "$previous_report" ]; then
        debug "Previous report found: $previous_report" >&2
        echo "$previous_report"
    else
        debug "No previous report found." >&2
    fi
}

# Ensure to adjust the compare_and_delete_if_identical function to handle the output correctly, focusing on capturing only the path returned by find_previous_report.


# Function to compare and delete the report if identical
compare_and_delete_if_identical() {
    local current_report=$1
    local previous_report
    previous_report=$(find_previous_report "$current_report")

    # Ensure debug mode is active
    if [ "$DEBUG_MODE" = "true" ]; then
        debug "Received previous report path: '$previous_report' for current report: '$current_report'"

        # Check if the previous report exists
        if [ -n "$previous_report" ]; then
            if [ -f "$previous_report" ]; then
                debug "Previous report file exists: '$previous_report'"
            else
                debug "Previous report file does not exist: '$previous_report'"
            fi
        else
            debug "No previous report found for '$current_report'"
        fi
    fi

    if [ -n "$previous_report" ] && [ -f "$previous_report" ]; then
        debug "Starting comparison between current report: '$current_report' and previous report: '$previous_report'."
        debug "Comparing current report: '$current_report' with previous report: '$previous_report'"

        if cmp -s "$current_report" "$previous_report"; then
            debug "Reports are identical. Proceeding to delete current report: '$current_report'"
            rm "$current_report"
            debug "Current report: '$current_report' deleted successfully."
        else
            debug "Reports differ. Keeping current report: '$current_report'"
        fi
    else
        debug "Previous report does not exist or could not be determined for current report: '$current_report'"
    fi
}

# Main execution
rm -f plugins.json
compare_and_delete_if_identical "$csv_file"

# Compare and potentially delete the report for plugins not defining a Jenkinsfile
compare_and_delete_if_identical "$csv_file_no_jenkinsfile"

# Compare and potentially delete the report for plugins not defining a Jenkinsfile
compare_and_delete_if_identical "$plugins_list_no_jenkinsfile_output_file"

# Compare and potentially delete the report for plugins still using old Java
compare_and_delete_if_identical "$plugins_list_old_java_output_file"
