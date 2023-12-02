* Create a utility script that decorates the output with colors for:
  * Information
  * Warning
  * Success
  * Error
  * Debug
* Replace the echo commands with calls to the utility script functions. 
* Create a CSV file that contains all the recipes we want to apply to the repositories.
  * We could have fields for the recipe name, its URL on openrewrite.org, the maven command to run to apply the recipe, and the commit message to use when committing the changes.
  * We would read this CSV file in the script and use the information to apply the recipes to the repositories one by one.
    * We would have colored logs to let the end user know we are applying the recipe and when we are done.
    * We would have a specific CSV file per recipe that would contain the names and URLs of the repositories where the script made changes successfully.
    * We would have a specific CSV file per recipe that would contain the names and URLs of the repositories where the script failed to make changes.
    * Whenever the script makes changes to a repository and is successful (maven-wise), it would :
      * fork the repo thanks to gh
      * create a branch named `jdk8-removal`
      * commit the changes
      * push them to the forked repository.
      * enter the information into the CSV file for the recipe.
    * Whenever the script makes changes to a repository but fails (maven-wise), it would :
      * enter the information into the CSV file for the recipe.
    * When the script will be done with all the repositories and all the recipes, it will create a PR for each forked repository starting from the 'jdk8-removal' branch if and only if the maven command  `mvn -U -ntp verify -Dmaven.test.skip=true` is successful.