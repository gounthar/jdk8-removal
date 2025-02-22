#!/usr/bin/env bash

source config.sh

# Check if pom_xml_java_version_xpath is defined
if [ -z "${pom_xml_java_version_xpath+x}" ]; then
  echo "Error: pom_xml_java_version_xpath array is not defined"
  exit 1
fi

# Check if pom_xml_jenkins_core_version_xpath is defined
if [ -z "${pom_xml_jenkins_core_version_xpath+x}" ]; then
  echo "Error: pom_xml_jenkins_core_version_xpath array is not defined"
  exit 1
fi

# Check if pom_xml_jenkins_parent_pom_version_xpath is defined
if [ -z "${pom_xml_jenkins_parent_pom_version_xpath+x}" ]; then
  echo "Error: pom_xml_jenkins_parent_pom_version_xpath array is not defined"
  exit 1
fi


if [ ! -f 'remove-namespaces.xsl' ]; then
  echo "remove-namespaces.xsl not found. Place it in the same directory or adjust the path."
  exit 1
fi

if ! command -v xsltproc >/dev/null 2>&1; then
  echo "xsltproc is not installed. Install it before proceeding."
  exit 1
fi

# Rest of the script...
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

normalize_version() {
    local version=$1
    # Remove the dot and add trailing zeroes
    normalized_version=$(echo "$version" | sed 's/\.//g' | awk '{printf "%-6s", $0}' | tr ' ' '0')
    # Cut after 6 characters
    normalized_version=${normalized_version:0:6}
    echo "$normalized_version"
}

compare_versions() {
    local found_version=$1
    local ref_version=$2

    normalized_found_version=$(normalize_version "$found_version")
    normalized_ref_version=$(normalize_version "$ref_version")

    if [ "$normalized_found_version" -lt "$normalized_ref_version" ]; then
        echo "less"
    elif [ "$normalized_found_version" -gt "$normalized_ref_version" ]; then
        echo "greater"
    else
        echo "equal"
    fi
}

determine_jdk_version() {
    local found_version=$1

    # Reference versions
    local jdk8_last_version="4.39"
    local jdk11_first_version="4.40"
    local jdk11_last_version="4.88"
    local jdk17_first_version="4.52"
    local jdk17_required_version="5.0"

    if [ "$(compare_versions "$found_version" "$jdk8_last_version")" = "less" ] || [ "$(compare_versions "$found_version" "$jdk8_last_version")" = "equal" ]; then
        echo "8"
    elif [ "$(compare_versions "$found_version" "$jdk11_first_version")" = "greater" ] && [ "$(compare_versions "$found_version" "$jdk11_last_version")" = "less" ] || [ "$(compare_versions "$found_version" "$jdk11_last_version")" = "equal" ]; then
        echo "11"
    elif [ "$(compare_versions "$found_version" "$jdk17_first_version")" = "greater" ] && [ "$(compare_versions "$found_version" "$jdk17_required_version")" = "less" ] || [ "$(compare_versions "$found_version" "$jdk17_required_version")" = "equal" ]; then
        echo "17"
    elif [ "$(compare_versions "$found_version" "$jdk17_required_version")" = "greater" ]; then
        echo "17"
    else
        echo "Unknown JDK version"
    fi
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

  # Convert space-delimited items into an array
  IFS=' ' read -r -a pom_xml_java_version_xpath <<< "$pom_xml_java_version_xpath_items"

  # Check if the pom_xml_java_version_xpath array is defined
  if [ -z "${pom_xml_java_version_xpath+x}" ]; then
      error "Error: pom_xml_java_version_xpath array is not defined" >&2
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
      debug "Didn't find java.version, using default $java_version"
  fi
  if [[ "$java_version" == 1.* ]]; then
      java_version="8"
      debug "Found java.version $java_version thanks to $xpath"
  fi

  # Round up to 8 if the version is less than 8
  if [[ "$java_version" -lt 8 ]]; then
      java_version="8"
      debug "Found java.version less than 8, rounding up to $java_version"
  fi

  # Ensure java_version is a number, default to 17 if not
  if ! [[ "$java_version" =~ ^[0-9]+$ ]]; then
      java_version="17"
      debug "Invalid java.version, setting to default $java_version"
  fi

  echo "$java_version"
}

# Function to extract Jenkins core version from pom.xml
get_jenkins_core_version_from_pom() {
    local pom_file=$1
    if [ -z "${pom_xml_jenkins_core_version_xpath_items+x}" ]; then
        error "pom_xml_jenkins_core_version_xpath_items is not defined" >&2
        return 1
    fi
    # Convert space-delimited items into an array
    IFS=' ' read -r -a pom_xml_jenkins_core_version_xpath <<< "$pom_xml_jenkins_core_version_xpath_items"
    if [ -z "${pom_xml_jenkins_core_version_xpath+x}" ]; then
        error "pom_xml_jenkins_core_version_xpath array is not defined" >&2
        return 1
    fi

    local jenkins_core_version=""
    for xpath in "${pom_xml_jenkins_core_version_xpath[@]}"; do
        if jenkins_core_version=$(xmllint --xpath "string($xpath)" "$pom_file" 2>/dev/null) && [ -n "$jenkins_core_version" ]; then
            break
        fi
    done

    # If no version is found, default to JDK 8
    if [ -z "$jenkins_core_version" ]; then
        error "No version found, defaulting to JDK 8 for $pom_file"
        echo "8"
        return
    fi

    # Split the version into major, minor, and patch components
    IFS='.' read -r major minor patch <<< "$jenkins_core_version"

    # Default minor and patch to 0 if they are not present
    minor=${minor:-0}
    patch=${patch:-0}

    # Determine the underlying Java version
    local jdk_version=""
    if [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 346 ]; }; then
        jdk_version="8"
    elif [ "$major" -eq 2 ] && [ "$minor" -le 462 ]; then
        jdk_version="11"
    else
        jdk_version="17"
    fi

    debug "$jenkins_core_version implies JDK $jdk_version for $pom_file"
    echo "$jdk_version"
}

# Function to download the POM file and transform it
download_and_transform_pom() {
     local repo_path=$1
    # Check the rate limit before making API requests
    check_rate_limit

    default_branch=$(gh repo view "$repo_path" --json defaultBranchRef --jq '.defaultBranchRef.name')
    if [ -z "$default_branch" ]; then
      error "Failed to retrieve default branch for $repo. Skipping repository."
      return 1
    fi
    debug "Found $default_branch as default branch for the repo $repo_path"
    # https://github.com/jenkinsci/xstream/raw/refs/heads/master/pom.xml
    # https://github.com/jenkinsci/xstream/raw/refs/heads/main/pom.xml
    pom_url="https://github.com/$repo_path/raw/refs/heads/$default_branch/pom.xml"
    local pom_file=$(mktemp /tmp/pom.XXXXXX.xml)
    debug "Will store in $pom_file the file found at $pom_url"
    # Ensure the temporary file is removed if the function exits unexpectedly
    trap 'rm -f "$pom_file"' EXIT

    curl  -s -L -H "Authorization: token $GITHUB_TOKEN"  -o "$pom_file" "$pom_url"
    # Convert space-delimited items into an array
    IFS=' ' read -r -a pom_xml_jenkins_parent_pom_version_xpath <<< "$pom_xml_jenkins_parent_pom_version_xpath_items"
    # Check if the pom_xml_jenkins_parent_pom_version_xpath array is defined
    if [ -z "${pom_xml_jenkins_parent_pom_version_xpath+x}" ]; then
        error "pom_xml_jenkins_parent_pom_version_xpath array is not defined" >&2
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)

    # Ensure the temporary file is removed if the function exits unexpectedly
    trap 'rm -f "$temp_file"' EXIT

    # Transform the XML file to remove namespaces
    if ! xsltproc remove-namespaces.xsl "$pom_file" > "$temp_file" 2>/dev/null; then
        rm -f "$temp_file"
        error "Failed to transform $pom_file XML file" >&2
        return 1
    fi
    debug "Stored the XML without namespaces in $temp_file"
    echo "$temp_file"
}


# Function to extract Jenkins parent POM version from pom.xml
# Ensure that config.sh is sourced to define the pom_xml_jenkins_parent_pom_version_xpath array
get_jenkins_parent_pom_version_from_pom() {
    local repo_path=$1
    local temp_file
    temp_file=$(download_and_transform_pom "$repo_path")
    if [ $? -ne 0 ]; then
        echo "Failed to download and transform POM for $repo_path"
        return 1
    fi

    echo "Will try to find parent pom version for $repo_path in the $temp_file XML file"

    # Convert space-delimited items into an array
    IFS=' ' read -r -a pom_xml_jenkins_parent_pom_version_xpath <<< "$pom_xml_jenkins_parent_pom_version_xpath_items"
    if [ -z "${pom_xml_jenkins_parent_pom_version_xpath+x}" ]; then
        echo "Error: pom_xml_jenkins_parent_pom_version_xpath array is not defined" >&2
        return 1
    fi
    local jenkins_parent_pom_version=""
    # Iterate over the array of XPath expressions to capture the first non-empty value
    for xpath in "${pom_xml_jenkins_parent_pom_version_xpath[@]}"; do
        echo "Trying XPath: $xpath"
        if jenkins_parent_pom_version=$(xmllint --xpath "string($xpath)" "$temp_file" 2>/dev/null) && [ -n "$jenkins_parent_pom_version" ]; then
            break
        fi
    done

    echo "Parent POM version is $jenkins_parent_pom_version for $repo_path"
    jdk_version=$(determine_jdk_version "$jenkins_parent_pom_version")
    echo "Induced JDK version is $jdk_version for $repo_path"
    jdk_version_from_pom=$(get_java_version_from_pom $temp_file)
    echo "Found JDK version $jdk_version_from_pom in POM for $repo_path"
    jenkins_core_version=$(get_jenkins_core_version_from_pom $temp_file)
    echo "Found Jenkins core version $jenkins_core_version in POM for $repo_path"

    # Determine the lowest detected Java version
    lowest_java_version=$jdk_version
    if [ "$jdk_version_from_pom" -lt "$lowest_java_version" ]; then
        lowest_java_version=$jdk_version_from_pom
    fi
    if [ "$jenkins_core_version" -lt "$lowest_java_version" ]; then
        lowest_java_version=$jenkins_core_version
    fi

    # Create files based on the lowest detected Java version
    case $lowest_java_version in
        8)
            echo "$repo_path" >> "$depends_on_java_8_txt"
            echo "$repo_path" >> "$depends_on_java_8_csv"
            ;;
        11)
            echo "$repo_path" >> "$depends_on_java_11_txt"
            echo "$repo_path" >> "$depends_on_java_11_csv"
            ;;
        *)
            echo "Unknown Java version for $repo_path"
            ;;
    esac

    # Explicitly remove the temporary file
    rm -f "$temp_file"
}
