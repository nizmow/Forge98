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

The project is in its planning and environment-bootstrap phase. QEMU boots a
Windows 98 SE image, and the test loop can deliver a program, run it, and
capture its output over a serial port. The compiler pipeline and automated PE
checks have not been implemented.

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
