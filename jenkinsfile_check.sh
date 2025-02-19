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
get_java_version_from_pom() {
    local pom_file=$1
    local java_version
    java_version=$(xmllint --xpath "string(//properties/maven.compiler.source)" "$pom_file")
    if [ -z "$java_version" ]; then
        java_version=$(xmllint --xpath "string(//properties/maven.compiler.target)" "$pom_file")
    fi
    if [ -z "$java_version" ]; then
        java_version=$(xmllint --xpath "string(//plugin[artifactId='maven-compiler-plugin']/configuration/source)" "$pom_file")
    fi
    if [ -z "$java_version" ]; then
        java_version=$(xmllint --xpath "string(//plugin[artifactId='maven-compiler-plugin']/configuration/target)" "$pom_file")
    fi
    echo "$java_version"
}

# Function to extract Jenkins core version from pom.xml
get_jenkins_core_version_from_pom() {
    local pom_file=$1
    local jenkins_core_version=$(xmllint --xpath "string($pom_xml_jenkins_core_version_xpath)" "$pom_file")
    echo "$jenkins_core_version"
}
