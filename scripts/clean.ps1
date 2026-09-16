[CmdletBinding()]
param(
    [ValidateSet("downloads", "transient", "image", "all")]
    [string] $Scope = "downloads",
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Resolve-Targets {
    param([string[]] $RelativePaths)
    foreach ($rel in $RelativePaths) {
        $p = Join-Path $projectRoot $rel
        if (Test-Path -LiteralPath $p) { $p }
    }
}

function Get-ImageTargets {
    $dir = Join-Path $projectRoot "vm/local"
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    Get-ChildItem -LiteralPath $dir -File |
        Where-Object { $_.Extension -in ".qcow2", ".img" } |
        ForEach-Object { $_.FullName }
}

$downloads = Resolve-Targets @("downloads")
$transient = Resolve-Targets @(
    "work", "out", "sysroot",
    "vm/local/install.raw", "vm/local/input.raw",
    "vm/local/share", "vm/local/install-share"
)
$image = @(Get-ImageTargets)

$targets = switch ($Scope) {
    "downloads" { $downloads }
    "transient" { $transient }
    "image" { $image }
    "all" { @($downloads) + @($transient) + @($image) }
}

function Get-RelativePath {
    param([string] $Path)
    return $Path.Substring($projectRoot.Length + 1)
}

if (-not $targets -or $targets.Count -eq 0) {
    Write-Output "nothing to clean for scope '$Scope'"
    return
}

foreach ($target in $targets) {
    if ($DryRun) {
        Write-Output "would remove $(Get-RelativePath $target)"
    } else {
        Remove-Item -LiteralPath $target -Recurse -Force
        Write-Output "removed $(Get-RelativePath $target)"
    }
}
