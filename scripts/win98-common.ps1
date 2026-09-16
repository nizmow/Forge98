# Shared helpers for the QEMU Windows 98 test loop.

$script:Win98ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

function Get-Win98Qemu {
    $override = [Environment]::GetEnvironmentVariable("QEMU")
    if ($override -and (Test-Path -LiteralPath $override)) { return (Resolve-Path -LiteralPath $override).Path }
    $cmd = Get-Command "qemu-system-i386.exe" -CommandType Application -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidate = "C:\Program Files\qemu\qemu-system-i386.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    throw "qemu-system-i386.exe not found. Install QEMU or set QEMU. See docs/vm.md."
}

function Get-Win98QemuImg {
    $override = [Environment]::GetEnvironmentVariable("QEMU_IMG")
    if ($override -and (Test-Path -LiteralPath $override)) { return (Resolve-Path -LiteralPath $override).Path }
    $cmd = Get-Command "qemu-img.exe" -CommandType Application -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidate = "C:\Program Files\qemu\qemu-img.exe"
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    throw "qemu-img.exe not found. Install QEMU or set QEMU_IMG. See docs/vm.md."
}

function Get-Win98BaseImage {
    param([string] $Image)
    if ($Image) { return (Resolve-Path -LiteralPath $Image).Path }
    $fromEnv = [Environment]::GetEnvironmentVariable("FORGE98_QEMU_IMAGE")
    if ($fromEnv) { return (Resolve-Path -LiteralPath $fromEnv).Path }
    $default = Join-Path $script:Win98ProjectRoot "vm/local/win98se-qemu.qcow2"
    if (-not (Test-Path -LiteralPath $default)) {
        throw "Windows 98 base image not found at '$default'. See docs/vm.md."
    }
    return $default
}

function Get-Win98HarnessDir {
    return (Join-Path $script:Win98ProjectRoot "vm/harness")
}

function ConvertTo-CrlfText {
    param([Parameter(Mandatory)] [string] $Path)
    $text = [System.IO.File]::ReadAllText($Path)
    $text = ($text -replace "`r`n", "`n") -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($Path, $text)
}

function New-Win98Share {
    <#
        Stage the per-run input volume in a directory. Copies the harness files
        with CRLF line endings and places the binary under test as TEST.EXE.
    #>
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [string] $ShareDir = (Join-Path $script:Win98ProjectRoot "vm/local/share"),
        [switch] $Gui
    )
    if (Test-Path -LiteralPath $ShareDir) { Remove-Item -LiteralPath $ShareDir -Recurse -Force }
    $dest = Join-Path $ShareDir "FORGE98"
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    $harness = Get-Win98HarnessDir
    Copy-Item (Join-Path $harness "HARNESS.VBS") $dest
    Copy-Item (Join-Path $harness "BOOT.BAT") $dest
    Copy-Item (Join-Path $harness "INSTALL.BAT") $dest
    Get-ChildItem -LiteralPath $dest -Include *.bat, *.vbs -File |
        ForEach-Object { ConvertTo-CrlfText -Path $_.FullName }

    Copy-Item -LiteralPath $Exe -Destination (Join-Path $dest "TEST.EXE")

    $stdout = if ($Gui) { "0" } else { "1" }
    [System.IO.File]::WriteAllText((Join-Path $dest "TEST.INI"), "Stdout=$stdout`r`n")
    [System.IO.File]::WriteAllText((Join-Path $dest "FORGE98.MARK"), "FORGE98`r`n")

    return $dest
}

function New-Win98InputImage {
    param(
        [Parameter(Mandatory)] [string] $ShareDir,
        [Parameter(Mandatory)] [string] $OutImage
    )
    $qemuImg = Get-Win98QemuImg
    if (Test-Path -LiteralPath $OutImage) { Remove-Item -LiteralPath $OutImage -Force }
    & $qemuImg convert -f vvfat -O raw "fat:$ShareDir" $OutImage
    if ($LASTEXITCODE -ne 0) { throw "qemu-img convert failed with code $LASTEXITCODE." }
    return $OutImage
}

function Test-Win98QemuRunning {
    return [bool] (Get-Process qemu-system-i386 -ErrorAction SilentlyContinue)
}

function Stop-Win98QemuProcess {
    Get-Process qemu-system-i386 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

function Start-Win98Vm {
    param(
        [Parameter(Mandatory)] [string] $Image,
        [string] $InputImage,
        [string] $Cdrom,
        [ValidateSet("c", "d")] [string] $Boot = "c",
        [string] $Serial,
        [int] $QmpPort = 0,
        [string] $Display = "none",
        [switch] $Snapshot,
        [switch] $NoReboot,
        [switch] $KeepExisting
    )

    $qemu = Get-Win98Qemu
    if (-not $KeepExisting) {
        Get-Process qemu-system-i386 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }

    $qemuArgs = @(
        "-M", "pc,hpet=off",
        "-cpu", "pentium3",
        "-m", "128",
        "-rtc", "base=localtime,clock=host",
        "-accel", "tcg",
        "-drive", "file=$Image,format=qcow2,if=none,id=hd0",
        "-device", "ide-hd,drive=hd0,bus=ide.0,unit=0",
        "-boot", $Boot,
        "-name", "forge98"
    )
    if ($Display) { $qemuArgs += @("-display", $Display) }
    if ($InputImage) {
        $qemuArgs += @("-drive", "file=$InputImage,format=raw,if=none,id=vd0")
        $qemuArgs += @("-device", "ide-hd,drive=vd0,bus=ide.0,unit=1")
    }
    if ($Cdrom) { $qemuArgs += @("-cdrom", $Cdrom) }
    if ($Serial) { $qemuArgs += @("-serial", $Serial) }
    if ($QmpPort -gt 0) { $qemuArgs += @("-qmp", "tcp:127.0.0.1:$QmpPort,server=on,wait=off") }
    if ($NoReboot) { $qemuArgs += "-no-reboot" }
    if ($Snapshot) { $qemuArgs += "-snapshot" }

    function Quote([string] $s) {
        if ($s -match '[\s"]') { return '"' + ($s -replace '"', '\"') + '"' }
        return $s
    }
    $argLine = ($qemuArgs | ForEach-Object { Quote $_ }) -join " "
    $cmdLine = (Quote $qemu) + " " + $argLine

    $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine }
    if ($result.ReturnValue -ne 0) { throw "Failed to launch QEMU (Win32_Process.Create code $($result.ReturnValue))." }

    return [pscustomobject]@{ ProcessId = $result.ProcessId; CommandLine = $cmdLine }
}

function Open-Win98Qmp {
    param([Parameter(Mandatory)] [int] $Port, [int] $TimeoutMs = 30000)
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $client.Connect("127.0.0.1", $Port)
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream)
            [void] $reader.ReadLine()   # greeting
            return [pscustomobject]@{ Client = $client; Stream = $stream; Reader = $reader }
        } catch {
            if ($client) { $client.Close() }
            Start-Sleep -Milliseconds 300
        }
    }
    throw "Could not connect to QMP on port $Port."
}

function Invoke-Win98Qmp {
    param($Qmp, [Parameter(Mandatory)] [string] $Command)
    $writer = New-Object System.IO.StreamWriter($Qmp.Stream)
    $writer.AutoFlush = $true
    $writer.WriteLine($Command)
    while ($true) {
        $line = $Qmp.Reader.ReadLine()
        if ($null -eq $line) { throw "QMP connection closed." }
        if ($line -match '"return"') { return $line }
        if ($line -match '"error"') { throw "QMP error: $line" }
    }
}

function Stop-Win98Vm {
    param([int] $QmpPort)
    try {
        $qmp = Open-Win98Qmp -Port $QmpPort -TimeoutMs 3000
        [void] (Invoke-Win98Qmp -Qmp $qmp -Command '{"execute":"qmp_capabilities"}')
        [void] (Invoke-Win98Qmp -Qmp $qmp -Command '{"execute":"quit"}')
        $qmp.Client.Close()
    } catch {
        Get-Process qemu-system-i386 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
}
