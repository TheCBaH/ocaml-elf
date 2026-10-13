(** Architecture profiles. Class and machine are derived together from the architecture and cannot
    be set independently; the ABI is an explicit argument. All profiles are little-endian. *)

type arch = X86_32 | X86_64 | Arm | Aarch64 | Riscv32 | Riscv64

type attributes = {
  section_name : string;
  section_type : int64;
  segment_type : int64 option;  (** program header type carrying the same bytes, if any *)
  contents : Attributes.t;
}

type t = private {
  arch : arch;
  elf_class : Types.elf_class;
  endianness : Types.endianness;
  machine : int;
  flags : int64;
  osabi : int;
  max_page_size : int64;
  attributes : attributes option;
}

val x86_32 : t
val x86_64 : t

val aarch64 : ?page_size:int64 -> unit -> t
(** The default page size is 64 KiB, the value GNU ld uses, which is safe on kernels with 64 KiB
    pages. A size that is not a power of two is reported by [Exec.validate]. *)

val arm : Arm.abi -> t
(** Carries [.ARM.attributes] only when the ABI supplies attributes. *)

val riscv : Riscv.abi -> t
(** The class follows [abi.xlen]. *)

val ident : t -> Types.ident
val arch_of_string : string -> arch option
val pp_arch : Format.formatter -> arch -> unit
val all : arch list
