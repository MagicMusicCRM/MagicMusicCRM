param([switch]$Offline)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    npm --prefix server run contract:check
    if ($LASTEXITCODE -ne 0) { throw 'OpenAPI drift check failed.' }
    flutter test --no-pub test/core/api/expense_contract_test.dart --reporter expanded
    if ($LASTEXITCODE -ne 0) { throw 'Flutter wire contract failed.' }
    Push-Location server
    try {
        $testPaths = @('src/contracts/expense-contract.spec.ts')
        if (-not $Offline) { $testPaths += 'src/contracts/expense-http-postgres.integration.spec.ts' }
        $runnerArguments = @('--runTestsByPath') + $testPaths
        if ($Offline) { $runnerArguments = @('--no-database') + $runnerArguments }
        npm test -- @runnerArguments
        if ($LASTEXITCODE -ne 0) { throw 'Backend contract check failed.' }
    } finally { Pop-Location }
} finally { Pop-Location }
if ($Offline) { Write-Output 'PASS: offline contract checks. PostgreSQL HTTP verification was not run.' }
else { Write-Output 'PASS: OpenAPI, Flutter wire fixtures and HTTP/PostgreSQL expense contracts.' }
