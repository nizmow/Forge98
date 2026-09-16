[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Exe,
    [switch] $Gui,
    [string] $Image,
    [int] $TimeoutSeconds = 300,
    [int] $QmpPort = 45566,
    [int] $SerialPort = 45678,
    [switch] $Visible
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "win98-common.ps1")

$exePath = (Resolve-Path -LiteralPath $Exe).Path
$hash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
$base = Get-Win98BaseImage -Image $Image

$share = Join-Path $script:Win98ProjectRoot "vm/local/share"
[void] (New-Win98Share -Exe $exePath -ShareDir $share -Gui:$Gui)

$inputImage = Join-Path $script:Win98ProjectRoot "vm/local/input.raw"
Stop-Win98QemuProcess
[void] (New-Win98InputImage -ShareDir $share -OutImage $inputImage)

$display = if ($Visible) { "sdl" } else { "none" }
$vm = Start-Win98Vm -Image $base -InputImage $inputImage -Boot c `
    -Serial "tcp:127.0.0.1:$SerialPort,server=on,wait=off" -QmpPort $QmpPort `
    -Display $display -Snapshot

Write-Output "test:     $exePath"
Write-Output "sha256:   $hash"
Write-Output "qemu pid: $($vm.ProcessId)"
Write-Output "waiting for the guest report..."

# QEMU is the serial server; connect as the client.
$client = $null
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $deadline) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect("127.0.0.1", $SerialPort)
        break
    } catch {
        if ($client) { $client.Close() }
        $client = $null
        Start-Sleep -Milliseconds 300
    }
}
if (-not $client) {
    Stop-Win98Vm -QmpPort $QmpPort
    throw "Could not connect to the serial port $SerialPort."
}

$stream = $client.GetStream()
$stream.ReadTimeout = 1000
$reader = New-Object System.IO.StreamReader($stream)
$lines = New-Object System.Collections.Generic.List[string]
$done = $false
$sw = [Diagnostics.Stopwatch]::StartNew()

while (-not $done -and $sw.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
    try {
        $line = $reader.ReadLine()
    } catch {
        Start-Sleep -Milliseconds 200
        continue
    }
    if ($null -eq $line) { Start-Sleep -Milliseconds 200; continue }
    $lines.Add($line)
    if ($line -eq "@@FORGE98:END") { $done = $true }
}

$stream.Close()
Stop-Win98Vm -QmpPort $QmpPort

$exitCode = $null
$errorText = $null
$stdout = New-Object System.Collections.Generic.List[string]
$inStdout = $false
foreach ($l in $lines) {
    if ($l -eq "--- STDOUT ---") { $inStdout = $true; continue }
    if ($l -eq "--- END STDOUT ---") { $inStdout = $false; continue }
    if ($l -match '^@@FORGE98:EXITCODE=(-?\d+)\s*$') { $exitCode = [int] $Matches[1]; continue }
    if ($l -match '^@@FORGE98:ERROR=(.*)$') { $errorText = $Matches[1]; continue }
    if ($inStdout) { $stdout.Add($l) }
}

if ($stdout.Count -gt 0) {
    Write-Output "stdout:"
    $stdout | ForEach-Object { Write-Output "  $_" }
}
if ($errorText) { Write-Output "error:    $errorText" }

if (-not $done) {
    Write-Output "result:   TIMEOUT after ${TimeoutSeconds}s"
    exit 124
}
if ($errorText) {
    Write-Output "result:   ERROR"
    exit 2
}
Write-Output "exitcode: $exitCode"
if ($exitCode -ne 0) {
    Write-Output "result:   FAIL"
    exit 1
}
Write-Output "result:   PASS"
exit 0
