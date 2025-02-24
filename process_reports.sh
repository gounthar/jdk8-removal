#!/bin/bash

        # Define the directory containing the reports
        REPORTS_DIR="reports"

        # Output file to store the results
        OUTPUT_FILE="plugin_evolution.csv"

        # Initialize the output file with headers
        echo "Date,Plugins_Without_Jenkinsfile,Plugins_With_Java8,Plugins_Without_Java_Versions,Plugins_Using_JDK11,Plugins_Depends_On_Java_8,Plugins_Depends_On_Java_11" > $OUTPUT_FILE

        # Extract unique dates from filenames
        dates=$(find "$REPORTS_DIR" -type f -name "*.txt" -o -name "*.csv" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | uniq)

        # Initialize last known values
        last_plugins_without_jenkinsfile="NaN"
        last_plugins_with_java8="NaN"
        last_plugins_without_java_versions="NaN"
        last_plugins_using_jdk11="NaN"
        last_plugins_depends_on_java_8="NaN"
        last_plugins_depends_on_java_11="NaN"

        # Loop through each unique date
        for date in $dates; do
            # Initialize counts for this date
            plugins_without_jenkinsfile=$last_plugins_without_jenkinsfile
            plugins_with_java8=$last_plugins_with_java8
            plugins_without_java_versions=$last_plugins_without_java_versions
            plugins_using_jdk11=$last_plugins_using_jdk11
            plugins_depends_on_java_8=$last_plugins_depends_on_java_8
            plugins_depends_on_java_11=$last_plugins_depends_on_java_11

            # Find and count "plugins_no_jenkinsfile" files
            no_jenkinsfile_file=$(find $REPORTS_DIR -type f -name "plugins_no_jenkinsfile_$date.txt" | head -n 1)
            if [[ -n "$no_jenkinsfile_file" && -f "$no_jenkinsfile_file" ]]; then
                if ! grep -q "^[[:space:]]*$" "$no_jenkinsfile_file"; then
                    plugins_without_jenkinsfile=$(wc -l < "$no_jenkinsfile_file")
                    last_plugins_without_jenkinsfile=$plugins_without_jenkinsfile
                else
                    echo "Warning: Empty or invalid content in $no_jenkinsfile_file"
                fi
            fi

            # Find and count "plugins_old_java" files
            old_java_file=$(find $REPORTS_DIR -type f -name "plugins_old_java_$date.txt" | head -n 1)
            if [[ -n "$old_java_file" && -f "$old_java_file" ]]; then
                if ! grep -q "^[[:space:]]*$" "$old_java_file"; then
                    plugins_with_java8=$(wc -l < "$old_java_file")
                    last_plugins_with_java8=$plugins_with_java8
                else
                    echo "Warning: Empty or invalid content in $old_java_file"
                fi
            fi

            # Find and count "plugins_without_java_versions" files
            without_java_versions_file=$(find $REPORTS_DIR -type f -name "plugins_without_java_versions_$date.csv" | head -n 1)
            if [[ -n "$without_java_versions_file" && -f "$without_java_versions_file" ]]; then
                if ! grep -q "^[[:space:]]*$" "$without_java_versions_file"; then
                    plugins_without_java_versions=$(wc -l < "$without_java_versions_file")
                    last_plugins_without_java_versions=$plugins_without_java_versions
                else
                    echo "Warning: Empty or invalid content in $without_java_versions_file"
                fi
            fi

            # Find and count "plugins_using_jdk11" files
            jdk11_file=$(find $REPORTS_DIR -type f -name "plugins_using_jdk11_$date.csv" | head -n 1)
            if [[ -n "$jdk11_file" && -f "$jdk11_file" ]]; then
                if ! grep -q "^[[:space:]]*$" "$jdk11_file"; then
                    plugins_using_jdk11=$(wc -l < "$jdk11_file")
                    last_plugins_using_jdk11=$plugins_using_jdk11
                else
                    echo "Warning: Empty or invalid content in $jdk11_file"
                fi
            fi

            # Find and count "depends_on_java_8" files
            depends_on_java_8_file=$(find $REPORTS_DIR -type f -name "depends_on_java_8_$date.txt" | head -n 1)
            if [[ -n "$depends_on_java_8_file" && -f "$depends_on_java_8_file" ]]; then
                if ! grep -q "^[[:space:]]*$" "$depends_on_java_8_file"; then
                    plugins_depends_on_java_8=$(wc -l < "$depends_on_java_8_file")
                    last_plugins_depends_on_java_8=$plugins_depends_on_java_8
                else
                    echo "Warning: Empty or invalid content in $depends_on_java_8_file"
                fi
            fi

            # Find and count "depends_on_java_11" files
            depends_on_java_11_file=$(find $REPORTS_DIR -type f -name "depends_on_java_11_$date.txt" | head -n 1)
            if [[ -n "$depends_on_java_11_file" && -f "$depends_on_java_11_file" ]]; then
                if ! grep -q "^[[:space:]]*$" "$depends_on_java_11_file"; then
                    plugins_depends_on_java_11=$(wc -l < "$depends_on_java_11_file")
                    last_plugins_depends_on_java_11=$plugins_depends_on_java_11
                else
                    echo "Warning: Empty or invalid content in $depends_on_java_11_file"
                fi
            fi

            # Append the results to the output file
            echo "$date,$plugins_without_jenkinsfile,$plugins_with_java8,$plugins_without_java_versions,$plugins_using_jdk11,$plugins_depends_on_java_8,$plugins_depends_on_java_11" >> $OUTPUT_FILE
        done

        echo "Processing complete. Results saved to $OUTPUT_FILE"
