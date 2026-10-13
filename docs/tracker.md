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

Milestone M0 (infrastructure) then M1. Progress is committed in `elf/`'s own git repository.

Code for parts of M1 already exists as a draft, written before the design was
settled. Whether to keep it as the starting point or delete it is open (Q7).

## Blockers

| What | Blocks | Resolution |
| --- | --- | --- |
| `qemu-system-riscv32/64` absent: Debian ships them in `qemu-system-misc`, which this repository's devcontainer does not install | M3.5 (and RV system runs generally) | M3.1: add `qemu-system-misc` to the devcontainer(s) |
| x86-64 system-mode route undecided | M4.9 | Q3 |

## Status

### M0. Project infrastructure

| ID | Task | Status | Notes |
| --- | --- | --- | --- |
| M0.1 | dune project and opam metadata | done | err_trace pinned at `v0.0.1` via `pin-depends`; package name `elf` pending Q1 |
| M0.2 | Formatting | done | `.ocamlformat` copied from `asm/`; `@fmt` clean |
| M0.3 | Makefile | done | |
| M0.4 | Repository files | todo | License: `dune-project` says MIT, to be confirmed (Q8) |
| M0.5 | Devcontainer | todo | |
| M0.6 | GitHub Actions | todo | |
| M0.7 | Host-repository integration | todo | |
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
| M1.12 | GAS objects | todo | |

### M2. RV32 static `ET_EXEC`, Linux user mode

| ID | Task | Status | Notes |
| --- | --- | --- | --- |
| M2.1 | `Target` | done | `target.ml{,i}`, `all` and `arch_of_string`; `test_target` |
| M2.2 | `Riscv` | done | `riscv.ml{,i}`, `arm.ml{,i}`; profile ISA strings are GAS 2.44's defaults |
| M2.3 | ISA string | todo | Local GAS 2.44 default: `rv32i2p0_m2p0_a2p0_f2p0_d2p0_zmmul1p0_zaamo1p0_zalrsc1p0` |
| M2.4 | `Exec` spec and validation | todo | |
| M2.5 | `Exec.place` | todo | |
| M2.6 | `Exec.build` | todo | |
| M2.7 | `test/gnu` harness | todo | |
| M2.8 | RV32 payload generator | todo | |
| M2.9 | Structural checks | todo | `readelf --lint` available (binutils 2.44) |
| M2.10 | QEMU user matrix | todo | |

### M3. RV32 `virt` system mode

| ID | Task | Status | Notes |
| --- | --- | --- | --- |
| M3.1 | `qemu-system-misc` | todo | |
| M3.2 | Startup contract | todo | |
| M3.3 | System placement profile | todo | |
| M3.4 | System payload | todo | |
| M3.5 | QEMU system run | blocked | Needs M3.1 |

### M4. The other five architectures

| ID | Task | Status | Notes |
| --- | --- | --- | --- |
| M4.1 | Profiles | todo | AArch64 page size pending Q5 |
| M4.2 | RV64 user | todo | |
| M4.3 | x86-32 user | todo | |
| M4.4 | x86-64 user | todo | |
| M4.5 | ARM user | todo | |
| M4.6 | AArch64 user | todo | |
| M4.7 | AArch64 and ARM system | todo | `qemu-system-{aarch64,arm}` present |
| M4.8 | x86-32 system | todo | `qemu-system-i386` present |
| M4.9 | x86-64 system | blocked | Q3 |

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
| Q3 | x86-64 system-mode route | open | M4.9 |
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
