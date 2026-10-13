# `elf`: implementation plan

This is the detailed implementation plan for the design in
[design.md](design.md). Section numbers (§) refer to `design.md`. Status lives
in [tracker.md](tracker.md); task IDs are shared between the two files.

Each task gives:

- **Files**: what it creates or changes.
- **Interface**: the signatures it fixes.
- **Steps**: the order of work.
- **Tests**: the cases that must exist.
- **Done when**: the acceptance check.

Tasks marked *(toolchain)* need cross binutils or QEMU. They run under
`make test-gnu` / `make test-system`, never under `make test`.

---

## 0. Conventions (apply to every task)

### 0.1 Definition of done

A task is done only when all of these hold:

1. `make ci` passes (fmt-check, build, unit + cram tests). *(toolchain)* tasks
   also need `make test-gnu` (and `make test-system` where relevant) to pass.
2. Every new public module has an `.mli` with doc comments. Internal modules
   are listed in the library's `(private_modules ...)`.
3. Every new error constructor has a test that reaches it and a `pp_error` case.
4. `tracker.md` is updated in the same commit: status, notes, and a log line.
5. One commit per task (or per tightly coupled pair). Commit messages follow
   the repository rules: a short summary line, and no references to untracked
   files.

### 0.2 Code conventions

- **Error domains** (§4):
  - One closed `type error = [ ... ]` and one
    `pp_error : Format.formatter -> error -> unit` per module.
  - Constructor payloads with more than one field are named records declared
    next to `error`.
  - Every `Err.fail`, `Err.guard`, `Err.of_option`, `Err.map_error` and
    `Err.protect` passes `~pos:__POS__ ~pp_error`.
  - Widen with a local `let lift r = (r :> (_, error) Err.t)`, not with
    `Err.map_error`.
- **Integers**:
  - Never `Int64.to_int` on file-derived values except through
    `Decode.extent`/`U64.to_int`.
  - Never compare `int64` with polymorphic `<`; use `U64.lt`/`U64.le` or
    `Int64.equal`.
- **No exceptions across the public API.** Internal invariant violations use
  `assert false` with a comment that explains why the case is unreachable.
- **No `Unix`, `Str`, `Bigarray`, `Obj` or `Printf` to stdout in `src/`.**
  `Format` is fine.
- Formatting comes from `dune build @fmt` with the pinned ocamlformat 0.28.1.

### 0.3 Test conventions

- **Unit tests** are plain executables (`(test ...)` stanzas) using a tiny
  in-tree harness, `test/support/check.ml`. There is no PPX, so the suite also
  runs under js_of_ocaml.
- **Every test executable** starts with
  `Err.Config.set Err.Config.deterministic`, so rendered errors are identical
  on every backend.
- **Cram tests** (`test/cram/*.t`) pin `elf-inspect` output and rendered
  errors.
- **Toolchain tests** live in `test/gnu/` and are attached to aliases
  `@test-gnu` / `@test-system`, never `@runtest`.
  - A missing tool prints `SKIP <tool>` and exits 0.
  - With `ELF_REQUIRE_TOOLCHAIN=1` (set by CI) a missing tool fails instead.

### 0.4 Source tree after M2

```
elf/
  Makefile  dune-project  elf.opam  elf.opam.template  .ocamlformat
  README.md  LICENSE  CHANGES.md
  .devcontainer/{devcontainer.json,Dockerfile}
  .github/workflows/ci.yml
  docs/{design,plan,tracker}.md
  src/        dune  u64 types const names codec encode decode strtab
              attributes target riscv arm exec   (.ml + .mli)
  unix/       dune  elf_unix.ml{,i}
  bin/        dune  elf_inspect.ml
  test/support/  dune  check.ml{,i}  fixture.ml{,i}   (library elf_test_support)
  test/unit/     dune  test_u64.ml test_codec.ml test_encode.ml test_decode.ml
                 test_strtab.ml test_attributes.ml test_target.ml test_exec.ml
                 test_malformed.ml
  test/cram/     dune  inspect.t/  errors.t/
  test/gnu/      dune  toolchain.ml readelf.ml spec.ml payload_*.ml
                 test_objects.ml test_isa.ml run_user.ml run_system.ml
```

---

## M0. Project infrastructure

### M0.1 dune project and opam metadata

- **Files:** `dune-project`, `elf.opam` (generated), `elf.opam.template`.
- **Steps:**
  1. Set dune lang 3.15, `generate_opam_files`, and a package `elf` with depends
     `ocaml >= 4.14`, `dune >= 3.15`, `err_trace = dev`.
  2. Add `pin-depends` on `git+https://github.com/TheCBaH/err_trace.git#v0.0.1`
     through the template.
- **Done when:** `opam install . --deps-only --with-test -y` resolves from a
  switch without err_trace, and `dune build` succeeds.

### M0.2 Formatting

- **Files:** `.ocamlformat` (`version = 0.28.1`, `profile = conventional`,
  `margin = 100`, `parse-docstrings = false`).
- **Done when:** `dune build @fmt` is clean over the whole tree.

### M0.3 Makefile

- **Files:** `Makefile`.
- **Targets:**

  | Target | Command |
  | --- | --- |
  | `deps` | `opam install . --deps-only --with-test -y` |
  | `build` | `opam exec -- dune build @all` |
  | `test` | `opam exec -- dune build @runtest` |
  | `test-gnu` | `opam exec -- dune build @test-gnu` |
  | `test-system` | `opam exec -- dune build @test-system` |
  | `test-js` | `opam exec -- dune build @test-js` (js_of_ocaml unit tests under node) |
  | `fmt` | `opam exec -- dune build @fmt --auto-promote` |
  | `fmt-check` | `opam exec -- dune build @fmt` |
  | `ci` | `fmt-check build test` |
  | `clean` | `opam exec -- dune clean` |

- **Done when:** every target runs. The toolchain targets succeed with "SKIP"
  output when no tools are present.

### M0.4 Repository files

- **Files:** `README.md`, `LICENSE` (pending Q8), `CHANGES.md`.
- **README** covers scope and non-goals (§1), install including the err_trace
  pin, a 20-line example (build an RV32 executable from a spec, write it with
  `Elf_unix`), the test targets, and links to the docs.
- **Done when:** the README example is compiled as a test
  (`test/unit/test_readme.ml` mirrors it verbatim).

### M0.5 Devcontainer

- **Files:** `.devcontainer/devcontainer.json`, `.devcontainer/Dockerfile`.
- **Dockerfile** (Debian 13), apt packages:
  - `binutils-i686-linux-gnu binutils-x86-64-linux-gnu binutils-arm-linux-gnueabihf binutils-aarch64-linux-gnu binutils-riscv64-linux-gnu`
  - `qemu-user qemu-system-arm qemu-system-x86 qemu-system-riscv`
  - `nodejs make git ca-certificates curl`
  - Cross packages are installed only where the host architecture provides
    them. The toolchain targets skip what is absent.
- **devcontainer.json:**
  - Features: `common-utils`, and `ghcr.io/thecbah/ocaml-features/ocaml:1`
    with `version: ${localEnv:OCAML_VERSION}` and
    `packages: "ocamlformat#0.28.1 js_of_ocaml-compiler"`, plus
    `optional-packages: "melange"`.
  - `postCreateCommand`: `make deps`.
- **Done when:** the container builds on amd64, and inside it `make ci` and
  `make test-gnu` pass and `qemu-system-riscv32 --version` works.

### M0.6 GitHub Actions

- **Files:** `.github/workflows/ci.yml`.
- **Jobs:**
  1. `matrix`: an inline JSON list. OCaml `4.14.3` and `5.4.1` on
     `ubuntu-24.04` (linux/amd64) and `ubuntu-24.04-arm` (linux/arm64), plus
     `4.14.3` on `linux/i386` and `linux/arm/v7`.
  2. `ci`, per leg:
     - checkout, then `TheCBaH/devcontainer-action/devcontainer@v1` with
       `variant`/`platform`;
     - steps `make fmt-check`, `make build`, `make test`, then
       `make test-js` (64-bit legs);
     - then `ELF_REQUIRE_TOOLCHAIN=1 make test-gnu test-system` (amd64 and
       arm64 legs).
- **Done when:** `actionlint` is clean. The workflow runs green after
  extraction; until then, M0.7 provides CI.

### M0.7 Host-repository integration

- **Files:**
  - root `.github/workflows/elf.yml`: the same steps, using this repository's
    devcontainer and `make -C elf deps ci test-gnu`;
  - a root `CLAUDE.md` section describing `elf/` as a third independent
    project;
  - optionally root `Makefile` pass-throughs `elf-ci`, `elf-test-gnu`.
- **Done when:** the root workflow is green, and `make asm-ci` is unchanged
  because `elf/` is outside the `asm/` dune workspace.

### M0.8 Test skeleton

- **Files:** `test/support/{dune,check.ml,check.mli}`, `test/unit/dune`,
  `test/cram/dune`, `bin/{dune,elf_inspect.ml}` (stub printing a usage line).
- **`Check` interface:**

  ```ocaml
  val run : string -> (unit -> unit) list -> unit            (* suite name, cases; exit 1 on any failure *)
  val case : string -> (unit -> unit) -> unit -> unit
  val equal : pp:(Format.formatter -> 'a -> unit) -> ?eq:('a -> 'a -> bool) -> string -> 'a -> 'a -> unit
  val ok : pp_error:(Format.formatter -> 'e -> unit) -> string -> ('a, 'e) Err.t -> 'a
  val error : pp:(Format.formatter -> 'a -> unit) -> string -> ('e -> bool) -> ('a, 'e) Err.t -> unit
  val bytes_equal : string -> string -> string -> unit        (* hex diff of first mismatch *)
  ```

- **`@test-js` alias:** builds `test/unit/*.bc.js` with `(modes js)` and runs
  each under `node`.
- **Done when:** one trivial unit case and one cram case pass under
  `make test`, and the same unit case passes under `make test-js`.

---

## M1. Codecs and decoder

### M1.1 `U64`

- **Files:** `src/u64.ml{,i}`, `test/unit/test_u64.ml`.
- **Interface** (§3.2): `compare lt le max add sub mul fits_bits is_pow2
  align_up align_down is_aligned rem to_int of_int pp`.
- **Tests:**
  - `add (-1L) 1L = None`; `add 0xffff_ffffL 1L = Some 0x1_0000_0000L`.
  - `sub 0L 1L = None`.
  - `mul 0x1_0000_0000L 0x1_0000_0000L = None`; `mul 0L x = Some 0L`.
  - `lt 0x7fff_ffff_ffff_ffffL 0x8000_0000_0000_0000L` (unsigned).
  - `align_up (-1L) 4096L = None`; `align_up 0x1001L 0x1000L = Some 0x2000L`.
  - `fits_bits 32 0xffff_ffffL`; `not (fits_bits 32 0x1_0000_0000L)`.
  - `to_int (-1L) = None`; `to_int (Int64.of_int max_int) = Some max_int`.

### M1.2 `Types`, `Const`, `Names`

- **Files:** `src/types.ml{,i}`, `src/const.ml{,i}`, `src/names.ml{,i}`.
- **`Names` interface:** `et em pt sht stb stt shn : int(64) -> string option`,
  and `pp_pt`, `pp_sht`, … that print a known name or `0x…`. `pp_pf`/`pp_shf`
  print flag sets as `R W X` / `WAX` (readelf letters) plus residual hex.
- **Tests:** every constant in `Const` has a name; an unknown `p_type`
  `0x6fff_0000L` prints as hex; `pp_shf 0x8000_0006L` prints `AX` plus the
  residual.

### M1.3 `Codec`

- **Files:** `src/codec.ml` (private), `test/unit/test_codec.ml`.
- **Contents:** record sizes per class; scalar get/set for both byte orders;
  `read_*`/`write_*` for header, phdr, shdr, sym, rel/rela (§6.1).
- **Tests:**
  - For each record × {Elf32, Elf64} × {Little, Big}: write a value whose
    fields are pairwise distinct (e.g. `0x11…`, `0x22…`), read it back, and
    compare.
  - A golden hex for one ELF32-LE phdr and one ELF64-BE sym, written out by
    hand from the gABI field tables, to pin field *order* independently of
    the reader.
  - `r_info` packing: ELF32 sym `0xabcdef`/type `0x12` ↔ `0xabcdef12`; ELF64
    sym `0x1234`/type `0x5678_9abc` ↔ `0x0000_1234_5678_9abc`.
  - ELF32 RELA addend `-4` reads back as `-4L`.

### M1.4 `Encode`

- **Files:** `src/encode.ml{,i}`, `test/unit/test_encode.ml`.
- **Interface** (§6.2): `write_header`, `write_phdr`, `write_shdr`,
  `write_sym`, `write_rel`. All return `(unit, error) Err.t`, where
  `error = [ `Field_overflow of overflow ]`.
- **Tests:** each produces `` `Field_overflow `` with the right record, field
  and bits:
  - ELF32 `p_vaddr = 0x1_0000_0000`;
  - ELF32 `r_type = 256`;
  - ELF32 `r_sym = 0x100_0000`;
  - ELF32 addend `0x8000_0000` and `-0x8000_0001`;
  - `e_phnum = 0x10000`, `e_type = -1`, `osabi = 256`.
  - The ELF64 equivalents of the address and type cases are accepted.
  - The rendered message for one case is pinned in `test/cram/errors.t`.

### M1.5 `Decode` core

- **Files:** `src/decode.ml{,i}`.
- **Interface:** `type t = private {...}` and `of_string` (§6.3).
- **Algorithm:**
  1. `extent` the 16-byte ident; check magic, class, data, `EI_VERSION`.
  2. `extent` the class's header size; read the header.
  3. Section headers.
     - `e_shoff = 0` with `e_shnum ≠ 0` is `` `Section_headers_missing ``.
     - Otherwise check `e_shentsize`, read `shdr[0]`, resolve `shnum`
       (`e_shnum = 0` → `shdr[0].sh_size`), and `table`-check the whole array.
  4. `phnum`: `PN_XNUM` → `shdr[0].sh_info`. When `phnum > 0`, check
     `e_phentsize` and `table`-check the array.
  5. `shstrndx`: `SHN_XINDEX` → `shdr[0].sh_link`; range-check it.
  6. Name every section through `shstrndx`. A bad offset, or a string not
     terminated within the table, is an error.
- **Tests:** in M1.11. The positive tests here use `Fixture.minimal` from
  `test/support`, built with `Codec` writers directly, so they do not depend
  on `Exec`.
- **Extended numbering fixture:** `Fixture.many_sections 0xff10` produces
  `e_shnum = 0` and `e_shstrndx = SHN_XINDEX`. The test checks that
  `shnum = 0xff10` and that the names resolve.

### M1.6 `Decode` accessors

- **Interface:** `find_section`, `section_data`, `segment_data`, `string_at`,
  `symbols`, `relocations`, `notes`, `attributes` (the last after M1.8).
- **Rules:**
  - `expect_type` on every typed accessor.
  - `entries` checks a nonzero `sh_entsize`, and that `sh_size` is a whole
    number of entries.
  - `symbols` resolves `sh_link` (must be `SHT_STRTAB`) and the
    `SHT_SYMTAB_SHNDX` whose `sh_link` is this symtab.
  - `relocations` checks that `sh_link` is in range.
  - `notes` pads the name to 4 and the descriptor to 4, or to 8 when the alignment is 8.
- **Tests:** each accessor on a valid fixture, plus every error it can raise:
  - `` `Wrong_section_type ``: calling `symbols` on `.strtab`;
  - `` `Bad_entry_size ``: `sh_entsize` 20 on an ELF32 symtab;
  - `` `Bad_section_index ``: `sh_link` 999;
  - `` `Bad_section_index ``: `SHN_XINDEX` without a shndx table;
  - `` `Bad_note ``: `namesz` larger than the section.

### M1.7 `Strtab`

- **Files:** `src/strtab.ml{,i}`, `test/unit/test_strtab.ml`.
- **Interface:**

  ```ocaml
  type t
  type error = [ `Nul_in_name of string ]
  val create : unit -> t
  val add : t -> string -> (int64, error) Err.t     (* idempotent *)
  val contents : t -> string                        (* starts with "\000" *)
  ```

- **Tests:**
  - `add ""` returns 0.
  - Adding `"a"` twice returns the same offset.
  - Every offset decodes through `Decode.string_at` on a fixture that embeds
    `contents`.
  - `"a\000b"` is rejected.

### M1.8 `Attributes`

- **Files:** `src/attributes.ml{,i}`, `test/unit/test_attributes.ml`.
- **Interface** (§6.4): `value`, `scope`, `subsection`, `t`, `encode`,
  `decode`, `find : t -> vendor:string -> tag:int -> value option` (File
  scope), and `classify : vendor:string -> tag:int -> [`Uleb | `Ntbs | `Uleb_ntbs] option`.
- **Errors:**
  - `` `Bad_format_version of int ``;
  - `` `Truncated_subsection ``;
  - `` `Bad_subsection_length of { offset; length } ``;
  - `` `Uleb_overflow of int `` (offset);
  - `` `Unterminated_ntbs of int ``;
  - `` `Nul_in_value of string `` (encode);
  - `` `Unknown_scope of int ``.
- **Encoding:** `'A'`, then for each subsection the u32 length (self
  included), the vendor NTBS, then sub-subsections (ULEB scope tag; u32 length
  covering tag + length + body; index list terminated by 0 for the
  Section/Symbol scopes; attributes in input order).
- **Tests:**
  - Round trip with all three value kinds and scopes.
  - A hand-assembled RISC-V example byte-equal to GAS output, copied from a
    `readelf -x .riscv.attributes` dump and recorded with its provenance in a
    comment.
  - A ULEB with 10 continuation bytes is rejected.
  - An unknown vendor is kept `` `Raw `` byte-for-byte.

### M1.9 `elf.unix`

- **Files:** `unix/dune` (`(library (name elf_unix) (public_name elf.unix) (libraries elf unix err_trace))`), `unix/elf_unix.ml{,i}`.
- **Interface:**

  ```ocaml
  type io = { path : string; op : [ `Read | `Write | `Chmod ]; message : string }
  type error = [ `Io of io ]
  val read_file : string -> (string, error) Err.t
  val write_file : ?perm:int -> string -> string -> (unit, error) Err.t
  val write_executable : string -> string -> (unit, error) Err.t   (* write_file, then chmod 0o755 *)
  ```

  Exceptions (`Sys_error`, `Unix.Unix_error`) are converted with `Err.protect`.
- **Tests:** the write → read round trip; the executable bit is set; reading
  a missing file gives `` `Io { op = `Read } ``.

### M1.10 `elf-inspect`

- **Files:** `bin/elf_inspect.ml`, `bin/dune` (`public_name elf-inspect`),
  `test/cram/inspect.t/`.
- **CLI** (Stdlib `Arg`, no cmdliner):
  - `elf-inspect [--header] [--segments] [--sections] [--symbols] [--relocs] [--notes] [--attributes] [--all] FILE`.
  - Exit status 0 on success; 2 with `Err.Error.pp Decode.pp_error` on stderr
    for decode errors; 1 for I/O errors.
- **Output** is stable: one record per line, `key=value` fields, hex for
  addresses, names via `Names`. It is designed for diffing, not for looking
  like readelf.
- **Cram tests:** inputs are generated by a small test helper (`gen.exe`,
  using `Fixture`) inside the cram directory, so no binaries are checked in.

### M1.11 Malformed corpus (initial)

- **Files:** `test/support/fixture.ml` (mutators), `test/unit/test_malformed.ml`.
- **Mutators:**
  - `truncate n`;
  - `set_u8 off v`, `set_u16 off v`, `set_u32 off v`, `set_word off v` (class
    and byte order taken from the base);
  - `with_shdr i f` / `with_phdr i f`, which rewrite one record through
    `Codec`.
- **Cases:** one per `Decode.error` constructor, on ELF32-LE and ELF64-BE
  bases:
  - truncate at 3, 15, header-size − 1, and inside each table;
  - magic byte 0 = `0`;
  - class 3; data 3; `EI_VERSION` 2;
  - `e_shoff` = file length; `e_shoff = 0xffff_ffff_ffff_fff0` (overflow);
  - `e_shentsize` 41;
  - `e_shnum = 5` with `e_shoff = 0`;
  - `e_shstrndx` = `shnum`;
  - a `sh_name` past the table; the last byte of `.shstrtab` overwritten with
    `'x'`;
  - a symtab `sh_link` pointing at itself;
  - a note `descsz` of `0xffff_ffff`.
- **Invariant check:** every case also runs inside a wrapper that fails the
  test if any exception escapes.

### M1.12 GAS objects *(toolchain)*

- **Files:** `test/gnu/toolchain.ml`, `test/gnu/readelf.ml`,
  `test/gnu/test_objects.ml`, and `test/gnu/dune` (`@test-gnu` alias).
- **`Toolchain`:**

  ```ocaml
  type arch = Elf.Target.arch
  type tools = { as_ : string list; ld : string list; objdump : string; readelf : string;
                 qemu_user : string; qemu_system : string option }
  val find : arch -> (tools, [ `Missing of string ]) result
  val run : string list -> (int * string * string)   (* status, stdout, stderr via temp files + Sys.command *)
  ```

  Assembler command per arch:

  | Arch | Command |
  | --- | --- |
  | x86-32 | `i686-linux-gnu-as --32` |
  | x86-64 | `x86_64-linux-gnu-as --64` |
  | ARM | `arm-linux-gnueabihf-as -march=armv7-a` |
  | AArch64 | `aarch64-linux-gnu-as` |
  | RV32 | `riscv64-linux-gnu-as -march=rv32imafd -mabi=ilp32d` |
  | RV64 | `riscv64-linux-gnu-as -march=rv64imafd -mabi=lp64d` |

- **`Readelf`:** parsers for `-W` output of `-h` (key: value), `-l` (LOAD and
  other rows: type, offset, vaddr, paddr, filesz, memsz, flags, align), `-S`
  (index, name, type, addr, off, size, ES, flags, Lk, Inf, Al), `-s` (num,
  value, size, type, bind, vis, ndx, name), `-r` (offset, info, type, sym,
  addend) and `-A` (tag: value lines).
- **Test:** for each arch, a source with `.text` (one global and one local
  function), `.data` (a word that refers to a `.text` label, so it carries a
  relocation), `.bss` (`.zero 64`), and a call to an undefined external
  symbol. Assemble it, then:
  - check that `Decode` sections equal `readelf -S`;
  - check that symbols equal `-s`;
  - check that relocations equal `-r` (offset, type, symbol, addend);
  - for RV and ARM, check that `Decode.attributes` equals `-A`.

---

## M2. RV32 static `ET_EXEC`, Linux user mode

### M2.1 `Target`

- **Files:** `src/target.ml{,i}`, `test/unit/test_target.ml`.
- **Interface** (§6.5):

  ```ocaml
  type arch = X86_32 | X86_64 | Arm | Aarch64 | Riscv32 | Riscv64
  type attributes = { section_name : string; section_type : int64;
                      segment_type : int64 option; contents : Attributes.t }
  type t = private { arch : arch; elf_class : Types.elf_class; endianness : Types.endianness;
                     machine : int; flags : int64; osabi : int; max_page_size : int64;
                     attributes : attributes option }
  val x86_32 : t
  val x86_64 : t
  val aarch64 : ?page_size:int64 -> unit -> t
  val arm : Arm.abi -> t
  val riscv : Riscv.abi -> t
  val ident : t -> Types.ident
  val arch_of_string : string -> arch option
  val pp_arch : Format.formatter -> arch -> unit
  ```

  The record is `private`, so class and machine cannot be set independently.
  `riscv` derives the class from `abi.xlen`.
- **Tests:** the §6.5 table row by row.

### M2.2 `Riscv`

- **Files:** `src/riscv.ml{,i}`, `src/arm.ml{,i}` (flags only, for M4.1),
  test cases in `test/unit/test_target.ml`.
- **Interface:**

  ```ocaml
  type xlen = Rv32 | Rv64
  type float_abi = Soft | Single | Double | Quad
  type abi = { xlen : xlen; float_abi : float_abi; rvc : bool; rve : bool; tso : bool;
               arch : string; stack_align : int; unaligned_access : bool option }
  val flags : abi -> int64
  val attributes : abi -> Attributes.t
  val rv32imafd_ilp32d : abi
  val rv32im_ilp32 : abi
  val rv64imafd_lp64d : abi
  val rv64im_lp64 : abi
  ```

- **Tests:**
  - `flags` for all 4 × 2 × 2 × 2 combinations against a table written out
    from the psABI.
  - `attributes` for `rv32imafd_ilp32d` encodes `Tag_RISCV_stack_align = 16`
    and the profile's arch string.

### M2.3 ISA string *(toolchain)*

- **Files:** `Riscv.isa_string` in `src/riscv.ml`, and `test/gnu/test_isa.ml`.
- **Interface:**
  `isa_string : xlen -> base:[`I | `E] * (int * int) -> (string * (int * int)) list -> string`.
  - Canonical order: base, then single letters in `MAFDQLCBKJTPVH` order, then
    `z*` grouped by the category letter after `z` (in the same order), then
    alphabetically, then `s*`, then `x*`. Versions are written as `<major>p<minor>`.
- **Steps:** decide the profile strings per Q4 (explicit), for both ISA spec
  `2.2` and `20191213`. Record the spec revision in the profile's doc
  comment.
- **Test:** for each named profile, run `as -march=<march> -mabi=<abi> -misa-spec=<rev>`
  on an empty file. `Decode` its `.riscv.attributes` and `e_flags`, and
  require equality with `Riscv.attributes`/`Riscv.flags`.

### M2.4 `Exec` spec and validation

- **Files:** `src/exec.ml{,i}` (spec, validation), `test/unit/test_exec.ml`.
- **Interface:** the §6.6 types and
  `validate : spec -> (layout, error list) Err.t`. Here `layout` is the
  internal, validated, normalized form used by `build`: sorted segments,
  computed `filesz`/`memsz`/`p_align`, and resolved section indices.
- **Error constructors**, each with a named-record payload:

  | Constructor | Condition |
  | --- | --- |
  | `` `Bad_alignment `` | section align not a power of two |
  | `` `Bad_page_size `` | `max_page_size` not a power of two |
  | `` `Section_misaligned `` | `addr mod align ≠ 0` |
  | `` `Empty_segment `` | segment has no sections |
  | `` `Sections_overlap `` | sections in a segment out of order or overlapping |
  | `` `Data_after_zero_fill `` | `Bytes` after `Zero` in one segment |
  | `` `Range_exceeds_class `` | `vaddr + memsz` (or paddr range) > 2^32 for ELF32, or overflows 2^64 |
  | `` `Segments_share_page `` | two segments (or headers and a segment) touch the same page |
  | `` `Physical_overlap `` | paddr ranges overlap |
  | `` `Headers_misaligned `` | mapped header vaddr not page-aligned |
  | `` `Entry_not_executable `` | entry not inside the initialized part of an X segment |
  | `` `Duplicate_section `` | two sections with one name |
  | `` `Bad_name `` | NUL in a section or symbol name |
  | `` `Unknown_symbol_section `` | symbol names a section that does not exist |
  | `` `Symbols_without_sections `` | symbols given with `section_headers = false` |

  `Exec.error` also includes `Encode.error`, `Strtab.error` and
  `Attributes.error` by row inclusion.
- **Steps:**
  1. Validate each segment independently with `Err.Accum.map`.
  2. Then validate across segments (sorting, page sharing, physical overlap,
     entry).
  3. Then names and symbols.
  4. Collapse to `error list` with `Err.Accum.fold_errors`.
- **Tests:** one minimal spec per constructor; one spec with three
  independent problems that reports all three in input order; boundary specs:
  - ELF32 segment `[0xffff_f000, 0x1_0000_0000)`: accepted;
  - ELF32 segment `[0xffff_f000, 0x1_0000_0001)`: `` `Range_exceeds_class ``;
  - segments at `0x8000_0000` and `0x9000_0000`: accepted (high-address path).

### M2.5 `Exec.place`

- **Interface:**

  ```ocaml
  type request = { name : string; perms : perms; init_size : int64; zero_fill : int64; align : int64 }
  type shape = { mapped_headers : bool; gnu_stack : bool; segments : int }
  val phdr_count : Target.t -> shape -> int
  val headers_size : Target.t -> shape -> int64
  val place : Target.t -> mapped_headers:bool -> gnu_stack:bool -> base:int64 ->
              request list -> (headers * (string * int64) list, error) Err.t
  ```

- **`phdr_count`:**
  `segments + (if mapped then 2 else 0) + (if gnu_stack then 1 else 0) + (if target has an attribute segment type then 1 else 0)`.
  `build` calls the same function.
- **Algorithm:**
  1. `cursor = base`, which must be page-aligned.
  2. When headers are mapped, emit `Mapped { vaddr = base }`, then set
     `cursor = align_up (base + headers_size) page`.
  3. For each request: set
     `vaddr = align_up cursor (max page align)`, then
     `cursor = align_up (vaddr + init_size + zero_fill) page`.
  4. Check every step for overflow and class range.
- **Tests:**
  - A placed spec (with dummy bytes of the requested sizes) always passes
    `validate`.
  - `headers_size` equals `e_phoff + phnum × phentsize` in the built file.
  - A request with `align = 0x20000` on a 4 KiB page lands on a 128 KiB
    boundary.

### M2.6 `Exec.build`

- **Interface:** `build : spec -> (string, error) Err.t`.
- **Algorithm** (§6.6 file layout):
  1. `validate` → `layout`.
  2. `off = ehsize + phnum × phentsize`.
  3. For each loadable segment in vaddr order:
     - if `filesz > 0`: `p_offset` = the smallest value ≥ `off` with
       `p_offset ≡ vaddr (mod p_align)`, then `off = p_offset + filesz`;
     - otherwise `p_offset` = the largest congruent value ≤ `off`.
  4. Attributes payload: `Attributes.encode`, align 1, at `off`.
  5. With sections: build `.symtab` (locals first; `sh_info` = first
     non-local), `.strtab` and `.shstrtab` via `Strtab`, each placed at its
     alignment (symtab: word size). Then the section header table, aligned to
     the word size.
  6. Allocate `Bytes.make total '\000'` and write every record through
     `Encode`, every payload with `Bytes.blit_string`.
  7. Program-header order:
     - `PT_PHDR`;
     - `PT_LOAD`s sorted by vaddr (the header load included);
     - `PT_GNU_STACK` (offset 0, sizes 0, align 16, flags from the spec);
     - the attribute segment (vaddr/paddr 0, align 1, flags R).
  8. Extended numbering:
     - if `shnum ≥ 0xff00`: `e_shnum = 0` and `shdr[0].sh_size = shnum`;
     - if `shstrndx ≥ 0xff00`: `e_shstrndx = 0xffff` and
       `shdr[0].sh_link = shstrndx`;
     - if `phnum ≥ 0xffff`: `e_phnum = 0xffff` and `shdr[0].sh_info = phnum`.
     - A symbol whose `st_shndx` would need `SHT_SYMTAB_SHNDX` is reported as
       unsupported (`` `Unsupported_symbol_section_index ``).
- **Tests:** each test builds a file, decodes it with `Decode`, and checks:
  - `p_offset ≡ p_vaddr (mod p_align)` for every LOAD;
  - LOADs ascending; `PT_PHDR` first and inside the header LOAD;
  - a pure NOBITS segment has `p_filesz = 0` and `p_offset ≤ file length`;
  - section data equals the spec bytes; NOBITS sections have the right
    `sh_size`;
  - symtab locals come before globals and `sh_info` is correct;
  - the RISC-V attribute segment and section cover the same bytes;
  - `e_flags` and `e_entry` match the spec;
  - the extended-numbering path is exercised with 0xff10 tiny sections.

### M2.7 `test/gnu` harness *(toolchain)*

- **Files:** `test/gnu/spec.ml`, `test/gnu/payload.ml` (the generator
  interface), `test/gnu/run_user.ml`.
- **`Spec`:**

  ```ocaml
  type variant = { base : int64; sections : bool; abi : string }
  type t = { arch : Target.arch; target : Target.t; variant : variant;
             text : int64; aux : int64; rodata : int64; data : int64; bss : int64;
             data_init : int; data_zero : int64; bss_size : int64;
             markers : { rodata : int32; data : int32; aux : int32; store : int32 } }
  val make : Target.t -> variant -> t   (* addresses = base + 0x10000 × k, per design §9.3 *)
  val exec_spec : t -> text:string -> aux:string -> Exec.spec
  ```

  The rodata and data bytes come from `Spec` in the target byte order, not
  from GAS.
- **`Payload` interface:**

  ```ocaml
  module type S = sig
    val arch : Target.arch
    val source : Spec.t -> string   (* sections .text.main and .text.aux *)
  end
  ```

- **`run_user` flow:**
  1. Write the source and assemble it.
  2. `Decode` the object and assert that no `SHT_REL`/`SHT_RELA` section has
     `sh_info` pointing at a payload section.
  3. Extract `.text.main` and `.text.aux`.
  4. `Exec.build`, then `Elf_unix.write_executable`.
  5. Run the M2.9 checks, then the M2.10 QEMU run.
  6. Keep the artifacts (source, `.o`, ELF, tool outputs) in
     `_build/.../gnu-artifacts/<arch>-<variant>/` for debugging.

### M2.8 RV32 payload generator *(toolchain)*

- **Files:** `test/gnu/payload_riscv.ml` (shared by RV32 and RV64).
- **Source shape** (`.option norelax`; `s1` holds the current check code;
  `.Lfail` exits with `s1`):

  ```
  .section .text.main,"ax"
  _start: auipc t0,0 ; li s1,10 ; li t1,TEXT ; bne t0,t1,.Lfail
          li s1,11 ; li t0,RODATA ; lw t1,0(t0) ; li t2,M_RODATA ; bne t1,t2,.Lfail
          li s1,12 ; li t0,DATA ; ... M_DATA
          li s1,13 ; li t0,DATA+INIT ; lw t1,0(t0) ; bnez t1,.Lfail
          li s1,14 ; li t0,DATA+INIT+ZERO-4 ; ...
          li s1,15 / 16 : BSS, BSS+SIZE-4
          li s1,17 ; li t0,BSS+8 ; li t2,M_STORE ; sw t2,0(t0) ; lw t1,0(t0) ; bne t1,t2,.Lfail
          li s1,18 ; li t0,AUX ; jalr ra,0(t0) ; li t2,M_AUX ; bne a0,t2,.Lfail
          li a0,42 ; li a7,93 ; ecall
  .Lfail: mv a0,s1 ; li a7,93 ; ecall
  .section .text.aux,"ax"
  aux:    li a0,M_AUX ; ret
  ```

- **Markers** are below `0x8000_0000`, so `lw` sign extension on RV64 cannot
  change the comparison.
- **Done when:** both RV32 variants assemble relocation-free, and `Decode`
  shows no relocation sections at all.

### M2.9 Structural checks *(toolchain)*

- **Files:** `test/gnu/structural.ml`.
- **Checks** (the expected values come from `Spec`, never from `Decode`):
  - `readelf -W -h`: Class, Data, Type `EXEC`, Machine, Entry = `Spec.text`,
    Flags = `Riscv.flags abi`, which is computed independently in the test
    from the psABI table.
  - `readelf -W -l`: one LOAD per region (vaddr, memsz, flags `R`/`R E`/`RW `,
    align); the header LOAD; PHDR; GNU_STACK `RW `; RISCV_ATTRIBUTE.
  - `readelf -W -S` (section variants): names, types (`PROGBITS`/`NOBITS`),
    flags `AX`/`A`/`WA`.
  - `readelf -W -s`: `_start` FUNC GLOBAL, `aux` FUNC, markers OBJECT.
  - `readelf -A`: `Tag_RISCV_arch`, `Tag_RISCV_stack_align: 16-bytes`.
  - `readelf -W --lint -a`: stderr must be empty.
  - `objdump -d -j .text.main`: the instruction lines equal `objdump -d` of
    the `.o`, with addresses rebased.
  - For sectionless variants:
    `objdump -b binary -m riscv:rv32 -D --adjust-vma=TEXT` on the extracted
    segment, with the same comparison.
- **Report:** one line per mismatching field (`expected … got …`), and the
  run fails if there are any.

### M2.10 QEMU user matrix *(toolchain)*

- **Variants:**
  - base `0x40_0000` or `0x9000_0000`;
  - `sections` true or false;
  - ABI `ilp32d` (`rv32imafd_ilp32d`) or `ilp32` (`rv32im_ilp32`; the payload
    uses no FP);
  - giving 8 runs.
- **Run:** `timeout 10 qemu-riscv32 FILE`; the exit status must be 42.
- **Negative controls:**
  - a variant with the rodata marker flipped in the spec bytes must exit 11;
  - one with a nonzero byte injected into the mixed segment's zero-fill tail
    (as a `Bytes` section) must exit 13.
  These prove the checks can fail.
- **Done when:** all 8 runs and both controls pass, and the tracker records
  the QEMU and binutils versions.

---

## M3. RV32 `virt` system mode

### M3.1 `qemu-system-riscv`

Add it to `elf/.devcontainer/Dockerfile` (M0.5) and, for the host
repository's CI, to the root `.devcontainer/Dockerfile`. Confirm
`qemu-system-riscv32 -M virt -bios none` starts.

### M3.2 Startup contract

Write it into `design.md` §7:

- The core starts in M-mode at `e_entry`, with no firmware or device tree.
- Startup sets `mtvec` to a trap stub, which reports failure code `0x7f`, and
  `sp` to the top of a stack reserved in the RW segment (16-byte aligned).
- Startup must not rely on `a0`/`a1`.

### M3.3 System placement profile

- **Files:** `src/exec.ml` (or `src/profile.ml`): `system_riscv_virt : Target.t -> base:int64 -> ...`.
- **Rules:** RAM `[0x8000_0000, +128 MiB)`; every segment and the headers must
  lie inside it. `paddr = vaddr` (no MMU).
- **Errors:** add `` `Outside_ram of {...} `` to `Exec.error`, for placement
  outside RAM under a system profile.

### M3.4 System payload *(toolchain)*

- **Files:** `test/gnu/payload_riscv.ml`, a `~system:true` mode.
- **Prologue:** `li sp,STACK_TOP ; li t0,TRAP ; csrw mtvec,t0`.
- **Checks:** 10–18 as in user mode.
- **Exit:** the SiFive test device.
  - Pass: `li t0,0x100000 ; li t1,0x5555 ; sw t1,0(t0)`.
  - Fail: write `(s1 << 16) | 0x3333`.
  - Trap stub: `li s1,0x7f` and then the fail path.
- **Done when:** it assembles relocation-free.

### M3.5 QEMU system run *(toolchain)*

- **Command:**
  `timeout 20 qemu-system-riscv32 -M virt -smp 1 -m 128M -bios none -nographic -monitor none -serial none -device loader,file=FILE,cpu-num=0`.
- **Expected status:** 0 for pass; the check code for fail. A `timeout` status
  of 124 is a failure ("hang").
- **Zero-fill:** checks 13–16 verify zero-fill under QEMU's ELF loader. If
  they fail, the plan's fallback is for startup to clear `.bss` explicitly,
  documented as part of the contract.
- **Negative controls:** as in M2.10.

---

## M4. The other five architectures

### M4.1 Profiles

- `Target.x86_32`, `Target.x86_64` and `Target.aarch64 ()` (64 KiB default,
  per Q5).
- `Arm.abi = { float_abi : [`Hard | `Soft]; attributes : Attributes.t option }`,
  with `Arm.flags`.
- Tests: the §6.5 table.

### M4.2–M4.6 User-mode payload generators *(toolchain)*

These reuse the M2.7 harness. Only the `Payload.S` module and the
`Toolchain` row change.

| ID | Arch | Code register / fail path | PC check | Constants | Call aux | Exit |
| --- | --- | --- | --- | --- | --- | --- |
| M4.2 | RV64 | `s1` | `auipc` | `li` | `jalr` | `a7=93; ecall` |
| M4.3 | x86-32 | `%esi` | `call 1f; 1: pop %eax`, expect `TEXT+5` | immediates; absolute `mov ADDR,%eax` | `mov $AUX,%ecx; call *%ecx` | `mov %esi,%ebx; mov $1,%eax; int $0x80` |
| M4.4 | x86-64 | `%ebx` | `lea .Lstart(%rip),%rax` | `movabs` | `movabs $AUX,%rcx; call *%rcx` | `mov %ebx,%edi; mov $60,%eax; syscall` |
| M4.5 | ARM (A32, `.arm`, `-march=armv7-a`) | `r4` | `mov r0,pc`, expect `TEXT+8` | `movw/movt` | `blx r3` | `mov r0,r4; mov r7,#1; svc #0` |
| M4.6 | AArch64 | `w19` | `adr x0,.Lstart` | `movz/movk` × 4 | `blr x3` | `mov x0,x19; mov x8,#93; svc #0` |

Per arch:

- **Variants:**
  - low base `0x40_0000`;
  - high base: `0x9000_0000` for 32-bit targets, `0x1_2000_0000` for 64-bit
    targets;
  - with or without sections;
  - ARM also hard vs. soft `e_flags`.
- **Checks:** the M2.9 structural checks, with `-m` names `i386`,
  `i386:x86-64`, `arm`, `aarch64`, `riscv:rv64` for raw disassembly.
- **Done when:** `qemu-<arch>` exits 42 for every variant and both negative
  controls report their codes.

### M4.7 AArch64 and ARM system *(toolchain)*

- **Machine:** `virt`, RAM at `0x4000_0000`.
- **Command:**
  `qemu-system-aarch64 -M virt -cpu cortex-a53 -nographic -semihosting -kernel FILE`,
  and for ARM `qemu-system-arm -M virt -cpu cortex-a15 ...`.
- **Startup:** set `sp`; install a vector table (AArch64 `VBAR_EL1`, ARM
  `VBAR`) that reports `0x7f`.
- **Exit:**
  - AArch64: `SYS_EXIT` (`x0 = 0x18`, `x1` → `{0x20026, code}`), via
    `hlt #0xf000`.
  - ARM: `SYS_EXIT_EXTENDED` (`r0 = 0x20`, `r1` → `{0x20026, code}`), via
    `svc 0x123456` (A32).
- **First step:** confirm which exception level `-kernel` with an ELF enters
  on each machine, and record it in the startup contract.

### M4.8 x86-32 system *(toolchain)*

- **Header:** a Multiboot header in the first 8 KiB of the file: magic
  `0x1BADB002`, flags `0x0`, checksum. It sits in a dedicated R section at the
  start of the first loaded segment, and `place` must keep it inside the
  first 8 KiB.
- **Command:**
  `qemu-system-i386 -kernel FILE -nographic -device isa-debug-exit,iobase=0xf4,iosize=0x04`.
- **Exit:** `outl` of `c` to port `0xf4` makes QEMU exit with `(c << 1) | 1`.
  Pass writes `21` (status 43); fail writes the check code.
- **Startup:** 32-bit protected mode with paging off; set `esp`; install an
  IDT whose entries report `0x7f`.

### M4.9 x86-64 system *(toolchain, after Q3)*

- **Option A:** an ELF32 Multiboot container (`EM_386`) whose 32-bit entry
  sets up identity paging, enables long mode, and jumps to the 64-bit payload
  segment.
- **Option B:** the generic loader with a documented reset contract.
- The decision is recorded in the tracker before work starts.

---

## M5. Parser breadth and portability

### M5.1 GNU fixtures

- **Files:** `test/fixtures/<arch>/{obj.o,static,dynamic,lib.so}`,
  `test/fixtures/PROVENANCE`, and `tools/regen-fixtures.sh` (needs cross gcc;
  run manually, not in CI).
- **PROVENANCE** records tool versions, exact command lines, `-misa-spec` and
  the SHA-256 of each file.
- **Size:** each fixture is under 16 KiB (`-nostdlib`, small sources).

### M5.2 Fixture checks

- **Files:** `test/fixtures/<arch>/*.readelf` (recorded `readelf -W -a`
  output) and `test/unit/test_fixtures.ml`.
- **Test:** compare `Decode` with the recorded output, using the M1.12
  `Readelf` parser (moved to `test/support`). Runs under `make test`.

### M5.3 Edge fixtures

- Covered: `.note.gnu.property` (8-aligned), `SHT_GROUP` (from `-ffunction-sections`
  plus COMDAT), and extended numbering (an object with > 0xff00 sections,
  generated by a script).
- Big-endian: assembled with `aarch64_be-linux-gnu-as` or `armeb`, if
  available; otherwise generated by `Fixture` with `Big`.

### M5.4 Fuzz loop

- **Files:** `test/unit/test_fuzz.ml`.
- **Run:** a deterministic PRNG (`Random.State.make [|seed|]`); for each
  corpus file, N mutations (byte flip, truncate, 16/32/64-bit field set to an
  edge value). Every `Decode` accessor is run on the result.
- **Assertion:** no exception escapes.
- **Budgets:** N = 200 in `make test`; `make fuzz` runs N = 100 000.

### M5.5 Backend determinism

- First, check whether the pinned err_trace installs a Melange-mode library.
  If not, record it in the tracker and limit this task to js_of_ocaml until
  it does.
- **`@test-js`:** builds a determinism executable that runs `Exec.build` on a
  fixed spec set and prints SHA-256-free digests (`Digest` is MD5 and
  available everywhere).
- **Done when:** the native, bytecode and js_of_ocaml outputs are compared and
  equal.

---

## M6. `ET_REL` generation (deferred)

Broken down when started. Known scope:

- Input is the assembler's lowered module.
- Sections, symbols, and REL or RELA per target (RISC-V: RELA only).
- The RISC-V HI/LO anchor rule.
- No relaxation records until a policy exists.
- Verification: link with GNU `ld` and run under QEMU.

## M7. Assembler adapter (consumer side)

### M7.1 Adapter

- **Placement:** in `asm/`, depending on the `elf` package (installed or
  pinned). `elf` gains no dependency on `asm`.
- **Steps:**
  1. Assembler `plan_image` gives segment sizes and alignments.
  2. `Exec.place` chooses addresses.
  3. Assembler `bind_image` at those addresses gives the segment bytes.
  4. `Exec.build`.
- **Symbols:** exported symbols are emitted as `STT_NOTYPE` unless the
  assembler supplies symbol types.
- **Note:** the assembler's purity audit only permits vendored dependencies.
  Decide there whether `elf` is vendored like err_trace or allowlisted.

### M7.2 Assembler-produced executables *(toolchain)*

Run the existing freestanding corpus through the adapter under `qemu-<arch>`.
Exit statuses must match the assembler's current QEMU oracle.

---

## Critical path and ordering

```
M0.1 ─ M0.2 ─ M0.3 ─ M0.8 ─┬─ M1.1 ─ M1.3 ─ M1.4 ──────────────┐
                           │         └─ M1.5 ─ M1.6 ─┬─ M1.11   │
                           │   M1.2 ─ M1.7           ├─ M1.8 ─ M1.10
                           │                         └─ M1.12 (toolchain)
                           └─ M0.4 M0.5 M0.6 M0.7 (parallel)
M1.4 + M1.6 + M1.7 + M1.8 ─ M2.1 ─ M2.2 ─ M2.4 ─ M2.5 ─ M2.6
M1.12 ─ M2.7 ─ M2.8 ─ M2.9 ─ M2.10        M2.2 + M1.12 ─ M2.3
M2.10 ─ M4.1..M4.6        M3.1 + M2.10 ─ M3.2..M3.5 ─ M4.7 M4.8 ─ (Q3) M4.9
M1.11 + M5.1 ─ M5.2..M5.4        M2.6 ─ M5.5        M2.6 + M4.* ─ M7
```

**Suggested sequence of commits:**

1. M0.1–M0.3 + M0.8 (buildable empty project).
2. M1.1–M1.4.
3. M1.5–M1.7.
4. M1.8 + M1.11.
5. M1.9 + M1.10.
6. M0.4–M0.7.
7. M1.12.
8. M2.1–M2.3.
9. M2.4–M2.6.
10. M2.7–M2.10.
11. Then M3 and M4 in either order, depending on `qemu-system-riscv`
    availability.
