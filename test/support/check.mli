(** A tiny test harness: no PPX, so the suites also run under js_of_ocaml. *)

val run : string -> (unit -> unit) list -> unit
(** [run suite cases] selects {!Err.Config.deterministic} (so rendered errors are identical on
    every backend), runs every case, prints one line per failure and exits 1 if any failed. *)

val case : string -> (unit -> unit) -> unit -> unit
(** [case name f] is a named case; an exception raised by [f] is a failure. *)

val equal :
  pp:(Format.formatter -> 'a -> unit) -> ?eq:('a -> 'a -> bool) -> string -> 'a -> 'a -> unit
(** [equal ~pp what expected actual] fails unless the values are equal ([eq] defaults to
    structural equality). *)

val ok : pp_error:(Format.formatter -> 'e -> unit) -> string -> ('a, 'e) Err.t -> 'a
(** Unwraps [Ok], failing with the rendered error otherwise. *)

val error : pp:(Format.formatter -> 'a -> unit) -> string -> ('e -> bool) -> ('a, 'e) Err.t -> unit
(** [error ~pp what accept r] fails unless [r] is an [Error] whose payload satisfies [accept]. *)

val bytes_equal : string -> string -> string -> unit
(** [bytes_equal what expected actual] reports the first mismatching offset as hex. *)

val fail : string -> 'a
(** Fails the current case. *)

val failf : ('a, Format.formatter, unit, 'b) format4 -> 'a
