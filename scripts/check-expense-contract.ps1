param([switch]$Offline)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $Offline) {
    if (-not $env:V4_PLATFORM_TEST_DATABASE_URL) {
        throw 'Set V4_PLATFORM_TEST_DATABASE_URL to an isolated localhost audit_fix database, or explicitly use -Offline.'
    }
    $target = [Uri]$env:V4_PLATFORM_TEST_DATABASE_URL
    if ($target.Host -notin @('localhost', '127.0.0.1') -or $target.AbsolutePath -notlike '*audit_fix*') {
        throw 'The full contract check requires an isolated localhost audit_fix database.'
    }
}
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
        npm test -- --runTestsByPath @testPaths
        if ($LASTEXITCODE -ne 0) { throw 'Backend contract check failed.' }
    } finally { Pop-Location }
} finally { Pop-Location }
if ($Offline) { Write-Output 'PASS: offline contract checks. PostgreSQL HTTP verification was not run.' }
else { Write-Output 'PASS: OpenAPI, Flutter wire fixtures and HTTP/PostgreSQL expense contracts.' }
