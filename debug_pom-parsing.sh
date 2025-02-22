#!/usr/bin/env bash

# Stop on errors
set -e
source config.sh

# Function to extract the Java version from a POM file
get_java_version_from_pom() {
  local pom_file=$1
  echo "Starting $pom_file"

  # Convert space-delimited items into an array
  IFS=' ' read -r -a pom_xml_java_version_xpath <<< "$pom_xml_java_version_xpath_items"

  # Check if the pom_xml_java_version_xpath array is defined
  if [ -z "${pom_xml_java_version_xpath+x}" ]; then
      echo "Error: pom_xml_java_version_xpath array is not defined" >&2
      return 1
  fi

  local java_version=""

  # Iterate over the array of XPath expressions to capture the first non-empty value
  for xpath in "${pom_xml_java_version_xpath[@]}"; do
      if java_version=$(xmllint --xpath "string($xpath)" "$pom_file" 2>/dev/null) && [ -n "$java_version" ]; then
          break
      fi
  done

  # Default to "17" if no java.version is found or if the version starts with "1."
  if [ -z "$java_version" ]; then
      java_version="17"
      echo "Didn't find java.version, using default $java_version"
  fi
  if [[ "$java_version" == 1.* ]]; then
      java_version="8"
      echo "Found java.version $java_version thanks to $xpath"
  fi

  # Round up to 8 if the version is less than 8
  if [[ "$java_version" -lt 8 ]]; then
      java_version="8"
      echo "Found java.version less than 8, rounding up to $java_version"
  fi

  echo "$java_version"
  echo "Found java.version $java_version thanks to $xpath"

  # Ensure java_version is a number, default to 17 if not
  if ! [[ "$java_version" =~ ^[0-9]+$ ]]; then
      java_version="17"
      echo "Invalid java.version, setting to default $java_version"
      echo "Found java.version $java_version thanks to invalid java version"
  fi

  echo "Ending $pom_file"
}

# Check if a version argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <pom_file>"
    exit 1
fi

# Get the POM file to check from the argument
pom_file=$1
java_version=$(get_java_version_from_pom "$pom_file")
echo "Java version: $java_version for $pom_file"
