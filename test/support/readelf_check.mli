(** Comparisons of a decoded file with the output of [readelf -W]. Each check appends one line per
    disagreeing field to {!mismatches}, so a run reports every difference at once. *)

val mismatches : string list ref

val check_sections : Elf.Target.arch -> Elf.Decode.t -> string -> unit
(** [check_sections arch d out]: section names, types, addresses, offsets, sizes, entry sizes, flags,
    links, infos and alignments against [readelf -S] output [out]. *)

val check_symbols : Elf.Decode.t -> string -> unit
(** Every symbol of every table against [readelf -s]. *)

val check_relocs : Elf.Decode.t -> string -> unit
(** Every relocation (offset, [r_info], symbol name, addend) against [readelf -r]. *)

val check_attributes : Elf.Target.arch -> Elf.Decode.t -> string -> unit
(** The File attributes of a RISC-V or ARM file against [readelf -A]; other architectures are
    skipped. *)

val check_segments : Elf.Decode.t -> string -> unit
(** Every program header against [readelf -l]. *)

val check_notes : Elf.Decode.t -> string -> unit
(** Every note (owner, descriptor size) against [readelf -n]. *)

val check_header : Elf.Decode.t -> string -> unit
(** Type, machine, entry, flags and table counts against [readelf -h]. *)
