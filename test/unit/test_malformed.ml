[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Elf_test_support
open Elf
open Types
module F = Fixture
module Codec = Elf_test_support.Codec

let pp_any ppf _ = Format.pp_print_string ppf "<value>"
let bases = [ ("ELF32-LE", Elf32, Little); ("ELF64-BE", Elf64, Big) ]

(* No exception may escape the decoder, whatever the input. *)
let decode bytes =
  match Decode.of_string bytes with
  | r -> r
  | exception e -> Check.failf "exception escaped Decode.of_string: %s" (Printexc.to_string e)

let guard what f =
  match f () with
  | r -> r
  | exception e -> Check.failf "%s: exception escaped: %s" what (Printexc.to_string e)

let rejects what (pred : Decode.error -> bool) bytes =
  Check.error ~pp:pp_any what pred (guard what (fun () -> decode bytes))

(* An accessor failing on a file that still decodes. *)
let accessor_rejects what (pred : Decode.error -> bool) bytes f =
  match decode bytes with
  | Error _ -> Check.failf "%s: the file should decode" what
  | Ok d -> Check.error ~pp:pp_any what pred (guard what (fun () -> f d))

let case name f =
  Check.case name (fun () ->
      List.iter
        (fun (label, cls, endian) ->
          let base = F.minimal ~cls ~endian () in
          f label cls base)
        bases)

let sec bytes name =
  let d = Check.ok ~pp_error:Decode.pp_error "decode base" (Decode.of_string bytes) in
  match Decode.find_section d name with Some s -> s | None -> Check.failf "no %s" name

let () =
  Check.run "malformed"
    [
      case "truncated ident and header" (fun label cls base ->
          let truncated_at region n =
            rejects
              (Printf.sprintf "%s: truncate %d" label n)
              (function `Truncated { Decode.region = r; _ } -> r = region | _ -> false)
              (F.truncate n base)
          in
          truncated_at `Ident 3;
          truncated_at `Ident 15;
          truncated_at `Elf_header (Codec.ehdr_size cls - 1);
          truncated_at `Section_headers (String.length base - 1));
      case "bad ident" (fun label _ base ->
          rejects (label ^ " magic")
            (function `Bad_magic -> true | _ -> false)
            (F.set_u8 0 0 base);
          rejects (label ^ " class")
            (function `Bad_class 3 -> true | _ -> false)
            (F.set_u8 4 3 base);
          rejects (label ^ " class 0")
            (function `Bad_class 0 -> true | _ -> false)
            (F.set_u8 4 0 base);
          rejects (label ^ " data")
            (function `Bad_data_encoding 3 -> true | _ -> false)
            (F.set_u8 5 3 base);
          rejects (label ^ " version")
            (function `Bad_ident_version 2 -> true | _ -> false)
            (F.set_u8 6 2 base));
      case "section header table placement" (fun label cls base ->
          let len = Int64.of_int (String.length base) in
          rejects (label ^ " e_shoff at end")
            (function `Truncated { Decode.region = `Section_headers; _ } -> true | _ -> false)
            (F.with_header (fun h -> { h with e_shoff = len }) base);
          let huge = match cls with Elf64 -> 0xffff_ffff_ffff_fff0L | Elf32 -> 0xffff_fff0L in
          rejects (label ^ " e_shoff huge")
            (function
              | `Size_overflow `Section_headers -> cls = Elf64
              | `Truncated { Decode.region = `Section_headers; _ } -> cls = Elf32
              | _ -> false)
            (F.with_header (fun h -> { h with e_shoff = huge }) base);
          rejects (label ^ " e_shentsize")
            (function
              | `Bad_entry_size { Decode.table = `Section_headers; actual = 41; _ } -> true
              | _ -> false)
            (F.with_header (fun h -> { h with e_shentsize = 41 }) base);
          rejects
            (label ^ " e_shnum without table")
            (function `Section_headers_missing 5 -> true | _ -> false)
            (F.with_header (fun h -> { h with e_shoff = 0L; e_shnum = 5 }) base));
      case "program header table" (fun label _ base ->
          let len = Int64.of_int (String.length base) in
          rejects (label ^ " e_phoff at end")
            (function `Truncated { Decode.region = `Program_headers; _ } -> true | _ -> false)
            (F.with_header (fun h -> { h with e_phoff = len }) base);
          rejects (label ^ " e_phentsize")
            (function
              | `Bad_entry_size { Decode.table = `Program_headers; actual = 7; _ } -> true
              | _ -> false)
            (F.with_header (fun h -> { h with e_phentsize = 7 }) base);
          rejects
            (label ^ " extended count beyond the file")
            (function
              | `Truncated { Decode.region = `Program_headers; _ } -> true
              | `Size_overflow `Program_headers -> true
              | _ -> false)
            (base
            |> F.with_header (fun h -> { h with e_phnum = Const.pn_xnum })
            |> F.with_shdr 0 (fun sh -> { sh with sh_info = 0xffff_fff0L })));
      case "section name table" (fun label _ base ->
          let shnum = (Check.ok ~pp_error:Decode.pp_error "d" (Decode.of_string base)).shnum in
          rejects (label ^ " e_shstrndx = shnum")
            (function
              | `Bad_section_index { Decode.use = `Shstrndx; index; count } ->
                  index = Int64.of_int shnum && count = shnum
              | _ -> false)
            (F.with_header (fun h -> { h with e_shstrndx = shnum }) base);
          rejects
            (label ^ " sh_name past the table")
            (function
              | `Bad_string_offset { Decode.section = 6; offset = 0x1000L } -> true | _ -> false)
            (F.with_shdr 1 (fun sh -> { sh with sh_name = 0x1000L }) base);
          let shstrtab = sec base ".shstrtab" in
          let last =
            Int64.to_int shstrtab.shdr.sh_offset + Int64.to_int shstrtab.shdr.sh_size - 1
          in
          rejects (label ^ " unterminated names")
            (function `Unterminated_string { Decode.section = 6; _ } -> true | _ -> false)
            (F.set_u8 last (Char.code 'x') base);
          rejects (label ^ " .shstrtab too large")
            (function `Truncated { Decode.region = `Section 6; _ } -> true | _ -> false)
            (F.with_shdr 6 (fun sh -> { sh with sh_size = 0xffffL }) base));
      case "accessors" (fun label _ base ->
          let find name d = Option.get (Decode.find_section d name) in
          accessor_rejects
            (label ^ " symtab sh_link = self")
            (function `Wrong_section_type { Decode.section = 2; _ } -> true | _ -> false)
            (F.with_shdr 2 (fun sh -> { sh with sh_link = 2L }) base)
            (fun d -> Decode.symbols d (find ".symtab" d));
          accessor_rejects (label ^ " note descsz")
            (function `Bad_note (`Section 4) -> true | _ -> false)
            (F.set_u32 (Int64.to_int (sec base ".note.test").shdr.sh_offset + 4) 0xffff_ffffL base)
            (fun d -> Decode.notes d (`Section (find ".note.test" d)));
          accessor_rejects
            (label ^ " rela sh_link out of range")
            (function `Bad_section_index { Decode.use = `Link 5; _ } -> true | _ -> false)
            (F.with_shdr 5 (fun sh -> { sh with sh_link = 999L }) base)
            (fun d -> Decode.relocations d (find ".rela.text" d));
          accessor_rejects
            (label ^ " section past the end of the file")
            (function `Truncated { Decode.region = `Section 1; _ } -> true | _ -> false)
            (F.with_shdr 1 (fun sh -> { sh with sh_offset = 0xffff_0000L }) base)
            (fun d -> Decode.section_data d (find ".text" d));
          (* Only ELF64 has a word wide enough to overflow offset + size. *)
          if label = "ELF64-BE" then
            accessor_rejects
              (label ^ " section offset + size overflows")
              (function `Size_overflow (`Section 1) -> true | _ -> false)
              (F.with_shdr 1
                 (fun sh -> { sh with sh_offset = 0xffff_ffff_ffff_fff0L; sh_size = 0x100L })
                 base)
              (fun d -> Decode.section_data d (find ".text" d));
          accessor_rejects
            (label ^ " segment past the end of the file")
            (function `Truncated { Decode.region = `Segment 0; _ } -> true | _ -> false)
            (F.with_phdr 0 (fun p -> { p with p_filesz = 0x10_0000L }) base)
            (fun d -> Decode.segment_data d 0));
    ]
