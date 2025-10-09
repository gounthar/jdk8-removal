#!/usr/bin/env bash

# check-jdk-versions.sh
# Scans Jenkins plugin Jenkinsfiles to detect which JDK versions they're building with
# Generates a CSV report with plugin name, repository URL, and detected JDK versions

# Enable debug mode if DEBUG_MODE is set to true
if [ "$DEBUG_MODE" = "true" ]; then
  set -x
fi

# Source the required scripts
source csv-utils.sh
source log-utils.sh
source check-env.sh
source config.sh

# Get the current date in YYYY-MM-DD format
current_date=$(date +"%Y-%m-%d")

# Define output files
output_csv="reports/jdk_versions_in_jenkinsfiles_$current_date.csv"
output_json="reports/jdk_versions_in_jenkinsfiles_$current_date.json"

# Set up log file if not already defined
if [ -z "$LOG_FILE" ]; then
  export LOG_FILE="logs/jdk_versions_$current_date.log"
fi

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Initialize log file with header
echo "========================================" > "$LOG_FILE"
echo "JDK Version Detection in Jenkinsfiles" >> "$LOG_FILE"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Create CSV file and write header
echo "Plugin,Repository,URL,JDK_8,JDK_11,JDK_17,JDK_21,JDK_25,Jenkinsfile_URL,Has_Jenkinsfile" > "$output_csv"

# Initialize JSON array
echo "[" > "$output_json"
first_entry=true

# Function to check the rate limit status of the GitHub API
check_rate_limit() {
  rate_limit_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/rate_limit")
  remaining=$(echo "$rate_limit_response" | jq '.resources.core.remaining')
  reset=$(echo "$rate_limit_response" | jq '.resources.core.reset')
  limit=$(echo "$rate_limit_response" | jq '.resources.core.limit')

  if [ "$remaining" -lt $((limit / 20)) ]; then
    current_time=$(date +%s)
    wait_time=$((reset - current_time))
    end_time=$(date -d "@$reset" +"%H:%M")
    error "API rate limit exceeded. Please wait $wait_time seconds before retrying. Come back at $end_time."

    start_time=$(date +%s)
    while [ $((current_time + wait_time)) -gt $(date +%s) ]; do
      elapsed_time=$(( $(date +%s) - start_time ))
      progress=$(printf "%d" $(( 100 * elapsed_time / wait_time )))
      printf "\rProgress: [%-50s] %d%%" $(printf "%0.s#" $(seq 1 $(( progress / 2 )))) $progress
      sleep 1
    done
    info -e "\nWait time completed. Resuming..."
  fi
}

# Function to check for JDK versions in Jenkinsfile
check_jdk_versions_in_jenkinsfile() {
  repo=$1

  if [ -z "$repo" ]; then
    error "Repository name is empty. Skipping."
    return 1
  fi

  check_rate_limit

  # Get default branch
  default_branch=$(gh repo view "$repo" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null)
  if [ -z "$default_branch" ]; then
    error "Failed to retrieve default branch for $repo. Skipping repository."
    return 1
  fi

  # Try to fetch Jenkinsfile from the default branch
  jenkinsfile_url="https://raw.githubusercontent.com/$repo/$default_branch/Jenkinsfile"
  response=$(curl -s -L -w "\n%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "$jenkinsfile_url")
  http_code=$(echo "$response" | tail -n1)
  jenkinsfile=$(echo "$response" | sed '$d')

  # Initialize JDK detection flags
  has_jdk8="false"
  has_jdk11="false"
  has_jdk17="false"
  has_jdk21="false"
  has_jdk25="false"
  has_jenkinsfile="false"

  if [ "$http_code" -eq 200 ]; then
    has_jenkinsfile="true"
    info "Jenkinsfile found in $repo"

    # Check for JDK versions in Jenkinsfile
    # Look for patterns like: jdk: '8', java: 8, version: 8, configurations: [[platform: 'linux', jdk: 8]]

    # JDK 8 patterns (including 1.8)
    if echo "$jenkinsfile" | grep -qiE "(jdk['\": ]+['\"]?1\.8|jdk['\": ]+['\"]?8['\"]?|java['\": ]+['\"]?1\.8|java['\": ]+['\"]?8['\"]?|openjdk-?8)"; then
      has_jdk8="true"
      info "JDK 8 detected in $repo"
    fi

    # JDK 11
    if echo "$jenkinsfile" | grep -qiE "(jdk['\": ]+['\"]?11['\"]?|java['\": ]+['\"]?11['\"]?|openjdk-?11)"; then
      has_jdk11="true"
      info "JDK 11 detected in $repo"
    fi

    # JDK 17
    if echo "$jenkinsfile" | grep -qiE "(jdk['\": ]+['\"]?17['\"]?|java['\": ]+['\"]?17['\"]?|openjdk-?17)"; then
      has_jdk17="true"
      info "JDK 17 detected in $repo"
    fi

    # JDK 21
    if echo "$jenkinsfile" | grep -qiE "(jdk['\": ]+['\"]?21['\"]?|java['\": ]+['\"]?21['\"]?|openjdk-?21)"; then
      has_jdk21="true"
      info "JDK 21 detected in $repo"
    fi

    # JDK 25
    if echo "$jenkinsfile" | grep -qiE "(jdk['\": ]+['\"]?25['\"]?|java['\": ]+['\"]?25['\"]?|openjdk-?25)"; then
      has_jdk25="true"
      info "JDK 25 detected in $repo"
    fi
  elif [ "$http_code" -eq 404 ]; then
    info "No Jenkinsfile found in $repo"
  else
    error "Failed to fetch Jenkinsfile for $repo. HTTP status code: $http_code"
  fi

  # Format the repository name for display
  formatted_repo=$(format_repo_name "$repo")

  # Write to CSV
  echo "$formatted_repo,$repo,https://github.com/$repo,$has_jdk8,$has_jdk11,$has_jdk17,$has_jdk21,$has_jdk25,$jenkinsfile_url,$has_jenkinsfile" >> "$output_csv"

  # Write to JSON
  if [ "$first_entry" = false ]; then
    echo "," >> "$output_json"
  fi
  first_entry=false

  cat >> "$output_json" <<EOF
  {
    "plugin": "$formatted_repo",
    "repository": "$repo",
    "url": "https://github.com/$repo",
    "jdk_versions": {
      "jdk8": $has_jdk8,
      "jdk11": $has_jdk11,
      "jdk17": $has_jdk17,
      "jdk21": $has_jdk21,
      "jdk25": $has_jdk25
    },
    "jenkinsfile_url": "$jenkinsfile_url",
    "has_jenkinsfile": $has_jenkinsfile
  }
EOF

  # Add a delay to avoid hitting the rate limit
  sleep "$RATE_LIMIT_DELAY"
}

# Export the function so it can be used by parallel
export -f check_jdk_versions_in_jenkinsfile
export -f check_rate_limit
export -f format_repo_name

info "Starting JDK version detection in Jenkins plugin Jenkinsfiles..."
info "Output will be written to: $output_csv and $output_json"

# Check if required files exist
if [ ! -f "top-250-plugins.csv" ]; then
  error "top-250-plugins.csv not found. Please run get-most-popular-plugins.sh first."
  exit 1
fi

if [ ! -f "plugins.json" ]; then
  error "plugins.json not found. Please ensure it exists in the current directory."
  exit 1
fi

# Read top-250 plugins and map to repository URLs
info "Reading top-250 plugins list..."
plugin_count=0
repos_list=$(mktemp)

# Skip header and read plugin names
tail -n +2 "top-250-plugins.csv" | while IFS=',' read -r plugin_name popularity; do
  # Get repository URL from plugins.json
  repo_url=$(jq -r --arg plugin "$plugin_name" '.plugins[$plugin].scm // empty' plugins.json)

  if [ -n "$repo_url" ]; then
    # Extract repository path (e.g., "jenkinsci/script-security-plugin")
    repo_path=$(echo "$repo_url" | sed 's|https://github.com/||' | sed 's|\.git$||')
    echo "$repo_path" >> "$repos_list"
    ((plugin_count++))
  else
    warning "No repository found for plugin: $plugin_name"
  fi
done

info "Found $plugin_count repositories to check"

# Deduplicate repositories (multiple plugins may map to same repo)
sort -u "$repos_list" -o "$repos_list"
unique_repo_count=$(wc -l < "$repos_list")
info "After deduplication: $unique_repo_count unique repositories to check"

info "Processing repositories..."

# Process repositories sequentially to avoid JSON/CSV corruption from parallel writes
while read -r repo_path; do
  check_jdk_versions_in_jenkinsfile "$repo_path"
done < "$repos_list"

# Clean up temp file
rm -f "$repos_list"

# Close JSON array
echo "" >> "$output_json"
echo "]" >> "$output_json"

# Sort the CSV file (excluding header)
info "Sorting results..."
header=$(head -n 1 "$output_csv")
tail -n +2 "$output_csv" | sort > temp_file.csv
echo "$header" > "$output_csv"
cat temp_file.csv >> "$output_csv"
rm temp_file.csv

sync

info "Done! Results saved to:"
info "  CSV: $output_csv"
info "  JSON: $output_json"
info "  Log: $LOG_FILE"

# Generate a summary
total_repos=$(tail -n +2 "$output_csv" | wc -l)
repos_with_jenkinsfile=$(tail -n +2 "$output_csv" | awk -F',' '$10=="true"' | wc -l)
repos_with_jdk8=$(tail -n +2 "$output_csv" | awk -F',' '$4=="true"' | wc -l)
repos_with_jdk11=$(tail -n +2 "$output_csv" | awk -F',' '$5=="true"' | wc -l)
repos_with_jdk17=$(tail -n +2 "$output_csv" | awk -F',' '$6=="true"' | wc -l)
repos_with_jdk21=$(tail -n +2 "$output_csv" | awk -F',' '$7=="true"' | wc -l)
repos_with_jdk25=$(tail -n +2 "$output_csv" | awk -F',' '$8=="true"' | wc -l)

info ""
info "Summary:"
info "  Total repositories scanned: $total_repos"
info "  Repositories with Jenkinsfile: $repos_with_jenkinsfile"
info "  Repositories building with JDK 8: $repos_with_jdk8"
info "  Repositories building with JDK 11: $repos_with_jdk11"
info "  Repositories building with JDK 17: $repos_with_jdk17"
info "  Repositories building with JDK 21: $repos_with_jdk21"
info "  Repositories building with JDK 25: $repos_with_jdk25"

# Add completion marker to log file
echo "" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "Completed: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

success "Log file saved to: $LOG_FILE"
