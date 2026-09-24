[CmdletBinding()]
param(
    [string] $SdkPath = "downloads/sdk-feb-2003",
    [string] $Destination = "work/sdk-pristine"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$projectRoot = $PSScriptRoot | Split-Path -Parent
$lockPath = Join-Path $projectRoot "sources.lock.json"
$workRoot = Join-Path $projectRoot "work"
$inputDirectory = [IO.Path]::GetFullPath($SdkPath, $projectRoot)
$outputDirectory = [IO.Path]::GetFullPath($Destination, $projectRoot)
$workFullPath = [IO.Path]::GetFullPath($workRoot)
$workPrefix = $workFullPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$pathComparison = if ([System.OperatingSystem]::IsWindows()) {
    [StringComparison]::OrdinalIgnoreCase
} else {
    [StringComparison]::Ordinal
}

if (-not $outputDirectory.StartsWith($workPrefix, $pathComparison)) {
    throw "Extraction destination '$Destination' must be inside '$workRoot'."
}

$inventoryPath = "$outputDirectory.inventory.json"
$scratchRoot = Join-Path $workRoot ".sdk-extract-$PID"
if (Test-Path -LiteralPath $outputDirectory) {
    throw "Extraction destination '$outputDirectory' already exists. Choose a new directory under 'work/'."
}
if (Test-Path -LiteralPath $inventoryPath) {
    throw "Inventory '$inventoryPath' already exists. Choose a new destination under 'work/'."
}
if (Test-Path -LiteralPath $scratchRoot) {
    throw "Temporary extraction directory '$scratchRoot' already exists. Remove the stale temporary directory and retry."
}

if (-not [System.OperatingSystem]::IsWindows()) {
    throw "SDK MSI file mapping currently uses the read-only Windows Installer API and runs on the supported Windows host."
}

$sevenZip = Get-Command "7z" -CommandType Application -ErrorAction SilentlyContinue
if (-not $sevenZip) {
    $sevenZip = Get-Command "7zz" -CommandType Application -ErrorAction SilentlyContinue
}
if (-not $sevenZip) {
    throw "7-Zip command-line tool was not found. Install 7-Zip and ensure '7z' (or '7zz') is on PATH. Version 26.03 was used to validate this extraction."
}

$sevenZipInfo = @(& $sevenZip.Source i 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Could not query the 7-Zip version at '$($sevenZip.Source)'."
}
$sevenZipText = $sevenZipInfo -join "`n"
$versionMatch = [regex]::Match($sevenZipText, '(?m)^7-Zip\s+([0-9.]+)')
if (-not $versionMatch.Success -or $sevenZipText -notmatch '(?m)^\s*0\s+.*\bCab\b') {
    throw "'$($sevenZip.Source)' did not identify itself as a 7-Zip build with CAB support."
}
$sevenZipVersion = $versionMatch.Groups[1].Value

if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
    throw "Source lock file was not found: '$lockPath'."
}
if (-not (Test-Path -LiteralPath $inputDirectory -PathType Container)) {
    throw "Verified SDK input directory '$inputDirectory' was not found. Run 'mise run sdk:acquire' or 'mise run sdk:download' first."
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

function Assert-LockedCabinet {
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

foreach ($source in $sdkSources) {
    Assert-LockedCabinet -Path (Join-Path $inputDirectory $source.filename) -Source $source
}

function Invoke-SevenZip {
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [switch] $AllowOuterCabTailWarning
    )

    $commandOutput = @(& $sevenZip.Source @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) { return }

    $text = $commandOutput -join "`n"
    if ($AllowOuterCabTailWarning -and
        $exitCode -eq 1 -and
        $text -match 'data after the end of archive') {
        Write-Verbose "7-Zip reported the known 6,728-byte trailing data in each Internet Archive cabinet."
        return
    }

    throw "7-Zip failed with exit code $exitCode while running '$($Arguments -join ' ')'.`n$text"
}

function Read-MsiTable {
    param(
        [Parameter(Mandatory)] $Database,
        [Parameter(Mandatory)] [string] $Query,
        [Parameter(Mandatory)] [string[]] $Columns,
        [int[]] $IntegerColumns = @()
    )

    $view = $null
    try {
        $view = $Database.OpenView($Query)
        $null = $view.Execute()
        while ($true) {
            $record = $view.Fetch()
            if (-not $record) { break }

            try {
                $values = [ordered]@{}
                for ($index = 0; $index -lt $Columns.Count; $index++) {
                    $field = $index + 1
                    if ($IntegerColumns -contains $field) {
                        $value = $record.IntegerData($field)
                    } else {
                        $value = $record.StringData($field)
                    }
                    $values[$Columns[$index]] = $value
                }
                [pscustomobject]$values
            } finally {
                if ([Runtime.InteropServices.Marshal]::IsComObject($record)) {
                    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($record)
                }
            }
        }
    } finally {
        if ($view) {
            $null = $view.Close()
            if ([Runtime.InteropServices.Marshal]::IsComObject($view)) {
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject($view)
            }
        }
    }
}

function Get-MsiTargetName {
    param([AllowNull()] [string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    $nameParts = $Value -split '\|', 2
    $targetName = if ($nameParts.Count -eq 2) { $nameParts[1] } else { $nameParts[0] }
    # MSI DefaultDir uses target:source in each short/long name; keep the target side.
    $sourceAndTarget = $targetName -split ':', 2
    if ($sourceAndTarget.Count -eq 2) { $targetName = $sourceAndTarget[0] }
    return $targetName
}

function Get-MsiRelativeFilePath {
    param(
        [Parameter(Mandatory)] $File,
        [Parameter(Mandatory)] [hashtable] $ComponentDirectories,
        [Parameter(Mandatory)] [hashtable] $Directories
    )

    if (-not $ComponentDirectories.ContainsKey($File.Component)) { return $null }
    $directoryId = $ComponentDirectories[$File.Component]
    $segments = [System.Collections.Generic.List[string]]::new()
    $visited = @{}

    while ($directoryId -and $directoryId -ne "INSTALLLOCATION") {
        if ($visited.ContainsKey($directoryId)) {
            throw "Cycle found in MSI Directory table at '$directoryId'."
        }
        $visited[$directoryId] = $true
        if (-not $Directories.ContainsKey($directoryId)) { return $null }

        $directory = $Directories[$directoryId]
        $folderName = Get-MsiTargetName -Value $directory.DefaultDir
        $folderParts = @($folderName -split '[\\/]')
        for ($index = $folderParts.Count - 1; $index -ge 0; $index--) {
            $part = $folderParts[$index]
            if ([string]::IsNullOrWhiteSpace($part) -or $part -eq ".") { continue }
            if ($part -eq ".." -or $part.Contains(":") -or [IO.Path]::IsPathRooted($part)) {
                throw "Unsafe relative directory '$part' found in MSI table for '$($File.Key)'."
            }
            $segments.Insert(0, $part)
        }
        $directoryId = $directory.Parent
    }

    if ($directoryId -ne "INSTALLLOCATION") { return $null }

    $fileNameParts = [string]$File.FileName -split '\|', 2
    $fileName = if ($fileNameParts.Count -eq 2) { $fileNameParts[1] } else { $fileNameParts[0] }
    if ([string]::IsNullOrWhiteSpace($fileName) -or
        $fileName -eq "." -or
        $fileName -eq ".." -or
        $fileName.Contains(":") -or
        $fileName -match '[\\/]') {
        throw "Unsafe file name '$fileName' found in MSI table for '$($File.Key)'."
    }

    $segments.Add($fileName)
    return [string]::Join([IO.Path]::DirectorySeparatorChar, $segments)
}

$outputCreated = $false
$scratchCreated = $false
$installer = $null
$database = $null
try {
    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    $outputCreated = $true
    New-Item -ItemType Directory -Path (Join-Path $outputDirectory "source") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $outputDirectory "x86") -Force | Out-Null
    New-Item -ItemType Directory -Path $scratchRoot -Force | Out-Null
    $scratchCreated = $true

    $outerCabinet = Join-Path $inputDirectory $sdkSources[0].filename
    Invoke-SevenZip -Arguments @(
        "x", $outerCabinet,
        "-o$(Join-Path $outputDirectory 'source')",
        "-y", "-bd", "-bb0", "-sccUTF-8"
    ) -AllowOuterCabTailWarning

    $setupDirectory = Join-Path $outputDirectory "source/setup"
    $msiPath = Join-Path $setupDirectory "CoreSDK-x86.msi"
    if (-not (Test-Path -LiteralPath $msiPath -PathType Leaf)) {
        throw "The outer CAB chain did not produce '$msiPath'."
    }

    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer
        # OpenDatabase mode 0 is MSIDBOPEN_READONLY. No install or custom action is run.
        $database = $installer.OpenDatabase($msiPath, 0)
    } catch {
        throw "Could not open the Core SDK MSI database read-only through Windows Installer: $($_.Exception.Message)"
    }

    $fileRows = @(
        Read-MsiTable -Database $database `
            -Query 'SELECT `File`, `FileName`, `Component_`, `FileSize`, `Sequence` FROM `File`' `
            -Columns @("Key", "FileName", "Component", "Size", "Sequence") `
            -IntegerColumns @(4, 5)
    )
    $componentRows = @(
        Read-MsiTable -Database $database `
            -Query 'SELECT `Component`, `Directory_` FROM `Component`' `
            -Columns @("Component", "Directory")
    )
    $directoryRows = @(
        Read-MsiTable -Database $database `
            -Query 'SELECT `Directory`, `Directory_Parent`, `DefaultDir` FROM `Directory`' `
            -Columns @("Directory", "Parent", "DefaultDir")
    )
    $mediaRows = @(
        Read-MsiTable -Database $database `
            -Query 'SELECT `DiskId`, `LastSequence`, `Cabinet` FROM `Media`' `
            -Columns @("DiskId", "LastSequence", "Cabinet") `
            -IntegerColumns @(1, 2)
    )

    $componentDirectories = @{}
    foreach ($row in $componentRows) {
        $componentDirectories[$row.Component] = $row.Directory
    }
    $directories = @{}
    foreach ($row in $directoryRows) {
        $directories[$row.Directory] = $row
    }

    $payloadFiles = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $fileRows) {
        $relativePath = Get-MsiRelativeFilePath -File $file -ComponentDirectories $componentDirectories -Directories $directories
        if (-not $relativePath) { continue }

        $hasIncludeOrLibSegment = $false
        foreach ($segment in ($relativePath -split '[\\/]')) {
            if ($segment -ieq "Include" -or $segment -ieq "Lib") {
                $hasIncludeOrLibSegment = $true
                break
            }
        }
        if (-not $hasIncludeOrLibSegment) { continue }

        $payloadFiles.Add([pscustomobject]@{
            Key = $file.Key
            Sequence = [int]$file.Sequence
            Size = [int64]$file.Size
            RelativePath = $relativePath
        })
    }

    if ($payloadFiles.Count -eq 0) {
        throw "The Core SDK MSI did not map any files into Include or Lib directories."
    }

    $payloadRoot = Join-Path $outputDirectory "x86"
    $lastSequence = 0
    $materializedKeys = @{}
    foreach ($media in ($mediaRows | Sort-Object DiskId)) {
        $currentMediaFiles = @(
            $payloadFiles |
                Where-Object { $_.Sequence -gt $lastSequence -and $_.Sequence -le $media.LastSequence }
        )
        $lastSequence = [int]$media.LastSequence
        if ($currentMediaFiles.Count -eq 0) { continue }

        $cabinetName = [string]$media.Cabinet
        if ($cabinetName.StartsWith("#")) {
            throw "Embedded MSI cabinet '$cabinetName' is not supported; expected an external CAB beside the MSI."
        }
        $cabinetPath = Join-Path $setupDirectory $cabinetName
        if (-not (Test-Path -LiteralPath $cabinetPath -PathType Leaf)) {
            throw "MSI cabinet '$cabinetName' referenced by DiskId $($media.DiskId) is missing."
        }

        $cabinetScratch = Join-Path $scratchRoot "cab-$($media.DiskId)"
        New-Item -ItemType Directory -Path $cabinetScratch | Out-Null
        Invoke-SevenZip -Arguments @(
            "x", $cabinetPath,
            "-o$cabinetScratch",
            "-y", "-bd", "-bb0", "-sccUTF-8"
        )

        foreach ($file in $currentMediaFiles) {
            if ($materializedKeys.ContainsKey($file.Key)) {
                throw "MSI File key '$($file.Key)' appears in more than one cabinet sequence."
            }
            $cabinetMember = Join-Path $cabinetScratch $file.Key
            if (-not (Test-Path -LiteralPath $cabinetMember -PathType Leaf)) {
                throw "MSI File key '$($file.Key)' (sequence $($file.Sequence)) was not present in '$cabinetName'."
            }

            $sourceFile = Get-Item -LiteralPath $cabinetMember
            if ($sourceFile.Length -ne $file.Size) {
                throw "Wrong size for MSI File key '$($file.Key)': expected $($file.Size), got $($sourceFile.Length)."
            }

            $destinationFile = [IO.Path]::GetFullPath((Join-Path $payloadRoot $file.RelativePath))
            $payloadPrefix = $payloadRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            if (-not $destinationFile.StartsWith($payloadPrefix, $pathComparison)) {
                throw "MSI file path '$($file.RelativePath)' escapes the x86 payload directory."
            }
            $destinationParent = Split-Path -Parent $destinationFile
            New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null

            $contentHash = (Get-FileHash -LiteralPath $cabinetMember -Algorithm SHA256).Hash.ToLowerInvariant()
            $relativeInventoryPath = "x86/$($file.RelativePath.Replace('\', '/'))"
            if (Test-Path -LiteralPath $destinationFile -PathType Leaf) {
                $existingHash = (Get-FileHash -LiteralPath $destinationFile -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($existingHash -ne $contentHash) {
                    throw "Different MSI payload files map to '$relativeInventoryPath'."
                }
            } else {
                Copy-Item -LiteralPath $cabinetMember -Destination $destinationFile
            }

            $materializedKeys[$file.Key] = $true
        }

        Remove-Item -LiteralPath $cabinetScratch -Recurse -Force
    }

    if ($materializedKeys.Count -ne $payloadFiles.Count) {
        throw "Only $($materializedKeys.Count) of $($payloadFiles.Count) selected MSI payload files were extracted."
    }

    $requiredPayloadFiles = @(
        "Include/Windows.h", "Include/WinBase.h", "Include/WinDef.h",
        "Include/WinUser.h", "Include/WinNT.h", "Lib/Kernel32.Lib", "Lib/User32.Lib"
    )
    foreach ($requiredFile in $requiredPayloadFiles) {
        $requiredPath = Join-Path $payloadRoot $requiredFile
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required x86 SDK payload '$requiredFile' was not extracted."
        }
    }

    $relativeFiles = @(
        Get-ChildItem -LiteralPath $outputDirectory -File -Recurse -Force |
            ForEach-Object { [IO.Path]::GetRelativePath($outputDirectory, $_.FullName).Replace('\', '/') }
    )
    [Array]::Sort([string[]]$relativeFiles, [StringComparer]::Ordinal)
    $inventoryFiles = [System.Collections.Generic.List[object]]::new()
    foreach ($relativePath in $relativeFiles) {
        $filePath = Join-Path $outputDirectory ($relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $fileInfo = Get-Item -LiteralPath $filePath
        $hash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $inventoryFiles.Add([pscustomobject][ordered]@{
            path = $relativePath
            size = [int64]$fileInfo.Length
            sha256 = $hash
        })
    }

    $inventory = [ordered]@{
        schemaVersion = 1
        sdk = [ordered]@{
            name = "Microsoft Platform SDK February 2003"
            version = "5.2.3790.0"
        }
        extraction = [ordered]@{
            cabTool = "7-Zip"
            cabToolVersion = $sevenZipVersion
            msiMapping = "Windows Installer COM database opened read-only; no installer actions executed"
            payload = "CoreSDK-x86 Include and Lib files"
        }
        inputs = @(
            foreach ($source in $sdkSources) {
                [pscustomobject][ordered]@{
                    filename = $source.filename
                    size = [int64]$source.size
                    sha256 = $source.sha256.ToLowerInvariant()
                }
            }
        )
        files = $inventoryFiles.ToArray()
    }
    $json = ConvertTo-Json -InputObject $inventory -Depth 8
    Set-Content -LiteralPath $inventoryPath -Value $json -Encoding utf8NoBOM
    $outputCreated = $false

    Write-Output "Extracted the verified SDK CAB chain into '$outputDirectory/source'."
    Write-Output "Mapped $($payloadFiles.Count) CoreSDK-x86 Include/Lib files into '$payloadRoot'."
    Write-Output "Inventory: $inventoryPath ($($inventoryFiles.Count) files)"
} finally {
    if ($database -and [Runtime.InteropServices.Marshal]::IsComObject($database)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($database)
    }
    if ($installer -and [Runtime.InteropServices.Marshal]::IsComObject($installer)) {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($installer)
    }
    if ($scratchCreated -and (Test-Path -LiteralPath $scratchRoot)) {
        Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($outputCreated -and (Test-Path -LiteralPath $outputDirectory)) {
        Remove-Item -LiteralPath $outputDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($outputCreated -and (Test-Path -LiteralPath $inventoryPath)) {
        Remove-Item -LiteralPath $inventoryPath -Force -ErrorAction SilentlyContinue
    }
}
