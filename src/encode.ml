[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

open Types
open Err.Syntax

type record =
  [ `Header | `Program_header of int | `Section_header of int | `Symbol of int | `Relocation of int ]

type overflow = { record : record; field : string; value : int64; bits : int; signed : bool }
type error = [ `Field_overflow of overflow ]

let pp_record ppf = function
  | `Header -> Format.pp_print_string ppf "ELF header"
  | `Program_header i -> Format.fprintf ppf "program header %d" i
  | `Section_header i -> Format.fprintf ppf "section header %d" i
  | `Symbol i -> Format.fprintf ppf "symbol %d" i
  | `Relocation i -> Format.fprintf ppf "relocation %d" i

let pp_error ppf = function
  | `Field_overflow { record; field; value; bits; signed } ->
      Format.fprintf ppf "%a: %s = %Ld (0x%Lx) does not fit in %d %s bits" pp_record record field
        value value bits
        (if signed then "signed" else "unsigned")

let overflow record field bits ~signed value =
  Err.fail ~pos:__POS__ ~pp_error (`Field_overflow { record; field; value; bits; signed })

let check record (field, bits, value) =
  if U64.fits_bits bits value then Ok () else overflow record field bits ~signed:false value

let check_int record (field, bits, value) = check record (field, bits, Int64.of_int value)
let all record checks = Err.List.iter (check record) checks
let all_int record checks = Err.List.iter (check_int record) checks

let write_header b h =
  let wb = Codec.word_bits h.ident.elf_class in
  let* () =
    all_int `Header
      [
        ("ei_osabi", 8, h.ident.osabi);
        ("ei_abiversion", 8, h.ident.abiversion);
        ("e_type", 16, h.e_type);
        ("e_machine", 16, h.e_machine);
        ("e_ehsize", 16, h.e_ehsize);
        ("e_phentsize", 16, h.e_phentsize);
        ("e_phnum", 16, h.e_phnum);
        ("e_shentsize", 16, h.e_shentsize);
        ("e_shnum", 16, h.e_shnum);
        ("e_shstrndx", 16, h.e_shstrndx);
      ]
  in
  let+ () =
    all `Header
      [
        ("e_version", 32, h.e_version);
        ("e_entry", wb, h.e_entry);
        ("e_phoff", wb, h.e_phoff);
        ("e_shoff", wb, h.e_shoff);
        ("e_flags", 32, h.e_flags);
      ]
  in
  Codec.write_header b h

let write_phdr id b off ~index p =
  let wb = Codec.word_bits id.elf_class in
  let+ () =
    all (`Program_header index)
      [
        ("p_type", 32, p.p_type);
        ("p_flags", 32, p.p_flags);
        ("p_offset", wb, p.p_offset);
        ("p_vaddr", wb, p.p_vaddr);
        ("p_paddr", wb, p.p_paddr);
        ("p_filesz", wb, p.p_filesz);
        ("p_memsz", wb, p.p_memsz);
        ("p_align", wb, p.p_align);
      ]
  in
  Codec.write_phdr id.elf_class id.endianness b off p

let write_shdr id b off ~index sh =
  let wb = Codec.word_bits id.elf_class in
  let+ () =
    all (`Section_header index)
      [
        ("sh_name", 32, sh.sh_name);
        ("sh_type", 32, sh.sh_type);
        ("sh_flags", wb, sh.sh_flags);
        ("sh_addr", wb, sh.sh_addr);
        ("sh_offset", wb, sh.sh_offset);
        ("sh_size", wb, sh.sh_size);
        ("sh_link", 32, sh.sh_link);
        ("sh_info", 32, sh.sh_info);
        ("sh_addralign", wb, sh.sh_addralign);
        ("sh_entsize", wb, sh.sh_entsize);
      ]
  in
  Codec.write_shdr id.elf_class id.endianness b off sh

let write_sym id b off ~index s =
  let wb = Codec.word_bits id.elf_class in
  let* () =
    all_int (`Symbol index)
      [ ("st_info", 8, s.st_info); ("st_other", 8, s.st_other); ("st_shndx", 16, s.st_shndx) ]
  in
  let+ () =
    all (`Symbol index)
      [ ("st_name", 32, s.st_name); ("st_value", wb, s.st_value); ("st_size", wb, s.st_size) ]
  in
  Codec.write_sym id.elf_class id.endianness b off s

let check_addend index c a =
  match c with
  | Elf64 -> Ok ()
  | Elf32 ->
      if Int64.compare a (-0x8000_0000L) >= 0 && Int64.compare a 0x7fff_ffffL <= 0 then Ok ()
      else overflow (`Relocation index) "r_addend" 32 ~signed:true a

let write_rel id b off ~index r =
  let c = id.elf_class in
  let sym_bits, type_bits = match c with Elf32 -> (24, 8) | Elf64 -> (32, 32) in
  let* () =
    all (`Relocation index)
      [
        ("r_offset", Codec.word_bits c, r.r_offset);
        ("r_sym", sym_bits, r.r_sym);
        ("r_type", type_bits, r.r_type);
      ]
  in
  let+ () = match r.r_addend with None -> Ok () | Some a -> check_addend index c a in
  Codec.write_rel c id.endianness b off r
