(** String-table builder. Offset 0 is the empty string, equal strings share one entry, and a NUL
    inside a name is rejected rather than silently splitting it in two. *)

type t
type error = [ `Nul_in_name of string ]

val pp_error : Format.formatter -> error -> unit
val create : unit -> t

val add : t -> string -> (int64, error) Err.t
(** [add t s] is the offset of [s], adding it on first use. Idempotent. *)

val contents : t -> string
(** The table so far; it starts with a NUL byte. *)
