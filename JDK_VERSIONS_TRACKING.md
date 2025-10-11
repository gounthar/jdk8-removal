# JDK Versions Tracking (17, 21, 25)

**Status:** ✅ Operational (First successful run: 2025-10-11)

## Overview

Unified tracking system that monitors JDK 17, 21, and 25 adoption across ALL Jenkins plugins (~1,892 plugins) in a single efficient pass.

## Components

### 1. Core Script: `check-jdk-versions.sh`

**Purpose:** Scans all Jenkins plugins for JDK version usage in Jenkinsfiles

**Key Features:**
- Single-pass checking (fetches each Jenkinsfile once, checks all versions)
- Scans ALL plugins by default (not just top 250)
- Generates both CSV and JSON reports
- Handles repository failures gracefully (continues processing even if individual repos fail)
- Rate-limited API calls (2 second delay)
- Security: Conditional auth headers, token protection in debug mode

**Output Files:**
- `reports/jdk_versions_tracking_YYYY-MM-DD.json` - Complete tracking data (1,892 plugins)
- `reports/jdk_versions_tracking_YYYY-MM-DD.csv` - CSV format
- Updates `plugin_evolution.csv` - Historical time series data

### 2. Automated Workflow: `.github/workflows/jdk-versions-tracking.yml`

**Schedule:** Daily at 7:00 AM UTC
**Duration:** ~83 minutes
**Concurrency:** Single workflow instance (prevents overlapping runs)

**Steps:**
1. Install dependencies (jq, parallel, gh CLI, curl)
2. Download Jenkins plugin registry
3. Run unified tracking script
4. Generate summary with adoption statistics
5. Commit and push results to main branch
6. Upload artifacts (90-day retention)

**Environment Variables:**
- `GITHUB_TOKEN` / `GH_TOKEN` - GitHub API authentication
- `RATE_LIMIT_DELAY` - API rate limiting (default: 2)
- `DEBUG_MODE` - Enable debug output (default: false)

### 3. Data Processing: `process_reports.sh`

Extracts JDK 17, 21, and 25 data from unified tracking files and updates `plugin_evolution.csv` for visualization.

**New Columns Added:**
- `Plugins_With_JDK17` - Count of plugins building with JDK 17
- `Plugins_With_JDK21` - Count of plugins building with JDK 21
- `Plugins_With_JDK25` - Count of plugins building with JDK 25

**Backward Compatibility:** Falls back to legacy tracking files when new unified files don't exist.

### 4. Visualization: `plot-jenkins-stats.py`

Generates evolution plots with JDK 17, 21, and 25 trend lines.

**Colors:**
- JDK 17: Turquoise (#1abc9c)
- JDK 21: Orange (#f39c12)
- JDK 25: Purple (#9b59b6)

## First Run Results (2025-10-11)

```
Total plugins scanned: 1,892
Plugins with Jenkinsfile: 1,321 (69.8%)

JDK Adoption (of plugins with Jenkinsfile):
- JDK 17: 728 plugins (55.1%)
- JDK 21: 642 plugins (48.6%)
- JDK 25: 72 plugins (5.5%)
```

## Bug Fixes Applied

During the first deployment, three critical bugs were identified and fixed:

### Fix #1: Unbound Variables (PR #561)
**Problem:** Script failed with `LOG_FILE: unbound variable` error
**Solution:** Added default values using `${VAR:-default}` syntax
**Files:** `check-jdk-versions.sh` lines 13 and 31

### Fix #2: Arithmetic Expression Exit (PR #562)
**Problem:** `((plugin_count++))` caused exit when count was 0 due to `set -e`
**Solution:** Added `|| true` to prevent exit on zero evaluation
**Files:** `check-jdk-versions.sh` line 235

### Fix #3: Repository Failure Handling (Commit 6b73bf0)
**Problem:** Script exited when individual repository checks failed
**Solution:** Added `|| true` to continue processing all repos
**Files:** `check-jdk-versions.sh` line 252

## Daily Workflow Schedule (UTC)

1. **5:30 AM** - Update Plugins List (top 250 + all plugin lists)
2. **7:00 AM** - JDK Versions Tracking (17, 21, 25) [~83 minutes]
3. **8:30 AM** - Update Plugins Evolution Plot [uses fresh data from step 2]

## Comparison with Legacy JDK 25 Tracking

### Old System (`check-jdk25-with-pr.sh`)
- Tracked only **top 204 most popular plugins**
- Required PR verification (searched git history for merge commits)
- Found 22 plugins with JDK 25 (10.8% of top plugins)
- Took similar time but checked far fewer plugins

### New Unified System (`check-jdk-versions.sh`)
- Tracks **ALL 1,892 plugins**
- Checks current Jenkinsfile content (faster, no git history search)
- Found 72 plugins with JDK 25 (3.8% of all plugins)
- **Includes all 22 from old tracking + 50 additional plugins**

**Key Insight:** Top/popular plugins adopt new JDK versions faster (10.8%) than the overall ecosystem (3.8%).

## Pattern Detection

The script detects JDK versions using these regex patterns:

```bash
# JDK 17
grep -qiE "(jdk['\": ]+['\"]?17['\"]?|java['\": ]+['\"]?17['\"]?|openjdk-?17)"

# JDK 21
grep -qiE "(jdk['\": ]+['\"]?21['\"]?|java['\": ]+['\"]?21['\"]?|openjdk-?21)"

# JDK 25
grep -qiE "(jdk['\": ]+['\"]?25['\"]?|java['\": ]+['\"]?25['\"]?|openjdk-?25)"
```

## Monitoring

Workflow completion notifications can be sent via Telegram bridge:
- Success notifications include runtime and adoption statistics
- Failure notifications include error details and run URL
- Configurable per-session emoji identification

## Future Enhancements

Possible improvements:
1. Add JDK 11 tracking to complete the picture
2. Implement trend analysis and adoption rate predictions
3. Add alerting for significant adoption changes
4. Create detailed per-plugin history tracking
5. Generate weekly/monthly summary reports

## Troubleshooting

### Workflow Fails Immediately
Check for:
- Unbound variable errors → Ensure all variables have defaults
- Arithmetic expression failures → Add `|| true` where needed
- Permission issues → Verify `GITHUB_TOKEN` has required scopes

### Incomplete Data
- Check `logs/jdk_versions_tracking_YYYY-MM-DD.log` for errors
- Review rate limiting delays
- Verify plugin registry download succeeded

### Plot Not Updating
- Ensure plot workflow runs AFTER tracking completes (8:30 AM UTC)
- Check `plugin_evolution.csv` for new data
- Verify `process_reports.sh` is extracting JDK columns

## Related Documentation

- [JDK 25 Tracking](JDK25_TRACKING.md) - Legacy JDK 25-specific tracking system
- [CLAUDE.md](CLAUDE.md) - Project guidance and coding patterns
- [README.md](README.md) - Project overview and usage instructions
