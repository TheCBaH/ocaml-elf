# `elf`: design

Status: design, pre-implementation. Date: 2026-10-13.

A small, pure-OCaml library that reads ELF32/ELF64 files and writes static
`ET_EXEC` executables for the six architectures the assembler in this
repository targets: x86-32, x86-64, ARM32, AArch64, RV32 and RV64. RV32 is the
primary target and the first one to be completed end to end.

The project incubates in `elf/` and is meant to become a standalone GitHub
repository. Everything under `elf/` is therefore laid out as a repository root
and must not depend on anything elsewhere in this tree.

## 1. Goals and non-goals

Goals:

- Checked ELF32/ELF64 codecs (both byte orders) over common semantic records.
- Bounded parsing of untrusted input: executables with and without sections,
  sections, string tables, symbols, REL/RELA, notes, and build attributes.
- Static executable generation from caller-chosen addresses, preserving bound
  bytes exactly: the writer never moves code or data.
- Target profiles that derive ELF class and machine together and keep ABI
  and execution environment explicit.
- Two execution profiles per architecture: Linux user mode and bare-metal
  system mode under QEMU.
- Portability: native, js_of_ocaml and Melange produce identical bytes.

Non-goals for the first release:

- Dynamic linking, shared objects, `PT_INTERP`, linker relaxation.
- Applying relocations or loading code into the current process.
- Byte-identical decode/re-encode round trips. That needs a separate raw
  preservation model (original offsets, padding, unknown payloads) and is only
  worth building if binary editing becomes a requirement.
- `ET_REL` generation (milestone 6, §11): it needs symbolic sections and fixups
  from *before* the assembler binds them. A bound image cannot recover them.

## 2. Existing OCaml libraries

None of the inspected options meets the requirement for both ELF32 generation
and ELF64 parsing:

| Candidate | What it provides | Why it is not enough |
| --- | --- | --- |
| Owee | ELF64 decoder: header, section and symbol readers | No ELF32, no writer. Useful as an independent ELF64 parser check. |
| `object` 0.1 | ELF reader | Rejects ELF32; no writer API despite its README; depends on Unix and Bigarray. |
| `bap-elf` | Parser and loader | Pulls in BAP and Core_kernel, which is far too heavy for a portable closure. |
| `ocaml-elf` (gazagnaire) | ELF64 little-endian reader | No ELF32, no writer. |

## 3. Constraints

### 3.1 Portability

The core library depends only on the OCaml standard library and err_trace,
which is itself dependency-free pure OCaml. The core uses no Unix, Bigarray, C stubs, `Obj` or PPX. File access lives in a separate
`elf.unix` library. The OCaml lower bound is 4.14, because `String.get_int64_le`
and friends need 4.13 and the devcontainer matrix starts at 4.14.3.

### 3.2 Integer representation

A target address cannot be an OCaml `int`. RV32 addresses reach 2^32 − 1, and
a native `int` is 31 bits on 32-bit hosts and 32 bits signed under
js_of_ocaml. So:

- Every field 32 bits wide or wider is an `int64` bit pattern. That covers
  addresses, offsets, sizes, `p_type`, `sh_type`, flags, and
  `sh_link`/`sh_info`.
- Fields of 16 bits or fewer (`e_type`, `e_machine`, `st_info`, `st_shndx`, the
  header counts) are `int`.
- A `U64` module provides unsigned compare and checked `add`, `sub` and `mul`
  (returning `option`), plus `align_up`/`align_down`, `fits_bits` and
  `to_int : int64 -> int option`.
- A file offset becomes a native index in exactly one place, the decoder's
  `extent` check. It does so only after `offset + size` has been computed
  without overflow and shown to be ≤ the input length.

### 3.3 Open-ended numeric values

Constants (`Const.pt_load`, `Const.em_riscv`, …) name values without
restricting them. Records store raw numbers, decoding keeps unknown values, and
printers show a known name or the hex value.

## 4. Error handling with err_trace

err_trace (module `Err`) is the error layer. `('a, 'e) Err.t` is
`('a, 'e Err.Error.t) result`: a typed payload plus a bounded detection origin
and event trail.

Rules:

1. **Each module owns one closed polymorphic-variant domain.** The pair
   `type error = [ ... ]` and `pp_error` is exhaustiveness-checked. A domain
   built from others includes them (`[ Encode.error | Attributes.error | ... ]`)
   and delegates in `pp_error` with `#Encode.error as e -> Encode.pp_error ppf e`.
2. **Signatures use closed rows.** `(t, error) Err.t`, not `[> error ]`.
   Because `Err.Error.t` is covariant, a caller widens with a coercion
   (`(r :> (_, Exec.error) Err.t)`), and no conversion event is recorded. Use
   `Err.map_error ~pos:__POS__` only for a real domain change that adds context,
   such as wrapping a decoder failure in a test-harness error.
3. **Payloads carry domain values, not renderings.** Examples are
   `` `Truncated of { region; offset; size; available } `` and
   `` `Field_overflow of { record; field; value; bits; signed } ``.
   Polymorphic variants cannot carry inline records, so each such payload is a
   named record type declared next to the domain.
4. **Every failure site passes `~pos:__POS__` and `~pp_error`.** Provenance then
   stays portable when stack capture is off.
5. **The library never calls `Err.Config.set`.** Trace policy belongs to the
   process. Tests and the CLI choose `Err.Config.deterministic`, so error output
   in golden files is identical on every backend.
6. **Validators that must report every problem use `Err.Accum`.** One example
   is `Exec.validate`. Decoding stops at the first error with `Err.List`.

### Dependency

err_trace is consumed as an opam package installed from GitHub, not vendored:

```sh
opam pin add err_trace "git+https://github.com/TheCBaH/err_trace.git#v0.0.1"
```

`dune-project` declares `err_trace (= dev)`, because the pinned package has no
version of its own. `elf.opam.template` adds the matching `pin-depends` entry,
so `opam install .` resolves it with no manual step. The library is
`err_trace` (`wrapped false`, module `Err`). Moving to a released version means
changing the pin, or dropping `pin-depends` once err_trace is in
opam-repository.

## 5. Project layout

```
elf/                          future repository root
  dune-project  elf.opam(.template)  .ocamlformat  Makefile  README.md  LICENSE
  .devcontainer/              devcontainer.json + Dockerfile (§10)
  .github/workflows/ci.yml    devcontainer-based CI (§10)
  docs/design.md              this file
  src/                        library `elf` (portable core)
  unix/                       library `elf.unix` (file I/O)
  bin/                        `elf-inspect` CLI (decoded dump, for cram tests)
  test/unit/                  codec, decoder, builder, malformed input
  test/cram/                  elf-inspect golden output
  test/gnu/                   GAS payloads, readelf/objdump checks, QEMU runs
```

## 6. Modules

All modules live in the wrapped library `elf` (`Elf.Decode`, `Elf.Exec`, …).

| Module | Role |
| --- | --- |
| `U64` | Unsigned checked arithmetic over `int64` (§3.2). |
| `Types` | Semantic records `ident`, `header`, `phdr`, `shdr`, `sym`, `rel`; `elf_class`, `endianness`. |
| `Const` | Named constants: `ET_*`, `EM_*`, `PT_*`, `PF_*`, `SHT_*`, `SHF_*`, `SHN_*`, `STB_*`/`STT_*`, RISC-V and ARM `e_flags`. |
| `Codec` | Field layouts of every fixed-size record, for both classes and byte orders. Unchecked readers and writers. Internal; the only place offsets live. |
| `Encode` | Checked serialization: range-checks every field against its width in the chosen class, then calls `Codec`. |
| `Decode` | Bounded parsing into a validated file view, plus accessors for symbols, relocations, notes and section/segment data. |
| `Strtab` | String-table builder: offset 0 is the empty string, entries are deduplicated, NUL inside a name is rejected. |
| `Attributes` | Build-attribute sections (format `'A'`): vendor subsections, File/Section/Symbol scopes, ULEB/NTBS values. Shared by RISC-V and ARM. |
| `Riscv` | `e_flags` from the ABI; `.riscv.attributes` contents; ISA-string builder; named ABI profiles. |
| `Arm` | EABI version and float-ABI `e_flags`; `aeabi` attribute classification. |
| `Target` | Architecture profile: class, byte order, machine, flags, OS ABI, maximum page size, attributes. |
| `Exec` | Executable spec, validation, address planning and serialization. |
| `Elf_unix` (separate library) | `read_file`; `write_executable`, which sets mode 0755 (QEMU user mode needs the execute bit). |

The adapter from the assembler's bound image to an `Exec.spec` belongs to the
*consumer*: `elf` never depends on the assembler. The assembler's image
segment carries only one address, its initialized bytes, zero-fill,
permissions and alignment, which maps directly to one `Exec.segment` per image
segment.

### 6.1 Record layouts (`Codec`)

ELF32 and ELF64 differ in field order, not only in width, so there is one
codec per class over the common records:

| Record | ELF32 size | ELF64 size | Order difference |
| --- | --- | --- | --- |
| ELF header | 52 | 64 | none; `e_entry` at 24, then 3 words, `e_flags`, 6 × u16 |
| Program header | 32 | 56 | `p_flags` after `p_memsz` (32) vs. after `p_type` (64) |
| Section header | 40 | 64 | none; only word sizes |
| Symbol | 16 | 24 | `st_value`/`st_size` before `st_info` (32) vs. after `st_shndx` (64) |
| REL / RELA | 8 / 12 | 16 / 24 | `r_info` = sym≪8 \| type:8 (32) vs. sym≪32 \| type:32 (64); ELF32 addend is signed 32-bit |

### 6.2 `Encode`

```ocaml
type record = [ `Header | `Program_header of int | `Section_header of int
              | `Symbol of int | `Relocation of int ]
type overflow = { record : record; field : string; value : int64; bits : int; signed : bool }
type error = [ `Field_overflow of overflow ]

val write_header : Bytes.t -> header -> (unit, error) Err.t
val write_phdr   : ident -> Bytes.t -> int -> index:int -> phdr -> (unit, error) Err.t
(* likewise write_shdr, write_sym, write_rel *)
```

Checks catch ELF32 addresses ≥ 2^32, a relocation type wider than 8 bits in
ELF32, an addend outside [−2^31, 2^31), and negative or oversized 16-bit
counts. Nothing is ever silently truncated.

### 6.3 `Decode`

```ocaml
type t = private {
  data : string; header : header;
  phnum : int; shnum : int; shstrndx : int;   (* after extended numbering *)
  phdrs : phdr array; sections : section array;
}
val of_string     : string -> (t, error) Err.t
val section_data  : t -> section -> (string, error) Err.t   (* "" for NOBITS *)
val segment_data  : t -> int -> (string, error) Err.t
val string_at     : t -> section -> int64 -> (string, error) Err.t
val symbols       : t -> section -> (symbol array, error) Err.t
val relocations   : t -> section -> (rel array, error) Err.t
val notes         : t -> [ `Section of section | `Segment of int ] -> (note list, error) Err.t
val attributes    : t -> section -> (Attributes.t, error) Err.t
```

Validation performed, each failure with its own constructor:

- `e_ident`: magic, class, data encoding, `EI_VERSION`.
- The header extent, and table extents computed as `offset + count × entsize`
  with checked multiply and add.
- `e_phentsize`/`e_shentsize` equal the class's record size whenever the
  table is present. `e_shnum ≠ 0` with `e_shoff = 0` is an error.
- **Extended numbering:** `e_shnum = 0` takes the real count from
  `shdr[0].sh_size`, `e_shstrndx = SHN_XINDEX` uses `shdr[0].sh_link`, and
  `e_phnum = PN_XNUM` uses `shdr[0].sh_info`.
- Every linked index (`e_shstrndx`, `sh_link`) is in range and has the
  expected section type.
- Every string offset lies inside its table and is NUL-terminated inside it.
- Table sections: `sh_entsize` matches when nonzero, and `sh_size` is a whole
  number of entries.
- `SHN_XINDEX` symbols are resolved through the `SHT_SYMTAB_SHNDX` section
  linked to their symbol table.
- Notes: the name is padded to 4 bytes and the descriptor to 4, or to 8 when the
  section/segment alignment is 8 (`.note.gnu.property` on ELF64), as binutils
  reads them; every name/descriptor length is bounds-checked.
- Section and segment *contents* are validated lazily by the accessors. A file
  with one bad section still decodes, and only that section's accessor fails.

### 6.4 `Attributes`

```ocaml
type value = Uleb of int64 | Ntbs of string | Uleb_ntbs of int64 * string
type scope = File | Section of int list | Symbol of int list
type subsection = { vendor : string; contents : [ `Parsed of (scope * (int * value) list) list
                                                 | `Raw of string ] }
type t = subsection list
val encode : endianness -> t -> (string, error) Err.t
val decode : endianness -> string -> (t, error) Err.t
```

Layout: one `'A'` byte, then subsections. Each subsection is a u32 length that
includes itself, an NTBS vendor name, and sub-subsections. Each sub-subsection
is a ULEB scope tag, a u32 length, an index list for the Section/Symbol scopes,
and the attributes.

A tag's value form is vendor-specific:

- `riscv`: even tags are ULEB, odd tags are NTBS.
- `aeabi`: tags 4, 5 and 67 are NTBS; 32 (`Tag_compatibility`) is ULEB + NTBS;
  other tags below 32 are ULEB; tags above 32 are NTBS when odd and ULEB when
  even.
- Unknown vendors are kept `Raw`.
- ULEB decoding rejects values wider than 64 bits and truncated input.

### 6.5 Target profiles (`Target`, `Riscv`, `Arm`)

```ocaml
type arch = X86_32 | X86_64 | Arm | Aarch64 | Riscv32 | Riscv64
type t = { arch; elf_class; endianness; machine : int; flags : int64; osabi : int;
           max_page_size : int64; attributes : attributes option }
and attributes = { section_name : string; section_type : int64;
                   segment_type : int64 option; contents : Attributes.t }
```

Class and machine come from `arch` together and are never set independently.
The ABI is an explicit argument:

| Arch | Class | `e_machine` | `e_flags` | Max page | Attributes | QEMU user |
| --- | --- | --- | --- | --- | --- | --- |
| RV32 (primary) | ELF32 | 243 | from `Riscv.abi` | 4 KiB | `.riscv.attributes` + `PT_RISCV_ATTRIBUTES` | `qemu-riscv32` |
| RV64 | ELF64 | 243 | from `Riscv.abi` | 4 KiB | same | `qemu-riscv64` |
| x86-32 | ELF32 | 3 | 0 | 4 KiB | none | `qemu-i386` |
| x86-64 | ELF64 | 62 | 0 | 4 KiB | none | `qemu-x86_64` |
| ARM32 | ELF32 | 40 | `0x05000000` \| float ABI | 4 KiB | optional `.ARM.attributes` | `qemu-arm` |
| AArch64 | ELF64 | 183 | 0 | 64 KiB (GNU ld's default, safe on 64K-page kernels) | none | `qemu-aarch64` |

All profiles are little-endian initially. Byte order stays explicit
throughout, and both codecs and the decoder already handle big-endian files.

**RISC-V.**

```ocaml
type float_abi = Soft | Single | Double | Quad
type abi = { xlen : [`Rv32 | `Rv64]; float_abi; rvc : bool; rve : bool; tso : bool;
             arch : string; stack_align : int; unaligned_access : bool option }
```

- `e_flags` is `RVC 0x1 | float ABI (0, 0x2, 0x4, 0x6) | RVE 0x8 | TSO 0x10`.
- The float bits describe the argument-passing ABI, not whether the code uses
  floating-point instructions.
- `RVC` follows the `rvc` field (whether compressed alignment is permitted),
  not the register width.
- Attributes are `Tag_RISCV_stack_align` (4, ULEB; 16 by default),
  `Tag_RISCV_arch` (5, NTBS) and optionally `Tag_RISCV_unaligned_access` (6).

Named profiles:

- `rv32imafd_ilp32d`: the compatibility profile matching the assembler's
  current RV32 toolchain settings (no relaxation, no small-data placement).
- `rv32im_ilp32`: integer-only.
- `rv64imafd_lp64d` and `rv64im_lp64`.

The ISA string is caller-supplied text. `Riscv.isa_string` builds one in
canonical order (base, single-letter extensions, `z*` by category then name,
`s*`, `x*`) from an explicit extension/version list. It does **not** expand
implied extensions; the profile lists them explicitly. Each named profile's
string is checked against GAS (§9.4).

The local GAS (binutils 2.44, default `-misa-spec`) emits, for
`-march=rv32imafd`:

```
rv32i2p0_m2p0_a2p0_f2p0_d2p0_zmmul1p0_zaamo1p0_zalrsc1p0
```

The ISA spec version a profile follows is therefore part of the profile, and
the specification revision is recorded in test provenance.

**ARM.**

- `e_flags` is `EF_ARM_EABI_VER5 | EF_ARM_ABI_FLOAT_HARD (0x400)` for the
  `gnueabihf` profile, and `| EF_ARM_ABI_FLOAT_SOFT (0x200)` for soft-float.
- `.ARM.attributes` is optional in generated executables, but always decoded.

### 6.6 `Exec`: executable generation

**Spec.**

```ocaml
type perms = { read : bool; write : bool; execute : bool }
type content = Bytes of string | Zero of int64
type section = { name : string; addr : int64; align : int64; content : content }
type segment = { perms : perms; paddr : int64 option; sections : section list }
type headers = Unmapped | Mapped of { vaddr : int64; paddr : int64 option }
type symbol = { name : string; value : int64; size : int64;
                kind : [`Notype | `Object | `Func]; binding : [`Local | `Global | `Weak];
                section : string option (* None: SHN_ABS *) }
type spec = {
  target : Target.t; entry : int64;          (* required: no silent zero *)
  segments : segment list; headers : headers;
  gnu_stack : perms option;                  (* PT_GNU_STACK *)
  section_headers : bool; symbols : symbol list;
}
val build : spec -> (string, error) Err.t
```

A segment is a run of sections at fixed addresses. Its vaddr is the first
section's address. `filesz` runs to the end of the last `Bytes` section (gaps
are zero-filled in the file), and `memsz` runs to the end of the last section.
So a segment can be initialized, pure zero-fill, or mixed, and `filesz ≤ memsz`
holds by construction. `paddr` defaults to `vaddr`, and the two are distinct
fields everywhere; the execution profile decides what `paddr` means.

**Validation** (collects every problem via `Err.Accum`):

- Alignments are powers of two, and each section address is a multiple of its
  alignment.
- Sections in a segment are ascending and non-overlapping, and no `Bytes`
  section follows a `Zero` section.
- Every range fits the class: `vaddr + memsz ≤ 2^32` for ELF32, computed
  without overflow. The same applies to `paddr`.
- Segments do not overlap, and do not share a page (by `max_page_size`).
  Separate RX, R and RW page ranges are a requirement, not a preference.
  Physical ranges do not overlap either.
- Mapped headers are page-aligned, and their page does not intersect any
  segment.
- `entry` lies within the *initialized* part of an executable segment.
- Section and symbol names are unique where required and contain no NUL. A
  symbol's section exists. Symbols require `section_headers = true`.

**Planning.** Analysis workflow steps 1–4 are covered by `Exec.place`:

```ocaml
type request = { name : string; perms : perms; init_size : int64; zero_fill : int64; align : int64 }
val headers_size : spec_shape -> int64          (* ehdr + phnum × phentsize *)
val place : Target.t -> mapped_headers:bool -> base:int64 -> request list ->
            (headers * (string * int64) list, error) Err.t
```

`place` reserves the header page at `base` when headers are mapped. It then
gives each request a fresh page in list order, aligned to
`max(page, align)`. The program-header count is computed by the same function
`build` uses, so the reservation cannot disagree with the output. The caller
then binds its code at the returned addresses and calls `build`, which never
moves anything. Callers that choose addresses themselves (the tests do) skip
`place` entirely.

**File layout** produced by `build`:

1. The ELF header at 0, with the program-header table directly after it
   (`e_phoff = e_ehsize`).
2. Mapped headers, which add a read-only `PT_LOAD` covering file
   `[0, headers_size)` and a `PT_PHDR`, so startup code can find its own
   program headers in memory.
3. Each loadable segment in vaddr order, at the lowest offset ≥ the current end
   with `offset ≡ vaddr (mod p_align)`. `p_align = max(max_page_size, largest
   section alignment)`.
   - With page-aligned vaddrs this keeps every segment on its own file pages.
     No file page is mapped with two permission sets.
   - A pure zero-fill segment consumes no file bytes. Its `p_offset` is the
     largest congruent offset ≤ the current end, so it never points past EOF.
4. Non-loaded data: the attributes section, `.symtab` (word-aligned), `.strtab`,
   `.shstrtab`.
5. The section-header table, word-aligned.

**Program headers**, in this order:

1. `PT_PHDR` (mapped headers only; it must precede every `PT_LOAD`).
2. All `PT_LOAD`s, sorted by vaddr. This includes the header load.
3. `PT_GNU_STACK`, when requested; the Linux profile requests RW, non-exec.
4. The target's attribute segment (`PT_RISCV_ATTRIBUTES`, flags R, vaddr 0).

**Sections** (only when `section_headers` is true):

- The null section.
- One `SHT_PROGBITS`/`SHT_NOBITS` section per spec section.
  - `SHF_ALLOC`, plus `SHF_WRITE`/`SHF_EXECINSTR` from the segment perms.
  - A NOBITS section's `sh_offset` is where it would be in the file.
- The attributes section, `.symtab`, `.strtab` and `.shstrtab`.
- `.symtab`: locals first, `sh_info` = first non-local index,
  `sh_link` = `.strtab`. Symbol types come from the caller. Export addresses
  alone do not make a symbol `STT_FUNC`; an adapter without richer metadata
  emits `STT_NOTYPE`.
- More than `SHN_LORESERVE` sections uses extended numbering in the header.
  A symbol whose section index needs `SHT_SYMTAB_SHNDX` is reported as
  unsupported in the builder, though the decoder handles it.

**Header:** `ET_EXEC`, the target's machine and flags, `EV_CURRENT`, and
`e_entry` from the spec.

**Errors:** `Exec.error` includes `Encode.error` and `Attributes.error`, plus
builder constructors whose payloads name the offending section by name and
address. Examples: `` `Section_misaligned ``, `` `Segments_share_page ``,
`` `Range_exceeds_class ``, `` `Entry_not_executable ``.

## 7. Execution profiles

The format records allow distinct `vaddr`/`paddr`; the profile decides what
they mean, along with the startup code. The same payload can serve both
profiles, but placement, startup and termination differ. A Linux `ecall`
sequence does not become bare-metal output or termination.

| Concern | Linux user mode | Bare-metal system mode |
| --- | --- | --- |
| Placement | Process virtual address space; `paddr = vaddr` | The machine's RAM, avoiding firmware/device ranges; `paddr` is the load address |
| Entry | `e_entry` = startup routine | Reset routine, or the ELF entry set by QEMU's loader |
| Stack | Provided by the kernel | Set up by startup code |
| Zero-fill | Kernel (`memsz > filesz`) | QEMU's ELF loader zeroes `memsz − filesz`, verified per route |
| Termination | `exit` syscall | Machine-specific (below) |

**Linux user mode**, the exit sequence used by the test payloads:

| Arch | Exit |
| --- | --- |
| RV32/RV64 | `a7 = 93`, `a0 = status`, `ecall` |
| AArch64 | `x8 = 93`, `x0 = status`, `svc #0` |
| ARM (EABI) | `r7 = 1`, `r0 = status`, `svc #0` |
| x86-32 | `eax = 1`, `ebx = status`, `int $0x80` |
| x86-64 | `eax = 60`, `edi = status`, `syscall` |

**System mode** (one hart/CPU each; to be validated before it is relied on):

| Arch | Machine | Load route | RAM base | Termination |
| --- | --- | --- | --- | --- |
| RV32 / RV64 | `virt`, `-bios none` | `-device loader,file=…,cpu-num=0` (sets PC to `e_entry`) | `0x8000_0000` | SiFive test device at `0x10_0000`: `0x5555` pass, `(code << 16) \| 0x3333` fail |
| AArch64 | `virt`, `-cpu cortex-a53` | `-kernel` ELF, or the generic loader | `0x4000_0000` | Semihosting `SYS_EXIT` (`-semihosting`) |
| ARM32 | `virt` | as AArch64 | `0x4000_0000` | Semihosting `SYS_EXIT` |
| x86-32 | `pc` | `-kernel` with a Multiboot header in the first 8 KiB (QEMU's Multiboot loader accepts ELF32) | ≥ 1 MiB | `isa-debug-exit` (`iobase=0xf4`): exit status `(v << 1) \| 1` |
| x86-64 | `pc` | An ELF32 Multiboot container (`EM_386`) with a 32-bit entry stub that enables long mode and jumps to the 64-bit payload (decided, Q3; QEMU's Multiboot loader rejects ELF64) | ≥ 1 MiB | `isa-debug-exit` |

The startup contract per profile is part of the profile's documentation. It
covers privilege mode, stack setup, trap handling (at minimum, a trap reports
a failure code rather than hanging), and which registers it may assume. The
generic loader supplies no Linux, OpenSBI or device-tree arguments, so startup
must not depend on them.

**RISC-V `virt` startup contract** (validated by `test/gnu/run_system.ml`):

- Command: `qemu-system-riscv32 -M virt -smp 1 -m 128M -bios none -nographic -monitor none
  -serial none -device loader,file=FILE,cpu-num=0`. The loader places each `PT_LOAD` at its `paddr`
  and sets the PC to `e_entry`.
- The core starts in M-mode at `e_entry`, with no firmware and no device tree. Startup must not
  rely on `a0`/`a1`, or on any register.
- RAM is `[0x8000_0000, +128 MiB)`; `Exec.riscv_virt_ram` is that window, and `Exec.validate
  ~ram` rejects a segment or mapped headers outside it (`` `Outside_ram ``). With no MMU,
  `paddr = vaddr`.
- Startup sets `sp` to the top of a stack reserved in a read/write zero-fill segment (16-byte
  aligned) and `mtvec` to a trap stub (direct mode, 4-aligned). The stub reports failure code
  `0x7f`, so a stray trap fails instead of hanging.
- Termination is the SiFive test device at `0x10_0000`: writing `0x5555` exits QEMU with status 0,
  and `(code << 16) | 0x3333` exits with status `code`.
- Zero fill: QEMU's loader supplies `memsz - filesz` zero bytes. Checks 13–16 and the dirty
  zero-fill control confirm it, so startup does not clear `.bss`.

**AArch64 and ARM `virt` startup contract** (validated by `test/gnu/run_system.ml`):

- Commands: `qemu-system-aarch64 -M virt -cpu cortex-a53 -nographic -semihosting -kernel FILE` and
  `qemu-system-arm -M virt -cpu cortex-a15 ...`. QEMU's loader places each `PT_LOAD` at its `paddr`
  and enters at `e_entry`; RAM starts at `0x4000_0000` and QEMU's boot stub uses its first bytes,
  so the tests load at `0x4010_0000` (`Exec.arm_virt_ram` is the window).
- Entry state, measured: AArch64 starts at **EL1** (`CurrentEL` = 1), and ARM in **SVC mode**
  (`CPSR.M` = `0x13`); no MMU, no stack, no vectors, interrupts masked.
- Startup sets `sp` immediately after the first instruction (which reads the entry address) and
  installs a vector table: `VBAR_EL1` (2 KiB aligned, at `text + 0x800`) or `VBAR` (32-byte aligned,
  at `text + 0x400`). Every vector reports failure code `0x7f`. ARM's handler first reloads `sp`,
  because an exception runs in a mode whose banked `sp` is unset.
- Termination is semihosting (`-semihosting`): AArch64 `SYS_EXIT` (`x0 = 0x18`, `x1` → `{0x20026,
  code}`) via `hlt #0xf000`; ARM `SYS_EXIT_EXTENDED` (`r0 = 0x20`, `r1` → `{0x20026, code}`) via
  `svc 0x123456`. QEMU exits with `code`: 0 for pass, the failing check's code otherwise.

**x86-32 `pc` startup contract**:

- Command: `qemu-system-i386 -M pc -m 128 -kernel FILE -nographic -serial none -monitor none
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 -no-reboot`. QEMU's Multiboot loader accepts an
  ELF32 whose header (`0x1BADB002`, flags 0, checksum) lies in the first 8 KiB of the file; the
  tests give it its own read-only `.mbhdr` segment one page after the mapped headers. With flags 0
  the loader uses the ELF program headers, loads at `paddr` and enters at `e_entry`.
- Entry state (Multiboot): 32-bit protected mode, paging off, flat segments, interrupts off, `esp`
  undefined. Startup sets `esp` first (so `call`/`pop` can read the PC), then builds a 32-gate IDT
  in a read/write `.idt` section whose gates all name a trap stub at `text + 0x40`; the stub reports
  `0x7f`.
- Termination: `isa-debug-exit` at port `0xf4`. Writing `v` makes QEMU exit with `(v << 1) | 1`; a
  passing payload writes 21 (status 43) and a failing one the check code.
- RAM is `[1 MiB, +127 MiB)` (`Exec.x86_pc_ram`).

**x86-64 `pc` startup contract** (Q3, option A; validated by `test/gnu/run_system.ml`):

- QEMU's Multiboot loader rejects ELF64 ("Cannot load x86-64 image, give a 32bit one"), so the
  payload is wrapped in an ELF32 container with the x86-32 profile. The container's own entry is a
  32-bit stub; the 64-bit code is an ordinary section of that file. The library's ELF64 output is
  covered by user mode; system mode covers the 64-bit code and the switch.
- The stub (entered as for x86-32) sets `esp`, builds identity page tables for the low 1 GiB with
  2 MiB pages in a 4 KiB-aligned `.pt` section (PML4, PDPT, PD), loads a three-entry GDT
  (null, 64-bit code `0x08`, data `0x10`), sets `CR4.PAE`, `CR3`, `EFER.LME` and `CR0.PG`, and jumps
  through selector `0x08`. The container must therefore load below 1 GiB.
- The 64-bit code reloads the data segments and `rsp`, builds a 32-gate 64-bit IDT (`lidt`) whose
  gates all name a trap stub reporting `0x7f`, and terminates through `isa-debug-exit` as in x86-32.
- Inside `.text.main` the offsets are fixed with `.org`: `0x000` stub, `0x200` GDT, `0x220` its
  pointer, `0x300` trap stub, `0x400` the 64-bit code, so every address is an absolute constant.

**Environment note.** The current devcontainer has all six user-mode QEMUs and
`qemu-system-{aarch64,arm,i386,x86_64}`, but **no `qemu-system-riscv32/64`**,
because Debian ships those in `qemu-system-riscv`, which is not installed. The
standalone devcontainer installs `qemu-system-riscv`. Until then, RV32 system
mode (milestone 3) cannot be executed here.

## 8. Requirements traced to the ELF and psABI specifications

- `p_filesz ≤ p_memsz`; the excess is zero-filled.
- `PT_LOAD` entries are ascending by `p_vaddr`.
- `p_offset ≡ p_vaddr (mod p_align)`, and `p_align` is a power of two.
- `PT_PHDR` precedes every loadable entry and is covered by a `PT_LOAD`.
- RISC-V: float-ABI and RVC/RVE/TSO bits as in §6.5; `.riscv.attributes`
  (`SHT_RISCV_ATTRIBUTES = 0x70000003`) and `PT_RISCV_ATTRIBUTES`.
  - For future `ET_REL`: `SHT_RELA` only, and `R_RISCV_PCREL_LO12_*` must
    reference the *HI instruction's* anchor label, not the target symbol.
  - Relaxation records (`R_RISCV_RELAX`/`ALIGN`) need an explicit policy before
    they are ever emitted.

References:
[gABI program loading](https://gabi.xinuos.com/elf/07-pheader.html),
[RISC-V ELF psABI](https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/master/riscv-elf.adoc),
[QEMU RISC-V virt](https://www.qemu.org/docs/master/system/riscv/virt.html),
[QEMU generic loader](https://www.qemu.org/docs/master/system/generic-loader.html).

## 9. Verification

The library parsing its own output is never sufficient on its own. Acceptance
requires external `readelf` checks and QEMU execution.

### 9.1 Unit tests (`test/unit`, no toolchain)

- `U64`: wrap at every boundary (`0xffff_ffff_ffff_ffff + 1`, `mul` overflow,
  `align_up` near the top).
- Codec round trip for every record × class × byte order, with fields chosen so
  that a swapped ELF32/ELF64 field order is detected.
- Encoder rejections: ELF32 address `0x1_0000_0000`, ELF32 relocation type 256,
  addend 2^31, negative count.
- Builder validation: one test per error constructor, and an `Accum` test
  checking that several problems are reported together.
- Address boundaries:
  - ELF32 segments at `0x8000_0000` and ending exactly at `0xffff_f000 + 0x1000`
    (accepted).
  - One byte further (rejected).

### 9.2 Malformed-input corpus (`test/unit`, `test/cram`)

Mutations of generated and GNU-produced files, one per decoder constructor:

- Truncation at every header boundary.
- Bad magic, class or data encoding.
- `e_shoff`/`e_phoff` past EOF; `offset + size` overflow.
- A wrong `e_shentsize`.
- An `e_shstrndx` or `sh_link` out of range or pointing to the wrong type.
- An unterminated string table.
- Inconsistent extended numbering.
- A note whose length exceeds the section.

Each must produce its specific constructor, never an exception. A fuzz loop
(random byte flips over the corpus) asserts "returns `Ok`/`Error`, never
raises".

### 9.3 Generated executables under GNU tools and QEMU (`test/gnu`)

**Payload source.** GAS supplies instruction bytes only; the executable is
built entirely by `Exec`. An OCaml test spec fixes all addresses, initial data,
zero-fill extents, permissions and the expected exit status. The generator
emits per-architecture assembly that references other regions only through
**absolute constants from the spec** (`li`, `movz/movk`, `movw/movt`,
`movabs`), so each region assembles relocation-free.

The test then parses the GAS object with `Decode`, asserts that no REL/RELA
section applies to the payload sections, and extracts their bytes. This also
exercises the decoder on GNU-produced input. If a later payload needs
relocations, it is linked with `ld --oformat=binary` and a script that selects
exactly the payload sections; GNU never produces a reference *executable* for
the primary test.

RISC-V payloads use `.option norelax` and no `.align` in code, so no
`R_RISCV_RELAX`/`ALIGN` records appear.

**Layout under test** (`B` = base, 64 KiB-aligned so the same spec works with a
4 KiB or 64 KiB page):

| Region | Address | Perms | Content |
| --- | --- | --- | --- |
| headers | `B` | R | mapped ELF + program headers |
| `.text` | `B + 0x10000` | RX | main payload, `e_entry` |
| `.text.aux` | `B + 0x20000` | RX | second code segment: returns a marker |
| `.rodata` | `B + 0x30000` | R | marker word |
| `.data` + `.bss.data` | `B + 0x40000` | RW | 0x100 initialized bytes (marker first), then 0x3000 zero-fill in the same segment |
| `.bss` | `B + 0x50000` | RW | pure `SHT_NOBITS`, 0x2000 bytes |

Variants:

- Low base `0x40_0000`.
- High base `0x9000_0000` for the 32-bit targets, which exceeds a 31-bit `int`
  and exercises §3.2 end to end.
- `0x1_2000_0000` for the 64-bit targets.

The mixed RW segment is the last loaded segment in the file, so the bytes
following its `filesz` on the same file page are symbol/string tables. The
zero-fill check therefore really verifies that the loader zeroed them.

**Payload checks.** On failure the program exits with that check's code; on
success it exits with 42.

| Code | Check |
| --- | --- |
| 10 | Execution address: a PC-relative read of `_start` (`auipc`, `adr`, `call/pop`, `lea (%rip)`, `mov rX, pc`) equals the spec address |
| 11 | `.rodata` marker |
| 12 | `.data` marker |
| 13 / 14 | First / last word of the mixed segment's zero-fill is 0 |
| 15 / 16 | First / last word of the pure `.bss` is 0 |
| 17 | A store to `.bss` reads back |
| 18 | A call into `.text.aux` returns its marker |

A plain successful exit from a fall-through program would prove little, which
is why each check has its own code.

**Structural checks** on the OCaml-produced file:

- `readelf -W -h -l -S -s -A` output is parsed, and the decoded fields are
  compared with the **spec**, never with values read back from the candidate.
  The fields are class, machine, flags, entry, every `LOAD`'s
  vaddr/memsz/flags/alignment, `GNU_STACK` = RW, section names and types,
  symbol names and types, and RISC-V `Tag_RISCV_arch`/`stack_align`.
- `readelf --lint` (`-L`, available in binutils 2.44): stderr must be empty.
- `<triple>-objdump -d` on `.text`, comparing the instruction sequence with the
  GAS listing of the same source.
- For sectionless variants, the code segment is extracted and disassembled
  with `objdump -b binary -m <arch>`.

**Execution.** `qemu-<arch> ./file` must exit with 42.

Expected values come from the spec, and the readelf parse is independent of
`Decode`. As a secondary check, `Decode` also reads the file back and its view
is compared with the spec.

### 9.4 Differential and fixture checks (optional, not on the critical path)

- RISC-V attributes: for every named `Riscv` profile, assemble an empty file
  with the matching `-march`/`-mabi`/`-misa-spec`. The decoded
  `.riscv.attributes` and `e_flags` must equal what the profile generates.
- GNU reference executables: link the same payload with `ld`, decode it, and
  check that `Decode` agrees with `readelf`. These files become parser fixtures,
  checked in with a provenance file (tool versions, flags, specification
  revisions), and tests that need no toolchain can run against them.
- Owee as an independent ELF64 parser cross-check, if it becomes convenient to
  install.

### 9.5 Determinism

Every backend (native, bytecode, js_of_ocaml, Melange) must produce
byte-identical executables for the same spec. This is checked by hashing the
outputs of a fixed spec set.

## 10. Repository, devcontainer and CI

The project is laid out to become `github.com/TheCBaH/ocaml-elf`. That name is
a placeholder; it collides with gazagnaire's `ocaml-elf`, so the final name is
an open question.

**Devcontainer** (`elf/.devcontainer/`):

- Debian base image plus the `ghcr.io/thecbah/ocaml-features/ocaml:1` feature
  with `ocamlformat#0.28.1`, `js_of_ocaml-compiler`, and `melange` (optional,
  4.14 only).
- err_trace pinned from GitHub (§4). The pin is installed at image build time
  if the feature accepts a pin, and in `postCreateCommand` otherwise, so CI and
  local containers use the same commit.
- Cross **binutils only**, no cross GCC: `binutils-{i686,x86-64,arm,aarch64,riscv64}-linux-gnu*`.
  RV32 uses `riscv64-linux-gnu-as -march=rv32…` and `ld -m elf32lriscv`, so the
  separate RV32 toolchain this repository installs is unnecessary.
- `qemu-user`, `qemu-system-arm`, `qemu-system-x86`, and `qemu-system-riscv` (for
  RISC-V).

**CI** (`elf/.github/workflows/ci.yml`):

- Uses `TheCBaH/devcontainer-action/devcontainer@v1`, the same action this
  repository uses.
- Matrix: OCaml 4.14.3 and 5.x on `linux/amd64` and `linux/arm64`, plus 4.14 on
  `linux/i386` and `linux/arm/v7`. The 32-bit legs are the ones that prove
  §3.2.
- Steps: `make fmt-check`, `make build`, `make test` (unit + cram; no
  toolchain), `make test-gnu` (GAS + readelf + QEMU user), `make test-system`
  (QEMU system), `make test-js`.
- Toolchain/QEMU steps are separate targets, so a leg without them still runs
  the portable suite.

**While `elf/` lives here:** it is its own dune project. It is not part of the
`asm/` workspace, so `asm`'s purity and layer audits never see it. CI runs it
through a root workflow that calls `make -C elf ci` in this repository's
devcontainer. Extraction later is a `git subtree split`: `elf/` has no
submodules and nothing outside it to carry along.

## 11. Milestones

Each milestone is accepted only with the external checks in §9.

1. **Codecs and decoder.**
   - `U64`, `Types`, `Const`, `Codec`, `Encode`, `Decode`, `Strtab`,
     `Attributes`, `elf.unix`, and `elf-inspect`.
   - Unit tests and the malformed-input corpus.
   - Decoding of the GAS objects used by the later milestones.
2. **RV32 static `ET_EXEC`, Linux user mode.**
   - `Target`, `Riscv`, `Exec` (`place` + `build`).
   - The full §9.3 matrix for RV32: low and high base, with and without
     sections, `ilp32` and `ilp32d` flags.
   - readelf/lint/objdump checks and `qemu-riscv32`.
3. **RV32 `virt` system mode.**
   - Startup contract, SiFive-test termination, and generic-loader route.
   - Requires `qemu-system-riscv` (§7).
4. **The other five architectures.**
   - User mode first, using the §9.3 matrix with each architecture's payload
     generator.
   - Then system mode as validated in §7, with x86-64's route decided first.
5. **Parser breadth.**
   - GNU-produced fixtures (objects, static and dynamic executables, shared
     objects) with provenance.
   - Notes, `SHT_GROUP`, and extended-numbering fixtures.
   - The fuzz loop.
6. **`ET_REL` generation**, when interoperability with external linkers is
   needed.
   - Input is the assembler's *lowered* module (symbolic sections + fixups),
     not a bound image.
   - REL/RELA per target, with the RISC-V HI/LO anchor rule (§8).
7. **Assembler adapter**, on the consumer side: assembler `plan_image` →
   `Exec.place` → `bind_image` → `Exec.build`, plus a QEMU run of
   assembler-produced code.

Dynamic linking, shared libraries and linker relaxation remain separate
features. Their record types stay representable (the decoder reads
`PT_DYNAMIC`, `SHT_DYNSYM`, etc.) without the builder claiming to produce them.

## 12. Open questions

1. **Project/package name.** `elf` is short but generic, and `ocaml-elf` is
   taken on GitHub.
2. **err_trace version pinning.** Pin the `v0.0.1` tag, as now, or track
   `main` until err_trace's API settles.
3. **x86-64 system-mode route** (§7): *decided*: an ELF32 Multiboot container with a
   long-mode trampoline.
4. **Canonical RISC-V ISA strings:** whether to implement the implied-extension
   expansion (`m → zmmul`, `a → zaamo + zalrsc`, `f → zicsr`, …) or keep
   profiles explicit as proposed.
5. **AArch64 page size:** 64 KiB (portable to 64K-page kernels, larger files)
   or 4 KiB.
6. **Big-endian generation:** in scope for any target, or decode-only.
