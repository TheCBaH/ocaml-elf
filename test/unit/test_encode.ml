open Elf_test_support
open Elf
open Types

let le32 = { elf_class = Elf32; endianness = Little; osabi = 0; abiversion = 0 }
let be64 = { elf_class = Elf64; endianness = Big; osabi = 0; abiversion = 0 }

let phdr =
  {
    p_type = 1L;
    p_flags = 5L;
    p_offset = 0x1000L;
    p_vaddr = 0x40_0000L;
    p_paddr = 0x40_0000L;
    p_filesz = 0x10L;
    p_memsz = 0x20L;
    p_align = 0x1000L;
  }

let header id =
  {
    ident = id;
    e_type = Const.et_exec;
    e_machine = Const.em_riscv;
    e_version = 1L;
    e_entry = 0x1_0000L;
    e_phoff = 52L;
    e_shoff = 0L;
    e_flags = 0L;
    e_ehsize = 52;
    e_phentsize = 32;
    e_phnum = 1;
    e_shentsize = 40;
    e_shnum = 0;
    e_shstrndx = 0;
  }

let shdr =
  {
    sh_name = 0L;
    sh_type = 1L;
    sh_flags = 0L;
    sh_addr = 0L;
    sh_offset = 0L;
    sh_size = 0L;
    sh_link = 0L;
    sh_info = 0L;
    sh_addralign = 1L;
    sh_entsize = 0L;
  }

let sym = { st_name = 0L; st_info = 0; st_other = 0; st_shndx = 1; st_value = 0L; st_size = 0L }
let rel = { r_offset = 0L; r_sym = 0L; r_type = 0L; r_addend = None }
let buf = Bytes.make 128 '\000'

let overflow what ~record ~field ~bits ~signed ~value r =
  Check.error
    ~pp:(fun ppf () -> Format.pp_print_string ppf "()")
    what
    (function `Field_overflow o -> o = { Encode.record; field; value; bits; signed })
    r

let accepted what r = ignore (Check.ok ~pp_error:Encode.pp_error what r)

let () =
  Check.run "encode"
    [
      Check.case "ELF32 address too wide" (fun () ->
          overflow "p_vaddr" ~record:(`Program_header 3) ~field:"p_vaddr" ~bits:32 ~signed:false
            ~value:0x1_0000_0000L
            (Encode.write_phdr le32 buf 0 ~index:3 { phdr with p_vaddr = 0x1_0000_0000L });
          accepted "ELF64 p_vaddr"
            (Encode.write_phdr be64 buf 0 ~index:3 { phdr with p_vaddr = 0x1_0000_0000L }));
      Check.case "ELF32 relocation type and symbol" (fun () ->
          overflow "r_type" ~record:(`Relocation 2) ~field:"r_type" ~bits:8 ~signed:false
            ~value:256L
            (Encode.write_rel le32 buf 0 ~index:2 { rel with r_type = 256L });
          overflow "r_sym" ~record:(`Relocation 2) ~field:"r_sym" ~bits:24 ~signed:false
            ~value:0x100_0000L
            (Encode.write_rel le32 buf 0 ~index:2 { rel with r_sym = 0x100_0000L });
          accepted "ELF64 r_type" (Encode.write_rel be64 buf 0 ~index:2 { rel with r_type = 256L });
          accepted "ELF64 r_sym"
            (Encode.write_rel be64 buf 0 ~index:2 { rel with r_sym = 0x100_0000L }));
      Check.case "ELF32 addend range" (fun () ->
          let rela a = { rel with r_addend = Some a } in
          overflow "addend 2^31" ~record:(`Relocation 0) ~field:"r_addend" ~bits:32 ~signed:true
            ~value:0x8000_0000L
            (Encode.write_rel le32 buf 0 ~index:0 (rela 0x8000_0000L));
          overflow "addend -2^31-1" ~record:(`Relocation 0) ~field:"r_addend" ~bits:32 ~signed:true
            ~value:(-0x8000_0001L)
            (Encode.write_rel le32 buf 0 ~index:0 (rela (-0x8000_0001L)));
          accepted "addend 2^31-1" (Encode.write_rel le32 buf 0 ~index:0 (rela 0x7fff_ffffL));
          accepted "addend -2^31" (Encode.write_rel le32 buf 0 ~index:0 (rela (-0x8000_0000L)));
          accepted "ELF64 addend" (Encode.write_rel be64 buf 0 ~index:0 (rela 0x8000_0000L)));
      Check.case "header counts and fields" (fun () ->
          let h = header le32 in
          overflow "e_phnum" ~record:`Header ~field:"e_phnum" ~bits:16 ~signed:false ~value:0x10000L
            (Encode.write_header buf { h with e_phnum = 0x10000 });
          overflow "e_type" ~record:`Header ~field:"e_type" ~bits:16 ~signed:false ~value:(-1L)
            (Encode.write_header buf { h with e_type = -1 });
          overflow "osabi" ~record:`Header ~field:"ei_osabi" ~bits:8 ~signed:false ~value:256L
            (Encode.write_header buf { h with ident = { h.ident with osabi = 256 } });
          overflow "e_entry" ~record:`Header ~field:"e_entry" ~bits:32 ~signed:false
            ~value:0x1_0000_0000L
            (Encode.write_header buf { h with e_entry = 0x1_0000_0000L });
          accepted "valid" (Encode.write_header buf h);
          accepted "ELF64 e_entry"
            (Encode.write_header buf { (header be64) with e_entry = 0x1_0000_0000L }));
      Check.case "section header and symbol" (fun () ->
          overflow "sh_addr" ~record:(`Section_header 5) ~field:"sh_addr" ~bits:32 ~signed:false
            ~value:0x1_0000_0000L
            (Encode.write_shdr le32 buf 0 ~index:5 { shdr with sh_addr = 0x1_0000_0000L });
          overflow "sh_link" ~record:(`Section_header 5) ~field:"sh_link" ~bits:32 ~signed:false
            ~value:0x1_0000_0000L
            (Encode.write_shdr be64 buf 0 ~index:5 { shdr with sh_link = 0x1_0000_0000L });
          overflow "st_shndx" ~record:(`Symbol 7) ~field:"st_shndx" ~bits:16 ~signed:false
            ~value:0x10000L
            (Encode.write_sym le32 buf 0 ~index:7 { sym with st_shndx = 0x10000 });
          overflow "st_value" ~record:(`Symbol 7) ~field:"st_value" ~bits:32 ~signed:false
            ~value:0x1_0000_0000L
            (Encode.write_sym le32 buf 0 ~index:7 { sym with st_value = 0x1_0000_0000L });
          accepted "ELF64 st_value"
            (Encode.write_sym be64 buf 0 ~index:7 { sym with st_value = 0x1_0000_0000L }));
      Check.case "nothing is written on error" (fun () ->
          let b = Bytes.make 32 '\xaa' in
          ignore (Encode.write_phdr le32 b 0 ~index:0 { phdr with p_vaddr = 0x1_0000_0000L });
          Check.equal ~pp:Format.pp_print_string "untouched" (String.make 32 '\xaa')
            (Bytes.to_string b));
      Check.case "rendered message" (fun () ->
          match Encode.write_phdr le32 buf 0 ~index:3 { phdr with p_vaddr = 0x1_0000_0000L } with
          | Ok () -> Check.fail "expected an error"
          | Error e ->
              Check.equal ~pp:Format.pp_print_string "message"
                "program header 3: p_vaddr = 4294967296 (0x100000000) does not fit in 32 unsigned \
                 bits"
                (Format.asprintf "%a" (Err.Error.pp_kind Encode.pp_error) e));
    ]
