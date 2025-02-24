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
last_plugins_without_jenkinsfile=0
last_plugins_with_java8=0
last_plugins_without_java_versions=0
last_plugins_using_jdk11=0
last_plugins_depends_on_java_8=0
last_plugins_depends_on_java_11=0

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

    # Find and count "plugins_using_jdk11" files
    jdk11_file=$(find $REPORTS_DIR -type f -name "plugins_using_jdk11_$date.csv" | head -n 1)
    if [[ -n "$jdk11_file" && -f "$jdk11_file" ]]; then
        plugins_using_jdk11=$(wc -l < "$jdk11_file")
        last_plugins_using_jdk11=$plugins_using_jdk11
    fi

    # Find and count "depends_on_java_8" files
    # Find the first file matching the pattern "depends_on_java_8_$date.txt" in the reports directory
      depends_on_java_8_file=$(find $REPORTS_DIR -type f -name "depends_on_java_8_$date.txt" | head -n 1)

      # Check if the file exists and is not empty
      if [[ -n "$depends_on_java_8_file" && -f "$depends_on_java_8_file" ]]; then
        # Validate the file content to ensure it is not empty or contains only whitespace
        if ! grep -q "^[[:space:]]*$" "$depends_on_java_8_file"; then
          # Count the number of lines in the file and update the count of plugins depending on Java 8
          plugins_depends_on_java_8=$(wc -l < "$depends_on_java_8_file")
          last_plugins_depends_on_java_8=$plugins_depends_on_java_8
        else
          # Print a warning if the file is empty or contains invalid content
          echo "Warning: Empty or invalid content in $depends_on_java_8_file"
        fi
      fi

    # Find and count "depends_on_java_11" files
    depends_on_java_11_file=$(find $REPORTS_DIR -type f -name "depends_on_java_11_$date.txt" | head -n 1)

    # Check if the file exists and is not empty
    if [[ -n "$depends_on_java_11_file" && -f "$depends_on_java_11_file" ]]; then
      # Validate the file content to ensure it is not empty or contains only whitespace
      if ! grep -q "^[[:space:]]*$" "$depends_on_java_11_file"; then
        # Count the number of lines in the file and update the count of plugins depending on Java 11
        plugins_depends_on_java_11=$(wc -l < "$depends_on_java_11_file")
        last_plugins_depends_on_java_11=$plugins_depends_on_java_11
      else
        # Print a warning if the file is empty or contains invalid content
        echo "Warning: Empty or invalid content in $depends_on_java_11_file"
      fi
    fi

    # Append the results to the output file
    echo "$date,$plugins_without_jenkinsfile,$plugins_with_java8,$plugins_without_java_versions,$plugins_using_jdk11,$plugins_depends_on_java_8,$plugins_depends_on_java_11" >> $OUTPUT_FILE
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
    IFS=',' read -r date plugins_without_jenkinsfile plugins_with_java8 plugins_without_java_versions plugins_using_jdk11 plugins_depends_on_java_8 plugins_depends_on_java_11 <<< "${csv_lines[i]}"

    if [[ $plugins_without_jenkinsfile -eq 0 ]]; then
        for ((j=i+1; j<${#csv_lines[@]}; j++)); do
            IFS=',' read -r _ next_plugins_without_jenkinsfile _ _ _ _ _ <<< "${csv_lines[j]}"
            if [[ $next_plugins_without_jenkinsfile -ne 0 ]]; then
                plugins_without_jenkinsfile=$next_plugins_without_jenkinsfile
                break
            fi
        done
    fi

    if [[ $plugins_with_java8 -eq 0 ]]; then
        for ((j=i+1; j<${#csv_lines[@]}; j++)); do
            IFS=',' read -r _ _ next_plugins_with_java8 _ _ _ _ <<< "${csv_lines[j]}"
            if [[ $next_plugins_with_java8 -ne 0 ]]; then
                plugins_with_java8=$next_plugins_with_java8
                break
            fi
        done
    fi

    if [[ $plugins_without_java_versions -eq 0 ]]; then
        for ((j=i+1; j<${#csv_lines[@]}; j++)); do
            IFS=',' read -r _ _ _ next_plugins_without_java_versions _ _ _ <<< "${csv_lines[j]}"
            if [[ $next_plugins_without_java_versions -ne 0 ]]; then
                plugins_without_java_versions=$next_plugins_without_java_versions
                break
            fi
        done
    fi

    if [[ $plugins_using_jdk11 -eq 0 ]]; then
        for ((j=i+1; j<${#csv_lines[@]}; j++)); do
            IFS=',' read -r _ _ _ _ next_plugins_using_jdk11 _ _ <<< "${csv_lines[j]}"
            if [[ $next_plugins_using_jdk11 -ne 0 ]]; then
                plugins_using_jdk11=$next_plugins_using_jdk11
                break
            fi
        done
    fi

    if [[ $plugins_depends_on_java_8 -eq 0 ]]; then
        for ((j=i+1; j<${#csv_lines[@]}; j++)); do
            IFS=',' read -r _ _ _ _ _ next_plugins_depends_on_java_8 _ <<< "${csv_lines[j]}"
            if [[ $next_plugins_depends_on_java_8 -ne 0 ]]; then
                plugins_depends_on_java_8=$next_plugins_depends_on_java_8
                break
            fi
        done
    fi

    if [[ $plugins_depends_on_java_11 -eq 0 ]]; then
        for ((j=i+1; j<${#csv_lines[@]}; j++)); do
            IFS=',' read -r _ _ _ _ _ _ next_plugins_depends_on_java_11 <<< "${csv_lines[j]}"
            if [[ $next_plugins_depends_on_java_11 -ne 0 ]]; then
                plugins_depends_on_java_11=$next_plugins_depends_on_java_11
                break
            fi
        done
    fi

    csv_lines[i]="$date,$plugins_without_jenkinsfile,$plugins_with_java8,$plugins_without_java_versions,$plugins_using_jdk11,$plugins_depends_on_java_8,$plugins_depends_on_java_11"
done

# Create a backup of the original CSV file
cp "$OUTPUT_FILE" "${OUTPUT_FILE}.bak"

# Write the updated lines back to the CSV file
printf "%s\n" "${csv_lines[@]}" > "$OUTPUT_FILE"

echo "Processing complete. Results saved to $OUTPUT_FILE"
