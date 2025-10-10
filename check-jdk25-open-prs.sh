#!/usr/bin/env bash

# check-jdk25-open-prs.sh
# Detects open PRs (including drafts) that add JDK 25 to Jenkins plugin Jenkinsfiles
#
# This script:
# - Scans open PRs for each plugin repository
# - Checks if the PR modifies Jenkinsfile
# - Compares JDK 25 presence between PR head and base branches
# - Identifies PRs that are ADDING JDK 25 (not just modifying)
# - Tracks draft vs regular PRs

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
output_csv="reports/jdk25_open_prs_tracking_$current_date.csv"
output_json="reports/jdk25_open_prs_tracking_$current_date.json"

# Set up log file if not already defined
if [ -z "$LOG_FILE" ]; then
  export LOG_FILE="logs/jdk25_open_prs_$current_date.log"
fi

# Create required directories
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "reports"

# Initialize log file with header
echo "========================================" > "$LOG_FILE"
echo "JDK 25 Open PRs Detection" >> "$LOG_FILE"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Create CSV file and write header
echo "Plugin,Repository,URL,Has_Open_JDK25_PRs,Open_PRs_Count,Open_PR_Numbers,Open_PR_URLs,Has_Jenkinsfile" > "$output_csv"

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
    echo
    info "Wait time completed. Resuming..."
  fi
}

# Function to check if content has JDK 25
has_jdk25() {
  local content="$1"
  echo "$content" | grep -qiE "(jdk['\": ]+['\"]?25['\"]?|java['\": ]+['\"]?25['\"]?|openjdk-?25)"
}

# Function to check if PR modifies Jenkinsfile
pr_modifies_jenkinsfile() {
  local repo=$1
  local pr_number=$2

  check_rate_limit

  # Get list of files changed in this PR
  local files=$(gh api "repos/$repo/pulls/$pr_number/files" --jq '.[].filename' 2>/dev/null)

  if [ -z "$files" ]; then
    return 1
  fi

  # Check if Jenkinsfile is in the list
  echo "$files" | grep -q "^Jenkinsfile$"
}

# Function to get Jenkinsfile content from a specific ref (branch/commit)
get_jenkinsfile_from_ref() {
  local repo=$1
  local ref=$2

  check_rate_limit

  # Try to get Jenkinsfile content from the specified ref
  local content=$(gh api "repos/$repo/contents/Jenkinsfile?ref=$ref" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)

  if [ -n "$content" ]; then
    echo "$content"
    return 0
  fi

  return 1
}

# Function to check if repo already has JDK 25 merged
# This is an optimization - skip repos that already have JDK 25
check_repo_has_jdk25() {
  local repo=$1

  # Load the merged PRs data if it exists
  local merged_data_file="reports/jdk25_tracking_with_prs_$current_date.json"

  if [ ! -f "$merged_data_file" ]; then
    # If today's file doesn't exist, try yesterday's
    local yesterday=$(date -d "yesterday" +"%Y-%m-%d" 2>/dev/null || date -v-1d +"%Y-%m-%d" 2>/dev/null)
    merged_data_file="reports/jdk25_tracking_with_prs_$yesterday.json"
  fi

  if [ -f "$merged_data_file" ]; then
    # Check if this repo already has JDK 25
    local has_jdk25=$(jq -r --arg repo "$repo" '.[] | select(.repository == $repo) | .has_jdk25' "$merged_data_file" 2>/dev/null)

    if [ "$has_jdk25" = "true" ]; then
      return 0  # Yes, repo has JDK 25
    fi
  fi

  return 1  # No, repo doesn't have JDK 25 or file not found
}

# Function to find open PRs that add JDK 25
find_open_prs_with_jdk25() {
  local repo=$1

  # OPTIMIZATION: Skip repos that already have JDK 25 merged
  if check_repo_has_jdk25 "$repo"; then
    debug "Skipping $repo - already has JDK 25 on default branch"
    return 0
  fi

  check_rate_limit

  # Get all open PRs (includes drafts)
  local open_prs=$(gh pr list --repo "$repo" --state open \
    --json number,url,title,isDraft,author,createdAt,headRefName,baseRefName 2>/dev/null)

  if [ -z "$open_prs" ] || [ "$open_prs" = "[]" ]; then
    debug "No open PRs found in $repo"
    return 0
  fi

  local found_prs=()

  # Process each PR
  echo "$open_prs" | jq -c '.[]' | while read -r pr; do
    pr_number=$(echo "$pr" | jq -r '.number')
    head_ref=$(echo "$pr" | jq -r '.headRefName')
    base_ref=$(echo "$pr" | jq -r '.baseRefName')

    debug "Checking PR #$pr_number in $repo..."

    # Check if PR modifies Jenkinsfile
    if pr_modifies_jenkinsfile "$repo" "$pr_number"; then
      debug "PR #$pr_number modifies Jenkinsfile"

      # Get Jenkinsfiles from both branches
      head_jenkinsfile=$(get_jenkinsfile_from_ref "$repo" "$head_ref")
      base_jenkinsfile=$(get_jenkinsfile_from_ref "$repo" "$base_ref")

      # Check JDK 25 presence
      head_has_jdk25=false
      base_has_jdk25=false

      if [ -n "$head_jenkinsfile" ] && has_jdk25 "$head_jenkinsfile"; then
        head_has_jdk25=true
      fi

      if [ -n "$base_jenkinsfile" ] && has_jdk25 "$base_jenkinsfile"; then
        base_has_jdk25=true
      fi

      # If head has JDK 25 but base doesn't, this PR adds JDK 25!
      if [ "$head_has_jdk25" = "true" ] && [ "$base_has_jdk25" = "false" ]; then
        info "Found PR #$pr_number that adds JDK 25 to $repo"
        echo "$pr"
      fi
    fi

    # Add delay to respect rate limits
    sleep "$RATE_LIMIT_DELAY"
  done
}

# Function to process a single repository
process_repository() {
  local repo=$1

  if [ -z "$repo" ]; then
    error "Repository name is empty. Skipping."
    return 1
  fi

  info "Processing $repo..."

  # Format the repository name for display
  local formatted_repo=$(format_repo_name "$repo")

  # Find open PRs that add JDK 25
  local open_jdk25_prs=$(find_open_prs_with_jdk25 "$repo")

  # Initialize variables
  local has_open_jdk25_prs="false"
  local open_prs_count=0
  local pr_numbers=""
  local pr_urls=""
  local has_jenkinsfile="true"  # Assume true for now

  if [ -n "$open_jdk25_prs" ]; then
    has_open_jdk25_prs="true"
    open_prs_count=$(echo "$open_jdk25_prs" | jq -s 'length')

    # Extract PR numbers and URLs
    pr_numbers=$(echo "$open_jdk25_prs" | jq -r '.number' | paste -sd ',' -)
    pr_urls=$(echo "$open_jdk25_prs" | jq -r '.url' | paste -sd ',' -)

    info "Found $open_prs_count open PR(s) that add JDK 25 to $repo"
  fi

  # Write to CSV
  echo "$formatted_repo,$repo,https://github.com/$repo,$has_open_jdk25_prs,$open_prs_count,\"$pr_numbers\",\"$pr_urls\",$has_jenkinsfile" >> "$output_csv"

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
    "has_open_jdk25_prs": $has_open_jdk25_prs,
    "open_jdk25_prs": $(echo "$open_jdk25_prs" | jq -s '.'),
    "has_jenkinsfile": $has_jenkinsfile
  }
EOF
}

# Export functions for parallel processing (if needed)
export -f process_repository
export -f find_open_prs_with_jdk25
export -f check_repo_has_jdk25
export -f pr_modifies_jenkinsfile
export -f get_jenkinsfile_from_ref
export -f has_jdk25
export -f check_rate_limit
export -f format_repo_name

info "Starting JDK 25 open PRs detection in Jenkins plugin repositories..."
info "Output will be written to: $output_csv and $output_json"

# Determine which plugin list to use
# PLUGIN_LIST_MODE can be "top-250" (default) or "all"
PLUGIN_LIST_MODE="${PLUGIN_LIST_MODE:-top-250}"

case "$PLUGIN_LIST_MODE" in
  all)
    PLUGIN_LIST_FILE="all-plugins.csv"
    PLUGIN_LIST_NAME="all plugins"
    REQUIRED_SCRIPT="get-all-plugins.sh"
    ;;
  top-250)
    PLUGIN_LIST_FILE="top-250-plugins.csv"
    PLUGIN_LIST_NAME="top-250 plugins"
    REQUIRED_SCRIPT="get-most-popular-plugins.sh"
    ;;
  *)
    error "Invalid PLUGIN_LIST_MODE: $PLUGIN_LIST_MODE. Must be 'top-250' or 'all'."
    exit 1
    ;;
esac

info "Plugin list mode: $PLUGIN_LIST_MODE"
info "Using: $PLUGIN_LIST_FILE"

# Check if required files exist
if [ ! -f "$PLUGIN_LIST_FILE" ]; then
  error "$PLUGIN_LIST_FILE not found. Please run $REQUIRED_SCRIPT first."
  exit 1
fi

if [ ! -f "plugins.json" ]; then
  error "plugins.json not found. Please ensure it exists in the current directory."
  exit 1
fi

# Read plugins and map to repository URLs
info "Reading $PLUGIN_LIST_NAME list..."
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
    ((plugin_count++))
  else
    warning "No repository found for plugin: $plugin_name"
  fi
done < <(tail -n +2 "$PLUGIN_LIST_FILE")

info "Found $plugin_count repositories to check"

# Deduplicate repositories (multiple plugins may map to same repo)
sort -u "$repos_list" -o "$repos_list"
unique_repo_count=$(wc -l < "$repos_list")
info "After deduplication: $unique_repo_count unique repositories to check"

info "Processing repositories..."

# Process repositories sequentially (for better rate limit management)
while read -r repo_path; do
  process_repository "$repo_path"
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
repos_with_open_prs=$(tail -n +2 "$output_csv" | awk -F',' '$4=="true"' | wc -l)
total_open_prs=$(tail -n +2 "$output_csv" | awk -F',' '{sum+=$5} END {print sum}')

info ""
info "Summary:"
info "  Total repositories scanned: $total_repos"
info "  Repositories with open JDK 25 PRs: $repos_with_open_prs"
info "  Total open PRs adding JDK 25: $total_open_prs"

# Change tracking: Compare with previous run
info ""
info "Checking for changes since last run..."

# Find the most recent previous JSON file (excluding today's)
previous_json=$(ls -t reports/jdk25_open_prs_tracking_*.json 2>/dev/null | grep -v "$current_date" | head -1)

if [ -n "$previous_json" ] && [ -f "$previous_json" ]; then
  previous_date=$(basename "$previous_json" | sed 's/jdk25_open_prs_tracking_//' | sed 's/.json$//')
  info "Comparing with previous run from $previous_date"

  # Create temporary files for comparison
  current_prs=$(mktemp)
  previous_prs=$(mktemp)

  # Extract PR details: repo|pr_number|is_draft|url
  jq -r '.[] | select(.has_open_jdk25_prs == true) | .repository as $repo | .open_jdk25_prs[] | "\($repo)|\(.number)|\(.isDraft)|\(.url)"' "$output_json" | sort > "$current_prs"
  jq -r '.[] | select(.has_open_jdk25_prs == true) | .repository as $repo | .open_jdk25_prs[] | "\($repo)|\(.number)|\(.isDraft)|\(.url)"' "$previous_json" | sort > "$previous_prs"

  # Detect changes
  new_prs=$(comm -13 "$previous_prs" "$current_prs" | cut -d'|' -f1-2)
  closed_prs=$(comm -23 "$previous_prs" "$current_prs" | cut -d'|' -f1-2)

  # Detect draft status changes
  draft_to_regular=0
  regular_to_draft=0

  while IFS='|' read -r repo pr_num is_draft url; do
    # Check if this PR existed before
    prev_line=$(grep "^$repo|$pr_num|" "$previous_prs")
    if [ -n "$prev_line" ]; then
      prev_draft=$(echo "$prev_line" | cut -d'|' -f3)
      # Draft to regular
      if [ "$prev_draft" = "true" ] && [ "$is_draft" = "false" ]; then
        ((draft_to_regular++))
        info "  📝 PR #$pr_num in $repo: Draft → Ready for review"
      fi
      # Regular to draft
      if [ "$prev_draft" = "false" ] && [ "$is_draft" = "true" ]; then
        ((regular_to_draft++))
        info "  📝 PR #$pr_num in $repo: Ready → Draft"
      fi
    fi
  done < "$current_prs"

  new_count=$(echo "$new_prs" | grep -c . 2>/dev/null || echo 0)
  closed_count=$(echo "$closed_prs" | grep -c . 2>/dev/null || echo 0)

  info ""
  info "Changes since $previous_date:"
  info "  📈 New PRs opened: $new_count"
  info "  📉 PRs closed/merged: $closed_count"
  info "  ✅ Draft → Ready: $draft_to_regular"
  info "  ⏸️  Ready → Draft: $regular_to_draft"

  # Show details of new PRs
  if [ "$new_count" -gt 0 ]; then
    info ""
    info "New PRs:"
    echo "$new_prs" | while IFS='|' read -r repo pr_num; do
      if [ -n "$repo" ]; then
        pr_url=$(grep "^$repo|$pr_num|" "$current_prs" | cut -d'|' -f4)
        info "  • $repo #$pr_num - $pr_url"
      fi
    done
  fi

  # Show details of closed/merged PRs
  if [ "$closed_count" -gt 0 ]; then
    info ""
    info "Closed/Merged PRs:"
    echo "$closed_prs" | while IFS='|' read -r repo pr_num; do
      if [ -n "$repo" ]; then
        pr_url=$(grep "^$repo|$pr_num|" "$previous_prs" | cut -d'|' -f4)
        info "  • $repo #$pr_num - $pr_url"
      fi
    done
  fi

  # Clean up temp files
  rm -f "$current_prs" "$previous_prs"
else
  info "No previous run found for comparison"
fi

# Add completion marker to log file
echo "" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "Completed: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

success "Log file saved to: $LOG_FILE"
