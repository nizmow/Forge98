[CmdletBinding(DefaultParameterSetName = "SdkPath")]
param(
    [Parameter(Mandatory, ParameterSetName = "SdkPath")]
    [string] $SdkPath,

    [Parameter(Mandatory, ParameterSetName = "DownloadSdk")]
    [switch] $DownloadSdk
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$projectRoot = $PSScriptRoot
$lockPath = Join-Path $projectRoot "sources.lock.json"
$stagingDir = Join-Path $projectRoot "downloads/sdk-feb-2003"

if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
    throw "Source lock file was not found: '$lockPath'."
}

$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
$sdkSources = @(
    $lock.sources |
        Where-Object { $_.name -like "platform-sdk-feb-2003-cab-*" } |
        Sort-Object { [int]($_.name -replace '^.*-cab-', '') }
)

if ($sdkSources.Count -ne 13) {
    throw "Expected 13 platform-sdk-feb-2003 cabinet entries in '$lockPath'; found $($sdkSources.Count)."
}

foreach ($source in $sdkSources) {
    if ([string]::IsNullOrWhiteSpace($source.filename) -or
        [string]::IsNullOrWhiteSpace($source.destinationFilename) -or
        [string]::IsNullOrWhiteSpace($source.url) -or
        [string]::IsNullOrWhiteSpace($source.sha256) -or
        $source.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
        [int64]$source.size -le 0) {
        throw "Invalid lock entry '$($source.name)': expected URL, source/destination filenames, positive size, and SHA-256."
    }
}

function Assert-SdkFile {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] $Source
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing SDK cabinet '$Path'. Expected $($Source.size) bytes and SHA-256 $($Source.sha256)."
    }

    $file = Get-Item -LiteralPath $Path
    if ($file.Length -ne [int64]$Source.size) {
        throw "Wrong size for SDK cabinet '$Path': expected $($Source.size) bytes, got $($file.Length)."
    }

    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $Source.sha256.ToLowerInvariant()) {
        throw "Wrong SHA-256 for SDK cabinet '$Path': expected $($Source.sha256), got $actualHash."
    }
}

function Get-StagedPath {
    param([Parameter(Mandatory)] $Source)
    Join-Path $stagingDir $Source.destinationFilename
}

function Stage-LocalCabinets {
    param([Parameter(Mandatory)] [string] $InputDirectory)

    if (-not (Test-Path -LiteralPath $InputDirectory -PathType Container)) {
        throw "SDK input directory '$InputDirectory' does not exist. Supply a directory containing all 13 PSDK-FULL.N.cab files."
    }

    $resolvedInputDirectory = (Resolve-Path -LiteralPath $InputDirectory).Path

    # Validate the complete local input before copying any cabinet into the cache.
    foreach ($source in $sdkSources) {
        $inputFile = Join-Path $resolvedInputDirectory $source.filename
        Assert-SdkFile -Path $inputFile -Source $source
    }

    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

    foreach ($source in $sdkSources) {
        $inputFile = Join-Path $resolvedInputDirectory $source.filename
        $stagedFile = Get-StagedPath -Source $source

        if (Test-Path -LiteralPath $stagedFile -PathType Leaf) {
            Assert-SdkFile -Path $stagedFile -Source $source
            Write-Output "Reusing verified $($source.destinationFilename)."
            continue
        }

        $partialFile = "$stagedFile.partial"
        try {
            Copy-Item -LiteralPath $inputFile -Destination $partialFile
            Assert-SdkFile -Path $partialFile -Source $source
            Move-Item -LiteralPath $partialFile -Destination $stagedFile
        } catch {
            Remove-Item -LiteralPath $partialFile -Force -ErrorAction SilentlyContinue
            throw
        }

        Write-Output "Staged verified $($source.destinationFilename)."
    }
}

function Download-SdkCabinets {
    New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

    foreach ($source in $sdkSources) {
        $stagedFile = Get-StagedPath -Source $source
        if (Test-Path -LiteralPath $stagedFile -PathType Leaf) {
            Assert-SdkFile -Path $stagedFile -Source $source
            Write-Output "Reusing verified $($source.destinationFilename)."
            continue
        }

        $partialFile = "$stagedFile.partial"
        Remove-Item -LiteralPath $partialFile -Force -ErrorAction SilentlyContinue
        Write-Output "Downloading $($source.url)"
        try {
            Invoke-WebRequest -Uri $source.url -OutFile $partialFile
            Assert-SdkFile -Path $partialFile -Source $source
            Move-Item -LiteralPath $partialFile -Destination $stagedFile
        } catch {
            Remove-Item -LiteralPath $partialFile -Force -ErrorAction SilentlyContinue
            throw
        }
    }
}

if ($PSCmdlet.ParameterSetName -eq "SdkPath") {
    Stage-LocalCabinets -InputDirectory $SdkPath
} else {
    Download-SdkCabinets
}

# Both acquisition modes finish by validating exactly the same staged inputs.
foreach ($source in $sdkSources) {
    Assert-SdkFile -Path (Get-StagedPath -Source $source) -Source $source
}

Write-Output "Verified 13 February 2003 Platform SDK cabinets in '$stagingDir'."
