  $ elf-inspect
  usage: elf-inspect [--header] [--segments] [--sections] [--symbols] [--relocs] [--notes] [--attributes] [--all] [--trace] FILE
  [2]
  $ gen minimal-elf32-le a32.elf
  $ gen minimal-elf64-be a64.elf
  $ elf-inspect --all a32.elf
  header class=ELF32 data=little-endian osabi=0 abiversion=0 type=EXEC machine=RISCV version=1 entry=0x1000 flags=0x0 phoff=0x34 shoff=0x118 ehsize=52 phentsize=32 phnum=2 shentsize=40 shnum=7 shstrndx=6
  segment index=0 type=LOAD flags=RX offset=0x74 vaddr=0x1074 paddr=0x1074 filesz=0x10 memsz=0x10 align=0x4
  segment index=1 type=NOTE flags=R offset=0xc0 vaddr=0x10c0 paddr=0x10c0 filesz=0x14 memsz=0x14 align=0x4
  section index=0 name="" type=NULL flags=- addr=0x0 offset=0x0 size=0x0 link=0 info=0 align=0 entsize=0
  section index=1 name=".text" type=PROGBITS flags=AX addr=0x1000 offset=0x74 size=0x10 link=0 info=0 align=4 entsize=0
  section index=2 name=".symtab" type=SYMTAB flags=- addr=0x0 offset=0x84 size=0x30 link=3 info=1 align=4 entsize=16
  section index=3 name=".strtab" type=STRTAB flags=- addr=0x0 offset=0xb4 size=0xb link=0 info=0 align=1 entsize=0
  section index=4 name=".note.test" type=NOTE flags=- addr=0x0 offset=0xc0 size=0x14 link=0 info=0 align=4 entsize=0
  section index=5 name=".rela.text" type=RELA flags=- addr=0x0 offset=0xd4 size=0xc link=2 info=1 align=4 entsize=12
  section index=6 name=".shstrtab" type=STRTAB flags=- addr=0x0 offset=0xe0 size=0x37 link=0 info=0 align=1 entsize=0
  symbol section=".symtab" index=0 name="" value=0x0 size=0x0 type=NOTYPE bind=LOCAL other=0 shndx=UND
  symbol section=".symtab" index=1 name="data" value=0x10 size=0x4 type=OBJECT bind=LOCAL other=0 shndx=1
  symbol section=".symtab" index=2 name="main" value=0x0 size=0x8 type=FUNC bind=GLOBAL other=0 shndx=1
  reloc section=".rela.text" index=0 offset=0x4 sym=2 type=5 addend=-4
  note where=section:.note.test type=1 name="GNU" desc=01020304
  note where=segment:1 type=1 name="GNU" desc=01020304
  $ elf-inspect --all a64.elf
  header class=ELF64 data=big-endian osabi=0 abiversion=0 type=EXEC machine=RISCV version=1 entry=0x1000 flags=0x0 phoff=0x40 shoff=0x178 ehsize=64 phentsize=56 phnum=2 shentsize=64 shnum=7 shstrndx=6
  segment index=0 type=LOAD flags=RX offset=0xb0 vaddr=0x10b0 paddr=0x10b0 filesz=0x10 memsz=0x10 align=0x4
  segment index=1 type=NOTE flags=R offset=0x114 vaddr=0x1114 paddr=0x1114 filesz=0x14 memsz=0x14 align=0x4
  section index=0 name="" type=NULL flags=- addr=0x0 offset=0x0 size=0x0 link=0 info=0 align=0 entsize=0
  section index=1 name=".text" type=PROGBITS flags=AX addr=0x1000 offset=0xb0 size=0x10 link=0 info=0 align=4 entsize=0
  section index=2 name=".symtab" type=SYMTAB flags=- addr=0x0 offset=0xc0 size=0x48 link=3 info=1 align=8 entsize=24
  section index=3 name=".strtab" type=STRTAB flags=- addr=0x0 offset=0x108 size=0xb link=0 info=0 align=1 entsize=0
  section index=4 name=".note.test" type=NOTE flags=- addr=0x0 offset=0x114 size=0x14 link=0 info=0 align=4 entsize=0
  section index=5 name=".rela.text" type=RELA flags=- addr=0x0 offset=0x128 size=0x18 link=2 info=1 align=8 entsize=24
  section index=6 name=".shstrtab" type=STRTAB flags=- addr=0x0 offset=0x140 size=0x37 link=0 info=0 align=1 entsize=0
  symbol section=".symtab" index=0 name="" value=0x0 size=0x0 type=NOTYPE bind=LOCAL other=0 shndx=UND
  symbol section=".symtab" index=1 name="data" value=0x10 size=0x4 type=OBJECT bind=LOCAL other=0 shndx=1
  symbol section=".symtab" index=2 name="main" value=0x0 size=0x8 type=FUNC bind=GLOBAL other=0 shndx=1
  reloc section=".rela.text" index=0 offset=0x4 sym=2 type=5 addend=-4
  note where=section:.note.test type=1 name="GNU" desc=01020304
  note where=segment:1 type=1 name="GNU" desc=01020304
  $ gen riscv-attributes attrs.elf
  $ elf-inspect --attributes attrs.elf
  attribute section=".riscv.attributes" vendor="riscv" scope=file tag=4 uleb=16
  attribute section=".riscv.attributes" vendor="riscv" scope=file tag=5 ntbs="rv32i2p0_m2p0"
  attribute section=".riscv.attributes" vendor="riscv" scope=file tag=6 uleb=1
  attributes section=".riscv.attributes" vendor="other" raw=0102
  $ gen many-sections many.elf
  $ elf-inspect --header many.elf
  header class=ELF32 data=little-endian osabi=0 abiversion=0 type=EXEC machine=RISCV version=1 entry=0x0 flags=0x0 phoff=0x0 shoff=0x6ce3c ehsize=52 phentsize=32 phnum=0 shentsize=40 shnum=65296 shstrndx=65295
  $ elf-inspect a32.elf
  header class=ELF32 data=little-endian osabi=0 abiversion=0 type=EXEC machine=RISCV version=1 entry=0x1000 flags=0x0 phoff=0x34 shoff=0x118 ehsize=52 phentsize=32 phnum=2 shentsize=40 shnum=7 shstrndx=6
