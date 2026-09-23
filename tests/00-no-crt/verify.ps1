[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Exe,
    [string] $LlvmReadobj
)

$ErrorActionPreference = "Stop"

function Resolve-Readobj {
    param([Parameter(Mandatory)] [string] $Name)

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $directories = @()
    if ($env:ProgramFiles) {
        $directories += Join-Path $env:ProgramFiles "LLVM/bin"
    }
    $programFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    if ($programFiles) {
        $directories += Join-Path $programFiles "LLVM/bin"
    }

    foreach ($directory in ($directories | Select-Object -Unique)) {
        $candidate = Join-Path $directory "$Name.exe"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    throw "llvm-readobj was not found. Install the supported LLVM version or run inside the mise environment."
}

function Get-SingleField {
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $Pattern,
        [Parameter(Mandatory)] [string] $Description
    )

    $matches = [regex]::Matches($Text, $Pattern)
    if ($matches.Count -ne 1) {
        throw "could not verify ${Description}: expected exactly one llvm-readobj field, found $($matches.Count)."
    }
    return $matches[0].Groups[1].Value
}

function Assert-Field {
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $Pattern,
        [Parameter(Mandatory)] [string] $Description,
        [Parameter(Mandatory)] [string] $Expected
    )

    $actual = Get-SingleField -Text $Text -Pattern $Pattern -Description $Description
    if ($actual -ne $Expected) {
        throw "$Description must be $Expected; llvm-readobj reported $actual."
    }
}

function Assert-DataDirectoryZero {
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Description
    )

    Assert-Field -Text $Text -Pattern "(?m)^\s*${Name}RVA:\s*(0x[0-9A-Fa-f]+)\s*$" `
        -Description "$Description RVA" -Expected "0x0"
    Assert-Field -Text $Text -Pattern "(?m)^\s*${Name}Size:\s*(0x[0-9A-Fa-f]+)\s*$" `
        -Description "$Description size" -Expected "0x0"
}

if (-not $LlvmReadobj) {
    $LlvmReadobj = Resolve-Readobj -Name "llvm-readobj"
}
if (-not (Test-Path -LiteralPath $LlvmReadobj -PathType Leaf)) {
    throw "llvm-readobj not found at '$LlvmReadobj'. Install the supported LLVM version or run inside the mise environment."
}

$exePath = (Resolve-Path -LiteralPath $Exe).Path
$arguments = @(
    "--file-headers",
    "--coff-imports",
    "--coff-load-config",
    "--coff-tls-directory",
    "--coff-resources",
    "--sections",
    $exePath
)

Write-Output "> $LlvmReadobj $($arguments -join ' ')"
$readobjLines = @(& $LlvmReadobj @arguments 2>&1)
$readobjExitCode = $LASTEXITCODE
$inspection = $readobjLines -join [Environment]::NewLine
if ($readobjExitCode -ne 0) {
    throw "llvm-readobj failed with exit code $readobjExitCode.`n$inspection"
}
Write-Output $inspection

Assert-Field -Text $inspection -Pattern "(?m)^\s*Machine:\s+.*\((0x[0-9A-Fa-f]+)\)\s*$" `
    -Description "machine type" -Expected "0x14C"
Assert-Field -Text $inspection -Pattern "(?m)^\s*Magic:\s*(0x[0-9A-Fa-f]+)\s*$" `
    -Description "optional-header magic (PE32)" -Expected "0x10B"
Assert-Field -Text $inspection -Pattern "(?m)^\s*MajorOperatingSystemVersion:\s*(\d+)\s*$" `
    -Description "minimum OS major version" -Expected "4"
Assert-Field -Text $inspection -Pattern "(?m)^\s*MinorOperatingSystemVersion:\s*(\d+)\s*$" `
    -Description "minimum OS minor version" -Expected "0"
Assert-Field -Text $inspection -Pattern "(?m)^\s*Subsystem:\s+IMAGE_SUBSYSTEM_WINDOWS_CUI\s+\((0x[0-9A-Fa-f]+)\)\s*$" `
    -Description "subsystem (console)" -Expected "0x3"
Assert-Field -Text $inspection -Pattern "(?m)^\s*MajorSubsystemVersion:\s*(\d+)\s*$" `
    -Description "subsystem major version" -Expected "4"
Assert-Field -Text $inspection -Pattern "(?m)^\s*MinorSubsystemVersion:\s*(\d+)\s*$" `
    -Description "subsystem minor version" -Expected "0"

$importMatches = [regex]::Matches($inspection, '(?ms)^Import \{(.*?)^\}')
if ($importMatches.Count -ne 1) {
    throw "imports must contain exactly one DLL block (KERNEL32.dll); llvm-readobj reported $($importMatches.Count) blocks."
}
$importBlock = $importMatches[0].Groups[1].Value
$dllNames = [regex]::Matches($importBlock, '(?m)^\s*Name:\s*(\S+)\s*$')
if ($dllNames.Count -ne 1 -or $dllNames[0].Groups[1].Value -ine "KERNEL32.dll") {
    $reportedDlls = @($dllNames | ForEach-Object { $_.Groups[1].Value }) -join ", "
    if (-not $reportedDlls) { $reportedDlls = "none" }
    throw "the only imported DLL must be KERNEL32.dll; llvm-readobj reported: $reportedDlls."
}
$symbols = [regex]::Matches($importBlock, '(?m)^\s*Symbol:\s*([^\s(]+)')
if ($symbols.Count -ne 1 -or $symbols[0].Groups[1].Value -cne "ExitProcess") {
    $reportedSymbols = @($symbols | ForEach-Object { $_.Groups[1].Value }) -join ", "
    if (-not $reportedSymbols) { $reportedSymbols = "none" }
    throw "the only imported function must be ExitProcess; llvm-readobj reported: $reportedSymbols."
}

Assert-DataDirectoryZero -Text $inspection -Name "LoadConfigTable" -Description "load-config directory"
Assert-DataDirectoryZero -Text $inspection -Name "TLSTable" -Description "TLS directory"
Assert-DataDirectoryZero -Text $inspection -Name "DelayImportDescriptor" -Description "delay-import directory"
Assert-DataDirectoryZero -Text $inspection -Name "ResourceTable" -Description "resource directory"

if ($inspection -notmatch '(?s)Resources\s*\[\s*\]') {
    throw "the PE must contain no resources or manifest; llvm-readobj did not report an empty Resources list."
}
if ($inspection -notmatch '(?m)^Sections\s*\[') {
    throw "could not verify section names: llvm-readobj did not report the section table."
}
$sectionNames = [regex]::Matches($inspection, '(?m)^\s*Name:\s*(\S+)\s+\([^\r\n]*\)\s*$')
if ($sectionNames.Count -eq 0) {
    throw "could not verify section names: llvm-readobj reported no named sections."
}
$resourceSections = @($sectionNames | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -match '(?i)^\.rsrc' })
if ($resourceSections.Count -gt 0) {
    throw "the PE must not contain a .rsrc section; llvm-readobj reported: $($resourceSections -join ', ')."
}

Write-Output "PE verification: PASS (PE32 i386, console 4.0, minimum OS 4.0, KERNEL32.dll!ExitProcess only, no load-config/TLS/delay imports/resources)."
