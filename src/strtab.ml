[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

type t = { buf : Buffer.t; seen : (string, int64) Hashtbl.t }
type error = [ `Nul_in_name of string ]

let pp_error ppf : error -> unit = function
  | `Nul_in_name n -> Format.fprintf ppf "name %S contains a NUL byte" n

let create () =
  let buf = Buffer.create 64 in
  Buffer.add_char buf '\000';
  { buf; seen = Hashtbl.create 16 }

let add t s =
  if String.contains s '\000' then Err.fail ~pos:__POS__ ~pp_error (`Nul_in_name s)
  else if s = "" then Ok 0L
  else
    match Hashtbl.find_opt t.seen s with
    | Some off -> Ok off
    | None ->
        let off = Int64.of_int (Buffer.length t.buf) in
        Buffer.add_string t.buf s;
        Buffer.add_char t.buf '\000';
        Hashtbl.add t.seen s off;
        Ok off

let contents t = Buffer.contents t.buf
