$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$gitHooksDir = Join-Path $repoRoot ".git\hooks"
$sharedLinksScript = Join-Path $repoRoot "scripts\setup_shared_links.ps1"

if (-not (Test-Path -LiteralPath $gitHooksDir -PathType Container)) {
    throw "Git hooks folder not found: $gitHooksDir"
}

if (-not (Test-Path -LiteralPath $sharedLinksScript -PathType Leaf)) {
    throw "Shared links setup script not found: $sharedLinksScript"
}

$hookContent = @'
#!/bin/sh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/setup_shared_links.ps1
'@

$hookNames = @(
    "post-merge",
    "post-rewrite"
)

foreach ($hookName in $hookNames) {
    $hookPath = Join-Path $gitHooksDir $hookName
    Set-Content -LiteralPath $hookPath -Value $hookContent -Encoding ASCII
    Write-Host "Installed Git hook: $hookPath"
}

Write-Host "Git hooks are ready. Shared links will be recreated after git pull/merge and pull --rebase."
