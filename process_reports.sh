#!/bin/bash

        # Define the directory containing the reports
        REPORTS_DIR="reports"

        # Output file to store the results
        OUTPUT_FILE="plugin_evolution.csv"

        # Initialize the output file with headers
        echo "Date,Plugins_Without_Jenkinsfile,Plugins_With_Java8,Plugins_Without_Java_Versions" > $OUTPUT_FILE

        # Extract unique dates from filenames
        dates=$(find "$REPORTS_DIR" -type f -name "*.txt" -o -name "*.csv" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | uniq)

        # Initialize last known values
        last_plugins_without_jenkinsfile=0
        last_plugins_with_java8=0
        last_plugins_without_java_versions=0

        # Loop through each unique date
        for date in $dates; do
            # Initialize counts for this date
            plugins_without_jenkinsfile=$last_plugins_without_jenkinsfile
            plugins_with_java8=$last_plugins_with_java8
            plugins_without_java_versions=$last_plugins_without_java_versions

            # Find and count "plugins_no_jenkinsfile" files
            no_jenkinsfile_file=$(find $REPORTS_DIR -type f -name "plugins_no_jenkinsfile_$date.txt" | head -n 1)
            if [[ -n "$no_jenkinsfile_file" && -f "$no_jenkinsfile_file" ]]; then
                plugins_without_jenkinsfile=$(wc -l < "$no_jenkinsfile_file")
                last_plugins_without_jenkinsfile=$plugins_without_jenkinsfile
            fi

            # Find and count "plugins_old_java" files
            old_java_file=$(find $REPORTS_DIR -type f -name "plugins_old_java_$date.txt" | head -n 1)
            if [[ -n "$old_java_file" && -f "$old_java_file" ]]; then
                plugins_with_java8=$(wc -l < "$old_java_file")
                last_plugins_with_java8=$plugins_with_java8
            fi

            # Find and count "plugins_without_java_versions" files
            without_java_versions_file=$(find $REPORTS_DIR -type f -name "plugins_without_java_versions_$date.csv" | head -n 1)
            if [[ -n "$without_java_versions_file" && -f "$without_java_versions_file" ]]; then
                plugins_without_java_versions=$(wc -l < "$without_java_versions_file")
                last_plugins_without_java_versions=$plugins_without_java_versions
            fi

            # Append the results to the output file
            echo "$date,$plugins_without_jenkinsfile,$plugins_with_java8,$plugins_without_java_versions" >> $OUTPUT_FILE
        done

        # Check if the output CSV file exists and is non-empty
        if [[ -s "$OUTPUT_FILE" ]]; then
          # Read the CSV file into an array
          mapfile -t csv_lines < "$OUTPUT_FILE"
        else
          echo "Error: $OUTPUT_FILE does not exist or is empty."
          exit 1
        fi

        # Replace zeroes with the next non-zero value
        for ((i=1; i<${#csv_lines[@]}; i++)); do
            IFS=',' read -r date plugins_without_jenkinsfile plugins_with_java8 plugins_without_java_versions <<< "${csv_lines[i]}"

            if [[ $plugins_without_jenkinsfile -eq 0 ]]; then
                for ((j=i+1; j<${#csv_lines[@]}; j++)); do
                    IFS=',' read -r _ next_plugins_without_jenkinsfile _ _ <<< "${csv_lines[j]}"
                    if [[ $next_plugins_without_jenkinsfile -ne 0 ]]; then
                        plugins_without_jenkinsfile=$next_plugins_without_jenkinsfile
                        break
                    fi
                done
            fi

            if [[ $plugins_with_java8 -eq 0 ]]; then
                for ((j=i+1; j<${#csv_lines[@]}; j++)); do
                    IFS=',' read -r _ _ next_plugins_with_java8 _ <<< "${csv_lines[j]}"
                    if [[ $next_plugins_with_java8 -ne 0 ]]; then
                        plugins_with_java8=$next_plugins_with_java8
                        break
                    fi
                done
            fi

            if [[ $plugins_without_java_versions -eq 0 ]]; then
                for ((j=i+1; j<${#csv_lines[@]}; j++)); do
                    IFS=',' read -r _ _ _ next_plugins_without_java_versions <<< "${csv_lines[j]}"
                    if [[ $next_plugins_without_java_versions -ne 0 ]]; then
                        plugins_without_java_versions=$next_plugins_without_java_versions
                        break
                    fi
                done
            fi

            csv_lines[i]="$date,$plugins_without_jenkinsfile,$plugins_with_java8,$plugins_without_java_versions"
        done

        # Create a backup of the original CSV file
        cp "$OUTPUT_FILE" "${OUTPUT_FILE}.bak"

        # Write the updated lines back to the CSV file
        printf "%s\n" "${csv_lines[@]}" > "$OUTPUT_FILE"

        echo "Processing complete. Results saved to $OUTPUT_FILE"
