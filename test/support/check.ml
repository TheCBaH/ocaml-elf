[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

exception Failed of string

let fail msg = raise (Failed msg)
let failf fmt = Format.kasprintf fail fmt

let case name f () =
  try f () with
  | Failed msg -> failf "%s: %s" name msg
  | e -> failf "%s: exception %s" name (Printexc.to_string e)

let run suite cases =
  Err.Config.set Err.Config.deterministic;
  let failures =
    List.fold_left
      (fun n f ->
        match f () with
        | () -> n
        | exception Failed msg ->
            Format.printf "FAIL %s: %s@." suite msg;
            n + 1)
      0 cases
  in
  if failures > 0 then (
    Format.printf "%s: %d of %d failed@." suite failures (List.length cases);
    exit 1)
  else Format.printf "%s: %d passed@." suite (List.length cases)

let equal ~pp ?(eq = ( = )) what expected actual =
  if not (eq expected actual) then failf "%s: expected %a, got %a" what pp expected pp actual

let ok ~pp_error what = function
  | Ok v -> v
  | Error e -> failf "%s: unexpected error %a" what (Err.Error.pp_kind pp_error) e

let error ~pp what accept = function
  | Ok v -> failf "%s: expected an error, got Ok %a" what pp v
  | Error e ->
      let k = Err.Error.kind e in
      if not (accept k) then failf "%s: error of the wrong kind" what

let hex s =
  String.concat "" (List.init (String.length s) (fun i -> Printf.sprintf "%02x" (Char.code s.[i])))

let bytes_equal what expected actual =
  if expected <> actual then
    let n = min (String.length expected) (String.length actual) in
    let rec first i = if i < n && expected.[i] = actual.[i] then first (i + 1) else i in
    let i = first 0 in
    let window s =
      let lo = max 0 (i - 4) in
      hex (String.sub s lo (min 16 (String.length s - lo)))
    in
    failf "%s: first difference at offset 0x%x (lengths %d vs %d): expected ..%s got ..%s" what i
      (String.length expected) (String.length actual) (window expected) (window actual)
