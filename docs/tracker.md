# `elf`: tracker

This is the status of the tasks defined in [plan.md](plan.md). Update the
status, the notes and the log in the same change as the work itself.

Status values:

- `todo`
- `draft`: code exists, but it is untested or unreviewed against the design.
- `wip`
- `done`: the plan's Accept criterion is met.
- `blocked`
- `deferred`

Last updated: 2026-10-13.

## Current focus

M5 (parser breadth: fixtures, fuzz loop, determinism), then M7 (assembler adapter). M6 stays deferred.

## Blockers

| What | Blocks | Resolution |
| --- | --- | --- |
| (none) | | |

## Status

### M0. Project infrastructure

| ID | Task | Status | Notes |
| --- | --- | --- | --- |
| M0.1 | dune project and opam metadata | done | err_trace pinned at `v0.0.1` via `pin-depends`; package name `elf` pending Q1 |
| M0.2 | Formatting | done | `.ocamlformat` copied from `asm/`; `@fmt` clean |
| M0.3 | Makefile | done | |
| M0.4 | Repository files | done | README (its example is compiled and run by `test/readme`), MIT `LICENSE` (assumed, Q8), `CHANGES.md` |
| M0.5 | Devcontainer | draft | `.devcontainer/{Dockerfile,devcontainer.json}` written; the image build is not verified here (no Docker) |
| M0.6 | GitHub Actions | draft | `.github/workflows/ci.yml` written; actionlint is not installed here, so it is unlinted and unrun |
| M0.7 | Host-repository integration | draft | root `.github/workflows/elf.yml`, `CLAUDE.md` section and `elf-ci`/`elf-test-gnu` Makefile targets written in the host repository, not committed there |
| M0.8 | Test skeleton | done | `test/support/check`, `test/js` (`@test-js`), `inspect.t` cram |

### M1. Codecs and decoder

| ID | Task | Status | Notes |
| --- | --- | --- | --- |
| M1.1 | `U64` | done | `test/unit/test_u64.ml` |
| M1.2 | `Types`, `Const` | done | `names.ml{,i}`; test enumerates every Const name |
| M1.3 | `Codec` | done | `test_codec`; Codec stays private, tests compile its source via `copy_files` |
| M1.4 | `Encode` | done | `test_encode`; message pinned in `errors.t` |
| M1.5 | `Decode` core | done | `test_decode`, extended numbering via `Fixture.many_sections`; shstrtab type is checked; loops avoid binds so they run under js_of_ocaml |
| M1.6 | `Decode` accessors | done | added `Bad_segment_index`; `attributes` accessor; Decode.error includes Attributes.error |
| M1.7 | `Strtab` | done | `strtab.ml{,i}`, `test_strtab` |
| M1.8 | `Attributes` | done | `attributes.ml{,i}`; extra encode errors `Bad_value_kind`, `Unknown_vendor`, `Bad_tag`, `Bad_index`; GAS 2.44 golden |
| M1.9 | `elf.unix` | done | `unix/elf_unix.ml{,i}`, `test_unix` (native only) |
| M1.10 | `elf-inspect` | done | `bin/elf_inspect.ml`; `--trace` is opt-in so golden output does not pin library line numbers; cram `inspect.t`, `errors.t` |
| M1.11 | Malformed corpus | done | `test/unit/test_malformed.ml` (fuzz loop is M5.4) |
| M1.12 | GAS objects | done | `test/gnu/{toolchain,readelf,test_objects}.ml`; all six architectures match readelf -S/-s/-r/-A (binutils 2.44); `.gitignore` covers `gnu-artifacts` via `_build` |

### M2. RV32 static `ET_EXEC`, Linux user mode

| ID | Task | Status | Notes |
| --- | --- | --- | --- |
| M2.1 | `Target` | done | `target.ml{,i}`, `all` and `arch_of_string`; `test_target` |
| M2.2 | `Riscv` | done | `riscv.ml{,i}`, `arm.ml{,i}`; profile ISA strings are GAS 2.44's defaults |
| M2.3 | ISA string | done | `Riscv.isa_string`, `test/gnu/test_isa.ml`; profile strings follow GAS's default spec 2.2 (`-misa-spec=20191213` strings are reproduced by `isa_string`); GAS emits no `Tag_RISCV_stack_align`, so the test compares arch string and `e_flags` only |
| M2.4 | `Exec` spec and validation | done | `exec.ml{,i}` types and `validate`; `test_exec`; collected as thunks over `Err.Accum`; added `File_too_large` |
| M2.5 | `Exec.place` | done | `place`, `phdr_count`, `headers_size` (tests in `test_build`) |
| M2.6 | `Exec.build` | done | `build`; a failing validation becomes `Invalid_spec`; list helpers are tail-recursive so the 65K-section and 65K-segment cases run under js_of_ocaml; `test_build` |
| M2.7 | `test/gnu` harness | done | `spec.ml`, `payload.ml`, `harness.ml`, `run_user.ml`; object checked relocation-free; artifacts under `gnu-artifacts/<name>/` |
| M2.8 | RV32 payload generator | done | `payload_riscv.ml` (RV32 and RV64); section names `.text.main`/`.text.aux` |
| M2.9 | Structural checks | done | `structural.ml`, `objdump.ml`; readelf -h/-l/-S/-s/-A, `--lint`, objdump (sectioned and raw) all checked; verified the checks fail on wrong expectations |
| M2.10 | QEMU user matrix | done | 8 variants exit 42; controls exit 11 and 13. Versions: binutils 2.44 (Debian), qemu-riscv32 10.0.13 (Debian 1:10.0.13+ds-0+deb13u1) |

### M3. RV32 `virt` system mode

| ID | Task | Status | Notes |
| --- | --- | --- | --- |
| M3.1 | `qemu-system-riscv` | done | `qemu-system-riscv` added to `elf/.devcontainer/Dockerfile` and the root Dockerfile (the package is `qemu-system-riscv` in Debian 13, not `qemu-system-misc`). Here it is not installed system-wide: the identical-version .deb was extracted under /tmp and put on PATH |
| M3.2 | Startup contract | done | startup contract is in design §7 |
| M3.3 | System placement profile | done | `Exec.ram`, `riscv_virt_ram`, `validate ?ram`, `Outside_ram`; unit tests in `test_exec` |
| M3.4 | System payload | done | `payload_riscv.ml` system mode (trap stub at a fixed offset so mtvec needs no relocation); stack segment in `Spec` |
| M3.5 | QEMU system run | done | `run_system.ml`: 4 variants exit 0; controls 11, 13 and 0x7f (illegal instruction → trap stub). Run with the extracted qemu-system-riscv32 10.0.13 |

### M4. The other five architectures

| ID | Task | Status | Notes |
| --- | --- | --- | --- |
| M4.1 | Profiles | done | profiles were built in M2.1; added `Arm.armv7a_attributes` (GAS golden), used by the ARM test matrix so objdump decodes movw/movt |
| M4.2 | RV64 user | done | RV64: lp64d and lp64, bases 0x400000 and 0x120000000, all pass under qemu-riscv64 |
| M4.3 | x86-32 user | done | `payload_x86.ml` (32-bit): exit 42 for all variants and both controls under qemu-i386 |
| M4.4 | x86-64 user | done | `payload_x86.ml` (64-bit): under qemu-x86_64 |
| M4.5 | ARM user | done | `payload_arm.ml` (A32, movw/movt): hard and soft e_flags under qemu-arm |
| M4.6 | AArch64 user | done | `payload_aarch64.ml` (movz/movk): 64 KiB pages under qemu-aarch64 |
| M4.7 | AArch64 and ARM system | done | AArch64 enters at EL1 and ARM in SVC mode (measured; recorded in design §7); semihosting exit; `Exec.arm_virt_ram`; 26 runs including controls under qemu-system-aarch64/arm |
| M4.8 | x86-32 system | done | Multiboot ELF32 under qemu-system-i386, isa-debug-exit; statuses 43 and (code<<1) |
| M4.9 | x86-64 system | done | Q3 decided: option A (ELF32 Multiboot container with a long-mode stub, design §7); 6 runs incl. controls (statuses 43, 23, 27, 255) under qemu-system-x86_64 |

### M5. Parser breadth and portability

| ID | Task | Status | Notes |
| --- | --- | --- | --- |
| M5.1 | GNU fixtures | todo | |
| M5.2 | Fixture checks | todo | |
| M5.3 | Edge fixtures | todo | |
| M5.4 | Fuzz loop | todo | |
| M5.5 | Backend determinism | todo | Check err_trace's Melange packaging first |

### M6 and M7

| ID | Task | Status | Notes |
| --- | --- | --- | --- |
| M6 | `ET_REL` generation | deferred | |
| M7.1 | Assembler adapter | todo | |
| M7.2 | Assembler-produced executables | todo | |

## Open questions

Q1–Q6 are design §12. Q7 and Q8 are tracker-only.

| ID | Question | Status | Blocks |
| --- | --- | --- | --- |
| Q1 | Project/package name (`ocaml-elf` is taken on GitHub) | open | M0.4, M0.6 |
| Q2 | err_trace: stay on `v0.0.1` or track `main` | open (pinned `v0.0.1`) | — |
| Q3 | x86-64 system-mode route | decided: ELF32 Multiboot container with a long-mode stub | — |
| Q4 | RISC-V implied-extension expansion vs. explicit profiles | open (explicit) | M2.3 |
| Q5 | AArch64 page size, 64 KiB vs. 4 KiB | open (64 KiB) | M4.1, M4.6 |
| Q6 | Big-endian generation in scope | open (decode only) | — |
| Q7 | Keep the draft M1 code, or restart from the design | decided: keep | M1.1–M1.6 |
| Q8 | License (MIT assumed in `dune-project`) | open | M0.4 |

## Decision log

| Date | Decision | Where |
| --- | --- | --- |
| 2026-10-13 | `elf/` incubates here and is laid out as a future standalone repository root, with its own devcontainer and GitHub Actions CI | design §10 |
| 2026-10-13 | err_trace is an opam dependency pinned from GitHub (`v0.0.1`), not vendored; no submodules under `elf/` | design §4 |
| 2026-10-13 | Each module has a closed error row; widening is by coercion; payloads are named records | design §4 |
| 2026-10-13 | All ≥ 32-bit fields are `int64` with unsigned checked arithmetic | design §3.2 |
| 2026-10-13 | Segments may not share pages; offsets are congruent to vaddr mod `p_align` | design §6.6 |
| 2026-10-13 | GAS supplies payload bytes only; tests extract relocation-free sections with `Decode`, not with GNU-linked executables | design §9.3 |

## Log

- 2026-10-13: design written; err_trace switched from a vendored submodule to
  an opam pin; plan and tracker created. Draft code covers M1.1–M1.6.
- 2026-10-13: plan.md expanded into a step-level implementation plan with
  interfaces, algorithms, test cases and a commit sequence; task IDs are
  unchanged.
- 2026-10-13: M0.1–M0.3, M0.8 and M1.1 done; draft M1 code kept (Q7).
- 2026-10-13: M1.2–M1.4 done.
- 2026-10-13: M1.5–M1.8 and M1.11 done.
- 2026-10-13: M1.9 and M1.10 done.
- 2026-10-13: M2.1 and M2.2 done (ahead of M1.12, which needs the arch type).
- 2026-10-13: M1.12 done: GAS objects for all six architectures agree with readelf.
- 2026-10-13: M2.4–M2.6 done: Exec validate, place and build.
- 2026-10-13: M2.3 and M2.7–M2.10 done: RV32 user-mode matrix passes under qemu-riscv32 (8 runs, 2 negative controls).
- 2026-10-13: M3 done: RV32 virt system mode passes under qemu-system-riscv32 10.0.13 (4 runs, 3 controls).
- 2026-10-13: M4.1–M4.6 done: user-mode matrices for all six architectures pass under QEMU (48 runs, including the negative controls).
- 2026-10-13: M4.7 and M4.8 done: RV64, AArch64, ARM and x86-32 system mode under QEMU.
- 2026-10-13: Q3 decided (option A) and M4.9 done: x86-64 system mode runs in long mode under QEMU.
