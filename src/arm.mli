(** ARM EABI profile: [e_flags] and optional [.ARM.attributes]. *)

type abi = { float_abi : [ `Hard | `Soft ]; attributes : Attributes.t option }

val flags : abi -> int64
(** [EF_ARM_EABI_VER5], plus [EF_ARM_ABI_FLOAT_HARD] or [EF_ARM_ABI_FLOAT_SOFT]. *)

val hard_float : abi
(** The [gnueabihf] profile, without attributes. *)

val soft_float : abi
