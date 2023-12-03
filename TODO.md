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
* Delete rewrite.yml from the repositories where the script was successful before committing the changes.
* Removes the problem of git status:
  * [INFO] Processing ivytrigger-plugin in /tmp/plugins/ivytrigger-plugin
  * [DEBUG] ivytrigger-plugin in /tmp/plugins/ivytrigger-plugin already exists, pulling latest changes
  * [ERROR] Cannot pull with rebase because there are unstaged changes. Please commit or stash them.
  * Saved working directory and index state WIP on jdk8-removal: 20aefd7 Merge pull request #36 from
  * jenkinsci/dependabot/maven/org.jenkins-ci.plugins-plugin-4.50
  * [ERROR] Failed to pull the latest changes even after stashing. Exiting the script.
  * error: cannot pull with rebase: You have unstaged changes.
  * error: please commit or stash them.
  * There is no tracking information for the current branch.
  * Please specify which branch you want to rebase against.
  * See git-pull(1) for details.
  * git pull <remote> <branch>
  * If you wish to set tracking information for this branch you can do so with:
  * git branch --set-upstream-to=<remote>/<branch> jdk8-removal 
* Once we've made the first fork creation/push, we'll have to detect for the next loop we're already in the fork, so no need to fork, no need to branch, just a git pull and a git push. 
* Add a date to the file that lists plugins without a reference to JDK 17 11 or 21.