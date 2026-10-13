(** Parsers for [readelf -W] output. They are independent of {!Elf.Decode}: the tests compare the
    two. Numbers are kept as printed (hex addresses as [int64], decimal sizes as [int64]). *)

type section = {
  nr : int;
  name : string;
  typ : string;
  addr : int64;
  off : int64;
  size : int64;
  es : int64;
  flags : string;
  lk : int;
  inf : int;
  al : int64;
}

type symbol = {
  num : int;
  value : int64;
  size : int64;
  typ : string;
  bind : string;
  vis : string;
  ndx : string;
  name : string;
}

type reloc = {
  offset : int64;
  info : int64;
  rtype : string;
  sym_name : string;  (** empty when the relocation has no symbol *)
  addend : int64 option;
}

type segment = {
  ptype : string;
  p_offset : int64;
  vaddr : int64;
  paddr : int64;
  filesz : int64;
  memsz : int64;
  pflags : string;  (** e.g. ["R E"], ["RW"], without padding *)
  palign : int64;
}

val header : string -> (string * string) list
(** [readelf -h]: [(key, value)] pairs, e.g. [("Class", "ELF32")]. *)

val sections : string -> section list
(** [readelf -S]. *)

val symbols : string -> (string * symbol list) list
(** [readelf -s]: one entry per symbol table, keyed by the table's name. *)

val relocs : string -> (string * reloc list) list
(** [readelf -r]: one entry per relocation section, keyed by its name. *)

val segments : string -> segment list
(** [readelf -l]. *)

val attributes : string -> (string * string) list
(** [readelf -A]: the [(tag name, value)] lines of the first File Attributes block; string values
    keep their quotes. *)

val notes : string -> (string * (string * int64) list) list
(** [readelf -n]: for each "Displaying notes found in" block, the section or segment name and the
    [(owner, descriptor size)] of each note. *)
