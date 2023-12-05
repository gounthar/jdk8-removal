#!/usr/bin/env bash

# Import the logging utility functions
source log-utils.sh

# Function to pull the latest changes from a git repository and set the upstream branch if necessary
# Arguments:
#   repo: The name of the repository
#   tmp_dir: The path to the directory where the repository is located
pull_and_set_upstream() {
  # The URL of the repository
  url=$1".git"
  # The name of the repository
  repo=$2
  # The path to the directory where the repository is located
  tmp_dir=$3
  # Get the GitHub username of the current user
  username=$(gh api user | jq -r '.login')
  # Set the global Git username to the GitHub username
  git config --global user.name "$username"
  # Print a debug message with the repository name and directory
  debug "repo: $repo, repo dir: $tmp_dir/$repo"
  # Navigate to the repository directory
  # Check if the repository directory exists
  if [ -d "$tmp_dir/$repo" ]; then
    # If it does, navigate into the directory
    cd "$tmp_dir/$repo" || exit
  else
    # If it doesn't, clone the repository and navigate into the directory
    debug "New Cloning would be git clone https://${GITHUB_TOKEN}@${url#https://}"
    git clone "https://${GITHUB_TOKEN}@${url#https://}" "$tmp_dir/$repo"
    cd "$tmp_dir/$repo" || exit
  fi
  # Get the list of remote repositories and print a debug message
  remote_output=$(git remote -v 2>&1)
  debug "remote_output: $remote_output"
  # Try to pull the latest changes and capture the output
  pull_output=$(git pull 2>&1)
  # If the pull fails
  if [ $? -ne 0 ]; then
    # Stash any changes
    debug "Pull failed, stashing any changes"
    git stash
    # Try to pull again and capture the output
    pull_output=$(git pull 2>&1)
    # If the pull fails again
    if [ $? -ne 0 ]; then
      debug "Pull failed again, checking if the 'jdk8-removal' branch exists on the remote repository"
      # If the 'jdk8-removal' branch exists on the remote repository
      if git ls-remote --heads origin jdk8-removal; then
        debug "'jdk8-removal' branch exists on the remote repository"
        # Set the upstream branch to 'jdk8-removal'
        git branch --set-upstream-to=origin/jdk8-removal
      else
        debug "'jdk8-removal' branch does not exist on the remote repository"
        # If the 'jdk8-removal' branch does not exist on the remote repository
        # Create the 'jdk8-removal' branch locally
        debug "Creating the 'jdk8-removal' branch locally"
        git checkout -b jdk8-removal
        # Push the 'jdk8-removal' branch to the remote repository
        debug "Pushing the 'jdk8-removal' branch to the remote repository"
        git push origin jdk8-removal
        # Set the upstream branch to 'jdk8-removal'
        debug "Setting the upstream branch to 'jdk8-removal'"
        git branch --set-upstream-to=origin/jdk8-removal
      fi
      # Try to pull again and capture the output
      debug "Pulling again"
      pull_output=$(git pull 2>&1)
    fi
  fi

  # If the pull was successful
  if [ $? -eq 0 ]; then
    # Print a success message
    info "Successfully pulled the latest changes"
  else
    # If the pull failed, print the error message and exit the script
    error "$pull_output"
    exit 1
  fi
}

# Function to apply a patch to a repository and push the changes
# Arguments:
#   url: The URL of the repository
#   repo: The name of the repository
#   commit_message: The commit message to use when committing the changes
apply_patch_and_push() {
  # The URL of the repository
  url=$1
  # The name of the repository
  repo=$2
  # The commit message
  commit_message=$3

  # Get the GitHub username of the current user
  username=$(gh api user | jq -r '.login')

  debug "apply_patch_and_push: $url, $repo, $commit_message, pwd $(pwd)"
  # Create a patch file with all the modifications in the current repository
  git diff >../modifications.patch
  # Navigate up one directory level
  cd ..
  # Print a message indicating that the original local repository will be deleted
  info "Will delete the original repo locally"
  # Delete the original local repository
  rm -rf "$repo"
  # Print a message indicating that the repository will be forked and the fork will be cloned
  info "Will now fork and clone the fork"
  # Fork the repository and clone the fork
  gh repo fork "$url" --clone=true --remote=true --remote-name fork --default-branch-only
  # Navigate into the directory of the cloned repository
  cd "$repo" || exit
  # Create a new branch named 'jdk8-removal'
  git checkout -b "jdk8-removal"
  # Check if the 'jdk8-removal' branch exists on the remote repository
  debug "Checking if the 'jdk8-removal' branch exists on the remote repository"
  if ! git ls-remote --heads origin jdk8-removal; then
    # If it doesn't, push the 'jdk8-removal' branch to the remote repository
    debug "'jdk8-removal' branch does not exist on the remote repository. Creating it."
    git push origin jdk8-removal
  else
    debug "'jdk8-removal' branch exists on the remote repository."
    git pull origin jdk8-removal
    debug "Pulled the latest changes from the 'jdk8-removal' branch"
  fi
  # Apply the patch file to the repository
  if git apply --check --allow-empty ../modifications.patch; then
    # If the patch file is not empty, try to apply it
    if ! git apply --allow-empty ../modifications.patch; then
      # If the patch cannot be applied, print an error message
      error "Failed to apply patch. The patch may not be applicable to the current state of the repository."
    fi
  else
    # If the patch file is empty, print a warning message
    warning "Patch file is empty. No changes to apply."
  fi
  # Print the commit message
  info "Commit message: $commit_message"
  # Print a message indicating that changes are being committed
  info "Committing changes for $repo"
  # Stage all changes for commit
  git add .
  # Commit the changes with the provided commit message
  git commit -m "$commit_message"

  # Get the list of remote repositories and print a debug message
  remote_output=$(git remote -v 2>&1)
  debug "remote_output: $remote_output"
  # Print a message indicating that changes are being pushed
  info "Pushing changes"
  # Push the changes to the 'jdk8-removal' branch of the origin remote
  git push origin jdk8-removal

  # Print a message indicating that the changes have been pushed
  info "Changes pushed"
}

export -f apply_patch_and_push
# Export the function for use in other scripts
export -f pull_and_set_upstream
