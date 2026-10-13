(** Unsigned 64-bit arithmetic over [int64] bit patterns.

    Every operation that can wrap returns [None] instead. Conversion to a native
    [int] is the only way to index a buffer, and it fails rather than truncating. *)

type t = int64

val compare : t -> t -> int
val lt : t -> t -> bool
val le : t -> t -> bool
val max : t -> t -> t
val add : t -> t -> t option
val sub : t -> t -> t option
val mul : t -> t -> t option

val fits_bits : int -> t -> bool
(** [fits_bits n v] holds when [v] is representable in [n] unsigned bits. *)

val is_pow2 : t -> bool

val align_up : t -> t -> t option
(** [align_up v a] rounds [v] up to a multiple of [a], a power of two. *)

val align_down : t -> t -> t
val is_aligned : t -> t -> bool

val rem : t -> t -> t
(** Unsigned remainder. *)

val to_int : t -> int option
val of_int : int -> t
val pp : Format.formatter -> t -> unit
