[CmdletBinding()]
param(
    [switch] $Clean
)

# Build the no-CRT Windows 98 console sample with LLVM.
#
# Exact commands, from the project root:
#
#   llvm-dlltool -m i386 -k -d tests/00-no-crt/kernel32.def -l out/00-no-crt/kernel32.lib
#   clang-cl --target=i686-pc-windows-msvc /c /Zl /GS- tests/00-no-crt/hello.c /Fo:out/00-no-crt/hello.obj
#   lld-link /machine:x86 /nodefaultlib /entry:mainCRTStartup /subsystem:console,4.0 /osversion:4.0 `
#     /out:out/00-no-crt/hello.exe out/00-no-crt/hello.obj out/00-no-crt/kernel32.lib
#
# The import library is generated because Milestone 2 does not use the SDK
# yet. `-k` keeps the imported name undecorated (`ExitProcess`) while the
# stdcall-decorated `ExitProcess@4` in the .def provides the linker symbol.

$ErrorActionPreference = "Stop"

$sourceDir = $PSScriptRoot
$projectRoot = (Resolve-Path (Join-Path $sourceDir "../..")).Path
$outDir = Join-Path $projectRoot "out/00-no-crt"

$defPath = Join-Path $sourceDir "kernel32.def"
$cPath = Join-Path $sourceDir "hello.c"
$libPath = Join-Path $outDir "kernel32.lib"
$objPath = Join-Path $outDir "hello.obj"
$exePath = Join-Path $outDir "hello.exe"

function Resolve-Tool {
    param([Parameter(Mandatory)] [string] $Name)
    $cmd = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($dir in @((Join-Path $env:ProgramFiles "LLVM/bin"), "C:\Program Files\LLVM\bin")) {
        $candidate = Join-Path $dir "$Name.exe"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw "$Name not found. Install LLVM or run inside the mise environment. See README.md."
}

$dlltool = Resolve-Tool "llvm-dlltool"
$clang = Resolve-Tool "clang-cl"
$link = Resolve-Tool "lld-link"

function Invoke-Tool {
    param([Parameter(Mandatory)] [string] $Tool, [Parameter(Mandatory)] [string[]] $Arguments)
    Write-Output "> $Tool $($Arguments -join ' ')"
    & $Tool @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$([IO.Path]::GetFileName($Tool)) failed with exit code $LASTEXITCODE."
    }
}

if ($Clean -and (Test-Path -LiteralPath $outDir)) {
    Remove-Item -LiteralPath $outDir -Recurse -Force
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

Invoke-Tool $dlltool @("-m", "i386", "-k", "-d", $defPath, "-l", $libPath)
Invoke-Tool $clang @("--target=i686-pc-windows-msvc", "/c", "/Zl", "/GS-", $cPath, "/Fo:$objPath")
Invoke-Tool $link @(
    "/machine:x86", "/nodefaultlib", "/entry:mainCRTStartup",
    "/subsystem:console,4.0", "/osversion:4.0", "/out:$exePath",
    $objPath, $libPath
)

Write-Output "built $exePath"
