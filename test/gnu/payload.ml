(** A per-architecture payload generator: assembly that checks its own loaded image. *)

module type S = sig
  val arch : Elf.Target.arch

  val source : Spec.t -> string
  (** Assembly with sections [.text.main] (entry [_start]) and [.text.aux]. Every reference to the
      other regions is an absolute constant taken from the spec, so it assembles without relocations. *)
end

(** The memory checks every payload makes, in order: [(code, address, expected marker)]. A [None]
    marker means the word must be zero. Codes 10 (execution address), 17 (store and read back) and
    18 (call into [.text.aux]) are architecture-specific and handled by each generator. *)
let word_checks (s : Spec.t) =
  let init = Int64.of_int s.data_init in
  [
    (11, s.rodata, Some s.markers.rodata);
    (12, s.data, Some s.markers.data);
    (13, Int64.add s.data init, None);
    (14, Int64.sub (Int64.add (Int64.add s.data init) s.data_zero) 4L, None);
    (15, s.bss, None);
    (16, Int64.sub (Int64.add s.bss s.bss_size) 4L, None);
  ]

let hex64 v = Printf.sprintf "0x%Lx" v
let hex32 v = Printf.sprintf "0x%lx" v
