$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$harnessPath = Join-Path `
  $repoRoot `
  "infra\scripts\tests\deploy-api-release-behavior.contract.sh"
if (-not (Test-Path -LiteralPath $harnessPath -PathType Leaf)) {
  throw "Deploy behavior harness is missing: $harnessPath"
}

$workspaceMount = "type=bind,source=$repoRoot,target=/workspace,readonly"
docker run --rm `
  --network none `
  --read-only `
  --tmpfs /tmp:rw,nosuid,nodev,size=16m `
  --mount $workspaceMount `
  --workdir /workspace `
  bash:5.2 `
  bash infra/scripts/tests/deploy-api-release-behavior.contract.sh
if ($LASTEXITCODE -ne 0) {
  throw "Deploy behavior harness failed."
}
