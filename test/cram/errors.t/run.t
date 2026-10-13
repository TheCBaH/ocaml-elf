  $ gen encode-overflow
  program header 3: p_vaddr = 4294967296 (0x100000000) does not fit in 32 unsigned bits
  $ gen bad-magic bad.elf
  $ elf-inspect bad.elf
  elf-inspect: not an ELF file (bad magic)
  [2]
  $ gen truncated short.elf
  $ elf-inspect short.elf
  elf-inspect: ELF header at offset 0x0, size 0x34, extends past the 30-byte input
  [2]
  $ elf-inspect missing.elf
  elf-inspect: reading missing.elf: missing.elf: No such file or directory
  [1]
  $ elf-inspect --bogus a.elf
  elf-inspect: unknown option '--bogus'.
  usage: elf-inspect [--header] [--segments] [--sections] [--symbols] [--relocs] [--notes] [--attributes] [--all] [--trace] FILE
    --trace  print where in the library a decode error was detected
    -help  Display this list of options
    --help  Display this list of options
  [2]
