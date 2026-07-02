$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$sharedTarget = Join-Path $repoRoot "shared"
$linkPaths = @(
    (Join-Path $repoRoot "client\shared"),
    (Join-Path $repoRoot "server\shared")
)

if (-not (Test-Path -LiteralPath $sharedTarget -PathType Container)) {
    throw "Shared source folder not found: $sharedTarget"
}

foreach ($linkPath in $linkPaths) {
    if (Test-Path -LiteralPath $linkPath) {
        $item = Get-Item -LiteralPath $linkPath -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
            throw "$linkPath exists but is not a link/junction. Refusing to remove a real directory."
        }
        Remove-Item -LiteralPath $linkPath -Force -Confirm:$false
    }

    try {
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $sharedTarget | Out-Null
    }
    catch {
        # Directory junctions do not require Developer Mode/admin symlink privileges
        # on many Windows setups and are sufficient for Godot res://shared paths.
        cmd /c mklink /J "$linkPath" "$sharedTarget" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create shared link at $linkPath"
        }
    }

    $resolved = (Get-Item -LiteralPath $linkPath -Force).Target
    Write-Host "$linkPath -> $resolved"
}

Write-Host "Shared links are ready."
