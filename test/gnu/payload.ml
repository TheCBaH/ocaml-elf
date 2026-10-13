(** A per-architecture payload generator: assembly that checks its own loaded image. *)

module type S = sig
  val arch : Elf.Target.arch

  val source : Spec.t -> string
  (** Assembly with sections [.text.main] (entry [_start]) and [.text.aux]. Every reference to the
      other regions is an absolute constant taken from the spec, so it assembles without relocations. *)
end
