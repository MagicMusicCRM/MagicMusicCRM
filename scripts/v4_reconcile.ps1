param(
  [ValidateSet("clean", "drift")]
  [string]$Fixture = "clean",
  [switch]$ExpectFail
)

$arguments = @(
  "--prefix",
  "server",
  "run",
  "v4:reconcile",
  "--",
  "--fixture",
  $Fixture
)
if ($ExpectFail) {
  $arguments += "--expect-fail"
}

& npm @arguments
exit $LASTEXITCODE
