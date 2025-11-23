# AI Coding Agent Instructions for jdk8-removal

> Purpose: Automate and extend the Jenkins Plugin Modernization Pipeline (JDK 8 → 11/17/21/25) while preserving project conventions. Keep changes surgical. Do not introduce generic abstractions.

## Architecture & Data Flow
1. Discovery (`find-plugin-repos.sh`): Iterates all `jenkinsci/*` repos (paged REST), retrieves default branch, classifies Jenkinsfile Java usage, inspects POM-derived versions, writes date-stamped CSVs under `reports/`.
2. Modernization (`apply-recipe.sh`): Reads `recipes-to-apply.csv` (4 columns). For each repo: clone → run Maven OpenRewrite command(s) → capture diff → fork → create/ensure `jdk8-removal` branch → apply patch → push. Success/failure logged to `reports/repos_where_recipes_{work|dont_work}_DATE.csv` and per-repo recipe log in `reports/recipes/<repo>.csv`.
3. Unified JDK Tracking (`check-jdk-versions.sh`): Maps plugins from `plugins.json` via `get-all-plugins.sh`; scans ALL plugin repos once; detects JDK 17/21/25 via Jenkinsfile heuristics; outputs CSV+JSON `reports/jdk_versions_tracking_DATE.*` with summary in log file.
4. PR Collection (`jenkins-pr-collector.go`): GraphQL paginated search (monthly slices) for modernization-related PRs; filters out Dependabot/Renovate; matches body containing modernization keywords; outputs `jenkins_prs.json` + `found_prs.json`.
5. Reporting & Visualization: Python scripts (e.g. `plot-jenkins-stats.py`) consume accumulated CSV/JSON to produce `plugin_evolution.csv`, charts, and optionally Sheets updates.

## Conventions & Patterns
- All generated artifacts are date-stamped: `*_YYYY-MM-DD.{csv,json,txt}`; never overwrite historical files—append new runs.
- Logging: Use functions from `log-utils.sh` (`info|warning|success|error|debug`). Respect `DEBUG_MODE=true` for verbose debug output.
- Environment validation lives in `check-env.sh`; invoke / source it early in new entry scripts to enforce tooling (jq, parallel, gh, mvn, JAVA_HOME).
- Repo naming normalization uses `format_repo_name` (CSV friendly: hyphens → spaces, title case). Always reuse this before writing plugin names.
- Fork & patch workflow (modernization): Local clone → diff saved to `../modifications.patch` → fork via `gh repo fork` → new branch `jdk8-removal` → apply patch (skip if empty) → commit → push. Reuse `apply_patch_and_push`.
- Health checks (Docker compose) rely on sentinel files (e.g., `reports/repos-retrieved.txt`); when adding a service, prefer simple existence checks for readiness.
- XML parsing strategy: Strip namespaces via `remove-namespaces.xsl` then apply multiple XPath candidates (arrays flattened into space-delimited vars for GNU parallel compatibility).
- Rate limit handling: Functions like `check_rate_limit` pause with progress bar; retain this pattern for any added bulk GitHub operations.
- JDK inference combines Jenkinsfile scan + POM heuristics (`determine_jdk_version`, `get_java_version_from_pom`, `get_jenkins_core_version_from_pom`, parent POM version mapping). Use same logic if expanding version support.

## Key Files to Study First
- `config.sh`: Central date-based filenames + exported rate limit delay & XPath lists.
- `find-plugin-repos.sh`: Pattern for paginated org repo processing + parallel usage.
- `apply-recipe.sh` & `git-utils.sh`: Canonical modernization & forking workflow.
- `check-jdk-versions.sh`: Unified high-scale scanning strategy (sequential with rate limit + dedup).
- `jenkins-pr-collector.go`: GraphQL paging, filtering, retry, rate limiting.

## Adding / Modifying Scripts
- Source order: `log-utils.sh` → `csv-utils.sh` → `config.sh` → `check-env.sh` → domain helpers (e.g. `jenkinsfile_check.sh`). Maintain to ensure variables + logging available.
- Always export functions used by `parallel` (`export -f funcName`). Avoid relying on array inheritance; flatten arrays into string variables (`*_items`) like existing pattern.
- When introducing new output categories, follow naming: `reports/<descriptive_name>_DATE.(csv|json|txt)`.
- Prefer sequential processing if rate limit sensitivity outweighs parallel speed (see unified JDK script); otherwise wrap discrete lightweight tasks with `parallel`.

## Docker & Execution
- Default full pipeline: `docker compose up` → service chain (discovery → recipe application). For recipe-only runs use profile `recipes` (`apply-recipe-alone`).
- Build context copies all `*.sh`, `*.py`, `requirements.txt`; new runtime scripts must match those globs or adapt Dockerfile.
- Healthcheck scripts exit 0 when sentinel files appear; extend by writing a unique marker file at task completion.

## Safe Change Guidelines
- Never rewrite historical report files; generate new dated artifacts.
- Do not hardcode branch names other than `jdk8-removal` where modernization applies.
- Preserve commit message semantics from `recipes-to-apply.csv` (strip enclosing quotes as in existing code).
- Maintain rate limiting; any new GitHub loop should call `check_rate_limit`.
- Avoid altering existing CSV headers unless coordinated; downstream analysis expects them.

## Extending Tracking / Recipes
- New JDK version scanning: add version token patterns to unified script; keep JSON schema backward compatible (append fields, do not rename existing keys).
- Additional OpenRewrite recipes: append rows to `recipes-to-apply.csv` (4 columns). Do not rearrange column order.

## Common Pitfalls
- Missing `plugins.json` breaks unified tracking; run its generation beforehand if introducing dependency.
- Empty `modifications.patch` → skip apply (already handled); ensure new logic does not falsely mark success.
- Namespace removal prerequisite (`remove-namespaces.xsl`) must exist for POM parsing—surface error early.

## Recommended Agent Behaviors
- For batch additions: generate, then run script locally (or via container) to validate output files appear under `reports/` with correct date.
- For Go changes: run `go mod tidy` then `go build jenkins-pr-collector.go` before committing.

---
Feedback welcome: Identify unclear sections or missing workflow nuances to refine further.
