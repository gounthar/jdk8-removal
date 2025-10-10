#!/usr/bin/env bash

# check-jdk25-with-pr-incremental.sh
# Enhanced script that skips already-validated JDK 25 plugins
# Usage: ./check-jdk25-with-pr-incremental.sh [previous_results.json]

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
output_csv="reports/jdk25_tracking_with_prs_$current_date.csv"
output_json="reports/jdk25_tracking_with_prs_$current_date.json"
validated_plugins_file="validated_jdk25_plugins.txt"

# Set up log file if not already defined
if [ -z "$LOG_FILE" ]; then
  export LOG_FILE="logs/jdk25_tracking_$current_date.log"
fi

# Create required directories
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "reports"

# Initialize log file with header
echo "========================================" > "$LOG_FILE"
echo "JDK 25 Tracking with PR Detection (Incremental)" >> "$LOG_FILE"
echo "Started: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Load previously validated plugins if a previous results file is provided
validated_repos=()
if [ -n "$1" ] && [ -f "$1" ]; then
  info "Loading previously validated plugins from: $1"

  # Extract repositories that have JDK 25 with merged PRs
  readarray -t validated_repos < <(jq -r '.[] | select(.has_jdk25 == true and .jdk25_pr.is_merged == true) | .repository' "$1" 2>/dev/null)

  info "Found ${#validated_repos[@]} previously validated plugins with merged JDK 25 PRs"

  # Save the list to a file for future reference
  printf '%s\n' "${validated_repos[@]}" > "$validated_plugins_file"

elif [ -f "$validated_plugins_file" ]; then
  info "Loading validated plugins from: $validated_plugins_file"
  readarray -t validated_repos < "$validated_plugins_file"
  info "Found ${#validated_repos[@]} validated plugins to skip"
fi

# Function to check if a repository is already validated
is_validated() {
  local repo=$1
  for validated_repo in "${validated_repos[@]}"; do
    if [ "$validated_repo" = "$repo" ]; then
      return 0  # true
    fi
  done
  return 1  # false
}

# Create CSV file and write header
echo "Plugin,Repository,URL,Has_JDK25,JDK25_Commit_SHA,JDK25_Commit_Date,JDK25_PR_Number,JDK25_PR_URL,Is_Merged,Jenkinsfile_URL,Has_Jenkinsfile" > "$output_csv"

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

# Function to find the commit that added JDK 25 to Jenkinsfile
find_jdk25_commit() {
  local repo=$1
  local default_branch=$2

  # Clone the repo to a temporary directory
  local temp_dir=$(mktemp -d)
  trap "rm -rf $temp_dir" RETURN

  debug "Cloning $repo to $temp_dir"

  # Disable xtrace to prevent token leakage
  [[ "$DEBUG_MODE" = "true" ]] && set +x

  # Configure git to use token via HTTP header (more secure than URL embedding)
  git config --global credential.helper store
  git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"

  # Clone with minimal depth for faster operation
  if ! git clone --depth 100 "https://github.com/$repo.git" "$temp_dir" &>/dev/null; then
    # Re-enable xtrace if it was on
    [[ "$DEBUG_MODE" = "true" ]] && set -x
    error "Failed to clone $repo"
    return 1
  fi

  # Re-enable xtrace if it was on
  [[ "$DEBUG_MODE" = "true" ]] && set -x

  cd "$temp_dir" || return 1

  # Check if Jenkinsfile exists
  if [ ! -f "Jenkinsfile" ]; then
    debug "No Jenkinsfile found in $repo"
    cd - &>/dev/null
    return 1
  fi

  # Search for commits that added JDK 25 references
  local commit_sha=$(git log -G "25" --all --format="%H" --follow -- Jenkinsfile | while read sha; do
    # Check if this commit actually added JDK 25
    if git show "$sha:Jenkinsfile" 2>/dev/null | grep -qiE "(jdk['\": ]+['\"]?25['\"]?|java['\": ]+['\"]?25['\"]?|openjdk-?25)"; then
      # Check if the previous commit didn't have JDK 25
      local parent_sha=$(git rev-parse "$sha^" 2>/dev/null)
      if [ -n "$parent_sha" ]; then
        if ! git show "$parent_sha:Jenkinsfile" 2>/dev/null | grep -qiE "(jdk['\": ]+['\"]?25['\"]?|java['\": ]+['\"]?25['\"]?|openjdk-?25)"; then
          echo "$sha"
          break
        fi
      else
        # First commit, assume it added JDK 25
        echo "$sha"
        break
      fi
    fi
  done | head -1)

  cd - &>/dev/null

  if [ -n "$commit_sha" ]; then
    echo "$commit_sha"
    return 0
  else
    return 1
  fi
}

# Function to find PR associated with a commit
find_pr_for_commit() {
  local repo=$1
  local commit_sha=$2

  check_rate_limit

  # Use GitHub CLI to find PR containing this commit
  local pr_info=$(gh api "repos/$repo/commits/$commit_sha/pulls" --jq '.[0] | {number: .number, url: .html_url, merged: .merged_at != null}' 2>/dev/null)

  if [ -n "$pr_info" ]; then
    echo "$pr_info"
    return 0
  fi

  # Fallback: search for PRs that might contain this commit
  local pr_search=$(gh pr list --repo "$repo" --state all --search "$commit_sha" --json number,url,mergedAt --limit 1 2>/dev/null | jq '.[0] | {number: .number, url: .url, merged: (.mergedAt != null)}' 2>/dev/null)

  if [ -n "$pr_search" ] && [ "$pr_search" != "null" ]; then
    echo "$pr_search"
    return 0
  fi

  return 1
}

# Function to get commit date
get_commit_date() {
  local repo=$1
  local commit_sha=$2

  check_rate_limit

  local commit_date=$(gh api "repos/$repo/commits/$commit_sha" --jq '.commit.author.date' 2>/dev/null)

  if [ -n "$commit_date" ]; then
    echo "$commit_date"
    return 0
  fi

  return 1
}

# Function to add a validated plugin entry from cache
add_cached_entry() {
  local repo=$1
  local previous_results=$2

  if [ -z "$previous_results" ] || [ ! -f "$previous_results" ]; then
    return 1
  fi

  # Find the entry in the previous results
  local cached_entry=$(jq --arg repo "$repo" '.[] | select(.repository == $repo)' "$previous_results" 2>/dev/null)

  if [ -n "$cached_entry" ] && [ "$cached_entry" != "null" ]; then
    # Extract values
    local plugin=$(echo "$cached_entry" | jq -r '.plugin')
    local url=$(echo "$cached_entry" | jq -r '.url')
    local has_jdk25=$(echo "$cached_entry" | jq -r '.has_jdk25')
    local commit_sha=$(echo "$cached_entry" | jq -r '.jdk25_commit.sha')
    local commit_date=$(echo "$cached_entry" | jq -r '.jdk25_commit.date')
    local pr_number=$(echo "$cached_entry" | jq -r '.jdk25_pr.number')
    local pr_url=$(echo "$cached_entry" | jq -r '.jdk25_pr.url')
    local is_merged=$(echo "$cached_entry" | jq -r '.jdk25_pr.is_merged')
    local jenkinsfile_url=$(echo "$cached_entry" | jq -r '.jenkinsfile_url')
    local has_jenkinsfile=$(echo "$cached_entry" | jq -r '.has_jenkinsfile')

    # Write to CSV
    echo "$plugin,$repo,$url,$has_jdk25,$commit_sha,$commit_date,$pr_number,$pr_url,$is_merged,$jenkinsfile_url,$has_jenkinsfile" >> "$output_csv"

    # Write to JSON
    if [ "$first_entry" = false ]; then
      echo "," >> "$output_json"
    fi
    first_entry=false

    echo "$cached_entry" | jq '.' >> "$output_json"

    return 0
  fi

  return 1
}

# Function to check for JDK 25 and find associated PR
check_jdk25_with_pr() {
  repo=$1
  previous_results=$2

  if [ -z "$repo" ]; then
    error "Repository name is empty. Skipping."
    return 1
  fi

  # Check if this repository is already validated
  if is_validated "$repo"; then
    info "✓ Skipping $repo (already validated with merged JDK 25 PR)"

    # Add the cached entry if we have previous results
    if add_cached_entry "$repo" "$previous_results"; then
      return 0
    fi
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

  # Initialize variables
  has_jdk25="false"
  has_jenkinsfile="false"
  commit_sha=""
  commit_date=""
  pr_number=""
  pr_url=""
  is_merged="false"

  if [ "$http_code" -eq 200 ]; then
    has_jenkinsfile="true"
    info "Jenkinsfile found in $repo"

    # Check if JDK 25 is present
    if echo "$jenkinsfile" | grep -qiE "(jdk['\": ]+['\"]?25['\"]?|java['\": ]+['\"]?25['\"]?|openjdk-?25)"; then
      has_jdk25="true"
      info "JDK 25 detected in $repo"

      # Find the commit that added JDK 25
      info "Searching for commit that added JDK 25 to $repo..."
      commit_sha=$(find_jdk25_commit "$repo" "$default_branch")

      if [ -n "$commit_sha" ]; then
        info "Found commit: $commit_sha"

        # Get commit date
        commit_date=$(get_commit_date "$repo" "$commit_sha")
        info "Commit date: $commit_date"

        # Find PR associated with this commit
        info "Searching for PR associated with commit $commit_sha..."
        pr_info=$(find_pr_for_commit "$repo" "$commit_sha")

        if [ -n "$pr_info" ]; then
          pr_number=$(echo "$pr_info" | jq -r '.number')
          pr_url=$(echo "$pr_info" | jq -r '.url')
          is_merged=$(echo "$pr_info" | jq -r '.merged')

          info "Found PR #$pr_number: $pr_url (merged: $is_merged)"

          # If this PR is merged, add to validated list
          if [ "$is_merged" = "true" ]; then
            echo "$repo" >> "$validated_plugins_file"
          fi
        else
          warning "No PR found for commit $commit_sha in $repo"
        fi
      else
        warning "Could not find commit that added JDK 25 to $repo"
      fi
    else
      info "JDK 25 not found in $repo"
    fi
  elif [ "$http_code" -eq 404 ]; then
    info "No Jenkinsfile found in $repo"
  else
    error "Failed to fetch Jenkinsfile for $repo. HTTP status code: $http_code"
  fi

  # Format the repository name for display
  formatted_repo=$(format_repo_name "$repo")

  # Write to CSV
  echo "$formatted_repo,$repo,https://github.com/$repo,$has_jdk25,$commit_sha,$commit_date,$pr_number,$pr_url,$is_merged,$jenkinsfile_url,$has_jenkinsfile" >> "$output_csv"

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
    "has_jdk25": $has_jdk25,
    "jdk25_commit": {
      "sha": "$commit_sha",
      "date": "$commit_date"
    },
    "jdk25_pr": {
      "number": "$pr_number",
      "url": "$pr_url",
      "is_merged": $is_merged
    },
    "jenkinsfile_url": "$jenkinsfile_url",
    "has_jenkinsfile": $has_jenkinsfile
  }
EOF

  # Add a delay to avoid hitting the rate limit
  sleep "$RATE_LIMIT_DELAY"
}

# Export the functions so they can be used by parallel
export -f check_jdk25_with_pr
export -f check_rate_limit
export -f format_repo_name
export -f find_jdk25_commit
export -f find_pr_for_commit
export -f get_commit_date
export -f is_validated
export -f add_cached_entry

info "Starting incremental JDK 25 detection with PR tracking..."
info "Output will be written to: $output_csv and $output_json"

if [ ${#validated_repos[@]} -gt 0 ]; then
  info "Will skip ${#validated_repos[@]} already-validated plugins"
fi

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
previous_results="$1"

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

# Process repositories sequentially
while read -r repo_path; do
  check_jdk25_with_pr "$repo_path" "$previous_results"
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
info "  Validated plugins list: $validated_plugins_file"

# Generate a summary
total_repos=$(tail -n +2 "$output_csv" | wc -l)
repos_with_jenkinsfile=$(tail -n +2 "$output_csv" | awk -F',' '$11=="true"' | wc -l)
repos_with_jdk25=$(tail -n +2 "$output_csv" | awk -F',' '$4=="true"' | wc -l)
repos_with_jdk25_pr=$(tail -n +2 "$output_csv" | awk -F',' '$7!=""' | wc -l)
repos_with_merged_jdk25_pr=$(tail -n +2 "$output_csv" | awk -F',' '$9=="true"' | wc -l)

info ""
info "Summary:"
info "  Total repositories scanned: $total_repos"
info "  Repositories with Jenkinsfile: $repos_with_jenkinsfile"
info "  Repositories building with JDK 25: $repos_with_jdk25"
info "  Repositories with JDK 25 PR identified: $repos_with_jdk25_pr"
info "  Repositories with merged JDK 25 PR: $repos_with_merged_jdk25_pr"

# Add completion marker to log file
echo "" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
echo "Completed: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

success "Log file saved to: $LOG_FILE"
