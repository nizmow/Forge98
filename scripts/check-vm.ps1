[CmdletBinding()]
param(
    [string] $Image
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "win98-common.ps1")

$qemu = Get-Win98Qemu
$qemuImg = Get-Win98QemuImg
$qemuVersion = (& $qemu --version 2>&1 | Select-Object -First 1)
$qemuImgVersion = (& $qemuImg --version 2>&1 | Select-Object -First 1)

Write-Output "qemu:     $qemu"
Write-Output "version:  $qemuVersion"
Write-Output "qemu-img: $qemuImg"
Write-Output "version:  $qemuImgVersion"

try {
    $base = Get-Win98BaseImage -Image $Image
    $hash = (Get-FileHash -LiteralPath $base -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Output "image:    $base"
    Write-Output "sha256:   $hash"
} catch {
    Write-Output "image:    not found"
    Write-Output "          $($_.Exception.Message)"
}
