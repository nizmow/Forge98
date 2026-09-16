[CmdletBinding()]
param(
    [string] $Image,
    [string] $InputShare,
    [string] $InputImage,
    [string] $Cdrom,
    [ValidateSet("c", "d")] [string] $Boot = "c",
    [string] $Serial,
    [int] $QmpPort = 45566,
    [switch] $Snapshot,
    [switch] $NoReboot
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "win98-common.ps1")

$base = Get-Win98BaseImage -Image $Image

if ($InputShare -and -not $InputImage) {
    $InputImage = Join-Path $script:Win98ProjectRoot "vm/local/input.raw"
    [void] (New-Win98InputImage -ShareDir (Resolve-Path -LiteralPath $InputShare).Path -OutImage $InputImage)
}

$vm = Start-Win98Vm -Image $base -InputImage $InputImage -Cdrom $Cdrom -Boot $Boot `
    -Serial $Serial -QmpPort $QmpPort -Display "sdl" -Snapshot:$Snapshot -NoReboot:$NoReboot

Write-Output "QEMU pid: $($vm.ProcessId)"
Write-Output $vm.CommandLine
