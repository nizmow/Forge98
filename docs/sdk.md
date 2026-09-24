# February 2003 Platform SDK Assessment

This is the initial feasibility assessment for the SDK candidate in
[PLAN.md, Milestone 3](../PLAN.md#milestone-3-pin-and-acquire-the-sdk). It
records published evidence and explicitly separates that from checks that
require inspecting the SDK files themselves.

## Decision

**Go: continue with this SDK as the project candidate and proceed to pinned
acquisition/staging work.** Its own release metadata explicitly says that apps
built with this edition can run on Windows 98, and its x86 core package contains
the expected headers and import libraries. Its EULA allows local use and copies
for software development and testing. Keep SDK files and binaries out of Git and
do not redistribute the SDK. The claim that it is the *last* practical release
with Windows 9x support is still based on secondary release history, rather
than a complete first-party survey of later SDKs.

Two qualifications remain. The archived download is a community upload; its
files match the Internet Archive's recorded checksums, but have not been
compared with a Microsoft-hosted copy. Also, a first `windows.h` compile with
LLVM alone fails because the SDK/compiler boundary needs C runtime/compiler
headers (`excpt.h`, `ctype.h`, `string.h`) that are not part of Clang's builtin
headers. This is a concrete follow-up for the header/compiler gate, not evidence
that the SDK lacks Windows 98 support. The exact results and next checks are
below.

## Candidate identity and provenance

| Field | Current finding |
| --- | --- |
| Candidate | Microsoft Platform SDK, February 2003 edition |
| SDK version in package metadata | 5.2.3790.0 (`xml/version.xml`) |
| Package release date | February 2003 (`xml/windows_info.xml`) |
| Historical download layout | Thirteen chained `PSDK-FULL.N.cab` files, `PSDK-FULL.bat`, and `Extract.exe` |
| Repository's candidate reference | <https://archive.org/details/psdk-full.-1> |
| Original Microsoft download URL pattern | `http://download.microsoft.com/download/platformsdk/sdk/update/win98mexp/en-us/3790.0/FULL/PSDK-FULL.N.cab` |
| Archive size | About 323.4 MiB for the Internet Archive item |

The Internet Archive metadata identifies the item as “Platform SDK Feb 2003”
and supplies a size and SHA-1 for every cabinet. All 13 downloaded cabinets
match those recorded sizes and hashes. A 2003 Microsoft Platform SDK newsgroup
thread preserves the original Microsoft download URL pattern and enumerates
the cabinet chain [1]. The archived copy is community-uploaded, so these checks
establish consistency with the archive item, not byte-for-byte identity with
Microsoft's original download. The outer cabinet chain extracted successfully
with 7-Zip without running `Setup.exe`; 7-Zip reported 6,728 trailing bytes
after each cabinet's declared end.

The exact URL, destination filename, size, and SHA-256 for each of the 13
cabinets are pinned in `sources.lock.json`. The SHA-256 values were computed
from the cached files whose sizes and SHA-1 values match Internet Archive
metadata. Do not describe this mirror as a verified Microsoft-origin binary
until an original copy or an independent Microsoft checksum is found. For this
milestone, the Internet Archive item is the sole pinned source; no cross-source
comparison is claimed.

## Acquiring the pinned inputs

The bootstrap supports a local directory and a download mode. A local directory
must contain all 13 cabinet files directly, named `PSDK-FULL.1.cab` through
`PSDK-FULL.13.cab`; extra files are ignored. It validates every input before
staging any of them. Both modes then apply the same locked size and SHA-256
checks and stage files under the ignored `downloads/sdk-feb-2003/` directory.
Files already in that cache are reused only after they pass verification.
Downloads use temporary `.partial` files, which are verified before being
renamed into the cache. Missing, truncated, or modified inputs fail with the
expected size or hash in the error message. No SDK installer is run.

```powershell
.\bootstrap.ps1 -SdkPath .\downloads\sdk-feb-2003
.\bootstrap.ps1 -DownloadSdk
```

The local command also accepts another directory with that same flat layout.
Acquisition only stages the original cabinet chain; extraction and pristine
SDK inventory are separate follow-up work and do not alter the downloaded
inputs.

## Windows 98 coverage: evidence and gaps

The package's own `xml/windows_info.xml` says that apps built with this edition
can run on Windows Server 2003, Windows XP, Windows 2000, Windows NT, Windows
Me, Windows 98, and Windows 95 [2]. This is direct release documentation for
the target family (it says Windows 98, not specifically Windows 98 SE).

The Core SDK package's mapped payload contains 1,090 include files and 335
library files across shared and architecture-specific paths. The expected x86
files are present: `Windows.h`, `WinBase.h`, `WinDef.h`,
`WinUser.h`, `WinNT.h`, `Kernel32.Lib`, and `User32.Lib`. These were extracted
from the package's MSI cabinet payloads into ignored `work/` paths without
running the installer. The existing no-CRT sample then compiled and linked
against the original `Kernel32.Lib`; `llvm-readobj` and the fail-closed PE
verifier passed. It imports `KERNEL32.dll!ExitProcess` (by ordinal 175). This
proves basic x86 library compatibility with LLD. A no-CRT GUI probe with a
manual `MessageBoxA` declaration also linked against the original `User32.Lib`
and `Kernel32.Lib`; it imports `USER32.dll!MessageBoxA` (ordinal 478) and
`KERNEL32.dll!ExitProcess` (ordinal 175). Neither probe has been executed in the
VM, so Win98 SE export/ordinal availability and runtime behavior are still
unverified.

The package's own target statement establishes Windows 98 (not specifically
Windows 98 SE) support. A historical release table calls this the latest SDK
with Windows 95/98 support [7], but that remains secondary evidence. The
first-party files examined here prove this edition is a supported candidate;
they do not by themselves prove that no later SDK retained that support.

The headers use separate target controls. The candidate's `Windows.h` defaults
`WINVER` to `0x0501` (Windows XP). `WinBase.h` and `WinUser.h` gate declarations
on both `WINVER` / `_WIN32_WINNT` and `_WIN32_WINDOWS`; some guards specifically
accept `_WIN32_WINDOWS > 0x0400`. For a Windows 98 header probe, use
`WINVER=0x0400` and `_WIN32_WINDOWS=0x0410`, and leave the NT-family
`_WIN32_WINNT` policy distinct; do not use it as a substitute for the Win9x
target macro.

The initial compile probe with `clang-cl /X` failed on missing `excpt.h`. A
test-only empty `excpt.h` shim exposed subsequent missing `ctype.h`; after a
test-only `ctype.h` placeholder, compilation reached the expected `wchar_t`
definition and then failed on missing `string.h`. Clang's resource headers
provide `stdarg.h` but not these C runtime/compiler headers. The placeholders
were only diagnostic and are not part of the SDK or a proposed implementation.
Resolve this compiler/CRT-header dependency in the header milestone before
claiming that a normal C `windows.h` translation unit builds from LLVM plus the
SDK alone.

## License and repository handling

The package includes `License/License.htm` and `License/Redist.Txt`. The exact
EULA grants a limited, nonexclusive right to use and make copies of the SDK to
design, develop, and test applications for Windows (section 1.1). Redistribution
is narrower: sample source and code listed in `Redist.Txt` are covered by
specific terms, and redistributable `.lib` files may only be distributed as
linker output with an application (sections 2 and 3). The EULA also prohibits
reverse engineering, decompilation, and disassembly (section 6); component
EULAs may take precedence (section 4).

This supports local development use while reinforcing the repository's existing
policy: do not commit or redistribute SDK archives, extracted vendor headers,
or import libraries. Keep source-authored compatibility code separate from the
pristine SDK. The SDK EULA is not an open-source license, and the permission to
use the SDK does not make this community-upload source authoritative.

## Required checks to reach a decision

Remaining checks before making a broad compatibility claim:

1. Compare the community-uploaded files with a Microsoft-hosted copy or an
   independent Microsoft checksum if one becomes available.
2. Finish the pristine-file inventory and capture the exact x86 Include/Lib
   extraction recipe for reproducible staging.
3. Resolve the missing compiler/C headers identified by the `windows.h` probe
   without selecting modern Windows SDK declarations.
4. Audit the original libraries' imports, including the ordinal imports used by
   these probes, against Windows 98 SE exports.
5. Run the console and GUI samples on the Windows 98 SE VM. The SDK's own
   supported-target list is not runtime verification.

If the compiler/CRT-header boundary cannot be resolved without selecting
incompatible APIs or importing an unsupported runtime, revisit the candidate at
the Milestone 5 decision gate. Compatibility claims ultimately still require
execution on Windows 98 SE; a successful compile or link is not proof of runtime
compatibility.

## Sources

1. Microsoft Platform SDK newsgroup thread, “Where can I get an old version of
   the SDK” (contains the February 2003 Microsoft download URL pattern and
   cabinet list):
   <https://groups.google.com/g/microsoft.public.platformsdk.sdk_install/c/eOB4gomnDm4/m/nhXY9XgBewgJ>
2. Package file `xml/windows_info.xml` (release description and supported OSes)
   and `xml/version.xml` (build number and date) in the archived package [6].
3. Exact package license files `License/License.htm` and `License/Redist.Txt`
   in the archived package [6].
4. Microsoft Learn, `WINVER` and `_WIN32_WINNT` overview:
   <https://learn.microsoft.com/en-us/cpp/porting/modifying-winver-and-win32-winnt?view=msvc-170>;
   historical Win9x macro discussion:
   <https://mingw-dvlpr.narkive.com/2MQWFsf3/winver-and-win32-winnt-again>
5. Internet Archive item metadata for the archived February 2003 package,
   including file sizes and hashes:
   <https://archive.org/metadata/psdk-full.-1>
6. Archived candidate files: <https://archive.org/details/psdk-full.-1>
7. Historical SDK release table (secondary evidence for the “latest Win9x SDK”
   claim): <https://en.wikipedia.org/wiki/Windows_SDK>
