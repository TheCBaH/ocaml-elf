(** Bounded ELF32/ELF64 decoding, both byte orders.

    Every offset, table dimension, linked index and string is validated against the input before
    a slice is taken; arithmetic that could wrap is checked. Unknown numeric values are kept, not
    rejected. Extended section and program-header numbering is resolved through section header 0.

    Decoding is reading only: nothing here applies relocations or loads code. Offsets and padding
    of the original file are not preserved beyond what the records themselves state, so decoding
    and re-encoding is not a byte-identical round trip. *)

open Types

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

val pp_region : Format.formatter -> region -> unit
val pp_error : Format.formatter -> error -> unit

type section = { index : int; name : string; shdr : shdr }

type t = private {
  data : string;
  header : header;
  phnum : int;  (** after extended numbering *)
  shnum : int;  (** after extended numbering; 0 for a sectionless file *)
  shstrndx : int;  (** after extended numbering; 0 when there are no section names *)
  phdrs : phdr array;
  sections : section array;
}

val of_string : string -> (t, error) Err.t
val find_section : t -> string -> section option

val section_data : t -> section -> (string, error) Err.t
(** File bytes of a section; empty for [SHT_NOBITS]. *)

val segment_data : t -> int -> (string, error) Err.t
(** The [p_filesz] file bytes of program header [i]. *)

val string_at : t -> section -> int64 -> (string, error) Err.t
(** A NUL-terminated string at an offset into a string table section. *)

type symbol = {
  sym_index : int;
  sym_name : string;
  sym : sym;
  shndx : int64;  (** [st_shndx], or the [SHT_SYMTAB_SHNDX] entry when [st_shndx] is [SHN_XINDEX] *)
}

val symbols : t -> section -> (symbol array, error) Err.t
(** Entries of an [SHT_SYMTAB] or [SHT_DYNSYM] section, names resolved through [sh_link]. *)

val relocations : t -> section -> (rel array, error) Err.t
(** Entries of an [SHT_REL] or [SHT_RELA] section. *)

type note = { n_type : int64; n_name : string; n_desc : string }

val notes : t -> [ `Section of section | `Segment of int ] -> (note list, error) Err.t

val attributes : t -> section -> (Attributes.t, error) Err.t
(** Contents of a [.riscv.attributes] or [.ARM.attributes] section ([SHT_*_ATTRIBUTES], one value
    shared by both architectures). *)
