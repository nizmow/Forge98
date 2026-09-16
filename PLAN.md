# Forge98 Plan

## Goal

Produce a reproducible C development environment that runs on a modern Windows
host and emits 32-bit PE programs that run on Windows 98 SE.

Development and automated verification currently use the QuickInstall Windows 98
SE image. Verifying against an unmodified Windows 98 SE installation is
deliberately deferred; see Windows 98 Test Environment.

The first implementation will use Clang and LLD. The SDK adapter and target
runtime must remain compiler-neutral so that a GCC driver can be added later.

## Initial Scope

- Host: Windows 10/11 x86-64.
- Future host: Linux x86-64.
- Target: Windows 98 SE on 32-bit x86.
- Language: C only.
- Compiler: pinned LLVM release using `clang-cl` and `lld-link`.
- SDK candidate: Microsoft Platform SDK, February 2003 edition.
- C library candidate: the `msvcrt.dll` shipped with Windows 98 SE.
- SDK files are supplied by the user or fetched from a documented archive.
- Microsoft files and generated toolchains are not committed to Git.

## Non-Goals For The First Release

- Running the compiler on Windows 98.
- C++, exceptions, RTTI, or a C++ standard library.
- 64-bit targets.
- Windows drivers, DirectX, MFC, ATL, or managed code.
- Supporting Windows 95 or Windows Me before Windows 98 SE works.
- Reimplementing the complete C standard library.
- Claiming compatibility based only on a successful link.

## Reproducibility Rules

- Pin every downloaded input by URL, size, and SHA-256 in `sources.lock.json`.
- Never select a dependency by an unpinned `latest` URL.
- Keep pristine extracted inputs separate from normalized output.
- Express every modification as code or a patch under version control.
- Make generation idempotent: a second run produces the same file hashes.
- Record tool versions and commands in the generated build manifest.
- Fail closed when an input hash, PE property, or imported symbol is unexpected.
- Keep `downloads/`, `work/`, `out/`, and the generated `sysroot/` out of Git.

## Intended Layout

```text
PLAN.md
README.md
mise.toml
sources.lock.json
bootstrap.ps1
bootstrap.sh
cmake/
  win98-clang-toolchain.cmake
docs/
  sdk.md
  compatibility.md
  testing-loop.md
  vm.md
patches/
runtime/
  include/
  src/
scripts/
  acquire.py
  extract_sdk.py
  build_sysroot.py
  check_pe.py
  check-vm.ps1
  clean.ps1
  install-harness.ps1
  install-quick.ps1
  run-test.ps1
  run-win98.ps1
  win98-common.ps1
tests/
  00-no-crt/
  01-windows-header/
  02-console-crt/
  03-gui-crt/
  04-dll/
vm/
  harness/
```

## Milestone 0: Record The Contract

Add `README.md`, `.gitignore`, and `sources.lock.json`.

The README must distinguish the build host from the target and state that
Windows 98 SE compatibility is verified in a VM. The lock file schema must
contain a stable name, version, URL, size, SHA-256, license/source notes, and
destination filename for each input.

Acceptance:

```powershell
python -m json.tool sources.lock.json > $null
git status --short
```

Only intentional source files may appear in Git status. Downloaded and
generated files must be ignored.

## Milestone 1: Automate The Windows 98 Testing Loop

Make it possible to build a program on the host and run it in a Windows 98 SE
guest automatically, capturing an exit code and console output. Every later
execution milestone depends on this feedback loop.

Use QEMU as the documented emulator, run with software emulation and a fixed
CPU. Deliver the binary through a read-only host folder, capture results over a
serial port, and keep each run disposable. The guest harness must use only
components shipped with Windows 98 SE; no helper is compiled by the project.

The full design, phases, and risks are specified in
[docs/testing-loop.md](docs/testing-loop.md).

Acceptance:

- A built console program runs in the disposable guest and its exit code and
  standard output are reported on the host.
- A built GUI program runs and its exit code is reported.
- Consecutive runs of the same input produce the same result and leave the
  base image unchanged.
- The harness is built from stock Windows 98 SE components only.

## Milestone 2: Prove A No-CRT Windows 98 Executable

Use an already-installed, explicitly supported LLVM version. Do not download
or process the SDK yet.

Create a tiny C program that declares `ExitProcess` itself and supplies its own
entry point. Compile for `i686-pc-windows-msvc` with no standard includes and
link with `lld-link`, `/nodefaultlib`, an explicit `/entry`, and a Windows 4.x
subsystem version. Generate the `KERNEL32.dll` import library from a checked-in
minimal module-definition file if no suitable library is available.

This isolates LLVM code generation and PE linking from all SDK and CRT issues.

Acceptance:

- The result is PE32 for Intel 386, not PE32+.
- The entry point is the one supplied by the test.
- The only imported DLL is `KERNEL32.dll`.
- The only imported function is `ExitProcess`.
- There are no load-config, TLS, delay-import, or manifest surprises.
- The program exits successfully on Windows 98 SE.

Record the exact compile and link commands in the test directory.

## Milestone 3: Pin And Acquire The SDK

Inspect the February 2003 Platform SDK archive and verify that it is the final
practical SDK release whose headers and import libraries cover Windows 98.
Document evidence in `docs/sdk.md`; do not infer support only from an archive
title.

Support two acquisition modes:

```powershell
.\bootstrap.ps1 -SdkPath .\downloads\sdk
.\bootstrap.ps1 -DownloadSdk
```

`-SdkPath` accepts a documented directory or archive layout. `-DownloadSdk`
downloads the same pinned files from the URLs in `sources.lock.json`. Both
modes run the same hash verification before extraction.

The initial archive candidate is:

```text
https://archive.org/details/psdk-full.-1
```

Acceptance:

- A wrong or incomplete input fails with a useful message.
- A correct local input and a fetched input produce the same staged files.
- Re-running acquisition does not redownload valid files.
- Every staged file is covered by the lock file or generated manifest.

## Milestone 4: Extract Without Installing

Determine the smallest redistributable extraction dependency. Prefer tools
already available on both hosts; otherwise pin a standalone extractor.

Extract into `work/sdk-pristine/` without executing the SDK installer. Preserve
the original tree and write a machine-readable inventory containing relative
path, size, and SHA-256 for every extracted file.

Do not normalize names or patch headers in this milestone.

Acceptance:

- Extraction works from a fresh checkout plus the pinned SDK input.
- The pristine inventory is identical across two clean extractions.
- Required x86 `Include` and `Lib` trees are present.
- No registry or global environment changes are made.

## Milestone 5: Compile One Unmodified SDK Header

Compile a small `windows.h` program with `clang-cl` using the pristine SDK
include directory and Clang's builtin headers. Define the Windows 98 API level
explicitly, initially `_WIN32_WINNT=0x0410` and `WINVER=0x0410`.

Capture every incompatibility before adding a patch. Prefer compiler flags and
small compatibility headers over bulk rewrites of Microsoft headers.

Acceptance:

- The test compiles with warnings treated as errors, except for a documented
  allowlist of unavoidable SDK warnings.
- Include tracing proves that no modern Windows SDK header was selected.
- A clean rebuild emits a byte-identical object file when debug timestamps are
  disabled or normalized.

## Milestone 6: Link Against Original SDK Libraries

Link the header test directly against the SDK's x86 COFF import libraries with
`lld-link`. Start with `kernel32.lib`, then add `user32.lib` for a MessageBox
program.

Do not convert `.lib` files unless LLD demonstrates a concrete incompatibility.
If conversion is needed, generate a `.def` and new import library
deterministically rather than editing a binary library.

Acceptance:

- Console and GUI no-CRT samples link using staged SDK libraries.
- PE checks list only the expected Windows 98 DLLs and functions.
- Both samples run on Windows 98 SE.

## Milestone 7: Build A Minimal Sysroot

Create `scripts/build_sysroot.py` to copy only the required headers and x86
libraries from the pristine SDK into `sysroot/`. Apply compatibility overlays
from version-controlled source without modifying `work/sdk-pristine/`.

Write `sysroot/manifest.json` with input hashes, output hashes, source paths,
patch identities, target macros, and generator version.

Acceptance:

- Deleting `sysroot/` and rebuilding reproduces every output hash.
- The tests build using only LLVM plus `sysroot/`.
- Temporarily hiding any host Windows SDK does not break the build.

## Milestone 8: Audit Compiler-Generated Dependencies

Expand tests to operations that may require compiler helper functions:
64-bit integer division, shifts, multiplication, floating-point conversion,
and structure copies.

Compile each operation and inspect undefined symbols before introducing
compiler-rt. Build only the required compiler-rt builtins for the 32-bit
Windows target, or provide narrowly scoped source implementations when a full
compiler-rt build introduces unnecessary dependencies.

Acceptance:

- Every compiler-generated external symbol is documented.
- Compiler support code is built from pinned source.
- No compiler support DLL is required at runtime.
- The expanded test runs on Windows 98 SE.

## Milestone 9: Characterize Windows 98 MSVCRT

On a clean Windows 98 SE VM, inventory the actual `msvcrt.dll`: file version,
SHA-256, PE exports, and forwarded exports. Commit only the inventory and an
independently written module-definition file, not the DLL.

Compare those exports with any SDK-provided `msvcrt.lib`. Generate our own
import library from the reviewed definition if the SDK library exposes symbols
not present on Windows 98 SE.

Create a small public compatibility policy that classifies functions as:
available, wrapped, intentionally unsupported, or unverified.

Acceptance:

- The generated import library contains no symbol absent from the recorded
  Windows 98 SE export inventory.
- A checker rejects imports outside the approved MSVCRT set.
- No Microsoft runtime DLL is copied into project output.

## Milestone 10: Add Source-Owned CRT Startup

Implement the smallest startup objects needed for C:

```text
mainCRTStartup
WinMainCRTStartup
_DllMainCRTStartup
```

Start with process entry, calling the user entry point, and termination. Add
command-line parsing and `argc`/`argv` only after the basic console path works.
Add initialization tables only when a C feature in scope requires them.

Keep startup code separate from wrappers around missing MSVCRT functions.

Acceptance:

- A normal `main` program runs and returns its exit code on Windows 98 SE.
- A normal `WinMain` program runs without a console.
- A DLL loads, executes `DllMain`, and unloads cleanly.
- Startup objects have no imports outside the approved Win98 list.

## Milestone 11: Provide A Stable Driver

Add `win98-clang.cmd` and a PowerShell entry point that hide repeated target,
include, library, startup, and linker flags. Also add a CMake toolchain file.

The driver must print its resolved configuration with `--print-config` and
must not consult a globally installed Windows SDK.

Acceptance:

```powershell
win98-clang.cmd tests\02-console-crt\hello.c -o out\hello.exe
cmake -S tests\02-console-crt -B out\cmake-test `
  -DCMAKE_TOOLCHAIN_FILE=cmake\win98-clang-toolchain.cmake
cmake --build out\cmake-test
```

Both outputs must pass the PE checker and run on Windows 98 SE.

## Milestone 12: Automate Compatibility Checks

Implement `scripts/check_pe.py` without depending on the host's Visual Studio
tools. It must validate at least:

- PE32 and x86 machine type.
- subsystem and subsystem version.
- imported DLL allowlist.
- imported symbol allowlist per DLL.
- absence of accidental UCRT and modern API-set DLL imports.
- absence of unexpected runtime DLLs.

Keep the allowlist small and derived from the target VM plus documented Win98
components. An allowlist entry is not proof that an API behaves correctly, so
execution tests remain mandatory.

Acceptance:

- Known-good samples pass.
- Fixtures with a UCRT import, a modern Kernel32 import, or PE32+ format fail.
- Failure output identifies the exact incompatible property or symbol.

## Milestone 13: Make Windows Bootstrap Reproducible

`bootstrap.ps1` must orchestrate acquisition, extraction, sysroot generation,
runtime build, sample build, and static validation. It may use an installed
LLVM initially, but must enforce a supported version range.

After the process is stable, pin a portable LLVM package so a fresh Windows
host requires only PowerShell and Python. Keep use of the system Python
explicit until Python itself is pinned.

Acceptance:

- A clean Windows VM can build the complete environment from the documented
  prerequisites and supplied SDK input.
- A second clean run performs no unnecessary work.
- Removing `out/`, `work/`, and `sysroot/` then rebuilding reproduces manifests
  and binaries, excluding explicitly documented nondeterministic fields.

## Milestone 14: Add Linux Host Support

Add `bootstrap.sh` only after the Windows pipeline is stable. Both wrappers
must call the same Python implementation and consume the same lock file,
patches, sysroot recipe, runtime sources, and tests.

Pin a Linux LLVM distribution matching the Windows LLVM major version. Resolve
host-specific extraction differences without changing target outputs.

Acceptance:

- Windows and Linux builds produce equivalent PE headers and import tables.
- Normalized sample binaries have identical hashes, or every differing byte is
  understood and documented.
- The Linux-built samples run in the same Windows 98 SE VM.

## Milestone 15: Evaluate GCC

Only begin GCC integration after the SDK, runtime, import policy, and VM tests
are stable. Treat GCC as another compiler driver over the same target contract,
not as a second SDK project.

Build a pinned `i686-w64-mingw32` or `i686-pc-mingw32` GCC and binutils without
installing a modern MinGW runtime. Adapt archive formats and symbol decoration
where necessary. Reuse the source-owned startup and approved MSVCRT imports.

Acceptance:

- GCC builds the same console, GUI, DLL, and compiler-helper tests.
- GCC outputs pass the same PE and import checks without a separate relaxed
  allowlist.
- GCC outputs run on the same Windows 98 SE image.

## Windows 98 Test Environment

Treat QEMU as a documented host prerequisite and keep its emulated hardware
configuration under `vm/`. Record the exact emulator version for every
compatibility result; move to project-managed installation only if variation
between supported versions becomes a practical problem.

Development currently targets the QuickInstall lane: the pinned upstream
Windows 98 SE Stock image bootstrapped from the pinned ISO. It is fast to
create and adequate for developing the toolchain and the test loop.

This image is not an unmodified Windows 98 SE. It bundles Microsoft updates,
third-party patches, drivers, and utilities, so passing on it is not evidence
that a program runs on a clean Windows 98 SE installation. Verifying against an
unmodified reference image built from licensed media is deliberately deferred.
If it is reintroduced, it becomes the release compatibility gate and the
QuickInstall result remains necessary but not sufficient.

Neither image, installation media, nor mutable VM state is part of the
repository. Local defaults live under ignored `vm/local/`; set
`FORGE98_QEMU_IMAGE` or pass `-Image` to use an image stored elsewhere.

Run the emulator with software emulation and a fixed CPU so results do not
depend on host virtualization. The local iteration loop is automated per
Milestone 1 and [docs/testing-loop.md](docs/testing-loop.md): test binaries are
delivered through a read-only host folder, results are captured over a serial
port, and each run is disposable. Record OS edition, disk-image SHA-256,
emulator version, VM configuration revision, binary SHA-256, exit code, and
observed output for each result. Keep networking disabled so test transport does
not depend on host or guest network configuration.

For now a test passes when:

1. Static PE and import validation succeeds.
2. Execution succeeds on the QuickInstall Windows 98 SE image.

Unmodified-reference verification is deferred and is not currently a gate.

## Decision Gates

Stop and document findings before proceeding when any of these gates fails:

- The SDK candidate cannot be shown to support the intended Win98 API surface.
- Its license prevents the intended local transformation workflow.
- Clang cannot compile core headers without invasive bulk modification.
- LLD cannot consume the required SDK import libraries reliably.
- A supposedly minimal binary imports APIs absent from Windows 98 SE.
- The Windows 98 MSVCRT export set is too small for the desired C subset.
- Repeated clean builds do not reproduce their manifests.

At a failed gate, prefer narrowing the supported API or C-library surface over
adding opaque legacy binaries.

## Definition Of The First Usable Release

The first release is complete when a fresh Windows host can use a pinned LLVM
toolchain and a user-supplied, hash-verified SDK archive to build console, GUI,
and DLL C samples; all outputs pass automated PE/import checks and execute on
the Windows 98 SE test image; and no proprietary SDK or runtime binary is stored
in Git or redistributed with the project.
