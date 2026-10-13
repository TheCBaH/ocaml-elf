(** The layout and expected values shared by every payload test (design §9.3). Addresses are
    [base + 0x10000 * k], so one spec works with 4 KiB and 64 KiB pages. *)

type variant = { base : int64; sections : bool; abi : string }
type markers = { rodata : int32; data : int32; aux : int32; store : int32 }

type t = {
  arch : Elf.Target.arch;
  target : Elf.Target.t;
  variant : variant;
  text : int64;
  aux : int64;
  rodata : int64;
  data : int64;
  bss : int64;
  data_init : int;  (** initialized bytes of the mixed [.data] segment *)
  data_zero : int64;  (** zero-filled bytes after them, in the same segment *)
  bss_size : int64;
  markers : markers;
}

val make : Elf.Target.t -> variant -> t

type control =
  [ `None
  | `Flip_rodata  (** the rodata marker bytes differ from what the payload expects *)
  | `Dirty_zero_fill  (** a non-zero word is the first word of the mixed segment's zero fill *) ]

val exec_spec : ?control:control -> t -> text:string -> aux:string -> Elf.Exec.spec
(** The executable for [t] around the assembled code. Rodata and data bytes come from [t] in the
    target byte order, never from the assembler. *)

val word : Elf.Types.endianness -> int32 -> string
(** A 32-bit word in a byte order. *)

val symbols : t -> text:string -> aux:string -> Elf.Exec.symbol list
