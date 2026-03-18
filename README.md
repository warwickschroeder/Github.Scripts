# Github.Scripts

A collection of PowerShell scripts for automating GitHub operations via the [`gh` CLI](https://cli.github.com/) and GitHub's GraphQL/REST APIs.

## Prerequisites

- **gh CLI** — install with `winget install GitHub.cli`, then authenticate with the required scopes:

  ```powershell
  gh auth login --scopes read:project,read:org,project
  ```

## Scripts

### get-issues-on-project-board.ps1

Lists all issues in a specific column of a GitHub Projects V2 board. Supports filtering out activity from a specific team, limiting results, and exporting to CSV.

**Output fields:**

| Field                | Description                                                                                       |
| -------------------- | ------------------------------------------------------------------------------------------------- |
| `Repo`               | Repository name in `owner/repo` format                                                            |
| `Issue #`            | Issue number                                                                                      |
| `Title`              | Issue title                                                                                       |
| `Opened`             | Date the issue was created (`yyyy-MM-dd`)                                                         |
| `Date Added`         | Date the issue was added to the project board (`yyyy-MM-dd`), from the board's "Date Added" field |
| `Age (days)`         | Number of days since the issue was opened                                                         |
| `Days in Inbox`      | Number of days since the issue was added to the board column                                      |
| `Comments`           | Total number of comments on the issue                                                             |
| `Reactions`          | Total reactions across the issue body and all its comments                                        |
| `Last Edit`          | Date of the most recent update to the issue (`yyyy-MM-dd`)                                        |
| `Labels`             | Comma-separated list of labels applied to the issue                                               |
| `Last External Edit` | Date of the most recent timeline event from someone outside `-ExcludeTeam` (only with that flag)  |
| `URL`                | Full URL to the issue on GitHub                                                                   |

```powershell
# Basic usage — list issues in the "Inbox" column
.\get-issues-on-project-board.ps1 -Org "your-org" -ProjectNumber 1

# Exclude a team's activity and show last external edit date
.\get-issues-on-project-board.ps1 -Org "your-org" -ProjectNumber 1 -ExcludeTeam "my-team"

# Export results to CSV
.\get-issues-on-project-board.ps1 -Org "your-org" -ProjectNumber 1 -CsvPath "inbox.csv"

# Customise the column and status field names
.\get-issues-on-project-board.ps1 -Org "your-org" -ProjectNumber 1 -ColumnName "Triage" -StatusFieldName "Status"

# Limit the number of results
.\get-issues-on-project-board.ps1 -Org "your-org" -ProjectNumber 1 -Limit 10
```

| Parameter          | Required | Default   | Description                                                     |
| ------------------ | -------- | --------- | --------------------------------------------------------------- |
| `-Org`             | Yes      | —         | GitHub organisation login                                       |
| `-ProjectNumber`   | Yes      | —         | Projects V2 board number                                        |
| `-StatusFieldName` | No       | `Status`  | Name of the status field on the board                           |
| `-ColumnName`      | No       | `Inbox`   | Column/status value to filter by                                |
| `-ExcludeTeam`     | No       | —         | Team slug; excludes members' activity from "Last External Edit" |
| `-CsvPath`         | No       | —         | Path to export results as CSV                                   |
| `-Limit`           | No       | `0` (all) | Max number of issues to return                                  |

### set-project-board-fields.ps1

Updates GitHub Projects V2 fields for issues listed in a CSV file. The `-FieldMap` parameter maps CSV column names to project board field names. Supports text, number, date, and single-select field types.

```powershell
# Update a single field
.\set-project-board-fields.ps1 -Org "your-org" -ProjectNumber 1 -CsvPath "issues.csv" `
    -FieldMap @{ "Comments" = "My Comments Field" }

# Map multiple CSV columns to board fields
.\set-project-board-fields.ps1 -Org "your-org" -ProjectNumber 1 -CsvPath "issues.csv" `
    -FieldMap @{ "Reactions" = "Engagement"; "Age (days)" = "Issue Age" }

# Test with a limited number of rows first
.\set-project-board-fields.ps1 -Org "your-org" -ProjectNumber 1 -CsvPath "issues.csv" `
    -FieldMap @{ "Comments" = "My Comments Field" } -Limit 3
```

| Parameter        | Required | Default   | Description                                             |
| ---------------- | -------- | --------- | ------------------------------------------------------- |
| `-Org`           | Yes      | —         | GitHub organisation login                               |
| `-ProjectNumber` | Yes      | —         | Projects V2 board number                                |
| `-CsvPath`       | Yes      | —         | Path to the input CSV file (must have a `URL` column)   |
| `-FieldMap`      | Yes      | —         | Hashtable mapping CSV column names to board field names |
| `-Limit`         | No       | `0` (all) | Max number of CSV rows to process                       |
