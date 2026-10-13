(** A representative executable spec, laid out as in the design's test layout. *)

val text_size : int
val rodata_size : int
val data_init : int
val data_zero : int64
val bss_size : int64

val spec : ?base:int64 -> ?sections:bool -> ?symbols:bool -> Elf.Target.t -> Elf.Exec.spec
(** Headers at [base] (default [0x40_0000]), then [.text], [.text.aux], [.rodata], a mixed
    [.data] + [.bss.data] segment and a pure [.bss] segment at [base + 0x10000 * k]; entry at
    [.text]; [PT_GNU_STACK] read/write; section headers unless [sections] is false; a few symbols
    when [symbols] (default: same as [sections]). *)

val addr : ?base:int64 -> string -> int64
(** Address of a section of {!spec}: [".text"], [".text.aux"], [".rodata"], [".data"],
    [".bss.data"], [".bss"]. *)
