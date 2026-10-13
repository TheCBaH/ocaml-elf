# elf

A small pure-OCaml library that reads ELF32/ELF64 files and writes static `ET_EXEC` executables
for x86-32, x86-64, ARM32, AArch64, RV32 and RV64.

- **Reading**: checked, bounded decoding of untrusted input in both byte orders: headers,
  sections, string tables, symbols, `REL`/`RELA`, notes and build attributes. Every offset,
  count, index and string is validated, and no exception escapes.
- **Writing**: static executables built from addresses *you* choose. Bytes you bind are preserved
  exactly; the writer never moves code or data. `Exec.validate` reports every problem in a spec,
  and `Exec.place` can choose addresses for you.
- **Targets**: `Target` derives the ELF class and machine together, so they cannot disagree, and
  keeps ABI and execution environment explicit.
- **Portable**: the core depends only on the OCaml standard library and
  [err_trace](https://github.com/TheCBaH/err_trace). Native, js_of_ocaml and Melange are meant to
  produce identical bytes. File access lives in the separate `elf.unix` library.

Non-goals: dynamic linking, shared objects, linker relaxation, applying relocations, and
byte-identical decode/re-encode round trips. See [docs/design.md](docs/design.md).

## Install

err_trace is not in opam-repository yet; it is pinned from GitHub. `opam install .` does that
through `pin-depends`:

```sh
opam install . --deps-only --with-test -y
dune build
```

## Example

An RV32 program that exits with status 42, written as an executable file:

```ocaml
open Elf

let () =
  let target = Target.riscv Riscv.rv32imafd_ilp32d in
  (* li a0,42; li a7,93; ecall *)
  let code = "\x13\x05\xa0\x02\x93\x08\xd0\x05\x73\x00\x00\x00" in
  let rx = { Exec.read = true; write = false; execute = true } in
  let text = { Exec.name = ".text"; addr = 0x10000L; align = 4L; content = Exec.Bytes code } in
  let spec =
    { Exec.target; entry = 0x10000L; headers = Exec.Unmapped; gnu_stack = None;
      section_headers = true; symbols = [];
      segments = [ { Exec.perms = rx; paddr = None; sections = [ text ] } ] }
  in
  match Exec.build spec with
  | Error e -> Format.eprintf "%a@." (Err.Error.pp_kind Exec.pp_error) e; exit 1
  | Ok bytes -> (
      match Elf_unix.write_executable "hello" bytes with
      | Ok () -> ()
      | Error e -> Format.eprintf "%a@." (Err.Error.pp_kind Elf_unix.pp_error) e; exit 1)
```

This block is compiled by the unit tests (`test/unit/test_readme.ml`), so it cannot rot.
Run the result with `qemu-riscv32 ./hello; echo $?`.

Inspect any ELF file with `elf-inspect --all FILE`.

## Tests

| Command | What it runs |
| --- | --- |
| `make ci` | format check, build, unit and cram tests (no external tools) |
| `make test-js` | the unit tests under js_of_ocaml and Node |
| `make test-gnu` | GNU as/readelf/objdump checks and `qemu-<arch>` user-mode runs |
| `make test-system` | bare-metal runs under `qemu-system-*` |
| `make fuzz` | the long decoder fuzz loop |

The toolchain targets print `SKIP <tool>` for what is missing; with `ELF_REQUIRE_TOOLCHAIN=1`
a missing tool fails instead (CI sets it).

## Documents

- [docs/design.md](docs/design.md): the design.
- [docs/plan.md](docs/plan.md): the implementation plan, by task.
- [docs/tracker.md](docs/tracker.md): the status of each task.
