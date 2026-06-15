param(
  [ValidateSet('list-issues', 'issue-detail', 'issue-events', 'event-detail')]
  [string]$Command = 'list-issues',
  [string]$IssueId = '',
  [string]$EventId = '',
  [string]$Org = $env:SENTRY_ORG,
  [string]$Project = $env:SENTRY_PROJECT,
  [string]$Environment = 'production',
  [string]$TimeRange = '24h',
  [int]$Limit = 20,
  [string]$Query = 'is:unresolved'
)

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $env:USERPROFILE '.codex\plugins\cache\openai-curated-remote\sentry\0.1.2\skills\sentry\scripts\sentry_api.py'
if (-not (Test-Path -LiteralPath $scriptPath)) {
  throw "Sentry API helper not found: $scriptPath"
}

if (-not $env:SENTRY_AUTH_TOKEN) {
  throw 'SENTRY_AUTH_TOKEN is missing. Create a read-only Sentry token and store it in the user environment.'
}

if (-not $Org) {
  throw 'SENTRY_ORG is missing. Pass -Org or set SENTRY_ORG.'
}

if (($Command -eq 'list-issues' -or $Command -eq 'event-detail') -and -not $Project) {
  throw 'SENTRY_PROJECT is missing. Pass -Project or set SENTRY_PROJECT.'
}

$commonArgs = @($scriptPath, '--org', $Org)
if ($Project) {
  $commonArgs += @('--project', $Project)
}

switch ($Command) {
  'list-issues' {
    python @commonArgs list-issues --environment $Environment --time-range $TimeRange --limit $Limit --query $Query
  }
  'issue-detail' {
    if (-not $IssueId) { throw 'IssueId is required for issue-detail.' }
    python @commonArgs issue-detail $IssueId
  }
  'issue-events' {
    if (-not $IssueId) { throw 'IssueId is required for issue-events.' }
    python @commonArgs issue-events $IssueId --environment $Environment --time-range $TimeRange --limit $Limit --query $Query
  }
  'event-detail' {
    if (-not $EventId) { throw 'EventId is required for event-detail.' }
    python @commonArgs event-detail $EventId
  }
}
