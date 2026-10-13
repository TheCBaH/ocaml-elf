open Elf_test_support
open Elf
module Codec = Elf_test_support.Codec
open Types

let classes = [ Elf32; Elf64 ]
let orders = [ Little; Big ]

let each f =
  List.iter
    (fun c ->
      List.iter
        (fun e ->
          let label = Format.asprintf "%a/%a" pp_class c pp_endianness e in
          f label c e)
        orders)
    classes

let hex s =
  String.concat "" (List.init (String.length s) (fun i -> Printf.sprintf "%02x" (Char.code s.[i])))

let of_hex h =
  String.init
    (String.length h / 2)
    (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2)))

(* Field values are pairwise distinct, so swapped fields change the result. A
   64-bit value is only used where the class has 64-bit words. *)
let word c hi lo = match c with Elf32 -> lo | Elf64 -> Int64.logor (Int64.shift_left hi 32) lo

let round_trip ?(guard = true) label size write read value ~pp =
  let b = Bytes.make (size + 8) '\xaa' in
  write b 4 value;
  let s = Bytes.to_string b in
  Check.equal ~pp (label ^ " round trip") value (read s 4);
  if guard then
    Check.equal ~pp:Format.pp_print_string (label ^ " guard bytes") "aaaaaaaaaaaaaaaa"
      (hex (String.sub s 0 4 ^ String.sub s (size + 4) 4))

let pp_any ppf _ = Format.pp_print_string ppf "<record>"

let header c e =
  {
    ident = { elf_class = c; endianness = e; osabi = 3; abiversion = 7 };
    e_type = 0x0102;
    e_machine = 0x0304;
    e_version = 1L;
    e_entry = word c 0x1122_3344L 0x5566_7788L;
    e_phoff = word c 0x2233_4455L 0x34L;
    e_shoff = word c 0x3344_5566L 0x9900_aabbL;
    e_flags = 0xccdd_eeffL;
    e_ehsize = 0x1011;
    e_phentsize = 0x1213;
    e_phnum = 0x1415;
    e_shentsize = 0x1617;
    e_shnum = 0x1819;
    e_shstrndx = 0x1a1b;
  }

let phdr c =
  {
    p_type = 0x1111_1111L;
    p_flags = 0x2222_2222L;
    p_offset = word c 0xa1L 0x3333_3333L;
    p_vaddr = word c 0xa2L 0x4444_4444L;
    p_paddr = word c 0xa3L 0x5555_5555L;
    p_filesz = word c 0xa4L 0x6666_6666L;
    p_memsz = word c 0xa5L 0x7777_7777L;
    p_align = word c 0xa6L 0x8888_8888L;
  }

let shdr c =
  {
    sh_name = 0x1111_1111L;
    sh_type = 0x2222_2222L;
    sh_flags = word c 0xb1L 0x3333_3333L;
    sh_addr = word c 0xb2L 0x4444_4444L;
    sh_offset = word c 0xb3L 0x5555_5555L;
    sh_size = word c 0xb4L 0x6666_6666L;
    sh_link = 0x7777_7777L;
    sh_info = 0x8888_8888L;
    sh_addralign = word c 0xb5L 0x9999_9999L;
    sh_entsize = word c 0xb6L 0xaaaa_aaaaL;
  }

let sym c =
  {
    st_name = 0x1122_3344L;
    st_info = 0x12;
    st_other = 0x03;
    st_shndx = 0x5566;
    st_value = word c 0xc1L 0x7788_99aaL;
    st_size = word c 0xc2L 0xbbcc_ddeeL;
  }

let rel c ~rela =
  {
    r_offset = word c 0xd1L 0x1234_5678L;
    r_sym = (match c with Elf32 -> 0xab_cdefL | Elf64 -> 0x9abc_def0L);
    r_type = (match c with Elf32 -> 0x12L | Elf64 -> 0x3456_789aL);
    r_addend =
      (if rela then Some (match c with Elf32 -> -4L | Elf64 -> -0x1234_5678_9abcL) else None);
  }

let () =
  Check.run "codec"
    [
      Check.case "header" (fun () ->
          each (fun label c e ->
              let h = header c e in
              (* The header is always at offset 0. *)
              let b = Bytes.make (Codec.ehdr_size c) '\xaa' in
              Codec.write_header b h;
              Check.equal ~pp:pp_any label h (Codec.read_header h.ident (Bytes.to_string b))));
      Check.case "phdr" (fun () ->
          each (fun label c e ->
              round_trip label (Codec.phdr_size c) (Codec.write_phdr c e) (Codec.read_phdr c e)
                (phdr c) ~pp:pp_any));
      Check.case "shdr" (fun () ->
          each (fun label c e ->
              round_trip label (Codec.shdr_size c) (Codec.write_shdr c e) (Codec.read_shdr c e)
                (shdr c) ~pp:pp_any));
      Check.case "sym" (fun () ->
          each (fun label c e ->
              round_trip label (Codec.sym_size c) (Codec.write_sym c e) (Codec.read_sym c e) (sym c)
                ~pp:pp_any));
      Check.case "rel and rela" (fun () ->
          each (fun label c e ->
              round_trip (label ^ " rel") (Codec.rel_size c) (Codec.write_rel c e)
                (Codec.read_rel ~rela:false c e) (rel c ~rela:false) ~pp:pp_any;
              round_trip (label ^ " rela") (Codec.rela_size c) (Codec.write_rel c e)
                (Codec.read_rel ~rela:true c e) (rel c ~rela:true) ~pp:pp_any));
      (* Hand-assembled from the gABI field tables, independent of the reader. *)
      Check.case "golden ELF32-LE phdr" (fun () ->
          let p =
            {
              p_type = 1L;
              p_offset = 0x1000L;
              p_vaddr = 0x40_0000L;
              p_paddr = 0x40_0000L;
              p_filesz = 0x200L;
              p_memsz = 0x300L;
              p_flags = 5L;
              p_align = 0x1000L;
            }
          in
          let b = Bytes.make 32 '\000' in
          Codec.write_phdr Elf32 Little b 0 p;
          Check.equal ~pp:Format.pp_print_string "bytes"
            ("01000000" ^ "00100000" ^ "00004000" ^ "00004000" ^ "00020000" ^ "00030000"
           ^ "05000000" ^ "00100000")
            (hex (Bytes.to_string b));
          Check.equal ~pp:pp_any "read" p
            (Codec.read_phdr Elf32 Little
               (of_hex "01000000001000000000400000004000000200000003000005000000"
               ^ of_hex "00100000")
               0));
      Check.case "golden ELF64-BE sym" (fun () ->
          let s =
            {
              st_name = 0x1122_3344L;
              st_info = 0x12;
              st_other = 3;
              st_shndx = 0x5566;
              st_value = 0x0102_0304_0506_0708L;
              st_size = 0x1112_1314_1516_1718L;
            }
          in
          let b = Bytes.make 24 '\000' in
          Codec.write_sym Elf64 Big b 0 s;
          Check.equal ~pp:Format.pp_print_string "bytes"
            ("11223344" ^ "12" ^ "03" ^ "5566" ^ "0102030405060708" ^ "1112131415161718")
            (hex (Bytes.to_string b)));
      Check.case "r_info packing" (fun () ->
          let word32 sym typ = { r_offset = 0L; r_sym = sym; r_type = typ; r_addend = None } in
          let b = Bytes.make 8 '\000' in
          Codec.write_rel Elf32 Little b 0 (word32 0xab_cdefL 0x12L);
          Check.equal ~pp:Format.pp_print_string "elf32 info" "12efcdab"
            (hex (Bytes.sub_string b 4 4));
          let b = Bytes.make 16 '\000' in
          Codec.write_rel Elf64 Big b 0 (word32 0x1234L 0x5678_9abcL);
          Check.equal ~pp:Format.pp_print_string "elf64 info" "0000123456789abc"
            (hex (Bytes.sub_string b 8 8)));
      Check.case "negative ELF32 addend" (fun () ->
          let r = { r_offset = 0L; r_sym = 0L; r_type = 0L; r_addend = Some (-4L) } in
          let b = Bytes.make 12 '\000' in
          Codec.write_rel Elf32 Little b 0 r;
          Check.equal ~pp:Format.pp_print_string "bytes" "fcffffff" (hex (Bytes.sub_string b 8 4));
          match (Codec.read_rel ~rela:true Elf32 Little (Bytes.to_string b) 0).r_addend with
          | Some a -> Check.equal ~pp:(fun ppf -> Format.fprintf ppf "%Ld") "addend" (-4L) a
          | None -> Check.fail "no addend");
    ]
