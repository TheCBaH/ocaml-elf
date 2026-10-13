(** Checked serialization of fixed-size ELF records.

    Every field is range-checked against its width in the chosen class before any byte is written,
    so an ELF32 address above 2{^32}, a 9-bit ELF32 relocation type, or a negative count is
    reported rather than truncated. A writer that fails leaves the destination partly written. *)

open Types

type record =
  [ `Header | `Program_header of int | `Section_header of int | `Symbol of int | `Relocation of int ]

type overflow = { record : record; field : string; value : int64; bits : int; signed : bool }
type error = [ `Field_overflow of overflow ]

val pp_record : Format.formatter -> record -> unit
val pp_error : Format.formatter -> error -> unit
val write_header : Bytes.t -> header -> (unit, error) Err.t
val write_phdr : ident -> Bytes.t -> int -> index:int -> phdr -> (unit, error) Err.t
val write_shdr : ident -> Bytes.t -> int -> index:int -> shdr -> (unit, error) Err.t
val write_sym : ident -> Bytes.t -> int -> index:int -> sym -> (unit, error) Err.t

val write_rel : ident -> Bytes.t -> int -> index:int -> rel -> (unit, error) Err.t
(** Writes a REL entry when [r_addend] is [None] and a RELA entry otherwise. *)
