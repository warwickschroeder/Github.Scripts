# Github.Scripts

A collection of PowerShell scripts for automating GitHub operations via the [`gh` CLI](https://cli.github.com/) and GitHub's GraphQL/REST APIs.

## Prerequisites

- **gh CLI** — install with `winget install GitHub.cli`, then authenticate with the required scopes:

  ```powershell
  gh auth login --scopes read:project,read:org
  ```

## Scripts

### get-issues-on-project-board.ps1

Lists all issues in a specific column of a GitHub Projects V2 board. Supports filtering out activity from a specific team, limiting results, and exporting to CSV.

Output columns: `Repo`, `Issue #`, `Title`, `Opened`, `Date Added`, `Age (days)`, `Days in Inbox`, `Comments`, `Reactions`, `Last Edit`, `Labels`, `Last External Edit` (when `-ExcludeTeam` is used), `URL`.

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
