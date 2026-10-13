(** ARM EABI profile: [e_flags] and optional [.ARM.attributes]. *)

type abi = { float_abi : [ `Hard | `Soft ]; attributes : Attributes.t option }

val flags : abi -> int64
(** [EF_ARM_EABI_VER5], plus [EF_ARM_ABI_FLOAT_HARD] or [EF_ARM_ABI_FLOAT_SOFT]. *)

val hard_float : abi
(** The [gnueabihf] profile, without attributes. *)

val soft_float : abi

val armv7a_attributes : Attributes.t
(** The [aeabi] File attributes GNU as 2.44 writes for [-march=armv7-a]: [Tag_CPU_name "7-A"],
    [Tag_CPU_arch] v7, [Tag_CPU_arch_profile] Application, [Tag_ARM_ISA_use] and
    [Tag_THUMB_ISA_use] (Thumb-2). Without attributes, tools assume a baseline architecture and,
    for instance, disassemble [movw] as [tst]. *)
