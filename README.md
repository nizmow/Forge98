# Forge98

Forge98 is an experimental, reproducible C development environment
for building 32-bit PE programs on a modern Windows host and running them on
Windows 98 Second Edition.

The initial toolchain will use Clang and LLD. Microsoft SDK files, Windows
installation media, runtime DLLs, and virtual machine images are not included
and must not be committed to this repository.

Development is organized as small compatibility gates in [PLAN.md](PLAN.md).
The QEMU test environment is documented in [docs/vm.md](docs/vm.md), and the
automated testing loop in [docs/testing-loop.md](docs/testing-loop.md).

## Current Status

The project is in its early implementation phase. QEMU boots a Windows 98 SE
image, and the test loop can deliver a program, run it, and capture its output
over a serial port. The no-CRT sample builds with LLVM, passes fail-closed PE
header and import validation, and has a recorded Windows 98 execution result
in [tests/00-no-crt/README.md](tests/00-no-crt/README.md). The broader
SDK/compiler pipeline is still in progress.

### No-CRT sample

Build the sample and run its fail-closed PE checks:

```powershell
mise run test:no-crt:build
```

Exercise the verifier against the known-good executable and a deliberately
broken minimum-OS-version fixture:

```powershell
mise run test:no-crt:verify
```

## February 2003 Platform SDK

Supply the 13 `PSDK-FULL.N.cab` files in a directory, or let bootstrap download
the pinned Internet Archive copies. Both routes verify the locked size and
SHA-256 before staging files in ignored `downloads/sdk-feb-2003/`:

```powershell
mise run sdk:acquire
mise run sdk:download
mise run sdk:extract
```

See [docs/sdk.md](docs/sdk.md) for provenance, license notes, and the SDK
assessment.

## Prerequisites

Install [mise](https://mise.jdx.dev/), QEMU, and LLVM.

QEMU:

- Windows: `winget install SoftwareFreedomConservancy.QEMU`
- macOS: `brew install qemu`
- Debian/Ubuntu: `sudo apt install qemu-system-x86`
- Fedora: `sudo dnf install qemu-system-x86`

LLVM (Clang and LLD):

- Windows: `winget install LLVM.LLVM`
- macOS: `brew install llvm`
- Debian/Ubuntu: `sudo apt install clang lld`
- Fedora: `sudo dnf install clang lld`

QEMU and LLVM are host prerequisites and are not managed by mise. The project
mise environment adds the standard install directories to `PATH`. The
toolchain is pinned to LLVM 23.1.1 (`clang-cl 23.1.1`, `lld-link 23.1.1`);
later milestones depend on this exact version. Then run:

```powershell
mise run vm:check
```

The command validates the QEMU installation and the local Windows 98 image
without starting the VM. See [docs/vm.md](docs/vm.md).
