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
csv_file_recipe_list="recipes-to-apply.csv"

# Export the variables so they can be used by other scripts
# The `export` command is used to make the variables available to child processes of this script.
export csv_file
export csv_file_no_jenkinsfile
export csv_file_compiles
export csv_file_does_not_compile
export csv_file_recipe_list