# Jenkinsci Repository Analysis

This project is designed to analyze all repositories under the `jenkinsci` organization on GitHub. It checks for the presence of a Jenkinsfile in each repository and whether specific Java version numbers (11, 17, or 21) are found in the Jenkinsfile.

## Requirements

- jq
- parallel
- A GitHub Personal Access Token set as the `GITHUB_TOKEN` environment variable

## Usage

Run the `find-plugin-repos.sh` script:

```bash
./find-plugin-repos.sh
```

This script fetches all repositories under the `jenkinsci` organization, checks if a Jenkinsfile exists in either the `main` or `master` branch of each repository, and if it does, checks if the numbers 11, 17, or 21 exist in the Jenkinsfile. If these numbers do not exist, it writes the repository name and URL to a CSV file named `plugins_without_java_versions.csv`.

## Output
The output of the script is a CSV file named `plugins_without_java_versions.csv` that contains the names and URLs of the repositories where the script did not find any of the specified Java version numbers in the Jenkinsfile.
