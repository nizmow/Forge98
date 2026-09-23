# No-CRT Windows 98 Executable

This test builds a PE32 console executable without a C runtime. Its entry point
calls the Windows API `ExitProcess(0)` directly.

## Build

From the repository root, run:

```powershell
pwsh -NoProfile -File tests/00-no-crt/build.ps1
```

The build and verification below were run with LLVM 23.1.1 (`clang-cl`,
`lld-link`, `llvm-dlltool`, and `llvm-readobj`). The commands used to create the
tested executable were:

```powershell
llvm-dlltool -m i386 -k -d tests/00-no-crt/kernel32.def -l out/00-no-crt/kernel32.lib
clang-cl --target=i686-pc-windows-msvc /c /Zl /GS- tests/00-no-crt/hello.c /Fo:out/00-no-crt/hello.obj
lld-link /machine:x86 /nodefaultlib /entry:mainCRTStartup /subsystem:console,4.0 /osversion:4.0 /out:out/00-no-crt/hello.exe out/00-no-crt/hello.obj out/00-no-crt/kernel32.lib
```

## Static PE Verification

The build runs this command after linking. `--sections` is included to verify
that no `.rsrc` section is present:

```powershell
llvm-readobj --file-headers --coff-imports --coff-load-config --coff-tls-directory --coff-resources --sections out/00-no-crt/hello.exe
```

The verifier requires PE32/i386, console subsystem version 4.0, minimum OS
version 4.0, exactly `KERNEL32.dll!ExitProcess`, and no load-config, TLS,
delay-import, resource, manifest, or `.rsrc` section. The output for the tested
executable was:

```text
File: out/00-no-crt/hello.exe
Format: COFF-i386
Arch: i386
AddressSize: 32bit
ImageFileHeader {
  Machine: IMAGE_FILE_MACHINE_I386 (0x14C)
  SectionCount: 3
  TimeDateStamp: 2026-09-23 18:42:04 (0x6AB41D7C)
  PointerToSymbolTable: 0x0
  SymbolCount: 0
  StringTableSize: 0
  OptionalHeaderSize: 224
  Characteristics [ (0x102)
    IMAGE_FILE_32BIT_MACHINE (0x100)
    IMAGE_FILE_EXECUTABLE_IMAGE (0x2)
  ]
}
ImageOptionalHeader {
  Magic: 0x10B
  MajorLinkerVersion: 14
  MinorLinkerVersion: 0
  SizeOfCode: 512
  SizeOfInitializedData: 1024
  SizeOfUninitializedData: 0
  AddressOfEntryPoint: 0x1000
  BaseOfCode: 0x1000
  BaseOfData: 0x0
  ImageBase: 0x400000
  SectionAlignment: 4096
  FileAlignment: 512
  MajorOperatingSystemVersion: 4
  MinorOperatingSystemVersion: 0
  MajorImageVersion: 0
  MinorImageVersion: 0
  MajorSubsystemVersion: 4
  MinorSubsystemVersion: 0
  SizeOfImage: 16384
  SizeOfHeaders: 1024
  CheckSum: 0x0
  Subsystem: IMAGE_SUBSYSTEM_WINDOWS_CUI (0x3)
  Characteristics [ (0x8540)
    IMAGE_DLL_CHARACTERISTICS_DYNAMIC_BASE (0x40)
    IMAGE_DLL_CHARACTERISTICS_NO_SEH (0x400)
    IMAGE_DLL_CHARACTERISTICS_NX_COMPAT (0x100)
    IMAGE_DLL_CHARACTERISTICS_TERMINAL_SERVER_AWARE (0x8000)
  ]
  SizeOfStackReserve: 1048576
  SizeOfStackCommit: 4096
  SizeOfHeapReserve: 1048576
  SizeOfHeapCommit: 4096
  NumberOfRvaAndSize: 16
  DataDirectory {
    ExportTableRVA: 0x0
    ExportTableSize: 0x0
    ImportTableRVA: 0x2000
    ImportTableSize: 0x28
    ResourceTableRVA: 0x0
    ResourceTableSize: 0x0
    ExceptionTableRVA: 0x0
    ExceptionTableSize: 0x0
    CertificateTableRVA: 0x0
    CertificateTableSize: 0x0
    BaseRelocationTableRVA: 0x3000
    BaseRelocationTableSize: 0xC
    DebugRVA: 0x0
    DebugSize: 0x0
    ArchitectureRVA: 0x0
    ArchitectureSize: 0x0
    GlobalPtrRVA: 0x0
    GlobalPtrSize: 0x0
    TLSTableRVA: 0x0
    TLSTableSize: 0x0
    LoadConfigTableRVA: 0x0
    LoadConfigTableSize: 0x0
    BoundImportRVA: 0x0
    BoundImportSize: 0x0
    IATRVA: 0x2030
    IATSize: 0x8
    DelayImportDescriptorRVA: 0x0
    DelayImportDescriptorSize: 0x0
    CLRRuntimeHeaderRVA: 0x0
    CLRRuntimeHeaderSize: 0x0
    ReservedRVA: 0x0
    ReservedSize: 0x0
  }
}
DOSHeader {
  Magic: MZ
  UsedBytesInTheLastPage: 120
  FileSizeInPages: 1
  NumberOfRelocationItems: 0
  HeaderSizeInParagraphs: 4
  MinimumExtraParagraphs: 0
  MaximumExtraParagraphs: 0
  InitialRelativeSS: 0
  InitialSP: 0
  Checksum: 0
  InitialIP: 0
  InitialRelativeCS: 0
  AddressOfRelocationTable: 64
  OverlayNumber: 0
  OEMid: 0
  OEMinfo: 0
  AddressOfNewExeHeader: 120
}
Sections [
  Section {
    Number: 1
    Name: .text (2E 74 65 78 74 00 00 00)
    VirtualSize: 0x15
    VirtualAddress: 0x1000
    RawDataSize: 512
    PointerToRawData: 0x400
    PointerToRelocations: 0x0
    PointerToLineNumbers: 0x0
    RelocationCount: 0
    LineNumberCount: 0
    Characteristics [ (0x60000020)
      IMAGE_SCN_CNT_CODE (0x20)
      IMAGE_SCN_MEM_EXECUTE (0x20000000)
      IMAGE_SCN_MEM_READ (0x40000000)
    ]
  }
  Section {
    Number: 2
    Name: .rdata (2E 72 64 61 74 61 00 00)
    VirtualSize: 0x53
    VirtualAddress: 0x2000
    RawDataSize: 512
    PointerToRawData: 0x600
    PointerToRelocations: 0x0
    PointerToLineNumbers: 0x0
    RelocationCount: 0
    LineNumberCount: 0
    Characteristics [ (0x40000040)
      IMAGE_SCN_CNT_INITIALIZED_DATA (0x40)
      IMAGE_SCN_MEM_READ (0x40000000)
    ]
  }
  Section {
    Number: 3
    Name: .reloc (2E 72 65 6C 6F 63 00 00)
    VirtualSize: 0xC
    VirtualAddress: 0x3000
    RawDataSize: 512
    PointerToRawData: 0x800
    PointerToRelocations: 0x0
    PointerToLineNumbers: 0x0
    RelocationCount: 0
    LineNumberCount: 0
    Characteristics [ (0x42000040)
      IMAGE_SCN_CNT_INITIALIZED_DATA (0x40)
      IMAGE_SCN_MEM_DISCARDABLE (0x2000000)
      IMAGE_SCN_MEM_READ (0x40000000)
    ]
  }
]
Import {
  Name: KERNEL32.dll
  ImportLookupTableRVA: 0x2028
  ImportAddressTableRVA: 0x2030
  Symbol: ExitProcess (0)
}
TLSDirectory {
}
Resources [
]
```

## Windows 98 Execution

Run the test in the Windows 98 VM with:

```powershell
mise run test:win98 -- out/00-no-crt/hello.exe
```

Recorded result:

- OS: Windows 98 SE Stock QuickInstall image
- Disk image SHA-256: `4877dbabe8215591929b60f01d3e6037c7535af2823d8010303e4c04fc1ec791`
- QEMU: `11.1.0 (v11.1.0-12130-ge470268ff4)`
- VM configuration source revision: `a5dc91e424a5a7d230c20660d5b7f19ae53f7e8a`
- VM configuration: `pc,hpet=off`, Pentium III, 128 MiB RAM, TCG, snapshot run
- Executable SHA-256: `3a2d5bce12add58ee786519965af66697d781f4d7b3f6fefcfc17ce61ea2a8c7`
- Guest exit code: `0`
- Guest stdout: empty
- Result: `PASS`
