[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

type io = { path : string; op : [ `Read | `Write | `Chmod ]; message : string }
type error = [ `Io of io ]

let pp_error ppf : error -> unit = function
  | `Io { path; op; message } ->
      let verb =
        match op with
        | `Read -> "reading"
        | `Write -> "writing"
        | `Chmod -> "setting permissions of"
      in
      Format.fprintf ppf "%s %s: %s" verb path message

let catch path op = function
  | Sys_error message -> Some (`Io { path; op; message })
  | Unix.Unix_error (e, _, _) -> Some (`Io { path; op; message = Unix.error_message e })
  | _ -> None

let protect path op f = Err.protect ~pos:__POS__ ~pp_error ~catch:(catch path op) f

let read_file path =
  protect path `Read (fun () ->
      let ic = open_in_bin path in
      Fun.protect
        ~finally:(fun () -> close_in_noerr ic)
        (fun () -> really_input_string ic (in_channel_length ic)))

let write_file ?(perm = 0o644) path data =
  protect path `Write (fun () ->
      let oc = open_out_gen [ Open_wronly; Open_creat; Open_trunc; Open_binary ] perm path in
      Fun.protect ~finally:(fun () -> close_out_noerr oc) (fun () -> output_string oc data))

let write_executable path data =
  match write_file path data with
  | Error _ as e -> e
  | Ok () -> protect path `Chmod (fun () -> Unix.chmod path 0o755)
