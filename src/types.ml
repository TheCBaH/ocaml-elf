(* Semantic records shared by the decoder, the encoder and the executable
   builder. Field names follow the ELF specification. Values narrower than 32
   bits are [int]; everything else is an [int64] bit pattern (see U64), so a
   numeric field outside the named constants is kept rather than rejected. *)

type elf_class = Elf32 | Elf64
type endianness = Little | Big
type ident = { elf_class : elf_class; endianness : endianness; osabi : int; abiversion : int }

type header = {
  ident : ident;
  e_type : int;
  e_machine : int;
  e_version : int64;
  e_entry : int64;
  e_phoff : int64;
  e_shoff : int64;
  e_flags : int64;
  e_ehsize : int;
  e_phentsize : int;
  e_phnum : int;
  e_shentsize : int;
  e_shnum : int;
  e_shstrndx : int;
}
(** [e_phnum], [e_shnum] and [e_shstrndx] are the raw header fields; with extended numbering the
    real counts live in section header 0 (see {!Decode.t}). *)

type phdr = {
  p_type : int64;
  p_flags : int64;
  p_offset : int64;
  p_vaddr : int64;
  p_paddr : int64;
  p_filesz : int64;
  p_memsz : int64;
  p_align : int64;
}

type shdr = {
  sh_name : int64;
  sh_type : int64;
  sh_flags : int64;
  sh_addr : int64;
  sh_offset : int64;
  sh_size : int64;
  sh_link : int64;
  sh_info : int64;
  sh_addralign : int64;
  sh_entsize : int64;
}

type sym = {
  st_name : int64;
  st_info : int;
  st_other : int;
  st_shndx : int;
  st_value : int64;
  st_size : int64;
}

type rel = { r_offset : int64; r_sym : int64; r_type : int64; r_addend : int64 option }
(** [r_addend] is [None] for [SHT_REL] entries. [r_sym]/[r_type] are already split according to
    the file class. *)

let st_bind info = info lsr 4
let st_type info = info land 0xf
let st_info ~bind ~typ = (bind lsl 4) lor (typ land 0xf)

let pp_class ppf = function
  | Elf32 -> Format.pp_print_string ppf "ELF32"
  | Elf64 -> Format.pp_print_string ppf "ELF64"

let pp_endianness ppf = function
  | Little -> Format.pp_print_string ppf "little-endian"
  | Big -> Format.pp_print_string ppf "big-endian"
