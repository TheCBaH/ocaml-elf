(** Locating and running the cross binutils and QEMU binaries. *)

type arch = Elf.Target.arch

type tools = {
  as_ : string list;  (** assembler command, with the flags that select the target *)
  ld : string list;
  objdump : string;
  readelf : string;
  qemu_user : string;
  qemu_system : string option;
}

val find : arch -> (tools, [ `Missing of string ]) result
(** The binutils for [arch]; [`Missing tool] names the first one not on [PATH]. The QEMU binaries
    are not checked here: see {!have}. *)

val have : string -> bool
(** Whether a program is on [PATH]. *)

val run : string list -> int * string * string
(** [run argv] runs a command and returns its exit status, stdout and stderr (captured through
    temporary files). *)

val skip_or_fail : string -> unit
(** Called when a tool is missing: prints [SKIP <tool>] and returns, or, with
    [ELF_REQUIRE_TOOLCHAIN=1], prints [MISSING <tool>] and exits 1. *)

val artifacts : string -> string
(** [artifacts name] creates (if needed) and returns the directory [gnu-artifacts/<name>] under
    the current directory, where a test keeps its sources and outputs for debugging. *)
