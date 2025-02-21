#!/usr/bin/env bash

# Debug script to download a POM and call parsing functions

# Stop on errors
set -e

# Source the existing definitions (adjust the path if needed)
source jenkinsfile_check.sh

# Download the POM to a local file
pom_url="https://github.com/jenkinsci/concordionpresenter-plugin/raw/refs/heads/master/pom.xml"
pom_file='pom_concordion.xml'
curl  -s -L -w "\n%{http_code}" -H "Authorization: token $GITHUB_TOKEN"  -o $pom_file $pom_url

echo "Testing get_jenkins_core_version_from_pom..."
core_version="$(get_jenkins_core_version_from_pom "$pom_file")"
echo "Core version: $core_version"

echo "Testing get_java_version_from_pom..."
java_version="$(get_java_version_from_pom "$pom_file")"
echo "Java version: $java_version"

echo "Testing get_jenkins_parent_pom_version_from_pom..."
parent_version="$(get_jenkins_parent_pom_version_from_pom "$pom_file")"
echo "Parent POM version: $parent_version"
