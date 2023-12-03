# Jenkinsci Repository Analysis

This project is designed to analyze all repositories under the `jenkinsci` organization on GitHub. It checks for the presence of a Jenkinsfile in each repository and whether specific Java version numbers (11, 17, or 21) are found in the Jenkinsfile. It also applies a series of operations to each repository, including forking the repository, creating a new branch, and pushing changes to that branch.

## Requirements

- jq
- parallel
- A GitHub Personal Access Token set as the `GITHUB_TOKEN` environment variable

## Usage

1. Run the `find-plugin-repos.sh` script:

```bash
./find-plugin-repos.sh
```

This script fetches all repositories under the `jenkinsci` organization, checks if a Jenkinsfile exists in either the `main` or `master` branch of each repository, and if it does, checks if the numbers 11, 17, or 21 exist in the Jenkinsfile. If these numbers do not exist, it writes the repository name and URL to a CSV file named plugins_without_java_versions.csv.

2. Run the apply-recipe.sh script:

```bash
./apply-recipe.sh
```

This script reads a CSV file that contains a list of recipes to apply to the repositories. For each recipe, it applies the recipe to each repository, commits the changes, and pushes the changes to a new branch in a fork of the repository.  

## Output
The output of the find-plugin-repos.sh script is a CSV file named plugins_without_java_versions.csv that contains the names and URLs of the repositories where the script did not find any of the specified Java version numbers in the Jenkinsfile.

The output of the apply-recipe.sh script is a series of CSV files that contain the names and URLs of the repositories where the script made changes, failed to make changes, or did not find a Jenkinsfile.