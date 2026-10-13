# Changes

## Unreleased

- Checked ELF32/ELF64 codecs and a bounded decoder (`Decode`), both byte orders.
- `Strtab`, `Attributes` (`.riscv.attributes`, `.ARM.attributes`), `Names`.
- `Target`, `Riscv` and `Arm` profiles for x86-32, x86-64, ARM, AArch64, RV32 and RV64.
- `Exec`: validation, address placement and static `ET_EXEC` building.
- `elf.unix` file access and the `elf-inspect` command.
