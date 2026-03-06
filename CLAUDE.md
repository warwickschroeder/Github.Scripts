# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A collection of PowerShell scripts for automating GitHub operations via the `gh` CLI and GitHub's GraphQL/REST APIs.

## Prerequisites

- **gh CLI**: Install with `winget install GitHub.cli`, then authenticate with the required scopes: `gh auth login --scopes read:project,read:org,project`
- **PowerShell**: Scripts use PowerShell syntax (`.ps1` files)

## Running Scripts

```powershell
# List issues in a GitHub Projects V2 board column
.\get-issues-on-project-board.ps1 -Org "your-org" -ProjectNumber 1
.\get-issues-on-project-board.ps1 -Org "your-org" -ProjectNumber 1 -ExcludeTeam "my-team"
.\get-issues-on-project-board.ps1 -Org "your-org" -ProjectNumber 1 -CsvPath "inbox.csv"
```

## Conventions

- Scripts use `gh api graphql` for GitHub Projects V2 queries and `gh api` for REST endpoints
- Pagination is handled manually with cursor-based GraphQL pagination and `--paginate` for REST
- Scripts validate `gh` availability and exit early on errors with `Write-Error` + `exit 1`

## Maintenance Rules

- **Keep README.md up to date**: When adding, removing, or changing a script's parameters/behaviour, update the corresponding section in README.md (usage examples, parameter table, and description)
