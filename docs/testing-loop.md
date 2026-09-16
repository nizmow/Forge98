# Automated Testing Loop

This document specifies the local development loop that builds a Windows 98
program on the host, delivers it to a running guest, executes it, and reports
the result automatically. It backs Milestone 1 in [PLAN.md](../PLAN.md).

The loop is a development aid, not a compatibility gate. It runs on the
QuickInstall lane. Passing it does not by itself establish compatibility with an
unmodified Windows 98 SE; that reference verification is deferred (see
[vm.md](vm.md)).

## Goals

- Run a freshly built 32-bit PE in Windows 98 SE without manual copying.
- Capture the process exit code and, for console tests, standard output.
- Keep each run disposable so results do not depend on prior runs.
- Avoid any guest-side program compiled by the toolchain under test. The
  harness must not be circular.

## Decisions

- Emulator: QEMU, pinned to the installed major version. QEMU 11.1.0 is the
  current documented prerequisite.
- Acceleration: TCG only. Software emulation is deterministic and avoids the
  known WHPX instabilities with Windows 98 legacy VGA.
- Machine and CPU: `-M pc` (i440fx) with a fixed `-cpu pentium3`, `-m 128`,
  `-rtc base=localtime`.
- Input: a raw FAT disk image synthesized from a host directory with
  `qemu-img convert -f vvfat`, attached as an IDE disk. It is read-only in
  practice because runs use `-snapshot`.

  A read-only VVFAT folder is not usable directly: QEMU 11.1 refuses to attach
  it as an IDE disk.
- Output: a serial port, captured by the host (QEMU `-serial` to a file or a
  TCP socket).
- Lifecycle: `-snapshot` disposable runs. Shutdown is QMP `quit`; ACPI
  `system_powerdown` is not available on this image. A timeout falls back to
  forced termination.
- Harness: stock Windows components only (`command.com` and Windows Script
  Host 1.0, both shipped with Windows 98 SE).

## Architecture

```text
host share dir
  FORGE98/MARK, HARNESS.VBS, TEST.EXE, TEST.INI
        │  qemu-img convert -f vvfat -O raw
        ▼
input.img (raw FAT, partitioned)
        │
        ▼  -device ide-hd,drive=vd0,bus=ide.0,unit=1   (primary slave)
QEMU  -M pc,hpet=off -cpu pentium3 -m 128 -rtc base=localtime,clock=host -accel tcg
      -drive win98se-qemu.qcow2 -snapshot
      -serial file:<log>  (or tcp:127.0.0.1:<port>,server=on,wait=off)
      -qmp   tcp:127.0.0.1:<qmp>,server=on,wait=off
      -display none
        │
        ├─ serial ─► host captures the report
        └─ QMP ────► screendump, quit
```

The base image carries a one-time Startup hook and is never written to during a
test run because of `-snapshot`.

## Guest harness

The harness is delivered on the input disk and is executed by a stock Windows
Script Host script. Nothing in the guest is built by the project.

One-time installation into the base image:

- `C:\FORGE98\BOOT.BAT` scans drive letters for
  `<drive>:\FORGE98\MARK` and runs
  `wscript.exe //B <drive>:\FORGE98\HARNESS.VBS`.
- A copy of `BOOT.BAT` in the Startup folder makes it run at every boot.
- Installation is performed once by `scripts/install-harness.ps1` using the
  same input-disk mechanism. It is not part of the per-run loop.

Per-run share contents:

- `MARK` identifies the share volume. The guest drive letter is assigned by
  Windows, so the marker, not a fixed letter, is used.
- `HARNESS.VBS` runs the test and emits the report. It is host-controlled so it
  can change between runs.
- `TEST.EXE` is the binary under test.
- `TEST.INI` carries `Stdout` (1 for console, 0 for GUI) and optional `Args`.
  The host sets `Stdout` from the PE subsystem, which it already reads for the
  planned PE checker.

Execution modes:

- Console tests run through `command.com /c TEST.EXE > COM1 2>&1`, which waits
  and captures standard output.
- GUI tests run through `WshShell.Run(TEST.EXE, 1, True)`, which returns the
  exit code reliably.

### Report protocol

The harness frames its output on COM1 so the host can parse it unambiguously:

```text
@@FORGE98:BEGIN
@@FORGE98:TEST=TEST.EXE
--- STDOUT ---
<console output, when Stdout=1>
--- END STDOUT ---
@@FORGE98:EXITCODE=0
@@FORGE98:END
```

Serial carries text only. Binary results such as byte dumps must be encoded
(hex or base64) or moved to a writable results volume later.

## Host launcher

- `scripts/win98-common.ps1` resolves the QEMU executable, the base image, and
  the share directory, and honours the `QEMU` and `QEMU_IMG` overrides.
- `scripts/run-win98.ps1` launches QEMU interactively for reference or manual
  work.
- `scripts/run-test.ps1` implements the loop:
  1. Verify the input PE and record its SHA-256.
  2. Stage the share and select the execution mode from the PE subsystem.
  3. Start the serial listener and the QMP connection.
  4. Launch QEMU with `-snapshot`.
  5. Read the serial stream until `@@FORGE98:END` or a timeout.
  6. Send QMP `system_powerdown`; fall back to `quit` or termination on
     timeout.
  7. Print the parsed result and exit non-zero on failure.
  8. Optionally capture a `screendump` for GUI tests.
- `scripts/install-quick.ps1` keeps the pinned ISO download and verification
  from [sources.lock.json](../sources.lock.json) and creates the base image
  with `qemu-img create` instead of DOSBox-X `IMGMAKE`.

Networking remains disabled. Serial and VVFAT do not depend on host or guest
network configuration.

## Phases

### Phase 0: Spike

Validate the unknowns against the existing installed image before committing to
the design.

- Boot the raw QuickInstall image with TCG and the fixed CPU, and confirm
  Windows re-detects the changed hardware cleanly.
- Confirm VVFAT read-only is visible to Windows and that an executable can run
  from it.
- Confirm the serial TCP capture and the report protocol.
- Confirm `-snapshot` leaves the base image unchanged.
- Confirm a clean QMP `system_powerdown` and capture a `screendump`.
- Decide whether to reuse the existing image or reinstall from the pinned ISO
  with ACPI support enabled.

Acceptance: each item above is recorded, with the exact QEMU version, and any
fallback chosen for VVFAT is documented.

### Phase 0 findings

Recorded against QEMU 11.1.0 (v11.1.0-12130-ge470268ff4) on Windows with TCG.

Reusing the DOSBox-X image:

- The existing `vm/local/win98se-quick.img` is a complete Windows 98 SE install
  (`IO.SYS`, `WINDOWS`, and `QISETUP.EXE` are present), but it does not boot
  with QEMU defaults. The Windows 98 FAT32 boot sector reports `Disk I/O error`
  because the BPB uses 255 heads and 63 sectors per track while QEMU presents a
  different BIOS geometry.
- It boots when the logical geometry is set explicitly on the device:
  `-device ide-hd,drive=hd0,bus=ide.0,unit=0,lcyls=257,lheads=255,lsecs=63`.
  This workaround is specific to the DOSBox-X image; a QEMU-native image does
  not need it. The image was not reused.

Native QEMU install:

- A fresh Windows 98 SE install from the pinned QuickInstall ISO reaches the
  desktop and does not need the geometry workaround.
- `hpet=off` is required. With the default HPET setting, the Windows 98 boot
  countdown and clock do not advance.
- A guest-initiated reboot leaves the guest with no hardware interrupts (QEMU
  issue #771): the machine appears to hang, the clock stops, and resets do not
  recover it. The only reliable remedy is to stop the QEMU process and start it
  again. Every Windows 98 reboot must be a host-side power cycle, not an
  in-guest reset.
- Unclean power cycles during installation flag networking VXDs such as
  `ndis.vxd` and `vnetsup.vxd` as damaged. Networking is disabled for this
  project, so these prompts are harmless.
- A full TCG boot to the desktop takes on the order of two minutes. This is too
  slow for a tight loop on its own and motivates a `savevm`/`loadvm` test.
- QMP `system_powerdown` does not shut this image down (ACPI is likely not
  installed); QMP `quit` terminates the VM.

Input delivery:

- A read-only VVFAT folder cannot be attached as an IDE disk in QEMU 11.1:
  `file=fat:<dir>` fails with `Block node is read-only`, both through the legacy
  `-hdb` form and through an explicit `-device ide-hd`. There is no `readonly`
  device property, and `read-only=on` on the drive does not help.
- The working approach is to synthesize a raw FAT disk image from the host
  directory and attach that as an IDE disk:
  `qemu-img convert -f vvfat -O raw "fat:<dir>" input.img`. The result is a
  partitioned FAT image (about 528 MiB at the default size) that Windows mounts
  as a normal disk. Windows listed its files and ran `TEST.BAT` from it.
- The input image is read-only in practice because runs use `-snapshot`, so
  guest writes are discarded and the image itself is never modified.

Serial:

- COM1 capture works. With `-serial file:<path>`, a batch writing
  `echo TEXT>COM1` produced `TEXT` in the host file.
- `mode COM1: BAUD=115200 ...` is rejected by Windows 98 as `invalid parameter`;
  the shorthand `mode COM1: 115200,n,8,1` is the correct form. Redirection works
  without configuring the port first.
- DOS batch files on the input image must use CRLF line endings. LF-only files
  are mis-parsed by `command.com`.

QMP `screendump` produces valid PPM frames.

End-to-end validation:

- The loop runs a real Windows 98 console PE. `PING.EXE` extracted from the
  installed image was delivered, executed at Startup, and reported on the host:
  its stdout was captured and its exit code (0) produced a pass.
- The Startup hook is a single-line `for` in `BOOT.BAT`. Windows 98
  `command.com` does not support the multi-line `do (...)` block syntax.
- `INSTALL.BAT` locates its own directory with `%0\..`. Windows 98
  `command.com` does not support the `%~dp0` form.
- The input volume keeps the harness under a `FORGE98` subdirectory so the
  marker and payload paths match.

### Phase 1: Documentation and environment (done)

- `README.md`, `docs/vm.md`, and the Windows 98 Test Environment section of
  `PLAN.md` document QEMU as the emulator.
- `mise.toml` puts the QEMU installation directory on `PATH`. QEMU is a host
  prerequisite and is not managed by mise.
- The QEMU machine definition lives in `scripts/win98-common.ps1` rather than a
  separate per-emulator configuration file.
- Per-OS QEMU install commands are documented.

### Phase 2: Harness and launcher (done)

- `vm/harness/` contains the committed harness text files.
- The host scripts listed above are present.
- mise tasks: `vm:check`, `vm:prepare-quick`, `vm:install-quick`,
  `vm:install-harness`, `vm:run`, and `test:win98`.
- The obsolete DOSBox-X configuration and scripts were removed.

### Phase 3: Pipeline integration

Wire `test:win98` into the build so a test is compatible only when static PE
and import validation and VM execution both pass.

## Acceptance

- A built console PE runs in the disposable QEMU guest and its exit code and
  standard output are reported on the host. Met by the `PING.EXE` validation.
- A built GUI PE runs and its exit code is reported. Pending a GUI binary.
- Two consecutive runs of the same input produce the same result and leave the
  base image unchanged. Met.
- The harness uses only components shipped with Windows 98 SE. Met.
- No test input, image, or mutable state is committed to Git. Met.

## Risks

- Synthesizing the input image with `qemu-img convert -f vvfat` produces a
  528 MiB raw file on every run. If that proves too slow or large, replace it
  with a small fixed-size FAT image built once and updated in place.
- The image has no ACPI, so there is no clean guest shutdown; runs end with QMP
  `quit`. Reinstalling with ACPI support (`setup /pj`) would allow
  `system_powerdown`.
- A Windows 98 guest reboot breaks interrupt delivery (QEMU issue #771). Every
  reboot must be a host-side power cycle.
- A TCG boot to the desktop takes about two minutes, so a tight loop needs a
  `savevm`/`loadvm` snapshot or equivalent. This is not yet validated.
- Windows 98 has no idle `HLT` loop, so QEMU pins a host core during runs.
  Acceptable for short tests.
