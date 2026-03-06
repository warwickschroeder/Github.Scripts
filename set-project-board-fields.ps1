# set-project-board-fields.ps1
# Updates GitHub Projects V2 fields for issues listed in a CSV file.
#
# Prerequisites: gh cli (winget install GitHub.cli) + gh auth login --scopes read:project,read:org,project
# Usage: .\set-project-board-fields.ps1 -Org "your-org" -ProjectNumber 1 -CsvPath "issues.csv" -FieldMap @{ "Comments" = "My Comments Field" }

param(
    [Parameter(Mandatory)][string]$Org,
    [Parameter(Mandatory)][int]$ProjectNumber,
    [Parameter(Mandatory)][string]$CsvPath,
    [Parameter(Mandatory)][hashtable]$FieldMap,  # @{ "CsvColumn" = "BoardFieldName" }
    [int]$Limit = 0
)

# Verify gh is available
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "gh CLI not found. Install with: winget install GitHub.cli"
    exit 1
}

if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found: $CsvPath"
    exit 1
}

# Load CSV
$rows = Import-Csv -Path $CsvPath
if ($Limit -gt 0) {
    $rows = $rows | Select-Object -First $Limit
}

Write-Host "Loaded $($rows.Count) row(s) from $CsvPath"

# Validate that all mapped CSV columns exist in the CSV
$csvColumns = $rows[0].PSObject.Properties.Name
foreach ($csvCol in $FieldMap.Keys) {
    if ($csvCol -notin $csvColumns) {
        Write-Error "CSV column '$csvCol' not found. Available columns: $($csvColumns -join ', ')"
        exit 1
    }
}

# Fetch project ID and fields
Write-Host "Fetching project metadata..."
$metaQuery = @"
query {
  organization(login: \"$Org\") {
    projectV2(number: $ProjectNumber) {
      id
      fields(first: 50) {
        nodes {
          ... on ProjectV2Field {
            id
            name
            dataType
          }
          ... on ProjectV2SingleSelectField {
            id
            name
            dataType
            options { id name }
          }
          ... on ProjectV2IterationField {
            id
            name
            dataType
          }
        }
      }
    }
  }
}
"@

$metaResponse = gh api graphql -f query="$metaQuery" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to fetch project metadata: $metaResponse"
    exit 1
}

$metaData = $metaResponse | ConvertFrom-Json
$projectId = $metaData.data.organization.projectV2.id
$projectFields = $metaData.data.organization.projectV2.fields.nodes

Write-Host "Project ID: $projectId"

# Validate that all mapped board fields exist on the project
$boardFieldNames = $projectFields | ForEach-Object { $_.name }
foreach ($boardField in $FieldMap.Values) {
    if ($boardField -notin $boardFieldNames) {
        Write-Error "Board field '$boardField' not found on project. Available fields: $($boardFieldNames -join ', ')"
        exit 1
    }
}

# Build a lookup: board field name -> field metadata
$fieldLookup = @{}
foreach ($field in $projectFields) {
    if ($field.name) {
        $fieldLookup[$field.name] = $field
    }
}

# Fetch all project items to build URL -> item ID map
Write-Host "Fetching project items..."
$itemMap = @{}
$cursor = $null

do {
    $afterClause = if ($cursor) { ", after: \`"$cursor\`"" } else { "" }
    $itemQuery = @"
query {
  organization(login: \"$Org\") {
    projectV2(number: $ProjectNumber) {
      items(first: 100$afterClause) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          content {
            ... on Issue { url }
            ... on PullRequest { url }
          }
        }
      }
    }
  }
}
"@

    $itemResponse = gh api graphql -f query="$itemQuery" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to fetch project items: $itemResponse"
        exit 1
    }

    $itemData = $itemResponse | ConvertFrom-Json
    $itemPage = $itemData.data.organization.projectV2.items

    foreach ($node in $itemPage.nodes) {
        if ($node.content.url) {
            $itemMap[$node.content.url] = $node.id
        }
    }

    $cursor = if ($itemPage.pageInfo.hasNextPage) { $itemPage.pageInfo.endCursor } else { $null }
} while ($cursor)

Write-Host "Found $($itemMap.Count) item(s) on the board"

# Process each CSV row
$updated = 0
$skipped = 0

foreach ($row in $rows) {
    $url = $row.URL
    if (-not $url) {
        Write-Warning "Row missing URL, skipping: $($row.Title)"
        $skipped++
        continue
    }

    $itemId = $itemMap[$url]
    if (-not $itemId) {
        Write-Warning "Issue not found on board, skipping: $url"
        $skipped++
        continue
    }

    foreach ($csvCol in $FieldMap.Keys) {
        $boardFieldName = $FieldMap[$csvCol]
        $field = $fieldLookup[$boardFieldName]
        $rawValue = $row.$csvCol

        # Build the value block based on field type
        $valueBlock = switch ($field.dataType) {
            "TEXT"   { "text: \`"$rawValue\`"" }
            "NUMBER" { "number: $rawValue" }
            "DATE"   { "date: \`"$rawValue\`"" }
            "SINGLE_SELECT" {
                $option = $field.options | Where-Object { $_.name -eq $rawValue } | Select-Object -First 1
                if (-not $option) {
                    Write-Warning "Option '$rawValue' not found for field '$boardFieldName'. Valid options: $(($field.options | ForEach-Object { $_.name }) -join ', ')"
                    continue
                }
                "singleSelectOptionId: \`"$($option.id)\`""
            }
            default {
                Write-Warning "Unsupported field type '$($field.dataType)' for field '$boardFieldName', skipping"
                continue
            }
        }

        $mutation = @"
mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: \"$projectId\"
    itemId: \"$itemId\"
    fieldId: \"$($field.id)\"
    value: { $valueBlock }
  }) {
    projectV2Item { id }
  }
}
"@

        $mutResponse = gh api graphql -f query="$mutation" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to update '$boardFieldName' for $url`: $mutResponse"
        } else {
            Write-Host "  Updated '$boardFieldName' = '$rawValue' for $url"
        }
    }

    $updated++
}

Write-Host "`nDone. Updated: $updated, Skipped: $skipped"
