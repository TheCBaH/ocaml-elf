[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Types
open Err.Syntax

type region =
  [ `Ident | `Elf_header | `Program_headers | `Section_headers | `Section of int | `Segment of int ]

type truncated = { region : region; offset : int64; size : int64; available : int }
type entry_size = { table : region; expected : int; actual : int }
type index_use = [ `Shstrndx | `Link of int | `Symbol_section of int * int ]
type bad_index = { use : index_use; index : int64; count : int }
type string_ref = { section : int; offset : int64 }
type wrong_type = { section : int; expected : int64 list; actual : int64 }
type bad_segment = { segment : int; count : int }

type error =
  [ `Bad_magic
  | `Bad_class of int
  | `Bad_data_encoding of int
  | `Bad_ident_version of int
  | `Truncated of truncated
  | `Size_overflow of region
  | `Bad_entry_size of entry_size
  | `Section_headers_missing of int
  | `Bad_section_index of bad_index
  | `Bad_string_offset of string_ref
  | `Unterminated_string of string_ref
  | `Wrong_section_type of wrong_type
  | `Bad_segment_index of bad_segment
  | `Bad_note of region
  | Attributes.error ]

let pp_region ppf = function
  | `Ident -> Format.pp_print_string ppf "e_ident"
  | `Elf_header -> Format.pp_print_string ppf "ELF header"
  | `Program_headers -> Format.pp_print_string ppf "program header table"
  | `Section_headers -> Format.pp_print_string ppf "section header table"
  | `Section i -> Format.fprintf ppf "section %d" i
  | `Segment i -> Format.fprintf ppf "segment %d" i

let pp_use ppf = function
  | `Shstrndx -> Format.pp_print_string ppf "e_shstrndx"
  | `Link i -> Format.fprintf ppf "sh_link of section %d" i
  | `Symbol_section (s, i) -> Format.fprintf ppf "section index of symbol %d in section %d" i s

let pp_error ppf : error -> unit = function
  | `Bad_magic -> Format.pp_print_string ppf "not an ELF file (bad magic)"
  | `Bad_class c -> Format.fprintf ppf "unknown ELF class %d" c
  | `Bad_data_encoding d -> Format.fprintf ppf "unknown ELF data encoding %d" d
  | `Bad_ident_version v -> Format.fprintf ppf "unsupported EI_VERSION %d" v
  | `Truncated { region; offset; size; available } ->
      Format.fprintf ppf "%a at offset %a, size %a, extends past the %d-byte input" pp_region region
        U64.pp offset U64.pp size available
  | `Size_overflow r -> Format.fprintf ppf "%a: offset + size overflows" pp_region r
  | `Bad_entry_size { table; expected; actual } ->
      Format.fprintf ppf "%a: entry size %d, expected %d" pp_region table actual expected
  | `Section_headers_missing n -> Format.fprintf ppf "e_shnum is %d but e_shoff is 0" n
  | `Bad_section_index { use; index; count } ->
      Format.fprintf ppf "%a = %Lu is not a section index (%d sections)" pp_use use index count
  | `Bad_string_offset { section; offset } ->
      Format.fprintf ppf "string offset %a is outside string table %d" U64.pp offset section
  | `Unterminated_string { section; offset } ->
      Format.fprintf ppf "string at offset %a in section %d is not NUL-terminated" U64.pp offset
        section
  | `Wrong_section_type { section; expected; actual } ->
      Format.fprintf ppf "section %d has type 0x%Lx, expected one of [%a]" section actual
        (Format.pp_print_list
           ~pp_sep:(fun ppf () -> Format.pp_print_string ppf ", ")
           (fun ppf v -> Format.fprintf ppf "0x%Lx" v))
        expected
  | `Bad_segment_index { segment; count } ->
      Format.fprintf ppf "segment %d does not exist (%d segments)" segment count
  | `Bad_note r -> Format.fprintf ppf "%a: malformed note" pp_region r
  | #Attributes.error as e -> Attributes.pp_error ppf e

let fail e = Err.fail ~pos:__POS__ ~pp_error e

type section = { index : int; name : string; shdr : shdr }

type t = {
  data : string;
  header : header;
  phnum : int;
  shnum : int;
  shstrndx : int;
  phdrs : phdr array;
  sections : section array;
}

(* The one place a file offset becomes a native index: only after the whole
   extent is known to lie inside the input. *)
let extent data region ~offset ~size =
  let available = String.length data in
  match U64.add offset size with
  | None -> fail (`Size_overflow region)
  | Some stop when U64.le stop (Int64.of_int available) ->
      Ok (Int64.to_int offset, Int64.to_int size)
  | Some _ -> fail (`Truncated { region; offset; size; available })

let table data region ~offset ~count ~entsize =
  match U64.mul (Int64.of_int count) (Int64.of_int entsize) with
  | None -> fail (`Size_overflow region)
  | Some size -> extent data region ~offset ~size

let parse_ident data =
  let* _ = extent data `Ident ~offset:0L ~size:(Int64.of_int Codec.ei_nident) in
  let* () =
    Err.guard ~pos:__POS__ ~pp_error ~error:`Bad_magic (String.sub data 0 4 = Codec.magic)
  in
  let* elf_class =
    match Codec.get_u8 data 4 with 1 -> Ok Elf32 | 2 -> Ok Elf64 | c -> fail (`Bad_class c)
  in
  let* endianness =
    match Codec.get_u8 data 5 with 1 -> Ok Little | 2 -> Ok Big | d -> fail (`Bad_data_encoding d)
  in
  let* () = match Codec.get_u8 data 6 with 1 -> Ok () | v -> fail (`Bad_ident_version v) in
  Ok { elf_class; endianness; osabi = Codec.get_u8 data 7; abiversion = Codec.get_u8 data 8 }

let count_of region v =
  match U64.to_int v with Some n -> Ok n | None -> fail (`Size_overflow region)

let check_entsize table ~expected ~actual =
  if expected = actual then Ok () else fail (`Bad_entry_size { table; expected; actual })

(* Section header 0 carries the real counts under extended numbering. *)
let section_headers data (h : header) =
  let c = h.ident.elf_class and e = h.ident.endianness in
  let entsize = Codec.shdr_size c in
  if h.e_shoff = 0L then
    if h.e_shnum <> 0 then fail (`Section_headers_missing h.e_shnum) else Ok [||]
  else
    let* () = check_entsize `Section_headers ~expected:entsize ~actual:h.e_shentsize in
    let* off0, _ = table data `Section_headers ~offset:h.e_shoff ~count:1 ~entsize in
    let sh0 = Codec.read_shdr c e data off0 in
    let* shnum = if h.e_shnum = 0 then count_of `Section_headers sh0.sh_size else Ok h.e_shnum in
    let* off, _ = table data `Section_headers ~offset:h.e_shoff ~count:shnum ~entsize in
    Ok (Array.init shnum (fun i -> Codec.read_shdr c e data (off + (i * entsize))))

let raw_bytes data region ~offset ~size =
  let+ off, len = extent data region ~offset ~size in
  String.sub data off len

let shdr_bytes data i (sh : shdr) =
  if sh.sh_type = Const.sht_nobits then Ok ""
  else raw_bytes data (`Section i) ~offset:sh.sh_offset ~size:sh.sh_size

let cstring ~section bytes offset =
  match U64.to_int offset with
  | Some o when o < String.length bytes -> (
      match String.index_from_opt bytes o '\000' with
      | Some stop -> Ok (String.sub bytes o (stop - o))
      | None -> fail (`Unterminated_string { section; offset }))
  | _ -> fail (`Bad_string_offset { section; offset })

let section_index use count v =
  match U64.to_int v with
  | Some i when i < count -> Ok i
  | _ -> fail (`Bad_section_index { use; index = v; count })

let of_string data =
  let* ident = parse_ident data in
  let c = ident.elf_class and e = ident.endianness in
  let* _ = extent data `Elf_header ~offset:0L ~size:(Int64.of_int (Codec.ehdr_size c)) in
  let header = Codec.read_header ident data in
  let* shdrs = section_headers data header in
  let shnum = Array.length shdrs in
  let* phnum =
    if header.e_phnum = Const.pn_xnum && shnum > 0 then count_of `Program_headers shdrs.(0).sh_info
    else Ok header.e_phnum
  in
  let* phdrs =
    if phnum = 0 then Ok [||]
    else
      let entsize = Codec.phdr_size c in
      let* () = check_entsize `Program_headers ~expected:entsize ~actual:header.e_phentsize in
      let+ off, _ = table data `Program_headers ~offset:header.e_phoff ~count:phnum ~entsize in
      Array.init phnum (fun i -> Codec.read_phdr c e data (off + (i * entsize)))
  in
  let* shstrndx =
    if shnum = 0 then Ok 0
    else if header.e_shstrndx = Const.shn_xindex then
      section_index `Shstrndx shnum shdrs.(0).sh_link
    else section_index `Shstrndx shnum (Int64.of_int header.e_shstrndx)
  in
  let* sections =
    if shstrndx = 0 then Ok (Array.mapi (fun index shdr -> { index; name = ""; shdr }) shdrs)
    else
      let* () =
        if shdrs.(shstrndx).sh_type = Const.sht_strtab then Ok ()
        else
          fail
            (`Wrong_section_type
               {
                 section = shstrndx;
                 expected = [ Const.sht_strtab ];
                 actual = shdrs.(shstrndx).sh_type;
               })
      in
      let* strtab = shdr_bytes data shstrndx shdrs.(shstrndx) in
      (* A self-recursive loop with explicit matches rather than a monadic one: a
         file can have 64K sections and js_of_ocaml does not optimize the tail call
         through a bind. *)
      let rec name_from index acc =
        if index = shnum then Ok (Array.of_list (List.rev acc))
        else
          let shdr = shdrs.(index) in
          match cstring ~section:shstrndx strtab shdr.sh_name with
          | Error _ as e -> e
          | Ok name -> name_from (index + 1) ({ index; name; shdr } :: acc)
      in
      name_from 0 []
  in
  Ok { data; header; phnum; shnum; shstrndx; phdrs; sections }

let find_section t name =
  Array.fold_left
    (fun acc s -> match acc with Some _ -> acc | None -> if s.name = name then Some s else None)
    None t.sections

let section_data t s = shdr_bytes t.data s.index s.shdr

let segment t i =
  if i >= 0 && i < t.phnum then Ok t.phdrs.(i)
  else fail (`Bad_segment_index { segment = i; count = t.phnum })

let segment_data t i =
  let* p = segment t i in
  raw_bytes t.data (`Segment i) ~offset:p.p_offset ~size:p.p_filesz

let expect_type (s : section) expected =
  if List.mem s.shdr.sh_type expected then Ok ()
  else fail (`Wrong_section_type { section = s.index; expected; actual = s.shdr.sh_type })

let string_at t s offset =
  let* () = expect_type s [ Const.sht_strtab ] in
  let* bytes = section_data t s in
  cstring ~section:s.index bytes offset

let linked t (s : section) =
  let+ i = section_index (`Link s.index) t.shnum s.shdr.sh_link in
  t.sections.(i)

(* A fixed-size entry table: entsize must match when the file states one, and
   the section size must hold a whole number of entries. *)
let entries t (s : section) ~entsize =
  let* () =
    if s.shdr.sh_entsize = 0L || s.shdr.sh_entsize = Int64.of_int entsize then Ok ()
    else
      check_entsize (`Section s.index) ~expected:entsize
        ~actual:(Option.value (U64.to_int s.shdr.sh_entsize) ~default:max_int)
  in
  let* bytes = section_data t s in
  if String.length bytes mod entsize <> 0 then
    fail
      (`Bad_entry_size
         { table = `Section s.index; expected = entsize; actual = String.length bytes })
  else Ok (bytes, String.length bytes / entsize)

type symbol = { sym_index : int; sym_name : string; sym : sym; shndx : int64 }

let symbols t s =
  let c = t.header.ident.elf_class and e = t.header.ident.endianness in
  let* () = expect_type s [ Const.sht_symtab; Const.sht_dynsym ] in
  let entsize = Codec.sym_size c in
  let* bytes, count = entries t s ~entsize in
  let* strtab = linked t s in
  let* () = expect_type strtab [ Const.sht_strtab ] in
  let* strings = section_data t strtab in
  let xindex =
    Array.fold_left
      (fun acc (x : section) ->
        if x.shdr.sh_type = Const.sht_symtab_shndx && x.shdr.sh_link = Int64.of_int s.index then
          Some x
        else acc)
      None t.sections
  in
  let* xbytes =
    match xindex with
    | None -> Ok None
    | Some x ->
        let+ b, n = entries t x ~entsize:4 in
        Some (b, n)
  in
  let+ syms =
    Err.List.map
      (fun i ->
        let sym = Codec.read_sym c e bytes (i * entsize) in
        let* sym_name = cstring ~section:strtab.index strings sym.st_name in
        let+ shndx =
          if sym.st_shndx <> Const.shn_xindex then Ok (Int64.of_int sym.st_shndx)
          else
            match xbytes with
            | Some (b, n) when i < n -> Ok (Codec.get_u32 e b (4 * i))
            | _ ->
                fail
                  (`Bad_section_index
                     {
                       use = `Symbol_section (s.index, i);
                       index = Int64.of_int sym.st_shndx;
                       count = t.shnum;
                     })
        in
        { sym_index = i; sym_name; sym; shndx })
      (List.init count Fun.id)
  in
  Array.of_list syms

let relocations t s =
  let c = t.header.ident.elf_class and e = t.header.ident.endianness in
  let* () = expect_type s [ Const.sht_rel; Const.sht_rela ] in
  let rela = s.shdr.sh_type = Const.sht_rela in
  let entsize = if rela then Codec.rela_size c else Codec.rel_size c in
  let* bytes, count = entries t s ~entsize in
  let+ _ = linked t s in
  Array.init count (fun i -> Codec.read_rel ~rela c e bytes (i * entsize))

type note = { n_type : int64; n_name : string; n_desc : string }

(* The name is padded to 4 bytes and the descriptor to the note alignment: 4, or 8 for an 8-aligned
   section or segment (.note.gnu.property on ELF64), which is how binutils reads them too. *)
let parse_notes region e ~align bytes =
  let len = String.length bytes in
  let pad_to a n = (n + a - 1) land lnot (a - 1) in
  let bad () = fail (`Bad_note region) in
  let rec go off acc =
    if off = len then Ok (List.rev acc)
    else if len - off < 12 then bad ()
    else
      let field i = U64.to_int (Codec.get_u32 e bytes (off + i)) in
      match (field 0, field 4) with
      | Some namesz, Some descsz ->
          let name_off = off + 12 in
          let desc_off = name_off + pad_to 4 namesz in
          let next = desc_off + pad_to align descsz in
          if namesz > len || descsz > len || desc_off > len || next > len then bad ()
          else
            let n_name =
              (* namesz counts the terminating NUL. *)
              let raw = String.sub bytes name_off namesz in
              match String.index_opt raw '\000' with Some i -> String.sub raw 0 i | None -> raw
            in
            let n_type = Codec.get_u32 e bytes (off + 8) in
            go next ({ n_type; n_name; n_desc = String.sub bytes desc_off descsz } :: acc)
      | _ -> bad ()
  in
  go 0 []

let notes t where =
  let e = t.header.ident.endianness in
  match where with
  | `Section s ->
      let* () = expect_type s [ Const.sht_note ] in
      let* bytes = section_data t s in
      parse_notes (`Section s.index) e ~align:(if s.shdr.sh_addralign = 8L then 8 else 4) bytes
  | `Segment i ->
      let* p = segment t i in
      let* bytes = segment_data t i in
      parse_notes (`Segment i) e ~align:(if p.p_align = 8L then 8 else 4) bytes

let attributes t s =
  let* () = expect_type s [ Const.sht_riscv_attributes ] in
  let* bytes = section_data t s in
  (Attributes.decode t.header.ident.endianness bytes :> (Attributes.t, error) Err.t)
