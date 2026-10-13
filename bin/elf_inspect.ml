let () =
  prerr_endline
    "usage: elf-inspect [--header] [--segments] [--sections] [--symbols] [--relocs] [--notes] \
     [--attributes] [--all] FILE";
  exit 2
