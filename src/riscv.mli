(** RISC-V ABI profiles: [e_flags] and [.riscv.attributes] contents.

    The float bits of [e_flags] describe how floating-point arguments are passed, not whether the
    code uses floating-point instructions. [RVC] follows [rvc] (whether compressed alignment is
    permitted), not the register width. *)

type xlen = Rv32 | Rv64
type float_abi = Soft | Single | Double | Quad

type abi = {
  xlen : xlen;
  float_abi : float_abi;
  rvc : bool;
  rve : bool;
  tso : bool;
  arch : string;  (** the [Tag_RISCV_arch] ISA string, e.g. ["rv32i2p0_m2p0"] *)
  stack_align : int;  (** [Tag_RISCV_stack_align], in bytes *)
  unaligned_access : bool option;  (** [Tag_RISCV_unaligned_access]; omitted when [None] *)
}

val flags : abi -> int64
(** [RVC 0x1 | float ABI (0, 0x2, 0x4, 0x6) | RVE 0x8 | TSO 0x10]. *)

val attributes : abi -> Attributes.t
(** One [riscv] subsection with [Tag_RISCV_stack_align] (4), [Tag_RISCV_arch] (5) and, when
    present, [Tag_RISCV_unaligned_access] (6), in tag order. *)

val isa_string : xlen -> base:[ `I | `E ] * (int * int) -> (string * (int * int)) list -> string
(** Builds an ISA string in canonical order from an explicit extension list: the base, then
    single-letter extensions in [MAFDQLCBKJTPVH] order, then [z*] extensions grouped by the
    category letter after [z] (in [IEMAFDQLCBKJTPVH] order) and alphabetically within a group, then
    [s*], then [x*]. Versions are written [<major>p<minor>]. Implied extensions are not added:
    the caller lists every extension. *)

(** {1 Named profiles}

    The ISA strings are the ones GNU as 2.44 emits for the matching [-march] under its default ISA
    specification, 2.2 ([-misa-spec=2.2]): [i2p0], no [zicsr], and the [zmmul]/[zaamo]/[zalrsc]
    extensions it adds to [m] and [a]. Under [-misa-spec=20191213] the same [-march] gives
    different versions and adds [zicsr]; build such a string with {!isa_string}. *)

val rv32imafd_ilp32d : abi
(** [-march=rv32imafd -mabi=ilp32d]: the profile matching the assembler's RV32 toolchain settings
    (no relaxation, no small-data placement). *)

val rv32im_ilp32 : abi
val rv64imafd_lp64d : abi
val rv64im_lp64 : abi
