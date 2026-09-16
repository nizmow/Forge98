# Windows 98 SE Test VM

QEMU provides the project's emulated hardware. Reference-lane Windows 98 SE
media and all installed hard-disk images are supplied or created locally and are
never stored in Git. The optional QuickInstall task downloads its pinned Stock
installer ISO from the upstream GitHub release.

## Fresh Clone Setup

From a clean checkout, the QuickInstall lane is set up in four steps. Steps 2
and 3 are interactive; the rest are automated. Every generated file stays under
the ignored `vm/local/` and `downloads/` paths.

1. Install the prerequisites: mise and QEMU (see the README).

2. Install Windows 98 SE into a new disk. This downloads and verifies the
   pinned ISO, creates `vm/local/win98se-qemu.qcow2`, and boots the installer:

   ```powershell
   mise run vm:install-quick
   ```

   Complete the QuickInstall menus, keeping the default format and boot-record
   options. Do not let Windows reboot inside QEMU; if it does, stop QEMU and
   start it again. Close QEMU when the install finishes.

3. Install the one-time guest harness hook:

   ```powershell
   mise run vm:install-harness
   ```

   In the Windows window, open My Computer, find the second hard disk, and run
   `<drive>:\FORGE98\INSTALL.BAT`. It reports
   `FORGE98 harness installed. Reboot to activate.` Then close QEMU.

4. Verify the environment and run a program:

   ```powershell
   mise run vm:check
   mise run test:win98 -- path\to\your.exe
   ```

The `test:win98` task stages the binary, boots a disposable copy of the base
image, runs the program at Startup, and prints its console output and exit
code.

## Test Lanes

Development currently uses one lane: the QuickInstall lane. It uses the
published Windows 98 SE Stock QuickInstall image, not the 98Lite Micro variant.
Despite the name, the Stock image contains Microsoft updates, third-party
patches, drivers, and utilities, so success there is not evidence that a program
runs on an unmodified Windows 98 SE. Its expected installed-disk path is:

```text
vm/local/win98se-qemu.qcow2
```

Verifying against an unmodified Windows 98 SE reference image built from
licensed media is deliberately deferred. If it is reintroduced, it becomes the
release compatibility gate and the QuickInstall result remains necessary but not
sufficient. A future reference image would live at
`vm/local/win98se-reference.qcow2`.

The image path is ignored by Git. Set `FORGE98_QEMU_IMAGE` to an absolute path
to use an image stored elsewhere, or pass `-Image` to the scripts.

## Emulator

Install QEMU as a host prerequisite. It is not installed or upgraded by project
tasks.

- Windows: `winget install SoftwareFreedomConservancy.QEMU`
- macOS: `brew install qemu`
- Debian/Ubuntu: `sudo apt install qemu-system-x86`
- Fedora: `sudo dnf install qemu-system-x86`

Set `QEMU` or `QEMU_IMG` to the executable paths to override discovery. The
project mise environment adds the standard Winget directory,
`C:\Program Files\qemu`, to `PATH`.

Run with software emulation only:

```text
-M pc,hpet=off -cpu pentium3 -m 128 -rtc base=localtime,clock=host -accel tcg
```

`hpet=off` is required; with the default HPET setting, the Windows 98 boot
countdown and clock do not advance. TCG is used instead of hardware
acceleration because it is deterministic and avoids the known WHPX
instabilities with Windows 98. Networking is disabled.

## QuickInstall Setup

Prepare and launch the interactive Windows 98 SE Stock QuickInstall with:

```powershell
mise run vm:install-quick
```

The task downloads and verifies `win98qi_v1.0.1a_stock.iso` from
`sources.lock.json`, creates `vm/local/win98se-qemu.qcow2`, and boots the
installer. Complete the menus, keeping the default format and boot-record
options. To download and create the disk without launching, run
`mise run vm:prepare-quick`; to recreate the disk, run
`pwsh -NoProfile -File scripts/install-quick.ps1 -ResetDisk`.

Do not let Windows reboot inside QEMU. A guest-initiated reboot leaves the guest
with no interrupts (QEMU issue #771), so the machine appears to hang. Stop the
QEMU process and start it again for every reboot.

## One-time Harness Install

The automated loop runs a guest harness at boot. Install it once:

```powershell
mise run vm:install-harness
```

This boots the base image with a small input disk. In Windows, open My Computer,
note the letter of the second hard disk, and run `<letter>:\INSTALL.BAT`. That
copies `BOOT.BAT` to `C:\FORGE98` and to the Startup folder. Shut down Windows
and power-cycle the VM. After this, each boot runs the harness if an input disk
is present.

## Running

Start the base image interactively:

```powershell
mise run vm:run
```

Validate the emulator and image without starting the VM:

```powershell
mise run vm:check
```

## Automated Test Loop

Run a built executable in Windows 98 and report the result:

```powershell
mise run test:win98 -- out\hello.exe
mise run test:win98 -- -Gui out\messagebox.exe
```

The loop stages the binary and the harness into `vm/local/share/`, builds a raw
FAT input disk from that directory, boots a disposable copy of the base image
(`-snapshot`), waits for the serial report, and stops QEMU. Console output and
the process exit code are printed; the command exits non-zero on failure.

Input is delivered as a normal IDE disk because QEMU 11.1 refuses to attach a
read-only VVFAT folder as a disk. The image is built with
`qemu-img convert -f vvfat -O raw`. Results are returned on COM1 and parsed from
`@@FORGE98:BEGIN` to `@@FORGE98:END`.

This lane is a development aid. Passing it does not by itself establish
compatibility with an unmodified Windows 98 SE; that reference verification is
deferred.

## Cleanup

Remove the downloaded ISO (re-downloadable from `sources.lock.json`):

```powershell
mise run clean:downloads
```

Remove per-run scratch files:

```powershell
mise run clean:transient
```

Remove the installed Windows 98 disk images under `vm/local`. This is
destructive: the disk must be reinstalled afterwards with `vm:install-quick`
and `vm:install-harness`:

```powershell
mise run clean:image
```

`mise run clean:all` removes downloads, per-run files, and the disk images.

Every task accepts `-DryRun` to list what would be removed, for example
`mise run clean:image -- -DryRun`.

## Known Issues

- `hpet=off` is required (see above).
- A guest reboot breaks interrupt delivery (QEMU #771). Power-cycle instead.
- The image has no ACPI, so `system_powerdown` does not work. Runs end with QMP
  `quit`.
- A read-only VVFAT folder cannot be attached as an IDE disk; use the
  synthesized raw FAT image described above.
- DOS batch files delivered to the guest must use CRLF line endings.
- A full TCG boot to the desktop takes about two minutes.
- Reusing an image created by DOSBox-X requires explicit logical geometry
  (`lcyls`, `lheads`, `lsecs`) because its formatted geometry differs from
  QEMU's default. A QEMU-native image does not.

## Recording Results

Record the OS edition, disk-image SHA-256, QEMU version, VM configuration
revision, test binary SHA-256, process exit code, and observed output for each
compatibility result.
