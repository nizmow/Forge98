[CmdletBinding()]
param(
    [switch] $PrepareOnly,
    [switch] $ForceDownload,
    [switch] $ResetDisk
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "win98-common.ps1")

$projectRoot = $script:Win98ProjectRoot
$lockPath = Join-Path $projectRoot "sources.lock.json"
$downloadDir = Join-Path $projectRoot "downloads"
$vmDir = Join-Path $projectRoot "vm/local"
$diskPath = Join-Path $vmDir "win98se-qemu.qcow2"

$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$source = $lock.sources | Where-Object { $_.name -eq "win98-quickinstall-stock" }
if (-not $source -or @($source).Count -ne 1) {
    throw "Expected exactly one win98-quickinstall-stock entry in sources.lock.json."
}

$isoPath = Join-Path $downloadDir $source.filename

function Assert-SourceFile {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] $Source)
    $file = Get-Item -LiteralPath $Path
    if ($file.Length -ne [int64] $Source.size) {
        throw "Wrong size for '$Path': expected $($Source.size), got $($file.Length)."
    }
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $Source.sha256) {
        throw "Wrong SHA-256 for '$Path': expected $($Source.sha256), got $actualHash."
    }
}

New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
New-Item -ItemType Directory -Path $vmDir -Force | Out-Null

if ($ForceDownload -and (Test-Path -LiteralPath $isoPath)) {
    Remove-Item -LiteralPath $isoPath -Force
}

if (-not (Test-Path -LiteralPath $isoPath -PathType Leaf)) {
    $partialPath = "$isoPath.partial"
    Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
    Write-Output "Downloading $($source.url)"
    try {
        Invoke-WebRequest -Uri $source.url -OutFile $partialPath
        Assert-SourceFile -Path $partialPath -Source $source
        Move-Item -LiteralPath $partialPath -Destination $isoPath
    } catch {
        Remove-Item -LiteralPath $partialPath -Force -ErrorAction SilentlyContinue
        throw
    }
} else {
    Assert-SourceFile -Path $isoPath -Source $source
}

if ($ResetDisk -and (Test-Path -LiteralPath $diskPath)) {
    Remove-Item -LiteralPath $diskPath -Force
}

if (-not (Test-Path -LiteralPath $diskPath)) {
    Write-Output "Creating 2 GiB QEMU disk at '$diskPath'."
    & (Get-Win98QemuImg) create -f qcow2 $diskPath 2G
    if ($LASTEXITCODE -ne 0) { throw "qemu-img create failed with code $LASTEXITCODE." }
} else {
    Write-Output "Reusing QEMU disk '$diskPath'."
}

Write-Output "Installer: $isoPath"
Write-Output "SHA-256:   $($source.sha256)"
Write-Output "Target:    $diskPath"

if ($PrepareOnly) { return }

$vm = Start-Win98Vm -Image $diskPath -Cdrom $isoPath -Boot d -Display "sdl"
Write-Output "QEMU pid:  $($vm.ProcessId)"
Write-Output ""
Write-Output "Complete the Windows 98 SE Stock QuickInstall in the QEMU window."
Write-Output "Keep the default format and boot-record options."
Write-Output ""
Write-Output "IMPORTANT: do not let Windows reboot inside QEMU. A guest reboot"
Write-Output "leaves interrupts dead (QEMU #771). If Windows restarts, stop QEMU"
Write-Output "and relaunch with 'mise run vm:run'."
