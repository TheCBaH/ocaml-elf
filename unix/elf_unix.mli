(** File access for the portable [elf] library. Failures are reported as [`Io] errors; no [Sys_error]
    or [Unix.Unix_error] escapes. *)

type io = { path : string; op : [ `Read | `Write | `Chmod ]; message : string }
type error = [ `Io of io ]

val pp_error : Format.formatter -> error -> unit

val read_file : string -> (string, error) Err.t
(** The whole file, read in binary mode. *)

val write_file : ?perm:int -> string -> string -> (unit, error) Err.t
(** [write_file ?perm path data] creates or truncates [path] (mode [perm], default [0o644] before
    the umask). *)

val write_executable : string -> string -> (unit, error) Err.t
(** [write_file], then [chmod 0o755]: QEMU user mode refuses a file without the execute bit. *)
