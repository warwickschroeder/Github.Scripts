# get-issues.ps1
# Lists all issues in the "Inbox" column of a GitHub Projects V2 board
#
# Prerequisites: gh cli (winget install GitHub.cli) + gh auth login
# Usage: .\get-issues.ps1 -Org "your-org" -ProjectNumber 1
#        .\get-issues.ps1 -Org "your-org" -ProjectNumber 1 -ExcludeTeam "my-team"
#        .\get-issues.ps1 -Org "your-org" -ProjectNumber 1 -CsvPath "inbox.csv"

param(
    [Parameter(Mandatory)][string]$Org,
    [Parameter(Mandatory)][int]$ProjectNumber,
    [string]$StatusFieldName = "Status",
    [string]$ColumnName = "Inbox",
    [string]$ExcludeTeam,
    [string]$CsvPath,
    [int]$Limit = 0
)

# Verify gh is available and authenticated
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "gh CLI not found. Install with: winget install GitHub.cli"
    exit 1
}

# If a team is specified, fetch its members
$teamMembers = @()
if ($ExcludeTeam) {
    Write-Host "Fetching members of team '$ExcludeTeam'..."
    $membersJson = gh api "/orgs/$Org/teams/$ExcludeTeam/members" --paginate 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to fetch team members: $membersJson"
        exit 1
    }
    $teamMembers = ($membersJson | ConvertFrom-Json) | ForEach-Object { $_.login }
    Write-Host "Excluding activity from: $($teamMembers -join ', ')"
}

# Fetch project items with pagination
$allItems = @()
$cursor = $null

do {
    $afterClause = if ($cursor) { ", after: \`"$cursor\`"" } else { "" }

    $query = @"
query {
  organization(login: \"$Org\") {
    projectV2(number: $ProjectNumber) {
      items(first: 100$afterClause) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          fieldValueByName(name: \"$StatusFieldName\") {
            ... on ProjectV2ItemFieldSingleSelectValue {
              name
            }
          }
          dateAdded: fieldValueByName(name: \"Date Added\") {
            ... on ProjectV2ItemFieldDateValue {
              date
            }
          }
          content {
            ... on Issue {
              title
              number
              url
              createdAt
              updatedAt
              comments { totalCount }
              repository {
                nameWithOwner
              }
            }
          }
        }
      }
    }
  }
}
"@

    $response = gh api graphql -f query="$query" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "GraphQL query failed: $response"
        exit 1
    }

    $data = $response | ConvertFrom-Json
    $items = $data.data.organization.projectV2.items
    $allItems += $items.nodes
    $cursor = if ($items.pageInfo.hasNextPage) { $items.pageInfo.endCursor } else { $null }

} while ($cursor)

# Filter to Inbox column and only issues (not draft items)
$inboxIssues = $allItems | Where-Object {
    $_.fieldValueByName.name -eq $ColumnName -and
    $_.content.title
}

if ($inboxIssues.Count -eq 0) {
    Write-Host "No issues found in the '$ColumnName' column."
    exit 0
}

if ($Limit -gt 0) {
    $inboxIssues = $inboxIssues | Select-Object -First $Limit
}

Write-Host "`nIssues in '$ColumnName' ($($inboxIssues.Count)):`n"

# Helper: get the last update date excluding team members
function Get-LastExternalUpdate($repoFullName, $issueNumber) {
    $events = gh api "/repos/$repoFullName/issues/$issueNumber/timeline" --paginate 2>&1
    if ($LASTEXITCODE -ne 0) { return "" }

    $timeline = $events | ConvertFrom-Json

    # Exclude project board activity
    $excludedEvents = @("added_to_project", "moved_columns_in_project", "removed_from_project", "converted_note_to_issue")

    # Walk events newest-first, find the first one not from a team member
    $sorted = $timeline |
        Where-Object {
            $_.event -notin $excludedEvents -and
            $(
                $login = if ($_.actor.login) { $_.actor.login } elseif ($_.user.login) { $_.user.login } else { $null }
                $login -and ($login -notin $teamMembers)
            )
        } |
        Sort-Object { if ($_.created_at) { [datetime]$_.created_at } elseif ($_.updated_at) { [datetime]$_.updated_at } else { [datetime]::MinValue } } -Descending

    if ($sorted) {
        $latest = $sorted | Select-Object -First 1
        $date = if ($latest.created_at) { $latest.created_at } else { $latest.updated_at }
        if ($date) {
            return ([datetime]$date).ToString("yyyy-MM-dd")
        }
    }
    return ""
}

$count = 0
$results = $inboxIssues |
    Sort-Object { [datetime]$_.content.updatedAt } -Descending |
    ForEach-Object {
        $issue = $_.content
        $updatedDate = [datetime]$issue.updatedAt
        $updated = $updatedDate.ToString("yyyy-MM-dd")
        $dateAdded = if ($_.dateAdded.date) { $_.dateAdded.date } else { "" }

        $lastExternal = ""
        if ($ExcludeTeam) {
            $count++
            Write-Host "`r  Fetching timeline $count/$($inboxIssues.Count): $($issue.repository.nameWithOwner)#$($issue.number)" -NoNewline
            $lastExternal = Get-LastExternalUpdate $issue.repository.nameWithOwner $issue.number
        }

        $opened = ([datetime]$issue.createdAt).ToString("yyyy-MM-dd")

        $obj = [ordered]@{
            Repo         = $issue.repository.nameWithOwner
            "Issue #"    = $issue.number
            Title        = $issue.title
            "Opened"     = $opened
            "Date Added" = $dateAdded
            "Comments"   = $issue.comments.totalCount
            "Last Edit"  = $updated
        }
        if ($ExcludeTeam) {
            $obj["Last External Edit"] = $lastExternal
        }
        $obj["URL"] = $issue.url

        [PSCustomObject]$obj
    }

if ($ExcludeTeam) { Write-Host "" }

$results | Format-Table -AutoSize -Wrap

if ($CsvPath) {
    $results | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Exported to $CsvPath"
}
