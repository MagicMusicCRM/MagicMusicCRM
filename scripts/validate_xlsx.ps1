param(
  [Parameter(Mandatory = $true)]
  [string]$Fixture,
  [switch]$Excel
)

$ErrorActionPreference = "Stop"
$fixturePath = (Resolve-Path -LiteralPath $Fixture).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
$nodeExecutable = if ($nodeCommand) {
  $nodeCommand.Source
} else {
  Join-Path $env:USERPROFILE (
    ".cache/codex-runtimes/codex-primary-runtime/" +
    "dependencies/node/bin/node.exe"
  )
}
if (-not (Test-Path -LiteralPath $nodeExecutable)) {
  throw "Node.js executable was not found."
}

$validator = @'
const fs = require("node:fs");
const ExcelJS = require(process.argv[2]);
const fixture = process.argv[1];
(async () => {
  const buffer = fs.readFileSync(fixture);
  if (buffer.subarray(0, 2).toString("ascii") !== "PK") {
    throw new Error("Fixture is not an OOXML ZIP package.");
  }
  const workbook = new ExcelJS.Workbook();
  await workbook.xlsx.load(buffer);
  if (workbook.worksheets.length < 1) {
    throw new Error("Workbook contains no worksheets.");
  }
  const sheet = workbook.worksheets[0];
  if (sheet.rowCount < 2 || sheet.columnCount < 1) {
    throw new Error("Workbook fixture has no typed data rows.");
  }
  process.stdout.write(
    `OOXML PASS: ${sheet.name}, ${sheet.rowCount} rows, ${sheet.columnCount} columns\n`
  );
})().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exit(1);
});
'@

$excelJsPath = Join-Path $repoRoot "server/node_modules/exceljs"
& $nodeExecutable -e $validator $fixturePath $excelJsPath
if ($LASTEXITCODE -ne 0) {
  throw "OOXML validation failed with exit code $LASTEXITCODE."
}

if ($Excel) {
  $excelApplication = $null
  $workbook = $null
  try {
    $excelApplication = New-Object -ComObject Excel.Application
    $excelApplication.Visible = $false
    $excelApplication.DisplayAlerts = $false
    $excelApplication.AutomationSecurity = 3
    $workbook = $excelApplication.Workbooks.Open(
      $fixturePath,
      0,
      $true
    )
    if (-not $workbook -or $workbook.Worksheets.Count -lt 1) {
      throw "Microsoft Excel did not open a worksheet from the fixture."
    }
    Write-Host "EXCEL PASS: $($workbook.Name), no repair exception."
  } finally {
    if ($workbook) {
      $workbook.Close($false)
      [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook)
    }
    if ($excelApplication) {
      $excelApplication.Quit()
      [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
        $excelApplication
      )
    }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
  }
}
