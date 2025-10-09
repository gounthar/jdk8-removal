# GitHub Actions Setup for JDK 25 Tracking

This document explains how to set up the automated GitHub Actions workflow for JDK 25 compatibility tracking.

## Overview

The workflow (`jdk25-tracking.yml`) automatically:
- 🔍 Scans Jenkins plugins for JDK 25 usage
- 📊 Updates the Google Spreadsheet
- ✅ Validates results against manual tracking
- 💾 Commits results back to the repository
- 📦 Uploads artifacts for historical tracking

## Schedule

- **Daily:** Runs every day at 6:00 AM UTC
- **Manual:** Can be triggered manually with option for full scan

## Required Secrets

You need to add two secrets to your GitHub repository:

### 1. GOOGLE_CREDENTIALS

The Google service account credentials JSON file.

**Steps:**
1. Go to your repository on GitHub
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `GOOGLE_CREDENTIALS`
5. Value: Copy the entire contents of your Google service account credentials file (e.g., `google-credentials.json`)

**To get the JSON content:**
```bash
cat google-credentials.json
```

**Example format (DO NOT use this, use your actual credentials):**
```json
{
  "type": "service_account",
  "project_id": "<your-project-id>",
  "private_key_id": "...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "<your-service-account-email>",
  "client_id": "...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "..."
}
```

### 2. JDK25_SPREADSHEET_ID

The ID of the Google Spreadsheet to update.

**Steps:**
1. Go to your repository on GitHub
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `JDK25_SPREADSHEET_ID`
5. Value: Your spreadsheet ID (extract from the spreadsheet URL)

**To get the spreadsheet ID from URL:**
```text
https://docs.google.com/spreadsheets/d/SPREADSHEET_ID_HERE/edit
                                          ^^^^^^^^^^^^^^^^^^^^
Example: 1pNHWUuTx4eebJ8xOiZd6LM3IkzbNUBevRdiBxLK4WPI
```

### 3. GITHUB_TOKEN (Automatic)

GitHub automatically provides this token - no setup needed.

## Service Account Permissions

Make sure the service account has **Editor** access to the spreadsheet:

1. Open your spreadsheet in Google Sheets
2. Click **Share** button
3. Add your service account email (found in your credentials JSON file, e.g., `your-service-account@your-project.iam.gserviceaccount.com`)
4. Role: **Editor**
5. Uncheck "Notify people"
6. Click **Share**

## Manual Trigger

### Run an Incremental Scan (Default)

1. Go to **Actions** tab in your repository
2. Select **JDK 25 Compatibility Tracking** workflow
3. Click **Run workflow**
4. Leave "Run full scan" unchecked
5. Click **Run workflow**

This uses the incremental script which only scans new/changed plugins (faster).

### Run a Full Scan

1. Go to **Actions** tab in your repository
2. Select **JDK 25 Compatibility Tracking** workflow
3. Click **Run workflow**
4. Check ✅ "Run full scan instead of incremental"
5. Click **Run workflow**

This scans all 250 plugins from scratch (takes 20-30 minutes).

## Workflow Features

### Incremental Scanning
- Uses `check-jdk25-with-pr-incremental.sh` by default
- Only rescans plugins that haven't been validated yet
- Much faster (typically 5-10 minutes)
- Maintains `validated_jdk25_plugins.txt` for tracking

### Full Scanning
- Uses `check-jdk25-with-pr.sh`
- Scans all 250 plugins from scratch
- Takes 20-30 minutes
- Use when you want to refresh all data

### Automatic Updates
- Downloads latest Jenkins plugin registry
- Generates top-250 plugins list
- Runs detection with PR tracking
- Updates Google Spreadsheet
- Validates results
- Commits reports back to repo

### Artifacts
- Keeps results for 90 days
- Includes:
  - JSON reports
  - CSV reports
  - Log files

### Summary
- Displays results in GitHub Actions UI
- Shows count of plugins with JDK 25
- Lists all plugins with PR links

## Workflow Outputs

### Committed Files
- `reports/jdk25_tracking_with_prs_YYYY-MM-DD.json` - Detection results
- `reports/jdk25_tracking_with_prs_YYYY-MM-DD.csv` - CSV format
- `logs/jdk25_tracking_YYYY-MM-DD.log` - Execution log
- `validated_jdk25_plugins.txt` - List of validated plugins

### Google Spreadsheet
- Updated with latest JDK 25 data
- Installation Count header updated to current month
- PR URLs and merge status populated

### GitHub Artifacts
- Available for download from Actions tab
- Retained for 90 days
- Useful for historical analysis

## Troubleshooting

### Workflow Fails: "Permission denied"

**Problem:** Service account doesn't have access to spreadsheet

**Solution:**
1. Open the spreadsheet
2. Share with your service account email (found in your credentials JSON file)
3. Grant Editor permissions

### Workflow Fails: "Invalid credentials"

**Problem:** GOOGLE_CREDENTIALS secret is incorrect

**Solution:**
1. Verify the JSON is valid (use `jq . google-credentials.json`)
2. Copy the ENTIRE file content including braces
3. Update the secret in GitHub Settings

### Workflow Fails: "Spreadsheet not found"

**Problem:** JDK25_SPREADSHEET_ID is incorrect

**Solution:**
1. Get the ID from your spreadsheet URL (the long alphanumeric string between `/d/` and `/edit`)
2. Update the secret with the correct spreadsheet ID

### Rate Limiting

The workflow includes:
- `RATE_LIMIT_DELAY=2` (2 seconds between API calls)
- Automatic retry with exponential backoff
- Should handle GitHub API limits well

If you still hit limits:
- Run less frequently (change cron schedule)
- Increase `RATE_LIMIT_DELAY` in workflow file

### No Changes Committed

This is normal if:
- No new plugins added JDK 25 since last run
- Running incremental scan with no changes

## Monitoring

### Check Workflow Status

1. Go to **Actions** tab
2. View recent runs
3. Click on a run to see details
4. Check summary for results

### View Results

**In GitHub:**
- Actions → Workflow run → Summary tab
- Shows counts and plugin list

**In Spreadsheet:**
- Opens automatically updated
- Check Statistics sheet for trends

**In Repository:**
- Browse `reports/` directory
- Download artifacts from Actions

## Customization

### Change Schedule

Edit `.github/workflows/jdk25-tracking.yml`:

```yaml
schedule:
  # Examples:
  - cron: '0 6 * * *'      # Daily at 6 AM UTC
  - cron: '0 6 * * 1'      # Weekly on Monday at 6 AM UTC
  - cron: '0 6 1 * *'      # Monthly on 1st at 6 AM UTC
  - cron: '0 */6 * * *'    # Every 6 hours
```

### Change Rate Limit Delay

Edit the workflow file:

```yaml
env:
  RATE_LIMIT_DELAY: 5  # Change from 2 to 5 seconds
```

### Skip Commit

Comment out the "Commit and push results" step if you don't want to auto-commit.

### Change Artifact Retention

Edit the workflow file:

```yaml
retention-days: 30  # Change from 90 to 30 days
```

## Best Practices

1. **Run incremental scans daily** - Fast and efficient
2. **Run full scan monthly** - Refresh all data periodically
3. **Monitor the Actions tab** - Check for failures
4. **Review the spreadsheet** - Verify data quality
5. **Keep secrets secure** - Never commit credentials to repo

## Security Notes

- ✅ Credentials stored as GitHub secrets (encrypted)
- ✅ Credentials file cleaned up after workflow runs
- ✅ Service account has minimal permissions (Editor on one spreadsheet)
- ✅ Workflow uses official GitHub actions
- ✅ No credentials logged or exposed

## Support

If you encounter issues:

1. Check the workflow logs in Actions tab
2. Review this documentation
3. Check `JDK25_TRACKING.md` for script details
4. Verify all secrets are set correctly
5. Ensure service account has spreadsheet access

## Related Documentation

- `JDK25_TRACKING.md` - Main tracking documentation
- `README.md` - Project overview
- `.github/workflows/jdk25-tracking.yml` - Workflow definition
