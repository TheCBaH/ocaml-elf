(** The layout and expected values shared by every payload test (design §9.3). Addresses are
    [base + 0x10000 * k], so one spec works with 4 KiB and 64 KiB pages. *)

type variant = { base : int64; sections : bool; abi : string }

type control =
  [ `None
  | `Flip_rodata  (** the rodata marker bytes differ from what the payload expects *)
  | `Dirty_zero_fill  (** a non-zero word is the first word of the mixed segment's zero fill *)
  | `Illegal_instruction
    (** system payloads execute an illegal instruction after startup, to reach the trap handler *)
  ]
(** Deliberate faults, to prove that the checks can fail. *)

type kind = [ `User | `System ]
(** [`User]: a Linux process. [`System]: bare metal under [qemu-system-*], with a stack segment. *)

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
  kind : kind;
  control : control;
  long_mode : bool;
      (** system payload of 64-bit code in an ELF32 Multiboot container, which enters long mode *)
  stack : int64;  (** a read/write zero-filled region the system payload uses as its stack *)
  stack_size : int64;
}

val make : ?kind:kind -> ?control:control -> ?long_mode:bool -> Elf.Target.t -> variant -> t

val exec_spec : t -> text:string -> aux:string -> Elf.Exec.spec
(** The executable for [t] (including its [control]) around the assembled code. Rodata and data bytes come from [t] in the
    target byte order, never from the assembler. *)

val word : Elf.Types.endianness -> int32 -> string
(** A 32-bit word in a byte order. *)

val symbols : t -> text:string -> aux:string -> Elf.Exec.symbol list

val ram : t -> Elf.Exec.ram option
(** The RAM window the executable must fit in: [None] for user mode. *)

val multiboot_header : t -> int64 option
(** Address of the 12-byte Multiboot header segment ([.mbhdr]): present for x86 system payloads,
    one page after the mapped headers, so it lies in the first 8 KiB of the file. *)

val idt : t -> int64 option
(** Address of the 256-byte [.idt] section (right after [.stack]) for x86 system payloads. *)

val trap_offset : int64
(** Offset from [.text.main] of the trap handler / vector table of the system payloads that need
    one at a known address. *)

val idt_size : t -> int64
(** 0x100 for 32-bit gates, 0x200 for the 64-bit gates of a long-mode payload. *)

val page_tables : t -> int64 option
(** Address of the 0x3000-byte [.pt] section (PML4, PDPT, PD; 4 KiB aligned) of a long-mode
    payload. *)

val stack_segment_size : t -> int64
(** Memory size of the read/write segment holding [.stack] (and [.idt], [.pt] when present). *)
