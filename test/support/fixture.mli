(** Generated ELF files and mutators for the decoder tests.

    Files are built with the unchecked [Codec] writers, so they do not depend on [Exec]. The
    mutators rewrite fields in place, taking class and byte order from the file itself. *)

open Elf.Types

type sect = {
  name : string;
  typ : int64;
  flags : int64;
  addr : int64;
  link : int;
  info : int64;
  align : int64;
  entsize : int64;
  data : string;
  size : int64 option;  (** [sh_size] when it differs from [String.length data], e.g. NOBITS *)
}

val sect :
  ?flags:int64 ->
  ?addr:int64 ->
  ?link:int ->
  ?info:int64 ->
  ?align:int64 ->
  ?entsize:int64 ->
  ?size:int64 ->
  string ->
  int64 ->
  string ->
  sect

val build :
  ?e_type:int ->
  ?machine:int ->
  ?entry:int64 ->
  ?flags:int64 ->
  ?phdrs:(int64 array -> phdr list) ->
  elf_class ->
  endianness ->
  sect list ->
  string
(** [build cls endian sects] lays out the header, the program headers, every section (the null
    section is added first, [.shstrtab] last) and the section header table. [phdrs] receives the
    file offset of every section, indexed by section number. *)

val minimal : ?cls:elf_class -> ?endian:endianness -> unit -> string
(** A small valid file. Section numbers: 1 [.text], 2 [.symtab], 3 [.strtab], 4 [.note.test],
    5 [.rela.text] (RELA), 6 [.shstrtab]; one [PT_LOAD] and one
    [PT_NOTE] segment. The symbol table holds one local and one global symbol. *)

val text_index : int
val symtab_index : int
val strtab_index : int
val note_index : int
val rela_index : int
val shstrtab_index : int

val many_sections : ?cls:elf_class -> ?endian:endianness -> int -> string
(** [many_sections n]: [n] empty sections named [s<i>]; with [n >= 0xff00] the counts use
    extended numbering. *)

(** {1 Mutators} *)

val truncate : int -> string -> string
val set_u8 : int -> int -> string -> string
val set_u16 : int -> int -> string -> string
val set_u32 : int -> int64 -> string -> string
val set_word : int -> int64 -> string -> string
val header : string -> header
val with_header : (header -> header) -> string -> string
val with_shdr : int -> (shdr -> shdr) -> string -> string
val with_phdr : int -> (phdr -> phdr) -> string -> string

val shdr_offset : string -> int -> int
(** File offset of section header [i]. *)
