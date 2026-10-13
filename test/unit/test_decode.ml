[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Elf_test_support
open Elf
module Codec = Elf_test_support.Codec
open Types

let pp_any ppf _ = Format.pp_print_string ppf "<value>"
let pp_i64 ppf v = Format.fprintf ppf "%Ld" v
let pp_int ppf v = Format.fprintf ppf "%d" v
let ok what r = Check.ok ~pp_error:Decode.pp_error what r
let dec bytes = ok "decode" (Decode.of_string bytes)

let sec d name =
  match Decode.find_section d name with Some s -> s | None -> Check.failf "no section %s" name

let fails what (pred : Decode.error -> bool) (r : (_, Decode.error) Err.t) =
  Check.error ~pp:pp_any what pred r

let variants = [ ("ELF32-LE", Elf32, Little); ("ELF64-BE", Elf64, Big) ]

let each f =
  List.iter
    (fun (label, cls, endian) -> f label (Fixture.minimal ~cls ~endian ()) cls endian)
    variants

let () =
  Check.run "decode"
    [
      Check.case "header and tables" (fun () ->
          each (fun label bytes cls _ ->
              let d = dec bytes in
              Check.equal ~pp:pp_int (label ^ " shnum") 7 d.shnum;
              Check.equal ~pp:pp_int (label ^ " phnum") 2 d.phnum;
              Check.equal ~pp:pp_int (label ^ " shstrndx") Fixture.shstrtab_index d.shstrndx;
              Check.equal ~pp:pp_i64 (label ^ " entry") 0x1000L d.header.e_entry;
              Check.equal ~pp:pp_class (label ^ " class") cls d.header.ident.elf_class;
              Check.equal ~pp:Format.pp_print_string (label ^ " names")
                ".text .symtab .strtab .note.test .rela.text .shstrtab"
                (String.concat " "
                   (List.tl
                      (List.map (fun (s : Decode.section) -> s.name) (Array.to_list d.sections))))));
      Check.case "section and segment data" (fun () ->
          each (fun label bytes _ _ ->
              let d = dec bytes in
              Check.bytes_equal (label ^ " .text") (String.make 16 '\x90')
                (ok "text" (Decode.section_data d (sec d ".text")));
              Check.bytes_equal (label ^ " segment 0") (String.make 16 '\x90')
                (ok "segment" (Decode.segment_data d 0))));
      Check.case "NOBITS has no file data" (fun () ->
          let bytes =
            Fixture.build Elf32 Little [ Fixture.sect ".bss" Const.sht_nobits "" ~size:0x1000L ]
          in
          let d = dec bytes in
          let s = sec d ".bss" in
          Check.equal ~pp:pp_i64 "size" 0x1000L s.shdr.sh_size;
          Check.equal ~pp:Format.pp_print_string "data" "" (ok "data" (Decode.section_data d s)));
      Check.case "string_at" (fun () ->
          each (fun label bytes _ _ ->
              let d = dec bytes in
              let strtab = sec d ".strtab" in
              Check.equal ~pp:Format.pp_print_string (label ^ " 1") "main"
                (ok "1" (Decode.string_at d strtab 1L));
              Check.equal ~pp:Format.pp_print_string (label ^ " 0") ""
                (ok "0" (Decode.string_at d strtab 0L));
              fails (label ^ " past the table")
                (function `Bad_string_offset { section = 3; offset = 99L } -> true | _ -> false)
                (Decode.string_at d strtab 99L);
              fails (label ^ " not a string table")
                (function `Wrong_section_type { section = 1; _ } -> true | _ -> false)
                (Decode.string_at d (sec d ".text") 0L)));
      Check.case "symbols" (fun () ->
          each (fun label bytes _ _ ->
              let d = dec bytes in
              let syms = ok "symbols" (Decode.symbols d (sec d ".symtab")) in
              Check.equal ~pp:pp_int (label ^ " count") 3 (Array.length syms);
              Check.equal ~pp:Format.pp_print_string (label ^ " names") "|data|main"
                (String.concat "|"
                   (List.map (fun (s : Decode.symbol) -> s.sym_name) (Array.to_list syms)));
              let main = syms.(2) in
              Check.equal ~pp:pp_int (label ^ " global info")
                (st_info ~bind:Const.stb_global ~typ:Const.stt_func)
                main.sym.st_info;
              Check.equal ~pp:pp_i64 (label ^ " size") 8L main.sym.st_size;
              Check.equal ~pp:pp_i64 (label ^ " shndx") 1L main.shndx;
              Check.equal ~pp:pp_i64 (label ^ " local value") 0x10L syms.(1).sym.st_value));
      Check.case "relocations" (fun () ->
          each (fun label bytes _ _ ->
              let d = dec bytes in
              let rels = ok "rela" (Decode.relocations d (sec d ".rela.text")) in
              Check.equal ~pp:pp_int (label ^ " count") 1 (Array.length rels);
              let r = rels.(0) in
              Check.equal ~pp:pp_i64 (label ^ " offset") 4L r.r_offset;
              Check.equal ~pp:pp_i64 (label ^ " sym") 2L r.r_sym;
              Check.equal ~pp:pp_i64 (label ^ " type") 5L r.r_type;
              Check.equal
                ~pp:(fun ppf -> function
                  | Some v -> pp_i64 ppf v | None -> Format.pp_print_string ppf "none")
                (label ^ " addend") (Some (-4L)) r.r_addend));
      Check.case "notes" (fun () ->
          each (fun label bytes _ _ ->
              let d = dec bytes in
              let expected =
                [ { Decode.n_type = 1L; n_name = "GNU"; n_desc = "\001\002\003\004" } ]
              in
              Check.equal ~pp:pp_any (label ^ " section") expected
                (ok "section" (Decode.notes d (`Section (sec d ".note.test"))));
              Check.equal ~pp:pp_any (label ^ " segment") expected
                (ok "segment" (Decode.notes d (`Segment 1)))));
      Check.case "8-aligned notes pad the descriptor to 8, the name to 4" (fun () ->
          (* Two .note.gnu.property-style notes: header, "GNU\000" (4, no padding), a 12-byte
             descriptor padded to 16, then a 16-byte one. *)
          List.iter
            (fun (label, cls, endian) ->
              let w v =
                let b = Bytes.create 4 in
                Codec.set_u32 endian b 0 v;
                Bytes.to_string b
              in
              let note ty desc pad =
                w 4L
                ^ w (Int64.of_int (String.length desc))
                ^ w ty ^ "GNU\000" ^ desc ^ String.make pad '\000'
              in
              let data = note 5L (String.make 12 'a') 4 ^ note 5L (String.make 16 'b') 0 in
              let bytes =
                Fixture.build cls endian
                  [ Fixture.sect ".note.gnu.property" Const.sht_note data ~align:8L ]
              in
              let d = dec bytes in
              let notes = ok "notes" (Decode.notes d (`Section (sec d ".note.gnu.property"))) in
              Check.equal ~pp:pp_int (label ^ " count") 2 (List.length notes);
              Check.equal ~pp:Format.pp_print_string (label ^ " second descriptor")
                (String.make 16 'b') (List.nth notes 1).n_desc)
            variants);
      Check.case "extended numbering" (fun () ->
          let bytes = Fixture.many_sections 0xff0e in
          let h = Fixture.header bytes in
          Check.equal ~pp:pp_int "e_shnum" 0 h.e_shnum;
          Check.equal ~pp:pp_int "e_shstrndx" Const.shn_xindex h.e_shstrndx;
          let d = dec bytes in
          Check.equal ~pp:pp_int "shnum" 0xff10 d.shnum;
          Check.equal ~pp:pp_int "shstrndx" 0xff0f d.shstrndx;
          Check.equal ~pp:Format.pp_print_string "name" "s4" d.sections.(5).name;
          Check.equal ~pp:Format.pp_print_string "last" ".shstrtab" d.sections.(0xff0f).name);
      Check.case "extended program header count" (fun () ->
          let bytes =
            Fixture.minimal ()
            |> Fixture.with_header (fun h -> { h with e_phnum = Const.pn_xnum })
            |> Fixture.with_shdr 0 (fun sh -> { sh with sh_info = 2L })
          in
          Check.equal ~pp:pp_int "phnum" 2 (dec bytes).phnum);
      Check.case "sectionless file" (fun () ->
          let bytes =
            Fixture.minimal ()
            |> Fixture.with_header (fun h -> { h with e_shoff = 0L; e_shnum = 0; e_shstrndx = 0 })
          in
          let d = dec bytes in
          Check.equal ~pp:pp_int "shnum" 0 d.shnum;
          Check.equal ~pp:pp_int "phnum" 2 d.phnum;
          Check.bytes_equal "segment" (String.make 16 '\x90')
            (ok "segment" (Decode.segment_data d 0)));
      Check.case "accessor errors" (fun () ->
          each (fun label bytes cls _ ->
              let d = dec bytes in
              let symtab = sec d ".symtab" in
              fails (label ^ " symbols on .strtab")
                (function `Wrong_section_type { section = 3; _ } -> true | _ -> false)
                (Decode.symbols d (sec d ".strtab"));
              fails (label ^ " relocations on .text")
                (function `Wrong_section_type { section = 1; _ } -> true | _ -> false)
                (Decode.relocations d (sec d ".text"));
              fails (label ^ " bad segment")
                (function `Bad_segment_index { segment = 5; count = 2 } -> true | _ -> false)
                (Decode.segment_data d 5);
              fails (label ^ " bad segment, notes")
                (function `Bad_segment_index _ -> true | _ -> false)
                (Decode.notes d (`Segment 2));
              (* sh_entsize must match the class's symbol size. *)
              let wrong_entsize =
                Fixture.with_shdr 2 (fun sh -> { sh with sh_entsize = 20L }) bytes
              in
              let d' = dec wrong_entsize in
              fails (label ^ " entsize")
                (function
                  | `Bad_entry_size { table = `Section 2; expected; actual = 20 } ->
                      expected = Codec.sym_size cls
                  | _ -> false)
                (Decode.symbols d' (sec d' ".symtab"));
              (* A section size that is not a whole number of entries. *)
              let ragged =
                Fixture.with_shdr 2
                  (fun sh -> { sh with sh_size = Int64.add symtab.shdr.sh_size 1L })
                  bytes
              in
              let d' = dec ragged in
              fails (label ^ " ragged")
                (function `Bad_entry_size { table = `Section 2; _ } -> true | _ -> false)
                (Decode.symbols d' (sec d' ".symtab"));
              let bad_link = Fixture.with_shdr 2 (fun sh -> { sh with sh_link = 999L }) bytes in
              let d' = dec bad_link in
              fails (label ^ " sh_link")
                (function
                  | `Bad_section_index { use = `Link 2; index = 999L; count = 7 } -> true
                  | _ -> false)
                (Decode.symbols d' (sec d' ".symtab"));
              let off = Int64.to_int symtab.shdr.sh_offset in
              let xindex_sym =
                (* st_shndx of symbol 2 := SHN_XINDEX; the file has no SHT_SYMTAB_SHNDX. *)
                let shndx_off = match cls with Elf32 -> 14 | Elf64 -> 6 in
                Fixture.set_u16 (off + (2 * Codec.sym_size cls) + shndx_off) Const.shn_xindex bytes
              in
              let d' = dec xindex_sym in
              fails (label ^ " XINDEX without table")
                (function
                  | `Bad_section_index { use = `Symbol_section (2, 2); _ } -> true | _ -> false)
                (Decode.symbols d' (sec d' ".symtab"));
              let note_off = Int64.to_int (sec d ".note.test").shdr.sh_offset in
              let bad_note = Fixture.set_u32 note_off 0x1000L bytes in
              let d' = dec bad_note in
              fails (label ^ " note namesz")
                (function `Bad_note (`Section 4) -> true | _ -> false)
                (Decode.notes d' (`Section (sec d' ".note.test")))));
      Check.case "symbols through SHT_SYMTAB_SHNDX" (fun () ->
          List.iter
            (fun (label, cls, endian) ->
              let word v =
                let b = Bytes.create 4 in
                Codec.set_u32 endian b 0 v;
                Bytes.to_string b
              in
              let sym i =
                let b = Bytes.make (Codec.sym_size cls) '\000' in
                Codec.write_sym cls endian b 0
                  {
                    st_name = 0L;
                    st_info = 0;
                    st_other = 0;
                    st_shndx = (if i = 1 then Const.shn_xindex else 0);
                    st_value = 0L;
                    st_size = 0L;
                  };
                Bytes.to_string b
              in
              let bytes =
                Fixture.build cls endian
                  [
                    Fixture.sect ".symtab" Const.sht_symtab
                      (sym 0 ^ sym 1)
                      ~link:2
                      ~entsize:(Int64.of_int (Codec.sym_size cls));
                    Fixture.sect ".strtab" Const.sht_strtab "\000";
                    Fixture.sect ".symtab_shndx" Const.sht_symtab_shndx
                      (word 0L ^ word 0x12345L)
                      ~link:1 ~entsize:4L;
                  ]
              in
              let d = dec bytes in
              let syms = ok "symbols" (Decode.symbols d (sec d ".symtab")) in
              Check.equal ~pp:pp_i64 label 0x12345L syms.(1).shndx)
            variants);
      Check.case "attributes" (fun () ->
          List.iter
            (fun (label, cls, endian) ->
              let attrs =
                [
                  {
                    Attributes.vendor = "riscv";
                    contents = `Parsed [ (Attributes.File, [ (5, Attributes.Ntbs "rv32i2p0") ]) ];
                  };
                ]
              in
              let data =
                Check.ok ~pp_error:Attributes.pp_error "encode" (Attributes.encode endian attrs)
              in
              let bytes =
                Fixture.build cls endian
                  [
                    Fixture.sect ".riscv.attributes" Const.sht_riscv_attributes data;
                    Fixture.sect ".bad.attributes" Const.sht_riscv_attributes "B";
                  ]
              in
              let d = dec bytes in
              Check.equal ~pp:pp_any label attrs
                (ok "attributes" (Decode.attributes d (sec d ".riscv.attributes")));
              fails (label ^ " bad contents")
                (function `Bad_format_version 0x42 -> true | _ -> false)
                (Decode.attributes d (sec d ".bad.attributes"));
              let d' = dec (Fixture.minimal ~cls ~endian ()) in
              fails (label ^ " wrong type")
                (function `Wrong_section_type { section = 1; _ } -> true | _ -> false)
                (Decode.attributes d' (sec d' ".text")))
            variants);
      Check.case "section name table must be a string table" (fun () ->
          let bytes =
            Fixture.minimal ()
            |> Fixture.with_shdr Fixture.shstrtab_index (fun sh ->
                { sh with sh_type = Const.sht_progbits })
          in
          fails "shstrtab type"
            (function `Wrong_section_type { section = 6; _ } -> true | _ -> false)
            (Decode.of_string bytes));
    ]
