#!/bin/bash

# config.sh

# Get the current date in YYYY-MM-DD format
# The `date` command is used with the `+"%Y-%m-%d"` option to format the date.
current_date=$(date +"%Y-%m-%d")

# Define variables for the CSV files
# Each variable is assigned a string that includes the current date and the .csv extension.
# The current date is included in the filename by appending `_$current_date` to the base filename.
csv_file="reports/plugins_without_java_versions_$current_date.csv"
csv_file_no_jenkinsfile="reports/repos_without_jenkinsfile_$current_date.csv"
csv_file_compiles="reports/repos_where_recipes_work_$current_date.csv"
csv_file_does_not_compile="reports/repos_where_recipes_dont_work_$current_date.csv"
csv_file_recipe_list="/datas/recipes-to-apply.csv"
plugins_list_no_jenkinsfile_output_file="reports/plugins_no_jenkinsfile_$current_date.txt"  # Define the output file name.
plugins_list_no_jenkinsfile_main_output_file="plugins_no_jenkinsfile.txt"  # Define the output file name.
plugins_list_old_java_output_file="reports/plugins_old_java_$current_date.txt"  # Define the output file name.
plugins_list_old_java_main_output_file="plugins_old_java.txt"
plugins_list_depends_on_java_8_main_output_file="depends_on_java_8.txt"
plugins_list_depends_on_java_11_main_output_file="depends_on_java_11.txt"
plugins_list_output_file="plugins.txt"  # Define the output file name.
plugins_no_jenkinsfile=
plugins_list_jdk11_output_file="plugins_jdk11.txt"
export plugins_no_jenkinsfile
export plugins_list_jdk11_output_file
# The presence of this file will be used to determine whether the repositories have already been retrieved.
# Useful in the docker compose heakthcheck.
repos_retrieved_file="reports/repos-retrieved.txt"
csv_file_jdk11="reports/plugins_using_jdk11_$current_date.csv"

plugins_list_jdk11_main_output_file="plugins_jdk11_main_$current_date.txt"

# New variables for depends_on_java files
depends_on_java_8_txt="depends_on_java_8.txt"
depends_on_java_8_csv="depends_on_java_8.csv"
depends_on_java_11_txt="depends_on_java_11.txt"
depends_on_java_11_csv="depends_on_java_11.csv"

# Export the variables so they can be used by other scripts
export plugins_list_jdk11_main_output_file
export depends_on_java_8_txt
export depends_on_java_8_csv
export depends_on_java_11_txt
export depends_on_java_11_csv

# Define the rate limit delay in seconds
RATE_LIMIT_DELAY=${RATE_LIMIT_DELAY:-2}

# Export the variables so they can be used by other scripts
# The `export` command is used to make the variables available to child processes of this script.
export csv_file
export csv_file_no_jenkinsfile
export csv_file_compiles
export csv_file_does_not_compile
export csv_file_recipe_list
export repos_retrieved_file
export plugins_list_no_jenkinsfile_output_file
export plugins_list_old_java_output_file
export plugins_list_output_file
export plugins_list_no_jenkinsfile_main_output_file
export plugins_list_old_java_main_output_file
export plugins_list_depends_on_java_8_main_output_file
export plugins_list_depends_on_java_11_main_output_file
export csv_file_jdk11
export RATE_LIMIT_DELAY

# New configuration variables for pom.xml analysis
declare -a pom_xml_java_version_xpath=(
  "//properties/version.java.source"
  "//properties/java.level"
  "//properties/compileTarget"
  "//properties/maven.compiler.source"
  "//properties/maven.compiler.target"
  "//plugin[artifactId='maven-compiler-plugin']/configuration/source"
  "//plugin[artifactId='maven-compiler-plugin']/configuration/target"
)

# shell arrays are not automatically inherited by subshells created via parallel. One workaround is to store your array elements in a single variable, then rebuild the array in each function.
pom_xml_java_version_xpath_items="//properties/maven.compiler.release //properties/java.version //properties/project.java.version //properties/jdk.version //properties/jvm.version //properties/version.java.source //properties/java.level //properties/compileTarget //properties/maven.compiler.source //properties/maven.compiler.target //plugin[artifactId='maven-compiler-plugin']/configuration/source //plugin[artifactId='maven-compiler-plugin']/configuration/target"

declare -a pom_xml_jenkins_core_version_xpath=(
  "//properties/jenkins.baseline"
  "//properties/jenkins.version"
  "//dependencyManagement/dependencies/dependency[artifactId='jenkins-core']/version"
)
# shell arrays are not automatically inherited by subshells created via parallel. One workaround is to store your array elements in a single variable, then rebuild the array in each function.
pom_xml_jenkins_core_version_xpath_items="//properties/jenkins.baseline //properties/jenkins.version //dependencyManagement/dependencies/dependency[artifactId='jenkins-core']/version"

declare -a pom_xml_jenkins_parent_pom_version_xpath=(
  "//parent[artifactId='plugin']/version"
)
pom_xml_jenkins_parent_pom_version_xpath_items="//parent[artifactId='plugin']/version"

export pom_xml_java_version_xpath
export pom_xml_jenkins_core_version_xpath
export pom_xml_jenkins_parent_pom_version_xpath
export pom_xml_java_version_xpath_items
export pom_xml_jenkins_core_version_xpath_items
export pom_xml_jenkins_parent_pom_version_xpath_items
