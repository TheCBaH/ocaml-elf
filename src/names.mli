(** Names of the constants in {!Const}, for printers and diagnostics.

    The lookups return [None] for a value that has no name; the printers show the name when there
    is one and [0x...] otherwise. Flag printers show one letter per known bit followed by the
    residual bits, if any, as [+0x...]. *)

val et : int -> string option
val em : int -> string option
val pt : int64 -> string option
val sht : int64 -> string option
val stb : int -> string option
val stt : int -> string option
val shn : int -> string option
val pp_et : Format.formatter -> int -> unit
val pp_em : Format.formatter -> int -> unit
val pp_pt : Format.formatter -> int64 -> unit
val pp_sht : Format.formatter -> int64 -> unit
val pp_stb : Format.formatter -> int -> unit
val pp_stt : Format.formatter -> int -> unit
val pp_shn : Format.formatter -> int -> unit

val pp_pf : Format.formatter -> int64 -> unit
(** [R], [W], [X] in that order (e.g. [RX]); [-] when no bit is set. *)

val pp_shf : Format.formatter -> int64 -> unit
(** Section flags in bit order using readelf's letters: [W A X M S I L O G T C]. *)
