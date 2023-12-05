 
* Create a CSV file that contains all the recipes we want to apply to the repositories.
    * When the script will be done with all the repositories and all the recipes, it will create a PR for each forked repository starting from the 'jdk8-removal' branch if and only if the maven command  `mvn -U -ntp verify -Dmaven.test.skip=true` is successful.
* Once we've made the first fork creation/push, we'll have to detect for the next loop we're already in the fork, so no need to fork, no need to branch, just a git pull and a git push. 
* Add a date to the file that lists plugins without a reference to JDK 17 11 or 21.
* Add a CSV report per plugin that lists the plugins that have been modified and the ones that have not been modified, and the list of recipes, and if they produced a change or not.