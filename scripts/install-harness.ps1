[CmdletBinding()]
param(
    [string] $Image,
    [int] $QmpPort = 45999
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "win98-common.ps1")

$base = Get-Win98BaseImage -Image $Image
$share = Join-Path $script:Win98ProjectRoot "vm/local/install-share"
if (Test-Path -LiteralPath $share) { Remove-Item -LiteralPath $share -Recurse -Force }
$dest = Join-Path $share "FORGE98"
New-Item -ItemType Directory -Path $dest -Force | Out-Null

$harness = Get-Win98HarnessDir
Copy-Item (Join-Path $harness "BOOT.BAT") $dest
Copy-Item (Join-Path $harness "INSTALL.BAT") $dest
Copy-Item (Join-Path $harness "HARNESS.VBS") $dest
Get-ChildItem -LiteralPath $dest -Include *.bat, *.vbs -File | ForEach-Object { ConvertTo-CrlfText -Path $_.FullName }
[System.IO.File]::WriteAllText((Join-Path $dest "FORGE98.MARK"), "FORGE98`r`n")

$inputImage = Join-Path $script:Win98ProjectRoot "vm/local/install.raw"
Stop-Win98QemuProcess
[void] (New-Win98InputImage -ShareDir $share -OutImage $inputImage)

$vm = Start-Win98Vm -Image $base -InputImage $inputImage -Boot c -QmpPort $QmpPort -Display "sdl"

Write-Output "QEMU pid: $($vm.ProcessId)"
Write-Output "Base image: $base"
Write-Output ""
Write-Output "One-time setup. In the Windows 98 window:"
Write-Output "  1. Open My Computer and note the letter of the second hard disk."
Write-Output "  2. Run:  <letter>:\FORGE98\INSTALL.BAT"
Write-Output "  3. Shut down Windows, then relaunch with: mise run vm:run"
Write-Output ""
Write-Output "This writes the boot hook to C:\FORGE98 and the Startup folder."
