#!/usr/bin/env bash

# check-jdk-versions.sh
# Unified script that tracks JDK 17, 21, and 25 adoption across ALL Jenkins plugins
# Checks all versions in a single pass for optimal performance
# Usage: ./check-jdk-versions.sh

# Fail fast and catch unset vars
set -euo pipefail


# Enable debug mode if DEBUG_MODE is set to true
if [ "${DEBUG_MODE:-false}" = "true" ]; then
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
output_csv="reports/jdk_versions_tracking_$current_date.csv"
output_json="reports/jdk_versions_tracking_$current_date.json"

# Set up log file if not already defined
if [ -z "${LOG_FILE:-}" ]; then
  export LOG_FILE="logs/jdk_versions_tracking_$current_date.log"
fi

# Create required directories
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "reports"

# Initialize log file with header
echo "========================================" > "$LOG_FILE"
echo "JDK Versions Tracking (17, 21, 25) - ALL Plugins" >> "$LOG_FILE"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Create CSV file and write header
echo "Plugin,Repository,URL,Has_JDK17,Has_JDK21,Has_JDK25,Jenkinsfile_URL,Has_Jenkinsfile" > "$output_csv"

# Initialize JSON array
echo "[" > "$output_json"
first_entry=true

# Function to check the rate limit status of the GitHub API
check_rate_limit() {
  # Use conditional auth header to avoid empty Authorization header
  rl_hdr=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    rl_hdr=(-H "Authorization: token $GITHUB_TOKEN")
  fi
  rate_limit_response=$(curl -s "${rl_hdr[@]}" "https://api.github.com/rate_limit")
  remaining=$(echo "$rate_limit_response" | jq '.resources.core.remaining')
  reset=$(echo "$rate_limit_response" | jq '.resources.core.reset')
  limit=$(echo "$rate_limit_response" | jq '.resources.core.limit')

  if [ "$remaining" -lt $((limit / 20)) ]; then
    current_time=$(date +%s)
    wait_time=$((reset - current_time))
    end_time=$(date -d "@$reset" +"%H:%M")
    error "API rate limit exceeded. Please wait $wait_time seconds before retrying. Come back at $end_time."

    if [ "$wait_time" -le 0 ]; then
      info "Rate limit reset reached; continuing..."
      return
    fi

    start_time=$(date +%s)
    while [ $((current_time + wait_time)) -gt $(date +%s) ]; do
      elapsed_time=$(( $(date +%s) - start_time ))
      progress=$(printf "%d" $(( 100 * elapsed_time / wait_time )))
      printf "\rProgress: [%-50s] %d%%" $(printf "%0.s#" $(seq 1 $(( progress / 2 )))) $progress
      sleep 1
    done
    echo
    info "Wait time completed. Resuming..."
  fi
}

# Function to check for JDK versions in a repository
check_jdk_versions() {
  local repo=$1

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

  # Fetch Jenkinsfile with conditional auth header
  # Disable xtrace temporarily to prevent token leakage in DEBUG_MODE
  local xtrace_was_set=false
  if [[ "$-" == *x* ]]; then
    xtrace_was_set=true
    set +x
  fi
  
  auth_header=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth_header=(-H "Authorization: token $GITHUB_TOKEN")
  fi
  
  # Try to fetch Jenkinsfile from the default branch
  jenkinsfile_url="https://raw.githubusercontent.com/$repo/$default_branch/Jenkinsfile"
  response=$(curl -s -L -w "\n%{http_code}" "${auth_header[@]}" "$jenkinsfile_url")
  
  # Re-enable xtrace if it was set
  if [ "$xtrace_was_set" = true ]; then
    set -x
  fi
  http_code=$(echo "$response" | tail -n1)
  jenkinsfile=$(echo "$response" | sed '$d')

  # Initialize variables
  has_jdk17="false"
  has_jdk21="false"
  has_jdk25="false"
  has_jenkinsfile="false"

  if [ "$http_code" -eq 200 ]; then
    has_jenkinsfile="true"
    debug "Jenkinsfile found in $repo"

    # Check for JDK versions (17, 21, 25) with improved pattern to avoid false positives
    # Pattern explanation:
    # - (jdk|java)([: ]+['\"]?VER['\"]?|['\"]VER['\"]?) - requires at least one separator (: or space) OR immediate quote
    # - This avoids matching variable names like jdk17, JDK17_LABEL, etc.
    # - openjdk-?VER - matches openjdk17 or openjdk-17
    for ver in 17 21 25; do
      if grep -qiE "((jdk|java)([: ]+['\"]?${ver}['\"]?|['\"]${ver}['\"]?)|openjdk-?${ver})" <<< "$jenkinsfile"; then
        eval "has_jdk${ver}=true"
        info "JDK ${ver} detected in $repo"
      fi
    done

  elif [ "$http_code" -eq 404 ]; then
    debug "No Jenkinsfile found in $repo"
  else
    error "Failed to fetch Jenkinsfile for $repo. HTTP status code: $http_code"
  fi

  # Format the repository name for display
  formatted_repo=$(format_repo_name "$repo")

  # Write to CSV
  echo "$formatted_repo,$repo,https://github.com/$repo,$has_jdk17,$has_jdk21,$has_jdk25,$jenkinsfile_url,$has_jenkinsfile" >> "$output_csv"

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
    "has_jdk17": $has_jdk17,
    "has_jdk21": $has_jdk21,
    "has_jdk25": $has_jdk25,
    "jenkinsfile_url": "$jenkinsfile_url",
    "has_jenkinsfile": $has_jenkinsfile
  }
EOF

  # Add a delay to avoid hitting the rate limit
  sleep "$RATE_LIMIT_DELAY"
}

info "Starting unified JDK versions tracking (17, 21, 25)..."
info "Scanning ALL Jenkins plugins"
info "Output will be written to: $output_csv and $output_json"

# Force all-plugins mode
export PLUGIN_LIST_MODE="all"
info "Plugin list mode: ALL PLUGINS"

# Generate all-plugins list if it doesn't exist or is outdated
if [ ! -f "all-plugins.csv" ] || [ "plugins.json" -nt "all-plugins.csv" ]; then
  info "Generating all-plugins list..."
  ./get-all-plugins.sh
fi

PLUGIN_LIST_FILE="all-plugins.csv"
PLUGIN_LIST_NAME="all plugins"

# Check if required files exist
if [ ! -f "$PLUGIN_LIST_FILE" ]; then
  error "$PLUGIN_LIST_FILE not found. Please run get-all-plugins.sh first."
  exit 1
fi

if [ ! -f "plugins.json" ]; then
  error "plugins.json not found. Please ensure it exists in the current directory."
  exit 1
fi

# Read plugins and map to repository URLs
info "Reading all plugins list..."
plugin_count=0
repos_list=$(mktemp)

# Skip header and read plugin names (avoid subshell)
while IFS=',' read -r plugin_name popularity; do
  # Get repository URL from plugins.json
  repo_url=$(jq -r --arg plugin "$plugin_name" '.plugins[$plugin].scm // empty' plugins.json)

  if [ -n "$repo_url" ]; then
    # Extract repository path (e.g., "jenkinsci/script-security-plugin")
    repo_path=$(echo "$repo_url" | sed 's|https://github.com/||' | sed 's|\.git$||')
    echo "$repo_path" >> "$repos_list"
    ((plugin_count++)) || true  # Prevent set -e exit when count is 0
  else
    debug "No repository found for plugin: $plugin_name"
  fi
done < <(tail -n +2 "$PLUGIN_LIST_FILE")

info "Found $plugin_count repositories to check"

# Deduplicate repositories (multiple plugins may map to same repo)
sort -u "$repos_list" -o "$repos_list"
unique_repo_count=$(wc -l < "$repos_list")
info "After deduplication: $unique_repo_count unique repositories to check"

info "Processing repositories..."

# Process repositories sequentially
while read -r repo_path; do
  check_jdk_versions "$repo_path" || true  # Continue even if individual repos fail
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
# Calculate all stats in a single pass for efficiency
read -r repos_with_jenkinsfile repos_with_jdk17 repos_with_jdk21 repos_with_jdk25 < <(
  tail -n +2 "$output_csv" | awk -F',' '
    {j+=($8=="true"); j17+=($4=="true"); j21+=($5=="true"); j25+=($6=="true")}
    END {print j, j17, j21, j25}
  '
)

info ""
info "Summary:"
info "  Total repositories scanned: $total_repos"
info "  Repositories with Jenkinsfile: $repos_with_jenkinsfile"
info "  Repositories building with JDK 17: $repos_with_jdk17"
info "  Repositories building with JDK 21: $repos_with_jdk21"
info "  Repositories building with JDK 25: $repos_with_jdk25"

# Add completion marker to log file
echo "" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "Completed: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

success "JDK versions tracking complete! Log file saved to: $LOG_FILE"
