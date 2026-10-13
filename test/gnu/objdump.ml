[@@@ai_disclosure "ai-generated"]
[@@@ai_provider "Anthropic, OpenAI"]

let is_hex c = match c with '0' .. '9' | 'a' .. 'f' -> true | _ -> false

let strip_from s marker =
  let n = String.length marker in
  let rec find i =
    if i + n > String.length s then None
    else if String.sub s i n = marker then Some i
    else find (i + 1)
  in
  match find 0 with Some i -> String.sub s 0 i | None -> s

(* Instructions whose last operand is an address: jumps, calls and branches, on every target. *)
let is_branch m =
  m <> ""
  && (m.[0] = 'b'
     || m.[0] = 'j'
     || List.mem m
          [
            "call";
            "tail";
            "cbz";
            "cbnz";
            "tbz";
            "tbnz";
            "adr";
            "adrp";
            "c.j";
            "c.jal";
            "c.beqz";
            "c.bnez";
          ])

(* Subtract [vma] from a hex last operand, with or without a 0x prefix. *)
let rebase ~vma text =
  let i =
    max
      (Option.value (String.rindex_opt text ' ') ~default:(-1))
      (Option.value (String.rindex_opt text ',') ~default:(-1))
  in
  let target = String.sub text (i + 1) (String.length text - i - 1) in
  let digits =
    if String.length target > 2 && String.sub target 0 2 = "0x" then
      String.sub target 2 (String.length target - 2)
    else target
  in
  if digits <> "" && String.for_all is_hex digits then
    String.sub text 0 (i + 1)
    ^ Printf.sprintf "%Lx" (Int64.sub (Int64.of_string ("0x" ^ digits)) vma)
  else text

let instructions ~vma out =
  List.filter_map
    (fun line ->
      match String.split_on_char '\t' line with
      | addr :: bytes :: rest when rest <> [] ->
          let addr = String.trim addr in
          if
            String.length addr > 1
            && addr.[String.length addr - 1] = ':'
            && String.for_all is_hex (String.sub addr 0 (String.length addr - 1))
          then begin
            let text = String.concat " " (List.map String.trim rest) in
            let text = String.trim (strip_from (strip_from (strip_from text " #") " <") "//") in
            let mnemonic =
              (* skip prefixes that objdump prints as separate words *)
              let is_prefix w =
                (String.length w >= 3 && String.sub w 0 3 = "rex")
                || List.mem w
                     [
                       "lock";
                       "rep";
                       "repz";
                       "repnz";
                       "data16";
                       "addr32";
                       "notrack";
                       "bnd";
                       "cs";
                       "ds";
                       "es";
                       "ss";
                       "fs";
                       "gs";
                     ]
              in
              match List.find_opt (fun w -> not (is_prefix w)) (String.split_on_char ' ' text) with
              | Some w -> w
              | None -> text
            in
            Some (String.trim bytes, if is_branch mnemonic then rebase ~vma text else text)
          end
          else None
      | _ -> None)
    (String.split_on_char '\n' out)
