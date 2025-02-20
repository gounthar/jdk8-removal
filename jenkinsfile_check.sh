#!/usr/bin/env bash

 # Check if the csv_file_jdk11 variable is set
 if [ -z "$csv_file_jdk11" ]; then
   echo "Error: csv_file_jdk11 is not set"
   exit 1
 fi

 # Check if the csv_file variable is set
 if [ -z "$csv_file" ]; then
   echo "Error: csv_file is not set"
   exit 1
 fi

 # Function to write to JDK11 CSV file
 # Arguments:
 #   $1 - The repository name
 write_to_csv_jdk11() {
   repo=$1
   formatted_repo=$(format_repo_name "$repo")
   info "Writing $formatted_repo to JDK11 CSV file"
   echo "$formatted_repo,https://github.com/$repo" >>"$csv_file_jdk11"
   sync
 }

 # Function to write to CSV file for no Java or Java 8 version
 # Arguments:
 #   $1 - The repository name
 write_to_csv() {
   repo=$1
   formatted_repo=$(format_repo_name "$repo")
   info "Writing $formatted_repo to CSV file"
   echo "$formatted_repo,https://github.com/$repo" >>"$csv_file"
   sync
 }

 # Function to check for Java versions in Jenkinsfile
 # Arguments:
 #   $1 - The Jenkinsfile content
 #   $2 - The repository name
 # Behavior:
 #   - If the Jenkinsfile contains '11' and not '17' or '21', it writes to the JDK11 CSV file.
 #   - If the Jenkinsfile does not contain '11', '17', or '21', it writes to the CSV file for no Java version.
 check_java_version_in_jenkinsfile() {
   jenkinsfile=$1
   repo=$2
   if [[ "$jenkinsfile" != "404: Not Found"* ]] && [[ "$jenkinsfile" == *"buildPlugin("* ]]; then
     # Log Jenkinsfile content for debugging
     echo "Checking Jenkinsfile for $repo:"
     echo "$jenkinsfile" | grep -A 2 -B 2 "jdk"

     # More specific pattern for JDK11
     if grep -iE 'jdk.*11|java.*11|version.*11' <<< "$jenkinsfile"; then
       echo "JDK 11 was found in the Jenkinsfile for $repo"
       write_to_csv_jdk11 "$repo"
     elif ! grep -iE 'jdk.*1[1789]|java.*1[1789]|version.*1[1789]|jdk.*21|java.*21|version.*21' <<< "$jenkinsfile"; then
       echo "No Java version found in the Jenkinsfile for $repo"
       write_to_csv "$repo"
     fi
   fi
 }

# Function to extract Java version from pom.xml
# Function to extract Java version from pom.xml
# Ensure that config.sh is sourced to define the pom_xml_java_version_xpath array
get_java_version_from_pom() {
    local pom_file=$1

    # Check if the pom_xml_java_version_xpath array is defined
    if [ -z "${pom_xml_java_version_xpath+x}" ]; then
        echo "Error: pom_xml_java_version_xpath array is not defined" >&2
        return 1
    fi

    # Use a subshell to localize the trap
    (
        local temp_file
        temp_file=$(mktemp)

        # Ensure the temporary file is removed if the function exits unexpectedly
        trap 'rm -f "$temp_file"' EXIT

        # Transform the XML file to remove namespaces
        if ! xsltproc remove-namespaces.xsl "$pom_file" > "$temp_file" 2>/dev/null; then
            rm -f "$temp_file"
            echo "Error: Failed to transform XML file" >&2
            exit 1
        fi

        local java_version=""
        # Iterate over the array of XPath expressions to capture the first non-empty value
        for xpath in "${pom_xml_java_version_xpath[@]}"; do
            if java_version=$(xmllint --xpath "string($xpath)" "$temp_file" 2>/dev/null) && [ -n "$java_version" ]; then
                break
            fi
        done

        # Explicitly remove the temporary file
        rm -f "$temp_file"
        echo "$java_version"
    )
}

# Function to extract Jenkins core version from pom.xml
get_jenkins_core_version_from_pom() {
    local pom_file=$1
    local temp_file
    temp_file=$(mktemp)

    # Ensure the temporary file is removed if the function exits unexpectedly
    trap 'rm -f "$temp_file"' EXIT

    if ! xsltproc remove-namespaces.xsl "$pom_file" > "$temp_file" 2>/dev/null; then
        rm -f "$temp_file"
        echo "Error: Failed to transform XML file" >&2
        return 1
    fi

    local jenkins_core_version=""
    for xpath in "${pom_xml_jenkins_core_version_xpath[@]}"; do
        if jenkins_core_version=$(xmllint --xpath "string($xpath)" "$temp_file" 2>/dev/null) && [ -n "$jenkins_core_version" ]; then
            break
        fi
    done

    rm -f "$temp_file"
    echo "$jenkins_core_version"
}
