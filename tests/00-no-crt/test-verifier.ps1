[CmdletBinding()]
param(
    [string] $Exe = (Join-Path $PSScriptRoot "../../out/00-no-crt/hello.exe")
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$exePath = (Resolve-Path -LiteralPath $Exe).Path
$verifyScript = Join-Path $PSScriptRoot "verify.ps1"
$fixtureDir = Join-Path $projectRoot "out/00-no-crt"
$fixturePath = Join-Path $fixtureDir "verification-fixture-$PID.exe"

& $verifyScript -Exe $exePath

try {
    [byte[]] $bytes = [IO.File]::ReadAllBytes($exePath)
    if ($bytes.Length -lt 64) {
        throw "the known-good executable is too small to be a PE file."
    }

    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($peOffset -lt 0 -or $peOffset + 6 -gt $bytes.Length) {
        throw "the known-good executable has an invalid PE header offset."
    }
    if ([Text.Encoding]::ASCII.GetString($bytes, $peOffset, 4) -ne "PE`0`0") {
        throw "the known-good executable does not contain a PE signature."
    }

    # Raise the minimum OS major version while preserving a valid PE layout, so
    # llvm-readobj can inspect it and the verifier reports the target mismatch.
    $majorOsVersionOffset = $peOffset + 24 + 40
    if ($majorOsVersionOffset + 2 -gt $bytes.Length) {
        throw "the known-good executable has a truncated optional header."
    }
    [byte[]] $badOsVersion = [BitConverter]::GetBytes([UInt16] 5)
    [Array]::Copy($badOsVersion, 0, $bytes, $majorOsVersionOffset, $badOsVersion.Length)
    [IO.Directory]::CreateDirectory($fixtureDir) | Out-Null
    [IO.File]::WriteAllBytes($fixturePath, $bytes)

    $failureMessage = $null
    try {
        $null = & $verifyScript -Exe $fixturePath 2>&1
    } catch {
        $failureMessage = $_.Exception.Message
    }

    if (-not $failureMessage) {
        throw "the verifier accepted a deliberately broken minimum-OS-version fixture."
    }
    if ($failureMessage -notmatch 'minimum OS major version must be 4') {
        throw "the broken fixture failed without the expected actionable minimum-OS-version message: $failureMessage"
    }

    Write-Output "Broken-fixture check: PASS ($failureMessage)"
} finally {
    if (Test-Path -LiteralPath $fixturePath) {
        Remove-Item -LiteralPath $fixturePath -Force
    }
}
