(** Checks of a built executable against readelf and objdump. The expected values come from the
    spec, never from {!Elf.Decode}. *)

val check :
  Toolchain.tools -> Spec.t -> Elf.Exec.spec -> dir:string -> text:string -> aux:string -> unit
(** Raises (through the test harness) with one line per mismatching field. *)
