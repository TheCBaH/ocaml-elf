(** Assemble a payload, build the executable around it, and run it. *)

type run = {
  status : int;  (** the QEMU exit status; 124 means [timeout] killed it *)
  file : string;  (** the executable *)
  dir : string;  (** where the artifacts are kept *)
}

val build :
  (module Payload.S) ->
  name:string ->
  target:Elf.Target.t ->
  variant:Spec.variant ->
  control:Spec.control ->
  ( Toolchain.tools * Spec.t * Elf.Exec.spec * string * string * string,
    [ `Missing of string ] )
  result
(** [build payload ~name ~target ~variant ~control] writes the source, assembles it, checks that the
    object has no relocation against the payload sections, and builds the executable (written
    executable to [<artifacts>/<name>/prog]). The result is the tools, the spec, the exec spec, the
    directory, and the assembled [.text.main] and [.text.aux] bytes. *)

val run_user : Toolchain.tools -> dir:string -> string -> run
(** Runs the executable under QEMU user mode with a 10 second limit. *)
